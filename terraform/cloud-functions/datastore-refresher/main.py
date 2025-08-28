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


import base64
import json
import os
import hashlib
from urllib.parse import urlparse
import logging

from google.cloud import pubsub_v1
from google.cloud import storage
from google.cloud import discoveryengine_v1beta


logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables (ensure these are set in your Cloud Functions environment)
TOPIC_ID = os.environ.get("TOPIC_ID")
METADATA_BUCKET = os.environ.get("METADATA_BUCKET")
DATA_STORE_ID = os.environ.get("DATA_STORE_ID")
PROJECT_ID = os.environ.get("PROJECT_NUMBER")
GCP_PROJECT = os.environ.get("GCP_PROJECT")


if not METADATA_BUCKET:
    logger.error("METADATA_BUCKET environment variable is not set.")
    raise ValueError("METADATA_BUCKET environment variable must be set.")


publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(GCP_PROJECT, TOPIC_ID)


def import_documents_to_discovery_engine(project_id: str, data_store_id: str, gcs_uri: str) -> str:
    """Imports documents from a GCS JSONL file into Google Discovery Engine.

    Args:
        project_id: Google Cloud project ID.
        data_store_id: ID of the Discovery Engine Data Store.
        gcs_uri: GCS URI of the JSONL file to import (e.g., 'gs://your-bucket/path/to/file.jsonl').

    Returns:
        str: A message indicating the import status.
    """
    collection_id = "default_collection"  # Consider making this configurable if needed.

    try:
        logger.info(f"Importing documents from: {gcs_uri}")

        client = discoveryengine_v1beta.DocumentServiceClient()

        parent = (
            f"projects/{project_id}/locations/global/collections/{collection_id}/dataStores/{data_store_id}/branches/0"
        )

        request = discoveryengine_v1beta.ImportDocumentsRequest(
            parent=parent,
            gcs_source=discoveryengine_v1beta.GcsSource(input_uris=[gcs_uri]),
            reconciliation_mode=discoveryengine_v1beta.ImportDocumentsRequest.ReconciliationMode.INCREMENTAL,
        )

        operation = client.import_documents(request=request).result()

        if operation.error_samples:
            error_message = f"Operation failed with errors: {operation.error_samples}"
            logger.error(f"{gcs_uri}: {error_message}")
            return error_message
        else:
            success_message = f"Operation completed successfully."
            logger.info(f"{gcs_uri}: {success_message}")
            return f"{gcs_uri}: Imported successfully!"

    except Exception as e:
        error_message = f"Error importing documents: {str(e)}"
        logger.error(error_message)
        return error_message


def generate_jsonl_from_message(pubsub_event: dict, file_hash: str) -> dict:
    """Parses a Pub/Sub message and generates a JSONL object for Discovery Engine.

    Args:
        pubsub_event: The Pub/Sub event message containing document metadata.
        file_hash: A unique hash for the document.

    Returns:
        The generated JSONL object as a dictionary.
    """

    try:
        message = base64.b64decode(pubsub_event["data"]).decode("utf-8")
        logger.info("Parsing the incoming message.")
        data = json.loads(message)

        # Extract and default relevant fields
        city = data.get("city", "")
        street = data.get("street", "")
        province = data.get("province", "")
        postal_code = data.get("postalcode", "")
        lease_start_date = data.get("lease_start_date", "").replace("/", "-")
        lease_end_date = data.get("lease_end_date", "").replace("/", "-")
        rent = data.get("rent", "")
        file_path = data.get("file_path", "")
        document_language = data.get("document_language", "")

        # Default values for missing or invalid dates/rent
        lease_start_date = "1900-01-01" if lease_start_date.strip() in ["Not Available", ""] else lease_start_date
        lease_end_date = "1900-01-01" if lease_end_date.strip() in ["Not Available", ""] else lease_end_date
        rent = -1 if rent in ["Not Available", ""] else rent

        file_name = os.path.basename(urlparse(file_path).path)

        # Construct the HTTPS URL for structData
        parsed_gs_url = urlparse(file_path)
        bucket_name = parsed_gs_url.netloc
        object_path = parsed_gs_url.path.lstrip("/")
        https_url = f"https://storage.cloud.google.com/{bucket_name}/{object_path}"

        jsonl_object = {
            "id": file_hash,
            "content": {"mimeType": "application/pdf", "uri": file_path},
            "structData": {
                "title": file_name,
                "city": city,
                "street": street,
                "province": province,
                "postalcode": postal_code,
                "lease_start_date": lease_start_date,
                "lease_end_date": lease_end_date,
                "rent": rent,
                "document_language": document_language,
                "url": https_url,
            },
        }

        return jsonl_object

    except Exception as e:
        logger.error(f"Error generating JSONL: {e}")
        return None


def refresh_datastore_document(event: dict, context=None) -> None:
    """Cloud Function triggered by a Pub/Sub message to refresh a document in Discovery Engine.

    Args:
        event: Pub/Sub event payload.
        context: (Optional) Metadata for the event.
    """
    logger.info("Processing Pub/Sub message...")

    try:
        if "data" in event:
            message = base64.b64decode(event["data"]).decode("utf-8")
            logger.info("Parsed message from Pub/Sub.")
            data = json.loads(message)
            file_path = data.get("file_path", "")

            # Generate a unique hash for the file path
            hash_object = hashlib.md5(file_path.encode("utf-8"))
            file_hash = hash_object.hexdigest()

            # Generate the JSONL object for the document
            jsonl_object = generate_jsonl_from_message(event, file_hash)

            if not jsonl_object:
                 logger.error(f"Failed to generate JSONL object for file: {file_path}")
                 return

            # Upload the JSONL object to Cloud Storage
            storage_client = storage.Client()
            bucket = storage_client.bucket(METADATA_BUCKET)
            folder_name = "jsonl-metadata"
            file_name = f"{file_hash}.jsonl"
            blob = bucket.blob(f"{folder_name}/{file_name}")
            blob.upload_from_string(json.dumps(jsonl_object))

            # Construct the GCS path of the uploaded JSONL file
            gs_path = f"gs://{bucket.name}/{blob.name}"
            logger.info(f"JSONL file uploaded to: {gs_path}")

            # Import the document into Discovery Engine
            logger.info("Refreshing the datastore.")
            import_status = import_documents_to_discovery_engine(
                data_store_id=DATA_STORE_ID, project_id=PROJECT_ID, gcs_uri=gs_path
            )
            logger.info(f"Import status: {import_status}")

        else:
            logger.info("No data in the Pub/Sub message.")

    except Exception as e:
        logger.error(f"Error processing message: {e}")


# --- Code for Local Testing ---
if __name__ == "__main__":
    # Sample Pub/Sub message data for local testing
    LEASE_BUCKET_NAME = "<LEASE_BUCKET_NAME>"  # Update with your bucket name (should be similar to the lease bucket name in storage.tf)
    LEASE_BUCKET_PREFIX = "<LEASE_BUCKET_PREFIX>"  # Update with your bucket prefix (should be similar to the target path prefix in terraform.tfvars)
    LEASE_PDF_FILE_NAME = (
        "Ontario_Standard_Lease_2021_Kylan_Ryan.pdf"  # Example lease file name. Samples are available in assets/sample_lease_pdfs folder.
    )
    test_message = {
        "data": base64.b64encode(
            json.dumps(
                {
                    "city": "Test City",
                    "street": "123 Main St",
                    "province": "Test Province",
                    "postalcode": "A1B 2C3",
                    "lease_start_date": "2024-01-01",
                    "lease_end_date": "2025-01-01",
                    "rent": 2500,
                    "document_language": "English",
                    "file_path": f"gs://{LEASE_BUCKET_NAME}/{LEASE_BUCKET_PREFIX}/{LEASE_PDF_FILE_NAME}",
                }
            ).encode("utf-8")
        ).decode("utf-8")
    }

    # Call the Cloud Function locally
    refresh_datastore_document(test_message, None)