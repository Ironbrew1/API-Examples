# Uses only the standard library (Downloads).
using Downloads

const BASE_URL = "https://ironbrew1.com"
const API_KEY = "IB1-APIKEYHERE"

const INPUT_PATH = "input.lua"
const OUTPUT_PATH = "output.lua"

const QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

const RETRY_DELAY = 5
const MAX_WAIT = 240
const MAX_FAILS = 3

function fail(message)
    println(stderr, message)
    exit(1)
end

# Pulls a string value out of a flat JSON object without needing a JSON library.
function field(json, name)
    m = match(Regex("\"$(name)\"\\s*:\\s*\"([^\"]*)\""), json)
    m === nothing ? nothing : replace(m.captures[1], "\\/" => "/")
end

function request(method, path; body = nothing)
    out = IOBuffer()
    headers = ["Key" => API_KEY]
    body === nothing || push!(headers, "Content-Type" => "text/plain")
    response = Downloads.request(BASE_URL * path; method, headers, throw = false,
        input = body === nothing ? nothing : IOBuffer(body), output = out)
    (response.status, take!(out))
end

ok(code) = 200 <= code < 300

code, body = request("POST", "/obfuscate?" * QUERY; body = read(INPUT_PATH))
ok(code) || fail("Unable to queue obfuscation: $code")

queued = String(body)
println("Obfuscation started with GUID: ", field(queued, "uploadGuid"))
status_url = field(queued, "statusUrl")

global elapsed = 0
global fails = 0
global wait = 0

while true
    global wait += RETRY_DELAY
    sleep(wait)
    global elapsed += wait

    code, body = request("GET", status_url)
    if !ok(code)
        global fails += 1
        println("Status check failed with status: $code ($fails/$MAX_FAILS)")
        (fails >= MAX_FAILS || elapsed >= MAX_WAIT) && fail("Obfuscation failed (fails: $fails | elapsed time: $elapsed)")
        continue
    end

    status = String(body)
    state = field(status, "status")

    if state == "completed"
        println("Obfuscation completed in $elapsed seconds")
        download_code, script = request("GET", field(status, "downloadUrl"))
        ok(download_code) || fail("Download failed with status: $download_code")
        write(OUTPUT_PATH, script)
        println("Saved obfuscated script to $OUTPUT_PATH")
        break
    end

    if state == "failed" || elapsed >= MAX_WAIT
        fail("Obfuscation failed (status: $state | elapsed time: $elapsed)")
    end

    println("Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in $(RETRY_DELAY + wait) seconds.")
end
