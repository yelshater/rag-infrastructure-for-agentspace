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

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  user_project_override = true 
}

# Simplified locals to avoid circular dependencies
locals {
  # Use simple flags based on your knowledge of what exists
  create_metadata_bucket = false      # Set to false since the bucket exists
  create_function_code_bucket = false  # Set to false since the bucket exists
  create_subscription = false         # Set to false since the subscription exists
  
  # Define bucket names directly
  function_code_bucket_name = "${var.project_id}-function-code"
  metadata_bucket_name = "${var.project_id}-lease-metadata"
}