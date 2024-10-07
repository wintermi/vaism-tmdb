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

output "cloudrun_service_account" {
  value       = google_service_account.cloudrun_service_account.id
  description = "Output Cloud Run Service Account ID"
}

output "cloudbuild_service_account" {
  value       = google_service_account.cloudbuild_service_account.id
  description = "Output Cloud Build Service Account ID"
}

output "cloudbuild_storage_bucket" {
  value       = google_storage_bucket.cloudbuild_bucket.id
  description = "Output Cloud Build Storage Bucket ID"
}

output "artifact_registry_repository" {
  value       = google_artifact_registry_repository.vaism_tmdb.id
  description = "Output Artifact Registry Repository ID"
}
