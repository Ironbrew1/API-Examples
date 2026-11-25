-- MoonScript (compiles to Lua). Run with: moon script.moon
-- Needs LuaSocket, LuaSec and dkjson (apt install lua-socket lua-sec lua-dkjson) plus moonscript (luarocks install moonscript).
https = require "ssl.https"
ltn12 = require "ltn12"
socket = require "socket"
json = require "dkjson"

base_url = "https://ironbrew1.com"
api_key = "IB1-APIKEYHERE"

input_path = "input.lua"
output_path = "output.lua"

query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

retry_delay = 5
max_wait = 240
max_fails = 3

fail = (message) ->
  io.stderr\write message, "\n"
  os.exit 1

ok = (code) -> code >= 200 and code < 300

read_file = (path) ->
  file = assert io.open path, "rb"
  data = file\read "a"
  file\close!
  data

-- Returns the HTTP status code (0 on transport errors) and the response body.
request = (method, path, body) ->
  chunks = {}
  headers = Key: api_key
  if body
    headers["Content-Type"] = "text/plain"
    headers["Content-Length"] = tostring #body
  _, code = https.request {
    url: base_url .. path
    :method
    :headers
    source: body and ltn12.source.string(body) or nil
    sink: ltn12.sink.table chunks
  }
  (type(code) == "number" and code or 0), table.concat chunks

code, body = request "POST", "/obfuscate?" .. query, read_file input_path
fail "Unable to queue obfuscation: #{code}" unless ok code
queued = json.decode body
print "Obfuscation started with GUID: #{queued.uploadGuid}"

elapsed, fails, wait = 0, 0, 0
while true
  wait += retry_delay
  socket.sleep wait
  elapsed += wait
  code, body = request "GET", queued.statusUrl
  if not ok code
    fails += 1
    print "Status check failed with status: #{code} (#{fails}/#{max_fails})"
    if fails >= max_fails or elapsed >= max_wait
      fail "Obfuscation failed (fails: #{fails} | elapsed time: #{elapsed})"
  else
    status = json.decode body
    if status.status == "completed"
      code, script = request "GET", status.downloadUrl
      print "Obfuscation completed in #{elapsed} seconds"
      fail "Download failed with status: #{code}" unless ok code
      out = assert io.open output_path, "wb"
      out\write script
      out\close!
      print "Saved obfuscated script to #{output_path}"
      break
    elseif status.status == "failed" or elapsed >= max_wait
      fail "Obfuscation failed (status: #{status.status} | elapsed time: #{elapsed})"
    else
      print "Obfuscation is still in progress. Elapsed time: #{elapsed} seconds. Checking again in #{retry_delay + wait} seconds."
