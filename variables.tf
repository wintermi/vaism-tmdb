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

variable "project_id" {
  type        = string
  description = "The Google Cloud Project ID to deploy to"
}

variable "region" {
  type        = string
  description = "The Google Cloud Compute Region to deploy to"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The Google Cloud Compute Zone to deploy to"
  default     = "us-central1-a"
}

variable "deployment_name" {
  type        = string
  description = "The name of this particular deployment, will get added as a prefix to most resources."
  default     = "vaism-tmdb"
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to contained resources."
  default     = { "vaism-tmdb" = true }
}

variable "enable_apis" {
  type        = string
  description = "Whether or not to enable underlying apis in this solution. ."
  default     = true
}

variable "vaism_tmdb_repository_id" {
  type        = string
  description = "ID of Artifact Registry Repository"
  default     = "vaism-tmdb"
}

variable "tmdb_api_token_value" {
  type        = string
  description = "Value of TMDB API Token Secret"
  default     = "SECRET_VALUE"
}

variable "gcloud_platform" {
  type        = string
  description = "Platform 'gcloud' will run on. Defaults to linux. Valid values: linux, darwin"
  default     = "linux"
}

variable "tmdb_data_topic" {
  type        = string
  description = "The name of the Pub/Sub topic that 'get-tmdb-data' will publish to"
  default     = "tmdb-data"
}

variable "tmdb_data_schema" {
  type        = string
  description = "The Pub/Sub topic schema that 'get-tmdb-data' will publish to, encoded in BASE64"
  default     = ""
}

variable "api_endpoint_list" {
  type        = string
  description = "The list of TMDB API endpoints that 'get-tmdb-data' will call, encoded in BASE64"
  default     = ""
}
