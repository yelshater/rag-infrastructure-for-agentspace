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

resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "aiplatform.googleapis.com",
    "discoveryengine.googleapis.com" 
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
  disable_dependent_services = false
}

# Add a delay after enabling APIs to ensure they propagate
resource "time_sleep" "api_propagation" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

# Grant additional permissions to Cloud Build service account
resource "google_project_iam_member" "cloudbuild_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "cloudbuild_service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "cloudbuild_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}
