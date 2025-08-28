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

# Create Pub/Sub service account
resource "google_service_account" "pubsub_service_account" {
  account_id   = "pub-sub-service-account"
  display_name = "Pub/Sub Service Account"

  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_propagation,
    google_project_iam_member.cloudbuild_service_account_roles,
    google_project_iam_member.artifact_registry_reader,
    google_project_iam_member.cloudbuild_log_writer,
    google_project_iam_member.cloudbuild_run_admin,
    google_project_iam_member.compute_log_writer,
    google_firestore_database.metadata_db,
    google_project_iam_member.cloudbuild_act_as,
    google_project_iam_member.compute_storage_viewer,
    google_project_iam_member.compute_storage_admin
  ]
}

# Grant Vertex AI User role
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Cloud Function Invoker role
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Datastore User role
resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Storage Object Viewer role
resource "google_project_iam_member" "storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Storage Object Creator role
resource "google_project_iam_member" "storage_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Storage Admin role which includes objects.create and objects.delete to the metadata bucket
resource "google_storage_bucket_iam_member" "metadata_bucket_admin" {
  bucket = local.metadata_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant Log Writer role
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Add Discovery Engine roles for datastore refresher
resource "google_project_iam_member" "discovery_engine_viewer" {
  project = var.project_id
  role    = "roles/discoveryengine.viewer"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

resource "google_project_iam_member" "discovery_engine_admin" {
  project = var.project_id
  role    = "roles/discoveryengine.admin"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Grant permissions to Cloud Build service account
resource "google_project_iam_member" "cloudbuild_service_account_roles" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    time_sleep.api_propagation
  ]
}

# Grant the Cloud Build service account permission to deploy Cloud Run services (needed for Cloud Functions v2)
resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant Cloud Build service account permission to act as service accounts
resource "google_project_iam_member" "cloudbuild_act_as" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Ensure Cloud Build has logging permissions
resource "google_project_iam_member" "cloudbuild_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant permissions to Cloud Functions service agent
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:service-${var.project_number}@gcf-admin-robot.iam.gserviceaccount.com"

  depends_on = [
    time_sleep.api_propagation
  ]
}

# Grant logging permissions to the Compute Engine default service account
resource "google_project_iam_member" "compute_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant the Compute Engine default service account permissions to access Cloud Functions source buckets
resource "google_project_iam_member" "compute_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant Storage Admin role to Compute Engine service account to ensure it can access all buckets
resource "google_project_iam_member" "compute_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant Storage Object Viewer role to Compute Engine service account
resource "google_project_iam_member" "compute_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Add a check to see if the bucket exists before trying to set IAM policies
resource "null_resource" "check_gcf_bucket" {
  provisioner "local-exec" {
    command = "gsutil ls -b gs://gcf-v2-sources-${var.project_number}-${var.region} || echo 'Bucket does not exist yet'"
  }
}

# Use depends_on to ensure we don't try to set IAM on non-existent bucket
resource "google_storage_bucket_iam_member" "gcf_sources_access" {
  count = fileexists("/tmp/bucket_exists") ? 1 : 0
  
  bucket = "gcf-v2-sources-${var.project_number}-${var.region}"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  
  depends_on = [null_resource.check_gcf_bucket]
}

# Grant the Compute Engine service account permission to use the service account
resource "google_service_account_iam_member" "compute_service_account_user" {
  service_account_id = google_service_account.pubsub_service_account.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "cf_service_account_roles" {
  for_each = toset([
    "roles/artifactregistry.admin",
    "roles/cloudbuild.builds.builder",
    "roles/cloudfunctions.admin",
    "roles/iam.serviceAccountUser",
    "roles/run.admin",
    "roles/storage.admin"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:service-${var.project_number}@gcf-admin-robot.iam.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Keep these project-level permissions
resource "google_project_iam_member" "cloudbuild_artifact_admin_project" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "cf_artifact_admin_project" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:service-${var.project_number}@gcf-admin-robot.iam.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "compute_artifact_admin_project" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.api_propagation]
}

# Grant Cloud Functions Invoker role to Pub/Sub service account (for 1st gen functions)
resource "google_project_iam_member" "pubsub_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Grant Cloud Run Invoker role to Pub/Sub service account (for 2nd gen functions)
resource "google_project_iam_member" "pubsub_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Also grant Cloud Run Invoker to your custom service account
resource "google_project_iam_member" "custom_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Add specific run.routes.invoke permission for the Pub/Sub service account
resource "google_project_iam_member" "pubsub_run_routes_invoke" {
  project = var.project_id
  role    = "roles/run.developer"  # This includes run.routes.invoke
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}