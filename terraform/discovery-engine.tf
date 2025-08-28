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

# Generate a random suffix for the data store ID to ensure uniqueness
resource "random_id" "data_store_suffix" {
  byte_length = 4
}

# Get project data for import command
data "google_project" "project" {
  project_id = var.project_id
}

# Create the Vertex AI Search Datastore for linked unstructured documents
resource "google_discovery_engine_data_store" "unstructured_documents_data_store" {
  project                      = var.project_id
  location                     = "global"
  data_store_id                = "unstructured-documents-${random_id.data_store_suffix.hex}"
  display_name                 = var.discovery_engine_data_store_display_name
  industry_vertical            = "GENERIC"
  content_config               = "NO_CONTENT"  # Key setting for linked unstructured documents
  solution_types               = ["SOLUTION_TYPE_SEARCH"]
  create_advanced_site_search  = false

  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation
  ]
}

# Grant Vertex AI Search service account access to read from your unstructured data bucket
resource "google_storage_bucket_iam_member" "datastore_gcs_viewer" {
  bucket = data.google_storage_bucket.unstructured_data_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-discoveryengine.iam.gserviceaccount.com"

  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation
  ]
}

# Import documents from GCS bucket to Discovery Engine datastore
# This creates the initial link between your GCS documents and the datastore
resource "null_resource" "import_documents" {
  depends_on = [
    google_discovery_engine_data_store.unstructured_documents_data_store,
    google_storage_bucket_iam_member.datastore_gcs_viewer
  ]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud alpha discovery-engine documents import \
        --project=${var.project_id} \
        --location=global \
        --data-store=${google_discovery_engine_data_store.unstructured_documents_data_store.data_store_id} \
        --gcs-source="gs://${var.unstructured_data_bucket_name}/*" \
        --format=document
    EOT
  }

  # Optional: Add a trigger to re-run import if bucket contents change significantly
  triggers = {
    datastore_id = google_discovery_engine_data_store.unstructured_documents_data_store.data_store_id
    bucket_name  = var.unstructured_data_bucket_name
  }
}

# Output the datastore information
output "discovery_engine_data_store_id" {
  description = "The ID of the Discovery Engine data store"
  value       = google_discovery_engine_data_store.unstructured_documents_data_store.data_store_id
}

output "discovery_engine_data_store_name" {
  description = "The full name of the Discovery Engine data store"
  value       = google_discovery_engine_data_store.unstructured_documents_data_store.name
}

output "datastore_gcs_service_account" {
  description = "The Vertex AI Search service account that needs GCS access"
  value       = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-discoveryengine.iam.gserviceaccount.com"
}

output "gcs_bucket_name" {
  description = "The name of the GCS bucket containing unstructured documents"
  value       = var.unstructured_data_bucket_name
}