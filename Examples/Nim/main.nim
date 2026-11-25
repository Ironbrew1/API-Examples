# Build and run: nim c -d:ssl -r main.nim
import std/[httpclient, json, os, strformat]

const
  BaseUrl = "https://ironbrew1.com"
  ApiKey = "IB1-APIKEYHERE"

  InputPath = "input.lua"
  OutputPath = "output.lua"

  Query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

  RetryDelay = 5
  MaxWait = 240
  MaxFails = 3

proc fail(message: string) =
  stderr.writeLine(message)
  quit(1)

let client = newHttpClient(timeout = 120_000)

proc request(httpMethod: HttpMethod, path: string, body = ""): tuple[code: int, body: string] =
  let headers = newHttpHeaders({"Key": ApiKey, "Content-Type": "text/plain"})
  let response = client.request(BaseUrl & path, httpMethod = httpMethod, headers = headers, body = body)
  (response.code.int, response.body)

proc ok(code: int): bool = code div 100 == 2

let (queueCode, queueBody) = request(HttpPost, "/obfuscate?" & Query, readFile(InputPath))
if not ok(queueCode):
  fail(&"Unable to queue obfuscation: {queueCode}")

let queued = parseJson(queueBody)
echo &"Obfuscation started with GUID: {queued[\"uploadGuid\"].getStr}"

var
  elapsed = 0
  fails = 0
  wait = 0

while true:
  wait += RetryDelay
  sleep(wait * 1000)
  elapsed += wait

  let (code, body) = request(HttpGet, queued["statusUrl"].getStr)
  if not ok(code):
    inc fails
    echo &"Status check failed with status: {code} ({fails}/{MaxFails})"
    if fails >= MaxFails or elapsed >= MaxWait:
      fail(&"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})")
    continue

  let status = parseJson(body)
  let state = status["status"].getStr

  if state == "completed":
    echo &"Obfuscation completed in {elapsed} seconds"
    let (downloadCode, script) = request(HttpGet, status["downloadUrl"].getStr)
    if not ok(downloadCode):
      fail(&"Download failed with status: {downloadCode}")
    writeFile(OutputPath, script)
    echo &"Saved obfuscated script to {OutputPath}"
    break

  if state == "failed" or elapsed >= MaxWait:
    fail(&"Obfuscation failed (status: {state} | elapsed time: {elapsed})")

  echo &"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {RetryDelay + wait} seconds."
