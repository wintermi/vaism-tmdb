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
  source      = "terraform-google-modules/project-factory/google//modules/project_services"
  version     = "~> 17.0"
  project_id  = var.project_id
  enable_apis = var.enable_apis

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

#--------------------------------------------------------------------------------------------------
# Service Accounts
#--------------------------------------------------------------------------------------------------
module "cloudrun_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = module.project_services.project_id
  name         = "sa-cloudrun-${var.deployment_name}"
  display_name = "Service Account for Cloud Run"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${module.project_services.project_id}" = [
      "roles/secretmanager.secretAccessor",
    ]
  }
}

module "cloudbuild_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = module.project_services.project_id
  name         = "sa-cloudbuild-${var.deployment_name}"
  display_name = "Service Account for Cloud Build"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${module.project_services.project_id}" = [
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
  project_id  = module.project_services.project_id
  location    = var.region
  name        = var.vaism_tmdb_repository_id
  description = "VAIS:M TMDB Artifact Registry Repository"
  format      = { docker = { standard = {} } }
}

#--------------------------------------------------------------------------------------------------
# Secret Manager
#--------------------------------------------------------------------------------------------------
module "vaism_tmdb_secret_manager" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/secret-manager?ref=v35.0.0&depth=1"
  project_id = module.project_services.project_id
  secrets = {
    TMDB_API_TOKEN = {}
  }
  versions = {
    TMDB_API_TOKEN = {
      v1 = { enabled = true, data = var.tmdb_api_token_value }
    }
  }
}

#--------------------------------------------------------------------------------------------------
# Cloud Storage Buckets
#--------------------------------------------------------------------------------------------------
module "cloudbuild_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v35.0.0&depth=1"
  project_id    = module.project_services.project_id
  location      = var.region
  prefix        = var.deployment_name
  name          = "cloudbuild"
  force_destroy = true
  storage_class = "STANDARD"
  versioning    = false

  uniform_bucket_level_access = true
}

module "backfill_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v35.0.0&depth=1"
  project_id    = module.project_services.project_id
  location      = var.region
  prefix        = var.deployment_name
  name          = "backfill"
  force_destroy = true
  storage_class = "STANDARD"
  versioning    = false

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
      "--project '${module.project_services.project_id}'",
      "--service-account '${module.cloudbuild_service_account.id}'",
      "--gcs-log-dir '${module.cloudbuild_bucket.url}/logs'",
      "--gcs-source-staging-dir '${module.cloudbuild_bucket.url}/source'",
    ]
  )

  module_depends_on = [module.cloudbuild_service_account]
}

#--------------------------------------------------------------------------------------------------
# Deploy the Cloud Run Job - Backfill TMDB
#--------------------------------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "backfill_tmdb" {
  provider            = google-beta
  project             = module.project_services.project_id
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
              secret  = "TMDB_API_TOKEN"
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
          bucket = module.backfill_bucket.name
        }
      }
      service_account = module.cloudrun_service_account.email
      max_retries     = 1
    }
  }

  depends_on = [module.build_backfill_tmdb.wait]
}
