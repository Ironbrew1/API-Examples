from pathlib import Path
from urllib.parse import urlencode
import sys
import time

import requests


BASE_URL = "https://ironbrew1.com"
API_KEY = "IB1-APIKEYHERE"

INPUT_PATH = Path("input.lua")
OUTPUT_PATH = Path("output.lua")

OPTIONS = {
    "platform": "roblox",
    "aggressiveOptimizations": "0",
    "intenseVmScrambling": "false",
    "enableVmCompression": "false",
}

RETRY_DELAY = 5
MAX_WAIT = 240
MAX_FAILS = 3


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


session = requests.Session()
session.headers["Key"] = API_KEY

queue_response = session.post(
    f"{BASE_URL}/obfuscate?{urlencode(OPTIONS)}",
    data=INPUT_PATH.read_bytes(),
    headers={"Content-Type": "text/plain"},
    timeout=120,
)
if not queue_response.ok:
    fail(f"Unable to queue obfuscation: {queue_response.status_code}")

queued = queue_response.json()
print(f"Obfuscation started with GUID: {queued['uploadGuid']}")

elapsed = 0
fails = 0
wait = 0

while True:
    wait += RETRY_DELAY
    time.sleep(wait)
    elapsed += wait

    status_response = session.get(f"{BASE_URL}{queued['statusUrl']}", timeout=120)
    if not status_response.ok:
        fails += 1
        print(f"Status check failed with status: {status_response.status_code} ({fails}/{MAX_FAILS})")
        if fails >= MAX_FAILS or elapsed >= MAX_WAIT:
            fail(f"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})")
        continue

    status = status_response.json()

    if status["status"] == "completed":
        print(f"Obfuscation completed in {elapsed} seconds")
        download_response = session.get(f"{BASE_URL}{status['downloadUrl']}", timeout=120)
        if not download_response.ok:
            fail(f"Download failed with status: {download_response.status_code}")
        OUTPUT_PATH.write_bytes(download_response.content)
        print(f"Saved obfuscated script to {OUTPUT_PATH}")
        break

    if status["status"] == "failed" or elapsed >= MAX_WAIT:
        fail(f"Obfuscation failed (status: {status['status']} | elapsed time: {elapsed})")

    print(f"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {wait + RETRY_DELAY} seconds.")
    