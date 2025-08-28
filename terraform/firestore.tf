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

resource "time_sleep" "wait_db_cooldown" {
  create_duration = "4m"

  triggers = {
    database_name = var.firestore_db_name
  }
}

# Create or manage existing Firestore database
resource "google_firestore_database" "metadata_db" {
  project     = var.project_id
  name        = var.firestore_db_name
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      location_id,
      type
    ]
  }

  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation,
    time_sleep.wait_db_cooldown
  ]
}

# Additional IAM permissions for Firestore
resource "google_project_iam_member" "firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Create initial collections without indices
resource "google_firestore_document" "metadata_collection" {
  project     = var.project_id
  database    = google_firestore_database.metadata_db.name
  collection  = var.firestore_collection_name
  document_id = "_config"
  fields      = "{}"

  lifecycle {
    ignore_changes = all
    create_before_destroy = true
  }

  depends_on = [
    google_firestore_database.metadata_db
  ]
}
