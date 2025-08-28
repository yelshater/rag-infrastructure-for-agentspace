# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import json
import base64
import datetime
import pytz
import logging
from typing import Dict, Any, Optional

from google import genai
from vertexai.generative_models import Part
from pydantic import BaseModel, Field

from google.cloud import firestore
from google.cloud import pubsub_v1
from jinja2 import Environment, FileSystemLoader

# Set up logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# --- Configuration ---
# Environment variables (ensure these are set in your Cloud Functions environment)
GCP_PROJECT_ID = os.environ.get("PROJECT_ID")
VERTEX_AI_LOCATION = os.environ.get("VERTEX_AI_LOCATION", "us-central1")

DB_FIRESTORE_NAME = os.environ.get("DB_FIRESTORE_NAME", "lease-metadata")
TARGET_PATH_PREFIX = f"{os.environ.get('TARGET_PATH_PREFIX', 'lease-sample')}/"
FIRESTORE_COLLECTION_NAME = os.environ.get("FIRESTORE_COLLECTION_NAME", "lease-metadata-collection")
UPDATE_DATASTORE_TOPIC_ID = os.environ.get("UPDATE_DATASTORE_TOPIC_ID", "update-datastore-topic")
GEMINI_MODEL_NAME = os.environ.get("GEMINI_MODEL_NAME", "gemini-2.5-flash")
OVERWRITE_EXISTING_METADATA = os.environ.get("OVERWRITE_EXISTING_METADATA", "false").lower() == "true"


if not GCP_PROJECT_ID:
    logger.error("PROJECT_ID environment variable is not set.")
    raise ValueError("PROJECT_ID environment variable must be set.")


# Define the response schema for metadata extraction using Pydantic
class LeaseMetadata(BaseModel):
    """Pydantic model for lease metadata extraction."""

    city: str = Field(..., description="The city where the property is located.")
    street: str = Field(..., description="The street address of the property.")
    province: str = Field(..., description="The province or state of the property.")
    postalcode: str = Field(..., description="The postal code or ZIP code of the property.")
    lease_start_date: str = Field(..., description="The start date of the lease agreement in YYYY-MM-DD format.")
    lease_end_date: str = Field(..., description="The end date of the lease agreement in YYYY-MM-DD format.")
    rent: int = Field(..., description="The monthly rent amount.")
    document_language: str = Field(..., description="The language of the lease document.")


# Configuration for the Gemini model
GENERATION_CONFIG = {
    "response_mime_type": "application/json",
    "response_schema": LeaseMetadata,
    "temperature": 0,
}


def clean_up_firestore_collection(coll_ref: firestore.CollectionReference, batch_size: int = 100) -> None:
    """Optional, clean up documents from a Firestore collection in batches.

    Args:
        coll_ref (firestore.CollectionReference): Reference to the Firestore collection.
        batch_size (int): Number of documents to delete in each batch (default is 100).
    """
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0
    for doc in docs:
        logger.info(f"Deleting doc {doc.id} => {doc.to_dict()}")
        doc.reference.delete()
        deleted += 1

    if deleted >= batch_size:
        clean_up_firestore_collection(coll_ref, batch_size)


def process_pubsub_message(event: Dict, context: Optional[Any] = None) -> Optional[str]:
    """
    Cloud Function triggered by a Pub/Sub message. Processes lease documents.

    Args:
        event (dict): The dictionary with data specific to this type of event.
        context (Context): Metadata for the event.
    """

    # Check if the function was triggered to clear firestore
    clear_firestore = False
    if context:
        clear_firestore = (
            context.event_type == "google.cloud.functions.v2.Function.BEFORE_EXEC"
            and "clear_firestore" in context.resource["labels"]
            and context.resource["labels"]["clear_firestore"].lower() == "true"
        )

    if clear_firestore:
        logger.info("Cleaning up Firestore Collection")
        db = firestore.Client(database=DB_FIRESTORE_NAME)
        coll_ref = db.collection(FIRESTORE_COLLECTION_NAME)
        clean_up_firestore_collection(coll_ref)
        return "Firestore Collection Cleared"

    try:
        # Decode the Pub/Sub message
        message_data = base64.b64decode(event["data"]).decode("utf-8")

        try:
            message_json = json.loads(message_data)
        except json.JSONDecodeError:
            logger.info(f"Received non-JSON message: {message_data}")
            return "Non-JSON message skipped"

        file_path = message_json.get("name")
        bucket_name = message_json.get("bucket")

        if not file_path or not bucket_name:
            logger.error(f"Missing file path or bucket name in message: {message_json}")
            return "Missing file path or bucket name in message"

        # Check if file is in target path
        if not file_path.startswith(TARGET_PATH_PREFIX):
            logger.warning(f"File path {file_path} does not match target prefix {TARGET_PATH_PREFIX}")
            return None

        # Check if the file has a PDF extension
        if not file_path.lower().endswith(".pdf"):
            logger.info(f"Skipping file '{file_path}' - not a PDF file.")
            return "Not a PDF file"

        # Construct the full GCS URI
        pdf_file_uri = f"gs://{bucket_name}/{file_path}"
        logger.info(f"Processing file: {pdf_file_uri}")

        # Initialize clients
        client = genai.Client(vertexai=True, project=GCP_PROJECT_ID, location=VERTEX_AI_LOCATION)
        db = firestore.Client(database=DB_FIRESTORE_NAME)
        pdf_file = Part.from_uri(pdf_file_uri, mime_type="application/pdf")

        # Load and render the prompt from the Jinja template
        env = Environment(loader=FileSystemLoader("."))
        template = env.get_template("prompts/metadata_generation_prompt.j2")
        prompt = template.render()

        # Generate content with the model
        contents = [pdf_file, prompt]
        response = client.models.generate_content(
            model=GEMINI_MODEL_NAME,
            contents=contents,
            generation_config=GENERATION_CONFIG,
        )
        metadata_str = response.text
        logger.info(f"Metadata Response from Gemini: {metadata_str}")

        try:
            # Load and Process metadata from response.
            metadata = json.loads(metadata_str)
            metadata["file_path"] = pdf_file_uri

            # Get current times in UTC and convert to Eastern Time
            now_utc = datetime.datetime.now(datetime.timezone.utc)
            eastern = pytz.timezone("US/Eastern")
            now_est = now_utc.astimezone(eastern)
            now = now_est.strftime("%Y-%m-%d %H:%M:%S")
            metadata["update_datetime"] = now

            # Check if a document with the same file_path already exists
            docs = db.collection(FIRESTORE_COLLECTION_NAME).where("file_path", "==", pdf_file_uri).stream()
            existing_doc = next(docs, None)

            if existing_doc and not OVERWRITE_EXISTING_METADATA:
                logger.info(f"Skipping existing document: {existing_doc.id}")
                return f"Skipping existing document: {existing_doc.id}"

            else:
                logger.info(
                    f"Creating a new document or overwriting existing with id: {existing_doc.id if existing_doc else 'N/A'}"
                )
                metadata["create_datetime"] = now
                metadata["update_datetime"] = now
                doc_ref = db.collection(FIRESTORE_COLLECTION_NAME).document()
                doc_ref.set(metadata)
                logger.info(f"Metadata saved to Firestore with ID: {doc_ref.id}")

            # Publish to Pub/Sub
            logger.info("Publishing metadata to Pub/Sub.")
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(GCP_PROJECT_ID, UPDATE_DATASTORE_TOPIC_ID)
            metadata_json = json.dumps(metadata).encode("utf-8")
            future = publisher.publish(topic_path, metadata_json)
            logger.info(f"Published message to Pub/Sub. Message ID: {future.result()}")

            return "PDF processed successfully."

        except json.JSONDecodeError as e:
            logger.error(f"Error decoding JSON: {e}. Raw output: {metadata_str}")
            return f"Error decoding JSON: {e}."

    except Exception as e:
        logger.error(f"Error processing PDF: {e}")
        return f"Error processing PDF: {e}."
