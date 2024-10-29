# Copyright 2024, Matthew Winter
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

data "google_project" "project" {
  project_id = var.project_id
}

module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 17.0"

  project_id                  = data.google_project.project.project_id
  enable_apis                 = var.enable_apis
  disable_services_on_destroy = false

  activate_apis = [
    "serviceusage.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

#--------------------------------------------------------------------------------------------------
# Create Service Accounts
#--------------------------------------------------------------------------------------------------
resource "google_service_account" "cloudrun_service_account" {
  provider     = google-beta
  account_id   = "sa-cloudrun-${var.deployment_name}"
  display_name = "Service Account for Cloud Run"
}

resource "google_service_account" "cloudbuild_service_account" {
  provider     = google-beta
  account_id   = "sa-cloudbuild-${var.deployment_name}"
  display_name = "Service Account for Cloud Build"
}

#--------------------------------------------------------------------------------------------------
# Create IAM Roles
#--------------------------------------------------------------------------------------------------
resource "google_project_iam_member" "allrun" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
  ])
  project  = data.google_project.project.number
  role     = each.key
  member   = "serviceAccount:${google_service_account.cloudrun_service_account.email}"
}

resource "google_project_iam_member" "allbuild" {
  for_each = toset([
    "roles/storage.admin",
    "roles/artifactregistry.writer",
  ])
  project  = data.google_project.project.number
  role     = each.key
  member   = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}

#--------------------------------------------------------------------------------------------------
# Create Artifact Registry
#--------------------------------------------------------------------------------------------------
resource "google_artifact_registry_repository" "vaism_tmdb" {
  provider      = google-beta
  location      = var.region
  repository_id = var.vaism_tmdb_repository_id
  description   = "VAIS:M TMDB Artifact Registry Repository"
  format        = "DOCKER"
}

#--------------------------------------------------------------------------------------------------
# Create Secret Manager Secret
#--------------------------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tmdb_api_token_secret" {
  provider  = google-beta
  secret_id = var.tmdb_api_token

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "tmdb_api_token_secret_version" {
  provider = google-beta
  secret   = google_secret_manager_secret.tmdb_api_token_secret.id

  secret_data = var.tmdb_api_token_value
}

#--------------------------------------------------------------------------------------------------
# Create Cloud Build Storage Bucket for Logs and Source
#--------------------------------------------------------------------------------------------------
resource "google_storage_bucket" "cloudbuild_bucket" {
  provider      = google-beta
  name          = "${var.deployment_name}-cloudbuild"
  location      = var.region
  force_destroy = true
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
}

#--------------------------------------------------------------------------------------------------
# Create Storage Bucket for the Backfill Service
#--------------------------------------------------------------------------------------------------
resource "google_storage_bucket" "backfill_bucket" {
  provider      = google-beta
  name          = "${var.deployment_name}-backfill"
  location      = var.region
  force_destroy = true
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
}

#--------------------------------------------------------------------------------------------------
# Execute the Cloud Build
#--------------------------------------------------------------------------------------------------
module "cli" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.5.0"

  platform              = var.gcloud_platform
  additional_components = ["beta"]

  create_cmd_body = join(" ",
    [
        "builds submit ./src/backfill-tmdb",
        "--tag='${var.region}-docker.pkg.dev/${var.project_id}/${var.vaism_tmdb_repository_id}/backfill-tmdb'",
        "--region='${var.region}'",
        "--project='${var.project_id}'",
        "--service-account='${google_service_account.cloudbuild_service_account.id}'",
        "--gcs-log-dir='gs://${google_storage_bucket.cloudbuild_bucket.name}/logs'",
        "--gcs-source-staging-dir='gs://${google_storage_bucket.cloudbuild_bucket.name}/source'",
    ]
  )
}
