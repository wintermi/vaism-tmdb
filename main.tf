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
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

#--------------------------------------------------------------------------------------------------
# Service Accounts
#--------------------------------------------------------------------------------------------------
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
      "roles/logging.logWriter",
    ]
  }
}

module "cloudrun_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = module.project_services.project_id
  name         = "sa-cloudrun-${var.deployment_name}"
  display_name = "Service Account for Cloud Run"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${module.project_services.project_id}" = [
      "roles/secretmanager.secretAccessor",
      "roles/storage.objectUser",
      "roles/pubsub.publisher",
    ]
  }
}

module "pubsub_service_account" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v35.0.0&depth=1"
  project_id   = module.project_services.project_id
  name         = "sa-pubsub-${var.deployment_name}"
  display_name = "Service Account for Pub/Sub"

  # non-authoritative roles granted *to* the service accounts on other resources
  iam_project_roles = {
    "${module.project_services.project_id}" = [
      "roles/bigquery.dataEditor",
      "roles/pubsub.editor",
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
module "cloudbuild_backfill_tmdb_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v35.0.0&depth=1"
  project_id    = module.project_services.project_id
  location      = var.region
  prefix        = var.deployment_name
  name          = "cloudbuild-backfill-tmdb"
  force_destroy = true
  storage_class = "STANDARD"
  versioning    = false

  uniform_bucket_level_access = true
}

module "cloudbuild_get_tmdb_data_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v35.0.0&depth=1"
  project_id    = module.project_services.project_id
  location      = var.region
  prefix        = var.deployment_name
  name          = "cloudbuild-get-tmdb-data"
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
# BigQuery Dataset
#--------------------------------------------------------------------------------------------------
module "tmdb_bigquery_dataset" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset?ref=v35.0.0&depth=1"
  project_id = module.project_services.project_id
  location   = var.region
  id         = "tmdb"
  options = {
    default_table_expiration_ms     = null
    default_partition_expiration_ms = null
    delete_contents_on_destroy      = false
    max_time_travel_hours           = 168 # (7 days)
    storage_billing_model           = "PHYSICAL"
  }
  tables = {
    tmdb_data = {
      friendly_name       = "TMDB Data"
      schema              = file("./src/bigquery-schema/tmdb-data-schema.json")
      deletion_protection = false
      options = {
        clustering = ["type", "response_type"]
      }
    }
  }
}

#--------------------------------------------------------------------------------------------------
# Pub/Sub Topics and Schemas
#--------------------------------------------------------------------------------------------------
module "tmdb_data_topic" {
  # TODO: Requires the Fabric FAST module to be updated to allow the service account email to be set for the BigQuery subscription
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/pubsub?ref=v35.0.0&depth=1"
  project_id = module.project_services.project_id
  name       = var.tmdb_data_topic

  message_retention_duration = "604800s" # (7 days)
  schema = {
    msg_encoding = "JSON"
    schema_type  = "AVRO"
    definition   = file("./src/get-tmdb-data/build/tmdb-data-topic-schema.json")
  }
  subscriptions = {
    tmdb-data = {
      bigquery = {
        table                 = "${module.tmdb_bigquery_dataset.tables["tmdb_data"].project}:${module.tmdb_bigquery_dataset.tables["tmdb_data"].dataset_id}.${module.tmdb_bigquery_dataset.tables["tmdb_data"].table_id}"
        use_table_schema      = true
        write_metadata        = false
        service_account_email = module.pubsub_service_account.email
      }
    }
  }

  depends_on = [module.tmdb_bigquery_dataset, module.pubsub_service_account]
}

#--------------------------------------------------------------------------------------------------
# Cloud Build - Backfill TMDB History
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
      "--gcs-log-dir '${module.cloudbuild_backfill_tmdb_bucket.url}/logs'",
      "--gcs-source-staging-dir '${module.cloudbuild_backfill_tmdb_bucket.url}/source'",
    ]
  )

  module_depends_on = [module.cloudbuild_service_account]
}

#--------------------------------------------------------------------------------------------------
# Cloud Build - Get TMDB Data
#--------------------------------------------------------------------------------------------------
module "build_get_tmdb_data" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.5.0"

  platform = var.gcloud_platform

  create_cmd_entrypoint = "gcloud"
  create_cmd_body = join(" ",
    [
      "builds submit ./src/get-tmdb-data",
      "--tag '${module.vaism_tmdb_artifact_registry.url}/get-tmdb-data'",
      "--region '${var.region}'",
      "--project '${module.project_services.project_id}'",
      "--service-account '${module.cloudbuild_service_account.id}'",
      "--gcs-log-dir '${module.cloudbuild_get_tmdb_data_bucket.url}/logs'",
      "--gcs-source-staging-dir '${module.cloudbuild_get_tmdb_data_bucket.url}/source'",
    ]
  )

  module_depends_on = [module.cloudbuild_service_account]
}

#--------------------------------------------------------------------------------------------------
# Deploy Cloud Run Job - Backfill TMDB History
#--------------------------------------------------------------------------------------------------
module "deploy_backfill_tmdb" {
  # TODO: Update to use the v36.0.0 release tag assuming it contains the PR submitted to fix the GCS attribute issue
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?depth=1"
  project_id = module.project_services.project_id
  region     = var.region
  name       = "backfill-tmdb"
  create_job = true

  containers = {
    backfill-tmdb = {
      image = "${module.vaism_tmdb_artifact_registry.url}/backfill-tmdb"
      resources = {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }
      env = {
        BUCKET_MOUNT_PATH = "/mnt/bucket/backfill-tmdb"
        EXPORT_DATE       = ""
      }
      env_from_key = {
        API_KEY = {
          secret  = module.vaism_tmdb_secret_manager.secrets["TMDB_API_TOKEN"].name
          version = "latest"
        }
      }
      volume_mounts = {
        backfill-bucket = "/mnt/bucket"
      }
    }
  }
  volumes = {
    backfill-bucket = {
      gcs = {
        bucket       = module.backfill_bucket.name
        is_read_only = false
      }
    }
  }
  revision = {
    job = {
      max_retries = 1
      task_count  = 1
    }
    timeout = "3600s"
  }
  deletion_protection = false
  service_account     = module.cloudrun_service_account.email

  depends_on = [module.build_backfill_tmdb.wait, module.cloudrun_service_account, module.vaism_tmdb_secret_manager, module.backfill_bucket]
}

#--------------------------------------------------------------------------------------------------
# Deploy Cloud Run Service - Get TMDB Data
#--------------------------------------------------------------------------------------------------
module "deploy_get_tmdb_data" {
  # TODO: Update to use the v36.0.0 release tag assuming it contains the PR submitted to fix the GCS attribute issue
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?depth=1"
  project_id = module.project_services.project_id
  region     = var.region
  name       = "get-tmdb-data"

  containers = {
    get-tmdb-data = {
      image = "${module.vaism_tmdb_artifact_registry.url}/get-tmdb-data"
      ports = {
        HTTPS = {
          container_port = 8080
        }
      }
      resources = {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
        startup_cpu_boost = true
      }
      env = {
        PUBSUB_PROJECT_ID = module.project_services.project_id
        PUBSUB_TOPIC_ID   = var.tmdb_data_topic
      }
      env_from_key = {
        API_KEY = {
          secret  = module.vaism_tmdb_secret_manager.secrets["TMDB_API_TOKEN"].name
          version = "latest"
        }
      }
    }
  }
  revision = {
    max_concurrency = 60
    min_instances   = 0
    max_instances   = 4
    timeout         = "50s"
  }
  deletion_protection = false
  service_account     = module.cloudrun_service_account.email

  depends_on = [module.build_get_tmdb_data.wait, module.cloudrun_service_account, module.vaism_tmdb_secret_manager, module.tmdb_data_topic]
}
