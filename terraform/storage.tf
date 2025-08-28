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

data "google_storage_bucket" "lease_pdf_bucket" {
  name = var.unstructured_data_bucket_name
  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation
  ]
}

data "google_storage_bucket" "unstructured_data_bucket" {
  name = var.unstructured_data_bucket_name
  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation
  ]
}

resource "google_storage_bucket" "metadata_bucket" {
  count = local.create_metadata_bucket ? 1 : 0
  
  name                         = local.metadata_bucket_name
  location                     = var.region
  uniform_bucket_level_access  = true
  force_destroy                = true
  
  lifecycle {
    ignore_changes = all
    prevent_destroy = true
  }
}

# Create the jsonl-metadata directory in the metadata bucket
resource "google_storage_bucket_object" "jsonl_metadata_directory" {
  count  = local.create_metadata_bucket ? 1 : 0
  
  name   = "jsonl-metadata/"
  bucket = local.metadata_bucket_name
  content = " "  # Empty content, just creates the folder structure
  
  depends_on = [
    google_storage_bucket.metadata_bucket
  ]
}

resource "google_storage_bucket" "function_code" {
  count = local.create_function_code_bucket ? 1 : 0
  
  name                        = local.function_code_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  
  lifecycle {
    ignore_changes = all
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_member" "function_code_admin" {
  bucket = local.function_code_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Add permission for Cloud Storage service account to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  topic  = google_pubsub_topic.upload_notification.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_notification" "notification" {
  bucket         = data.google_storage_bucket.unstructured_data_bucket.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.upload_notification.id
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

resource "google_storage_bucket_iam_member" "notification_permissions" {
  bucket = data.google_storage_bucket.unstructured_data_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}



