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

URL="$(gcloud run services describe ${SERVICE_NAME} --platform managed --region ${REGION} --format 'value(status.url)')"

echo "Executing ${SERVICE_NAME} via POST to ${URL}"
curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -d '{"deliveryAttempt": 5,"message": {"data": "eyJ0eXBlIjoibW92aWUiLCJleHBvcnRfZGF0ZSI6IjIwMjQtMDctMDEiLCJpZCI6Nzg2ODkyfQ==","message_id": "2070443601311540","publish_time": "2021-02-26T19:13:55.749Z"},"subscription": "projects/myproject/subscriptions/mysubscription"}' \
    "${URL}/api/v1/export"
