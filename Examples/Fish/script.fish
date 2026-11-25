#!/usr/bin/env fish
# Requires: fish 3+, curl, jq

set base_url "https://ironbrew1.com"
set api_key "IB1-APIKEYHERE"

set input_path input.lua
set output_path output.lua

set query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

set retry_delay 5
set max_wait 240
set max_fails 3

function fail
    echo $argv >&2
    exit 1
end

set queue_response (curl -sS --fail-with-body -X POST "$base_url/obfuscate?$query" \
    -H "Key: $api_key" -H "Content-Type: text/plain" --data-binary "@$input_path")
or fail "Unable to queue obfuscation: $queue_response"

set status_url (echo $queue_response | jq -r .statusUrl)
echo "Obfuscation started with GUID: "(echo $queue_response | jq -r .uploadGuid)

set elapsed 0
set fails 0
set wait 0

while true
    set wait (math $wait + $retry_delay)
    sleep $wait
    set elapsed (math $elapsed + $wait)

    set status_response (curl -sS --fail-with-body "$base_url$status_url" -H "Key: $api_key")
    if test $status -ne 0
        set fails (math $fails + 1)
        echo "Status check failed ($fails/$max_fails)"
        if test $fails -ge $max_fails -o $elapsed -ge $max_wait
            fail "Obfuscation failed (fails: $fails | elapsed time: $elapsed)"
        end
        continue
    end

    set state (echo $status_response | jq -r .status)

    if test "$state" = completed
        echo "Obfuscation completed in $elapsed seconds"
        curl -sS --fail-with-body "$base_url"(echo $status_response | jq -r .downloadUrl) -H "Key: $api_key" -o $output_path
        or fail "Download failed"
        echo "Saved obfuscated script to $output_path"
        break
    end

    if test "$state" = failed -o $elapsed -ge $max_wait
        fail "Obfuscation failed (status: $state | elapsed time: $elapsed)"
    end

    echo "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in "(math $retry_delay + $wait)" seconds."
end
