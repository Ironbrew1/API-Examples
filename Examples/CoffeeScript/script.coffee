# Run with: npm install -g coffeescript && coffee script.coffee   (Node 18+, built-in fetch)
fs = require 'fs'

BASE_URL = 'https://ironbrew1.com'
API_KEY = 'IB1-APIKEYHERE'

INPUT_PATH = 'input.lua'
OUTPUT_PATH = 'output.lua'

OPTIONS =
  platform: 'roblox'
  aggressiveOptimizations: '0'
  intenseVmScrambling: 'false'
  enableVmCompression: 'false'

RETRY_DELAY = 5
MAX_WAIT = 240
MAX_FAILS = 3

sleep = (seconds) -> new Promise (resolve) -> setTimeout resolve, seconds * 1000

fail = (message) ->
  console.error message
  process.exit 1

main = ->
  queueResponse = await fetch "#{BASE_URL}/obfuscate?#{new URLSearchParams OPTIONS}",
    method: 'POST'
    headers: {Key: API_KEY, 'Content-Type': 'text/plain'}
    body: fs.readFileSync INPUT_PATH
  fail "Unable to queue obfuscation: #{queueResponse.status}" unless queueResponse.ok

  queued = await queueResponse.json()
  console.log "Obfuscation started with GUID: #{queued.uploadGuid}"

  elapsed = fails = wait = 0

  loop
    wait += RETRY_DELAY
    await sleep wait
    elapsed += wait

    statusResponse = await fetch BASE_URL + queued.statusUrl, headers: {Key: API_KEY}
    unless statusResponse.ok
      fails++
      console.log "Status check failed with status: #{statusResponse.status} (#{fails}/#{MAX_FAILS})"
      fail "Obfuscation failed (fails: #{fails} | elapsed time: #{elapsed})" if fails >= MAX_FAILS or elapsed >= MAX_WAIT
      continue

    status = await statusResponse.json()

    if status.status is 'completed'
      console.log "Obfuscation completed in #{elapsed} seconds"
      download = await fetch BASE_URL + status.downloadUrl, headers: {Key: API_KEY}
      fail "Download failed with status: #{download.status}" unless download.ok
      fs.writeFileSync OUTPUT_PATH, Buffer.from await download.arrayBuffer()
      console.log "Saved obfuscated script to #{OUTPUT_PATH}"
      return

    if status.status is 'failed' or elapsed >= MAX_WAIT
      fail "Obfuscation failed (status: #{status.status} | elapsed time: #{elapsed})"

    console.log "Obfuscation is still in progress. Elapsed time: #{elapsed} seconds. Checking again in #{RETRY_DELAY + wait} seconds."

main()
