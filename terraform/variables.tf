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

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "project_number" {
  description = "The GCP project number"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "unstructured_data_bucket_name" {
  description = "The Cloud Storage bucket name for unstructured data files"
  type        = string
}

# variable "data_store_id" {
#   description = "The Datastore ID"
#   type        = string
# }

variable "metadata_generation_topic_id" {
  description = "The Pub/Sub topic ID for metadata generation"
  type        = string
}

variable "firestore_db_name" {
  description = "Firestore database name"
  type        = string
}

variable "auto_process_path_prefix" {
  description = "Target path prefix for documents that are not required to be reviewed"
  type        = string
}

variable "review_path_prefix" {
  description = "Target path prefix for documents that are required to be reviewed"
  type        = string
}

variable "firestore_collection_name" {
  description = "Firestore collection name"
  type        = string
}

variable "update_datastore_topic_id" {
  description = "Pub/Sub topic ID for updating the datastore"
  type        = string
}

variable "gemini_model_name" {
  description = "Gemini model name for metadata generation"
  type        = string
}

variable "vertex_ai_location" {
  description = "Vertex AI location for Gemini model"
  type        = string
  default     = "us-central1"
}

variable "overwrite_existing_metadata" {
  description = "Overwrite existing file metadata"
  type        = bool
  default     = false
}

variable "metadata_generator_function_name" {
  description = "Name of the metadata generator Cloud Function"
  type        = string
  default     = "metadata-generator"
}

variable "datastore_refresher_function_name" {
  description = "Name of the datastore refresher Cloud Function"
  type        = string
  default     = "datastore-refresher"
}

variable "discovery_engine_data_store_display_name" {
  description = "Display name for the Discovery Engine data store"
  type        = string
  default     = "Unstructured Documents Data Store"
}