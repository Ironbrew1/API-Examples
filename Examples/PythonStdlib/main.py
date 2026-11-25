"""Python example that only uses the standard library (no pip install needed)."""
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "https://ironbrew1.com"
API_KEY = "IB1-APIKEYHERE"

INPUT_PATH = Path("input.lua")
OUTPUT_PATH = Path("output.lua")

QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

RETRY_DELAY = 5
MAX_WAIT = 240
MAX_FAILS = 3


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def request(method, path, body=None):
    """Returns the HTTP status code and response body (status 0 on transport errors)."""
    # urllib's default User-Agent is rejected by the API, so send our own.
    headers = {"Key": API_KEY, "User-Agent": "ironbrew1-python-example"}
    if body is not None:
        headers["Content-Type"] = "text/plain"
    req = urllib.request.Request(BASE_URL + path, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except urllib.error.URLError:
        return 0, b""


def ok(code):
    return 200 <= code < 300


code, body = request("POST", f"/obfuscate?{QUERY}", INPUT_PATH.read_bytes())
if not ok(code):
    fail(f"Unable to queue obfuscation: {code}")

queued = json.loads(body)
print(f"Obfuscation started with GUID: {queued['uploadGuid']}")

elapsed = fails = wait = 0

while True:
    wait += RETRY_DELAY
    time.sleep(wait)
    elapsed += wait

    code, body = request("GET", queued["statusUrl"])
    if not ok(code):
        fails += 1
        print(f"Status check failed with status: {code} ({fails}/{MAX_FAILS})")
        if fails >= MAX_FAILS or elapsed >= MAX_WAIT:
            fail(f"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})")
        continue

    status = json.loads(body)

    if status["status"] == "completed":
        print(f"Obfuscation completed in {elapsed} seconds")
        code, script = request("GET", status["downloadUrl"])
        if not ok(code):
            fail(f"Download failed with status: {code}")
        OUTPUT_PATH.write_bytes(script)
        print(f"Saved obfuscated script to {OUTPUT_PATH}")
        break

    if status["status"] == "failed" or elapsed >= MAX_WAIT:
        fail(f"Obfuscation failed (status: {status['status']} | elapsed time: {elapsed})")

    print(f"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {RETRY_DELAY + wait} seconds.")
