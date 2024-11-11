#!/bin/bash

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

export PROJECT_ID="$(gcloud config get project)"
export REGION="${REGION:=us-central1}"

export SERVICE_NAME="backfill-tmdb"
export DEPLOYMENT_NAME="vaism-tmdb"
export IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${DEPLOYMENT_NAME}/${SERVICE_NAME}"

export CLOUDBUILD_SERVICE_ACCOUNT="projects/${PROJECT_ID}/serviceAccounts/sa-cloudbuild-${DEPLOYMENT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export CLOUDBUILD_BUCKET="${DEPLOYMENT_NAME}-cloudbuild-backfill-tmdb"

export CLOUDRUN_SERVICE_ACCOUNT="sa-cloudrun-${DEPLOYMENT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

export BACKFILL_BUCKET="${DEPLOYMENT_NAME}-backfill"
