-- Run with Lune (https://lune-org.github.io/docs): lune run script.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local BASE_URL = "https://ironbrew1.com"
local API_KEY = "IB1-APIKEYHERE"

local INPUT_PATH = "input.lua"
local OUTPUT_PATH = "output.lua"

local QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

local RETRY_DELAY = 5
local MAX_WAIT = 240
local MAX_FAILS = 3

local function fail(message: string)
	warn(message)
	process.exit(1)
end

local function request(method: string, path: string, body: string?)
	return net.request({
		url = BASE_URL .. path,
		method = method,
		headers = { Key = API_KEY, ["Content-Type"] = "text/plain" },
		body = body,
	})
end

local queueResponse = request("POST", "/obfuscate?" .. QUERY, fs.readFile(INPUT_PATH))
if not queueResponse.ok then
	fail("Unable to queue obfuscation: " .. queueResponse.statusCode)
end

local queued = serde.decode("json", queueResponse.body)
print("Obfuscation started with GUID: " .. queued.uploadGuid)

local elapsed, fails, wait = 0, 0, 0

while true do
	wait += RETRY_DELAY
	task.wait(wait)
	elapsed += wait

	local statusResponse = request("GET", queued.statusUrl)
	if not statusResponse.ok then
		fails += 1
		print(`Status check failed with status: {statusResponse.statusCode} ({fails}/{MAX_FAILS})`)
		if fails >= MAX_FAILS or elapsed >= MAX_WAIT then
			fail(`Obfuscation failed (fails: {fails} | elapsed time: {elapsed})`)
		end
		continue
	end

	local status = serde.decode("json", statusResponse.body)

	if status.status == "completed" then
		print(`Obfuscation completed in {elapsed} seconds`)
		local download = request("GET", status.downloadUrl)
		if not download.ok then
			fail(`Download failed with status: {download.statusCode}`)
		end
		fs.writeFile(OUTPUT_PATH, download.body)
		print(`Saved obfuscated script to {OUTPUT_PATH}`)
		break
	end

	if status.status == "failed" or elapsed >= MAX_WAIT then
		fail(`Obfuscation failed (status: {status.status} | elapsed time: {elapsed})`)
	end

	print(`Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {RETRY_DELAY + wait} seconds.`)
end
