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

# Create ZIP archive of function code
data "archive_file" "metadata_generator_function" {
  type        = "zip"
  source_dir  = "${path.root}/cloud-functions/metadata-generator"
  output_path = "${path.root}/tmp/metadata-generator-source.zip"
}

# Upload ZIP to GCS
resource "google_storage_bucket_object" "metadata_generator_function_source" {
  name   = "source-${var.metadata_generator_function_name}.zip"
  bucket = local.function_code_bucket_name
  source = data.archive_file.metadata_generator_function.output_path
}

resource "google_cloudfunctions2_function" "metadata_generator" {
  name        = "metadata-generator"
  location    = var.region
  description = "Metadata generator function"

  build_config {
    runtime     = "python310"
    entry_point = "process_pubsub_message"
    source {
      storage_source {
        bucket = local.function_code_bucket_name
        object = google_storage_bucket_object.metadata_generator_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "2Gi"
    service_account_email          = google_service_account.pubsub_service_account.email
    all_traffic_on_latest_revision = true
    timeout_seconds    = 540
    environment_variables = {
      PROJECT_ID                  = var.project_id
      VERTEX_AI_LOCATION          = var.vertex_ai_location
      DB_FIRESTORE_NAME           = var.firestore_db_name
      TARGET_PATH_PREFIX          = var.auto_process_path_prefix
      REVIEW_TARGET_PATH_PREFIX   = var.review_path_prefix
      FIRESTORE_COLLECTION_NAME   = var.firestore_collection_name
      FILE_UPLOAD_TOPIC_ID        = google_pubsub_topic.upload_notification.name
      UPDATE_DATASTORE_TOPIC_ID   = var.update_datastore_topic_id
      GEMINI_MODEL_NAME           = var.gemini_model_name
      OVERWRITE_EXISTING_METADATA = var.overwrite_existing_metadata
      METADATA_BUCKET             = local.metadata_bucket_name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.upload_notification.id
    retry_policy   = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pubsub_service_account.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.function_invoker,
    google_project_iam_member.datastore_user,
    google_project_iam_member.storage_viewer,
    google_project_iam_member.storage_creator,
    google_storage_bucket_iam_member.metadata_bucket_admin,
    google_project_iam_member.log_writer,
    google_firestore_database.metadata_db
  ]
}

# Add required Eventarc role if not already present
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.pubsub_service_account.email}"
}

# Archive lease datastore refresher source
data "archive_file" "refresher_function" {
  type        = "zip"
  source_dir  = "${path.root}/cloud-functions/datastore-refresher"
  output_path = "${path.root}/tmp/datastore-refresher.zip"
}

# Upload refresher function code to bucket
resource "google_storage_bucket_object" "refresher_function_source" {
  name   = "source-${var.datastore_refresher_function_name}.zip"
  bucket = local.function_code_bucket_name
  source = data.archive_file.refresher_function.output_path
}

# Create lease datastore refresher function
resource "google_cloudfunctions2_function" "datastore_refresher" {
  name        = "datastore-refresher"
  location    = var.region
  description = "Datastore refresher function"

  build_config {
    runtime     = "python310"
    entry_point = "refresh_datastore_document"
    source {
      storage_source {
        bucket = local.function_code_bucket_name
        object = google_storage_bucket_object.refresher_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "1Gi"
    timeout_seconds    = 540
    environment_variables = {
      PROJECT_ID                = var.project_id
      DB_FIRESTORE_NAME         = var.firestore_db_name
      FIRESTORE_COLLECTION_NAME = var.firestore_collection_name
      DATA_STORE_ID             = google_discovery_engine_data_store.unstructured_documents_data_store.data_store_id  # Updated reference
      METADATA_BUCKET           = local.metadata_bucket_name
    }
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    service_account_email          = google_service_account.pubsub_service_account.email
    all_traffic_on_latest_revision = true
  }

  # Force replacement when environment variables change
  lifecycle {
    replace_triggered_by = [
      google_discovery_engine_data_store.unstructured_documents_data_store.data_store_id
    ]
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.metadata_generation.id
    retry_policy   = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pubsub_service_account.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.function_invoker,
    google_project_iam_member.datastore_user,
    google_project_iam_member.storage_viewer,
    google_project_iam_member.storage_creator,
    google_storage_bucket_iam_member.metadata_bucket_admin,
    google_project_iam_member.log_writer,
    google_firestore_database.metadata_db,
    google_discovery_engine_data_store.unstructured_documents_data_store,
  ]
}

# Allow Pub/Sub to invoke the metadata generator function (Cloud Run approach)
# resource "google_cloud_run_service_iam_member" "metadata_generator_invoker" {
#   project  = var.project_id
#   location = var.region
#   service  = google_cloudfunctions2_function.metadata_generator.name
#   role     = "roles/run.invoker"
#   member   = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
# }

# Allow Pub/Sub to invoke the datastore refresher function (Cloud Run approach)
# resource "google_cloud_run_service_iam_member" "datastore_refresher_invoker" {
#   project  = var.project_id
#   location = var.region
#   service  = google_cloudfunctions2_function.datastore_refresher.name
#   role     = "roles/run.invoker"
#   member   = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
# }

# Additional IAM binding for run.routes.invoke specifically
# resource "google_cloud_run_service_iam_member" "metadata_generator_developer" {
#   project  = var.project_id
#   location = var.region
#   service  = google_cloudfunctions2_function.metadata_generator.name
#   role     = "roles/run.developer"
#   member   = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
# }

# resource "google_cloud_run_service_iam_member" "datastore_refresher_developer" {
#   project  = var.project_id
#   location = var.region
#   service  = google_cloudfunctions2_function.datastore_refresher.name
#   role     = "roles/run.developer"
#   member   = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
# }