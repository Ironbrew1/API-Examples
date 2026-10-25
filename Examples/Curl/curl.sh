#!/usr/bin/env bash
# Requires: curl, jq
set -euo pipefail

BASE_URL="https://ironbrew1.com"
API_KEY="IB1-APIKEYHERE"

INPUT_PATH="input.lua"
OUTPUT_PATH="output.lua"

PLATFORM="roblox"
AGGRESSIVE_OPTIMIZATIONS="0"
INTENSE_VM_SCRAMBLING="false"
ENABLE_VM_COMPRESSION="false"

RETRY_DELAY=5
MAX_WAIT=240
MAX_FAILS=3

# Queue the obfuscation job
query="platform=$PLATFORM&aggressiveOptimizations=$AGGRESSIVE_OPTIMIZATIONS"
query="$query&intenseVmScrambling=$INTENSE_VM_SCRAMBLING&enableVmCompression=$ENABLE_VM_COMPRESSION"

queue_response=$(curl -sS --fail-with-body -X POST "$BASE_URL/obfuscate?$query" \
  -H "Key: $API_KEY" \
  -H "Content-Type: text/plain" \
  --data-binary "@$INPUT_PATH")

upload_guid=$(jq -r '.uploadGuid' <<<"$queue_response")
status_url=$(jq -r '.statusUrl' <<<"$queue_response")
echo "Obfuscation started with GUID: $upload_guid"

elapsed=0
fails=0
wait_time=0

while true; do
  wait_time=$((wait_time + RETRY_DELAY))
  sleep "$wait_time"
  elapsed=$((elapsed + wait_time))

  if ! status_response=$(curl -sS --fail-with-body "$BASE_URL$status_url" -H "Key: $API_KEY"); then
    fails=$((fails + 1))
    echo "Status check failed ($fails/$MAX_FAILS)" >&2
    if [ "$fails" -ge "$MAX_FAILS" ] || [ "$elapsed" -ge "$MAX_WAIT" ]; then
      echo "Obfuscation failed" >&2
      exit 1
    fi
    continue
  fi

  status=$(jq -r '.status' <<<"$status_response")

  if [ "$status" = "completed" ]; then
    download_url=$(jq -r '.downloadUrl' <<<"$status_response")
    curl -sS --fail-with-body "$BASE_URL$download_url" -H "Key: $API_KEY" -o "$OUTPUT_PATH"
    echo "Obfuscation completed in $elapsed seconds, saved to $OUTPUT_PATH"
    exit 0
  fi

  if [ "$status" = "failed" ] || [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "Obfuscation failed (status: $status | elapsed: $elapsed seconds)" >&2
    exit 1
  fi

  echo "Still in progress. Elapsed: $elapsed seconds. Checking again in $((wait_time + RETRY_DELAY)) seconds."
done
