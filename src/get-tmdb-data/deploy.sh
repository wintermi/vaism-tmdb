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

source ./config.sh

echo "Deploying Cloud Run Service ${SERVICE_NAME} using ${IMAGE_NAME}"
gcloud beta run deploy ${SERVICE_NAME} \
    --image "${IMAGE_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}" \
    --service-account "${CLOUDRUN_SERVICE_ACCOUNT}" \
    --no-allow-unauthenticated \
    --concurrency=60 \
    --min-instances=0 \
    --max-instances=4 \
    --platform=managed \
    --timeout=50s \
    --set-env-vars PUBSUB_PROJECT_ID="${PROJECT_ID}" \
    --set-env-vars PUBSUB_TOPIC_ID="${PUBSUB_TOPIC_ID}" \
    --set-secrets=API_KEY=TMDB_API_TOKEN:latest \
    --cpu=2 \
    --memory=1Gi
