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

echo "Deploying ${SERVICE_NAME} using ${IMAGE_NAME}"
gcloud run deploy ${SERVICE_NAME} \
    --image ${IMAGE_NAME} \
    --no-allow-unauthenticated \
    --concurrency=50 \
    --min-instances=0 \
    --max-instances=1 \
    --platform=managed \
    --timeout=30s \
    --cpu=1 \
    --memory=512Mi \
    --region=${REGION} \
    --project=${PROJECT_ID}