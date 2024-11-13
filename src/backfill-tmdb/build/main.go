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
	"bytes"
	"compress/gzip"
	"context"
	_ "embed"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/carlmjohnson/requests"
)

// Cloud Run Job Configuration
type JobConfig struct {
	TaskNum         string
	AttemptNum      string
	BucketMountPath string
	ExportDate      time.Time
	PubSubProjectID string
	PubSubTopicID   string
	APIKey          string
	OutputPath      string
	DailyExports    []string
}

//go:embed tmdb-trigger-topic-schema.json
var TMDB_TRIGGER_TOPIC_SCHEMA string

//---------------------------------------------------------------------------------------

// Main Job Logic
func main() {

	config := NewJobConfig()
	log.Printf("Starting Task #%s, Attempt #%s", config.TaskNum, config.AttemptNum)
	log.Print("  - Get Daily ID Exports")

	if err := config.CreateOutputPath(); err != nil {
		log.Fatalf("Create Output Path Failed: %v", err)
	}

	if err := config.GetDailyExports(); err != nil {
		log.Fatalf("Get Daily ID Exports Failed: %v", err)
	}

	log.Printf("Completed Task #%s, Attempt #%s", config.TaskNum, config.AttemptNum)
}

//---------------------------------------------------------------------------------------

// Calculate the Export Date to use, allowing for it to be overridden
func getExportDate(exportDate string) time.Time {

	// If "Export Date" is populated attempt to parse the date. If unable to parse
	// resort to using the UTC current date logic
	if exportDate != "" {
		result, err := time.Parse("2006-01-02", exportDate)
		if err == nil {
			return result
		}
	}

	// UTC current date logic
	//     The export job runs every day starting at around 7:00 AM UTC,
	//     and all files are available by 8:00 AM UTC.
	var result = time.Now().UTC()
	if result.Hour() < 8 {
		result = result.Add(time.Duration(-24) * time.Hour)
	}

	return result
}

//---------------------------------------------------------------------------------------

// Get a New Job Configuration from Environment Variables
func NewJobConfig() JobConfig {

	return JobConfig{
		TaskNum:         os.Getenv("CLOUD_RUN_TASK_INDEX"),
		AttemptNum:      os.Getenv("CLOUD_RUN_TASK_ATTEMPT"),
		BucketMountPath: os.Getenv("BUCKET_MOUNT_PATH"),
		ExportDate:      getExportDate(os.Getenv("EXPORT_DATE")),
		PubSubProjectID: os.Getenv("PUBSUB_PROJECT_ID"),
		PubSubTopicID:   os.Getenv("PUBSUB_TOPIC_ID"),
		APIKey:          os.Getenv("API_KEY"),
		OutputPath:      "",
		DailyExports: []string{
			"movie_ids",
			"tv_series_ids",
			"person_ids",
			"collection_ids",
			"tv_network_ids",
			"keyword_ids",
			"production_company_ids",
		},
	}

}

//---------------------------------------------------------------------------------------

// Create the Output Path as a sub folder of the provided Bucket Mount Path
func (config *JobConfig) CreateOutputPath() error {

	// Calculate the Absolute Output Path
	path, err := filepath.Abs(filepath.Join(config.BucketMountPath, fmt.Sprintf("export_date=%s", config.ExportDate.Format("2006-01-02"))))
	if err != nil {
		return fmt.Errorf("Failed To Get Absolute Output Path: %w", err)
	}

	// Create the Output File Path and Store in the Config
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err = os.MkdirAll(path, 0700); err != nil {
			return fmt.Errorf("Failed to Create the Output File Path: %w", err)
		}
	}
	config.OutputPath = path

	return nil
}

//---------------------------------------------------------------------------------------

// Get The Movie DB Daily ID Exports
func (config *JobConfig) GetDailyExports() error {

	log.Print("Initiating Request to Get Daily ID Exports")

	// Iterate through All of the Entries
	for _, dailyExport := range config.DailyExports {

		log.Printf("Exporting: %s", dailyExport)

		// Make the Export API Request
		var response bytes.Buffer
		err := requests.
			URL("http://files.tmdb.org").
			Pathf("/p/exports/%s.gz", fmt.Sprintf("%s_%s.json", dailyExport, config.ExportDate.Format("01_02_2006"))).
			Bearer(config.APIKey).
			ToBytesBuffer(&response).
			Fetch(context.Background())
		if err != nil {
			return fmt.Errorf("TMDB Movie API Request Failed: %w", err)
		}

		// Decompress the response data
		gz, err := gzip.NewReader(&response)
		if err != nil {
			return fmt.Errorf("GZIP Decompress Failed: %w", err)
		}

		data, err := io.ReadAll(gz)
		if err != nil {
			return fmt.Errorf("Reading Response Body Failed: %w", err)
		}

		exportFile, _ := filepath.Abs(filepath.Join(config.OutputPath, fmt.Sprintf("%s.json", dailyExport)))
		err = os.WriteFile(exportFile, data, 0600)
		if err != nil {
			return fmt.Errorf("Writing Response to File Failed: %w", err)
		}
	}

	log.Print("Completed the Daily ID Exports")

	return nil
}
