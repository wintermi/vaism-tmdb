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

module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 17.0"

  project_id                  = var.project_id
  enable_apis                 = var.enable_apis
  disable_services_on_destroy = false

  activate_apis = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

data "google_project" "project" {
  project_id = module.project_services.project_id
}

#--------------------------------------------------------------------------------------------------
# Service Accounts
#--------------------------------------------------------------------------------------------------
module "cloudrun_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = var.project_id
  name         = "sa-cloudrun-${var.deployment_name}"
  display_name = "Service Account for Cloud Run"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${var.project_id}" = [
      "roles/secretmanager.secretAccessor",
    ]
  }
}

module "cloudbuild_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = var.project_id
  name         = "sa-cloudbuild-${var.deployment_name}"
  display_name = "Service Account for Cloud Build"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${var.project_id}" = [
      "roles/storage.admin",
      "roles/artifactregistry.writer",
    ]
  }
}

#--------------------------------------------------------------------------------------------------
# Artifact Registry
#--------------------------------------------------------------------------------------------------
module "vaism_tmdb_artifact_registry" {
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v35.0.0&depth=1"
  project_id  = var.project_id
  location    = var.region
  name        = var.vaism_tmdb_repository_id
  description = "VAIS:M TMDB Artifact Registry Repository"
  format      = { docker = { standard = {} } }
}

#--------------------------------------------------------------------------------------------------
# Secret Manager
#--------------------------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tmdb_api_token_secret" {
  provider  = google
  project   = data.google_project.project.project_id
  secret_id = var.tmdb_api_token

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "tmdb_api_token_secret_version" {
  provider = google
  secret   = google_secret_manager_secret.tmdb_api_token_secret.id

  secret_data = var.tmdb_api_token_value
}

#--------------------------------------------------------------------------------------------------
# Create Cloud Build Storage Bucket for Logs and Source
#--------------------------------------------------------------------------------------------------
resource "google_storage_bucket" "cloudbuild_bucket" {
  provider      = google
  project       = data.google_project.project.project_id
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
  provider      = google
  project       = data.google_project.project.project_id
  name          = "${var.deployment_name}-backfill"
  location      = var.region
  force_destroy = true
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
}

#--------------------------------------------------------------------------------------------------
# Execute the Cloud Build - Backfill TMDB
#--------------------------------------------------------------------------------------------------
module "build_backfill_tmdb" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.5.0"

  platform = var.gcloud_platform

  create_cmd_entrypoint = "gcloud"
  create_cmd_body = join(" ",
    [
      "builds submit ./src/backfill-tmdb",
      "--tag '${module.vaism_tmdb_artifact_registry.url}/backfill-tmdb'",
      "--region '${var.region}'",
      "--project '${data.google_project.project.project_id}'",
      "--service-account '${module.cloudbuild_service_account.id}'",
      "--gcs-log-dir 'gs://${google_storage_bucket.cloudbuild_bucket.name}/logs'",
      "--gcs-source-staging-dir 'gs://${google_storage_bucket.cloudbuild_bucket.name}/source'",
    ]
  )

  module_depends_on = [module.cloudbuild_service_account]
}

#--------------------------------------------------------------------------------------------------
# Deploy the Cloud Run Job - Backfill TMDB
#--------------------------------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "backfill_tmdb" {
  provider            = google-beta
  project             = data.google_project.project.project_id
  name                = "backfill-tmdb"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1
    template {
      containers {
        image = "${module.vaism_tmdb_artifact_registry.url}/backfill-tmdb"
        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }
        env {
          name  = "BUCKET_MOUNT_PATH"
          value = "/mnt/bucket/backfill-tmdb"
        }
        env {
          name  = "EXPORT_DATE"
          value = ""
        }
        env {
          name = "API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.tmdb_api_token_secret.secret_id
              version = "latest"
            }
          }
        }
        volume_mounts {
          name       = "bucket"
          mount_path = "/mnt/bucket"
        }
      }
      volumes {
        name = "bucket"
        gcs {
          bucket = google_storage_bucket.backfill_bucket.name
        }
      }
      service_account = module.cloudrun_service_account.email
      max_retries     = 1
    }
  }

  depends_on = [module.build_backfill_tmdb.wait]
}
