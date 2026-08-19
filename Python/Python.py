from pathlib import Path
import time
import uuid

import requests

BASE_URL = "https://ironbrew1.com"
API_KEY = "APIKEYHERE"

INPUT_PATH = "input.lua"
OUTPUT_PATH = "output.lua"

PLATFORM = "luau"
AGGRESSIVE_OPTIMIZATIONS = 2
INTENSE_VM_SCRAMBLING = True
ANTI_TAMPER = False
ENABLE_VM_COMPRESSION = False

source = Path(INPUT_PATH).read_bytes()

session = requests.Session()
session.headers.update({
    "Key": API_KEY
})

params = {
    "fileName": Path(OUTPUT_PATH).name,
    "platform": PLATFORM,
    "aggressiveOptimizations": AGGRESSIVE_OPTIMIZATIONS,
    "intenseVmScrambling": INTENSE_VM_SCRAMBLING,
    "antiTamper": ANTI_TAMPER,
    "enableVmCompression": ENABLE_VM_COMPRESSION,
}

queue_res = session.post(
    f"{BASE_URL}/queue",
    params=params,
    data=source,
    headers={
        "Content-Type": "text/plain",
        "Idempotency-Key": str(uuid.uuid4()),
    },
    timeout=60,
)
queue_res.raise_for_status()

upload = queue_res.json()
upload_guid = upload["uploadGuid"]

print(f"Queued obfuscation: {upload_guid}")

deadline = time.monotonic() + 900

while True:
    if time.monotonic() >= deadline:
        raise TimeoutError("Obfuscation did not finish within 15 minutes")

    status_res = session.get(
        f"{BASE_URL}/uploads/{upload_guid}",
        timeout=30,
    )
    status_res.raise_for_status()

    status_data = status_res.json()
    status = status_data["status"]

    print(f"Status: {status}")

    if status == "completed":
        break

    if status in ("failed", "timed_out"):
        failure = status_data.get("failureCode") or status
        raise RuntimeError(f"Obfuscation failed: {failure}")

    retry_after = int(status_res.headers.get("Retry-After", "2"))
    time.sleep(max(retry_after, 1))

download_res = session.get(
    f"{BASE_URL}/download-script/{upload_guid}",
    timeout=120,
)
download_res.raise_for_status()

Path(OUTPUT_PATH).write_bytes(download_res.content)
print(f"Saved obfuscated script to {OUTPUT_PATH}")
