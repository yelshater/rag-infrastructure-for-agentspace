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

# Create Pub/Sub topics
resource "google_pubsub_topic" "upload_notification" {
  name = "upload-notification"
  
  lifecycle {
    ignore_changes = all
    prevent_destroy = false
  }

  depends_on = [
    google_project_service.required_apis
  ]
}

resource "google_pubsub_topic" "metadata_generation" {
  name = var.metadata_generation_topic_id
  
  lifecycle {
    ignore_changes = all
    prevent_destroy = false
  }
}

# Add this data source to check if subscription exists
data "google_pubsub_subscription" "existing_subscription" {
  name    = "upload-sub"
  project = var.project_id
  count   = 0  # Set to 0 initially to ignore errors if it doesn't exist
}

# Create subscription - only if it doesn't exist
resource "google_pubsub_subscription" "upload_sub" {
  count = local.create_subscription ? 1 : 0  # Use count instead of for_each
  
  name  = "upload-sub"
  topic = google_pubsub_topic.upload_notification.name
}

# Grant Pub/Sub Publisher permissions
resource "google_pubsub_topic_iam_member" "upload_notification_publisher" {
  topic  = google_pubsub_topic.upload_notification.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

resource "google_pubsub_topic_iam_member" "metadata_generation_publisher" {
  topic  = google_pubsub_topic.metadata_generation.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}
