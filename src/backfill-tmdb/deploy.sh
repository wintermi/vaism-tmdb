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

echo "Deleting the Cloud Run Job if it exists"
gcloud beta run jobs delete ${SERVICE_NAME} \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --quiet

echo "Deploying Cloud Run Job ${SERVICE_NAME} using ${IMAGE_NAME}"
gcloud beta run jobs create ${SERVICE_NAME} \
    --image "${IMAGE_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}" \
    --service-account "${CLOUDRUN_SERVICE_ACCOUNT}" \
    --tasks 1 \
    --max-retries 1 \
    --set-env-vars BUCKET_MOUNT_PATH=/mnt/bucket/${SERVICE_NAME} \
    --set-env-vars EXPORT_DATE="" \
    --set-env-vars PUBSUB_PROJECT_ID="${PROJECT_ID}" \
    --set-env-vars PUBSUB_TOPIC_ID="${PUBSUB_TOPIC_ID}" \
    --set-secrets API_KEY=TMDB_API_TOKEN:latest \
    --add-volume name=bucket,type=cloud-storage,bucket=${BACKFILL_BUCKET} \
    --add-volume-mount volume=bucket,mount-path=/mnt/bucket \
    --cpu 2 \
    --memory 2Gi
