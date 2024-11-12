// Copyright 2024, Matthew Winter
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/pubsub"
	"github.com/carlmjohnson/requests"
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	"github.com/linkedin/goavro"
)

// Cloud Run Service Configuration
type ServiceConfig struct {
	Port              int
	TimeoutSeconds    time.Duration
	APIKey            string
	APIEndpointList   map[string]map[string]string
	PubSubProjectID   string
	PubSubTopicID     string
	PubSubTopicSchema string
}

//---------------------------------------------------------------------------------------

// Initialise the Service
func init() {
	// Disable log prefixes such as the default timestamp.
	// Prefix text prevents the message from being parsed as JSON.
	// A timestamp is added when shipping logs to Cloud Logging.
	log.SetFlags(0)
}

//---------------------------------------------------------------------------------------

// Main Service
func main() {

	config := NewServiceConfig()
	PrintLogEntry(INFO, "Starting Export API Data Service...")
	PrintLogEntry(INFO, fmt.Sprintf("listening on port %d", config.Port))

	// Initialise the engine and define router API Endpoints
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	router.Use(gin.Recovery())
	apiv1 := router.Group("/api/v1")
	{
		apiv1.POST("/export", config.v1Export)
	}

	// Start listening and serve the API responses
	s := &http.Server{
		Addr:           fmt.Sprintf(":%d", config.Port),
		Handler:        router,
		ReadTimeout:    config.TimeoutSeconds,
		WriteTimeout:   config.TimeoutSeconds,
		MaxHeaderBytes: 1 << 20,
	}
	s.ListenAndServe()

	PrintLogEntry(INFO, "Ending Export API Data Service...")
}

//---------------------------------------------------------------------------------------

type PubSubMessage struct {
	Message struct {
		Data        string `json:"data"`
		MessageID   string `json:"message_id"`
		PublishTime string `json:"publish_time"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

//---------------------------------------------------------------------------------------

type ExportRequest struct {
	ID         int    `json:"id"`
	Type       string `json:"type"`
	ExportDate string `json:"export_date"`
}

type ExportResponse struct {
	ID                 int    `json:"id"`
	Type               string `json:"type"`
	ExportDate         string `json:"export_date"`
	ResponseType       string `json:"response_type"`
	ResponseJSONString string `json:"response_json_string"`
}

//---------------------------------------------------------------------------------------

// Get a New Service Configuration from Environment Variables
func NewServiceConfig() ServiceConfig {

	// Default the Port if not provided
	port, err := strconv.Atoi(os.Getenv("PORT"))
	if err != nil || port == 0 {
		port = 8080
	}

	// Default the Timeout if not provided
	timeout, err := strconv.Atoi(os.Getenv("CLOUD_RUN_TIMEOUT_SECONDS"))
	if err != nil || timeout == 0 {
		timeout = 10
	}

	// Attempt to Base64 Decode the API Endpoint List Environment Variable
	rawList, err := base64.StdEncoding.DecodeString(os.Getenv("API_ENDPOINT_LIST"))
	if err != nil {
		msg := fmt.Sprintf("Failed to Decode 'API_ENDPOINT_LIST' Base64 String: %v", err)
		PrintLogEntry(ERROR, msg)
		os.Exit(int(ERROR))
	}

	// Attempt to Bind the API Endpoint List JSON
	var apiEndpointList map[string]map[string]string
	err = json.Unmarshal(rawList, &apiEndpointList)
	if err != nil {
		msg := fmt.Sprintf("Failed to Bind 'API_ENDPOINT_LIST' JSON: %v", err)
		PrintLogEntry(ERROR, msg)
		os.Exit(int(ERROR))
	}

	return ServiceConfig{
		Port:              port,
		TimeoutSeconds:    time.Duration(timeout) * time.Second,
		APIKey:            os.Getenv("API_KEY"),
		APIEndpointList:   apiEndpointList,
		PubSubProjectID:   os.Getenv("PUBSUB_PROJECT_ID"),
		PubSubTopicID:     os.Getenv("PUBSUB_TOPIC_ID"),
		PubSubTopicSchema: os.Getenv("PUBSUB_TOPIC_SCHEMA"),
	}

}

//---------------------------------------------------------------------------------------

// Abort the request with an error message
func AbortWithError(c *gin.Context, code int, message string) {
	c.AbortWithStatusJSON(code, gin.H{
		"code":    code,
		"message": message,
	})
}

//---------------------------------------------------------------------------------------

// Publish the contents of the files to a Pub/Sub Topic
func (config *ServiceConfig) v1Export(c *gin.Context) {

	// Attempt to Bind the JSON Payload to a PubSubMessage instance
	var jsonData PubSubMessage
	if err := c.ShouldBindBodyWith(&jsonData, binding.JSON); err != nil {
		msg := fmt.Sprintf("Unable to Bind PubSubMessage JSON: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Attempt to Base64 Decode the 'message.data' attribute
	psMessage, err := base64.StdEncoding.DecodeString(jsonData.Message.Data)
	if err != nil {
		msg := fmt.Sprintf("Failed to Decode 'message.data' Base64 String: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Attempt to Bind the Pub/Sub Message JSON to an ExportRequest instance
	var request ExportRequest
	err = json.Unmarshal([]byte(psMessage), &request)
	if err != nil {
		msg := fmt.Sprintf("Unable to Bind ExportRequest JSON: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Retrieve the API Endpoint List for the Request Type
	list, ok := config.APIEndpointList[request.Type]
	if !ok {
		msg := fmt.Sprintf("Unable to Find the ExportRequest.Type in the API Endpoint List: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Setup the PubSub Client and Topic ready to publish messages to the given topic
	ctx := context.Background()
	psClient, err := pubsub.NewClient(ctx, config.PubSubProjectID)
	if err != nil {
		msg := fmt.Sprintf("Create Pub/Sub Client Failed: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}
	defer psClient.Close()
	psTopic := psClient.Topic(config.PubSubTopicID)

	// Decode the Topic Schema which is passed through as Base64
	rawSchema, err := base64.StdEncoding.DecodeString(config.PubSubTopicSchema)
	if err != nil {
		msg := fmt.Sprintf("Failed to Decode Topic Schema Base64 String: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Setup the AVRO Codec for the creation of the Pub/Sub Messages
	codec, err := goavro.NewCodec(string(rawSchema))
	if err != nil {
		msg := fmt.Sprintf("Failed to Create AVRO Codec: %v", err)
		PrintLogEntry(DEBUG, msg)
		AbortWithError(c, http.StatusBadRequest, msg)
		return
	}

	// Iterate through the API Endpoint List and Fetch Data
	var requestCount int = 0
	var avroMessages [][]byte
	for respType, endpoint := range list {
		url := strings.ReplaceAll(endpoint, "{id}", strconv.Itoa(request.ID))

		// Make the API Request
		var response string
		err := requests.
			URL(url).
			Bearer(config.APIKey).
			AddValidator(nil).
			ToString(&response).
			Fetch(context.Background())
		if err != nil {
			msg := fmt.Sprintf("API Request Failed: %v", err)
			PrintLogEntry(DEBUG, msg)
			AbortWithError(c, http.StatusBadRequest, msg)
			return
		}

		var exportResponse = ExportResponse{
			ID:                 request.ID,
			Type:               request.Type,
			ExportDate:         request.ExportDate,
			ResponseType:       respType,
			ResponseJSONString: response,
		}
		var datumRecord map[string]interface{}

		// Convert ExportResponse to JSON and then to the Datum Record
		exportResponseJSON, _ := json.Marshal(exportResponse)
		err = json.Unmarshal(exportResponseJSON, &datumRecord)
		if err != nil {
			msg := fmt.Sprintf("Failed to unmarshal ExportResponse JSON: %v", err)
			PrintLogEntry(DEBUG, msg)
			AbortWithError(c, http.StatusBadRequest, msg)
			return
		}

		// Convert ExportResponse using AVRO Schema to AVRO JSON format
		avroMessage, err := codec.TextualFromNative(nil, datumRecord)
		if err != nil {
			msg := fmt.Sprintf("Failed to create ExportResponse AVRO JSON message: %v", err)
			PrintLogEntry(DEBUG, msg)
			AbortWithError(c, http.StatusBadRequest, msg)
			return
		}

		avroMessages = append(avroMessages, avroMessage)
		requestCount++
	}

	// Iterate through the API Response and Publish to the Pub/Sub Topic
	var messageCount int = 0
	var psResults []*pubsub.PublishResult
	for _, avroMessage := range avroMessages {
		// Publish the messages and store the results for later processing
		psResults = append(psResults, psTopic.Publish(ctx, &pubsub.Message{Data: avroMessage}))
		messageCount++
	}

	// Check the Publish Results and count and report any failures
	var failureCount int = 0
	for _, result := range psResults {
		_, err = result.Get(ctx)
		if err != nil {
			failureCount++
		}
	}

	c.JSON(http.StatusOK, fmt.Sprintf("API Requests: %d, Messages Sent: %d, Failed Messages: %d", requestCount, messageCount, failureCount))

}
