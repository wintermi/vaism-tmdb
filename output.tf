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

output "cloudbuild_service_account" {
  value       = module.cloudbuild_service_account.id
  description = "Output Cloud Build Service Account ID"
}

output "cloudrun_service_account" {
  value       = module.cloudrun_service_account.id
  description = "Output Cloud Run Service Account ID"
}

output "pubsub_service_account" {
  value       = module.pubsub_service_account.id
  description = "Output Pub/Sub Service Account ID"
}

output "cloudbuild_backfill_tmdb_storage_bucket_url" {
  value       = module.cloudbuild_backfill_tmdb_bucket.url
  description = "Output Cloud Build Storage Bucket URL for Backfill TMDB"
}

output "cloudbuild_get_tmdb_data_storage_bucket_url" {
  value       = module.cloudbuild_get_tmdb_data_bucket.url
  description = "Output Cloud Build Storage Bucket URL for Get TMDB Data"
}

output "backfill_storage_bucket_url" {
  value       = module.backfill_bucket.url
  description = "Output Backfill Storage Bucket URL"
}

output "vaism_tmdb_artifact_registry_url" {
  value       = module.vaism_tmdb_artifact_registry.url
  description = "Output Artifact Registry Repository URL"
}

output "tmdb_trigger_pubsub_topic_id" {
  value       = module.tmdb_trigger_pubsub_topic.id
  description = "Output TMDB Trigger Pub/Sub Topic ID"
}

output "tmdb_data_pubsub_topic_id" {
  value       = module.tmdb_data_pubsub_topic.id
  description = "Output TMDB Data Pub/Sub Topic ID"
}
