from pathlib import Path
import os
import time
import uuid

import requests


BASE_URL = "https://ironbrew1.com"
API_KEY = "APIKEYHERE"

INPUT_PATH = Path("input.lua")
OUTPUT_PATH = Path("output.lua")

CLIENT_ID = "stable id here"

source = INPUT_PATH.read_bytes()

session = requests.Session()
session.headers.update({
    "Key": API_KEY,
    "X-IB1-Client-Id": CLIENT_ID,
})

params = {
    "fileName": OUTPUT_PATH.name,
    "platform": "roblox",
    "aggressiveOptimizations": "2",
    "intenseVmScrambling": "true",
    "enableVmCompression": "false",
}

queue_response = session.post(
    f"{BASE_URL}/queue",
    params=params,
    data=source,
    headers={
        "Content-Type": "text/plain",
        "Idempotency-Key": str(uuid.uuid4()),
    },
    timeout=60,
)
queue_response.raise_for_status()

upload = queue_response.json()
upload_guid = upload["uploadGuid"]

print(f"Queued obfuscation: {upload_guid}")

deadline = time.monotonic() + 900

while True:
    if time.monotonic() >= deadline:
        raise TimeoutError("Obfuscation did not finish within 15 minutes")

    status_response = session.get(
        f"{BASE_URL}/uploads/{upload_guid}",
        timeout=30,
    )
    status_response.raise_for_status()

    status_data = status_response.json()
    status = status_data["status"]

    print(f"Status: {status}")

    if status == "completed":
        break

    if status in {"failed", "timed_out"}:
        failure = status_data.get("failureCode") or status
        raise RuntimeError(f"Obfuscation failed: {failure}")

    try:
        retry_after = int(status_response.headers.get("Retry-After", "2"))
    except ValueError:
        retry_after = 2

    time.sleep(max(retry_after, 1))

download_response = session.get(
    f"{BASE_URL}/download-script/{upload_guid}",
    timeout=120,
)
download_response.raise_for_status()

OUTPUT_PATH.write_bytes(download_response.content)

print(f"Saved obfuscated script to {OUTPUT_PATH}")
