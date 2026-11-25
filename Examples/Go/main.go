package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"
)

const (
	baseURL    = "https://ironbrew1.com"
	apiKey     = "IB1-APIKEYHERE"
	inputPath  = "input.lua"
	outputPath = "output.lua"

	retryDelay = 5
	maxWait    = 240
	maxFails   = 3
)

var options = url.Values{
	"platform":                {"roblox"},
	"aggressiveOptimizations": {"0"},
	"intenseVmScrambling":     {"false"},
	"enableVmCompression":     {"false"},
}

var client = &http.Client{Timeout: 120 * time.Second}

func do(method, target string, body []byte) (int, []byte, error) {
	req, err := http.NewRequest(method, target, bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Key", apiKey)
	if body != nil {
		req.Header.Set("Content-Type", "text/plain")
	}
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	return resp.StatusCode, data, err
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func main() {
	source, err := os.ReadFile(inputPath)
	if err != nil {
		fail("Unable to read %s: %v", inputPath, err)
	}

	code, data, err := do("POST", baseURL+"/obfuscate?"+options.Encode(), source)
	if err != nil {
		fail("Unable to queue obfuscation: %v", err)
	}
	if code/100 != 2 {
		fail("Unable to queue obfuscation: %d", code)
	}

	var queued struct {
		UploadGuid string `json:"uploadGuid"`
		StatusUrl  string `json:"statusUrl"`
	}
	if err := json.Unmarshal(data, &queued); err != nil {
		fail("Unable to decode JSON: %v", err)
	}
	fmt.Printf("Obfuscation started with GUID: %s\n", queued.UploadGuid)

	elapsed, fails, wait := 0, 0, 0

	for {
		wait += retryDelay
		time.Sleep(time.Duration(wait) * time.Second)
		elapsed += wait

		code, data, err := do("GET", baseURL+queued.StatusUrl, nil)
		if err != nil || code/100 != 2 {
			fails++
			fmt.Printf("Status check failed (%d/%d): status %d, error %v\n", fails, maxFails, code, err)
			if fails >= maxFails || elapsed >= maxWait {
				fail("Obfuscation failed (fails: %d | elapsed time: %d)", fails, elapsed)
			}
			continue
		}

		var status struct {
			Status      string `json:"status"`
			DownloadUrl string `json:"downloadUrl"`
		}
		if err := json.Unmarshal(data, &status); err != nil {
			fail("Unable to decode JSON: %v", err)
		}

		if status.Status == "completed" {
			fmt.Printf("Obfuscation completed in %d seconds\n", elapsed)
			code, data, err := do("GET", baseURL+status.DownloadUrl, nil)
			if err != nil || code/100 != 2 {
				fail("Download failed: status %d, error %v", code, err)
			}
			if err := os.WriteFile(outputPath, data, 0o644); err != nil {
				fail("Unable to write %s: %v", outputPath, err)
			}
			fmt.Printf("Saved obfuscated script to %s\n", outputPath)
			return
		}

		if status.Status == "failed" || elapsed >= maxWait {
			fail("Obfuscation failed (status: %s | elapsed time: %d)", status.Status, elapsed)
		}

		fmt.Printf("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n", elapsed, retryDelay+wait)
	}
}
