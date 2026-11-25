-- Standalone Lua 5.1-5.4. Needs LuaSocket, LuaSec and dkjson:

local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local json = require("dkjson")

local BASE_URL = "https://ironbrew1.com"
local API_KEY = "IB1-APIKEYHERE"

local INPUT_PATH = "input.lua"
local OUTPUT_PATH = "output.lua"

local QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

local RETRY_DELAY = 5
local MAX_WAIT = 240
local MAX_FAILS = 3

local function fail(message)
	io.stderr:write(message, "\n")
	os.exit(1)
end

local function readfile(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("a")
	file:close()
	return data
end

-- Returns the HTTP status code (0 on transport errors) and the response body.
local function request(method, path, body)
	local chunks = {}
	local headers = { Key = API_KEY }
	local source
	if body then
		headers["Content-Type"] = "text/plain"
		headers["Content-Length"] = tostring(#body)
		source = ltn12.source.string(body)
	end
	local _, code = https.request({
		url = BASE_URL .. path,
		method = method,
		headers = headers,
		source = source,
		sink = ltn12.sink.table(chunks),
	})
	return type(code) == "number" and code or 0, table.concat(chunks)
end

local function ok(code)
	return code >= 200 and code < 300
end

local code, body = request("POST", "/obfuscate?" .. QUERY, readfile(INPUT_PATH))
if not ok(code) then
	fail("Unable to queue obfuscation: " .. code)
end

local queued = json.decode(body)
print("Obfuscation started with GUID: " .. queued.uploadGuid)

local elapsed, fails, wait = 0, 0, 0

while true do
	wait = wait + RETRY_DELAY
	socket.sleep(wait)
	elapsed = elapsed + wait

	code, body = request("GET", queued.statusUrl)
	if not ok(code) then
		fails = fails + 1
		print(("Status check failed with status: %d (%d/%d)"):format(code, fails, MAX_FAILS))
		if fails >= MAX_FAILS or elapsed >= MAX_WAIT then
			fail(("Obfuscation failed (fails: %d | elapsed time: %d)"):format(fails, elapsed))
		end
		goto continue
	end

	do
		local status = json.decode(body)

		if status.status == "completed" then
			print(("Obfuscation completed in %d seconds"):format(elapsed))
			local downloadCode, script = request("GET", status.downloadUrl)
			if not ok(downloadCode) then
				fail("Download failed with status: " .. downloadCode)
			end
			local out = assert(io.open(OUTPUT_PATH, "wb"))
			out:write(script)
			out:close()
			print("Saved obfuscated script to " .. OUTPUT_PATH)
			break
		end

		if status.status == "failed" or elapsed >= MAX_WAIT then
			fail(("Obfuscation failed (status: %s | elapsed time: %d)"):format(tostring(status.status), elapsed))
		end

		print(("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds."):format(elapsed, RETRY_DELAY + wait))
	end

	::continue::
end
