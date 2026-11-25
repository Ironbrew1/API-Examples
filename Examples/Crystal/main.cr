# Run with: crystal run main.cr
require "http/client"
require "json"

BASE_URL = "https://ironbrew1.com"
API_KEY  = "IB1-APIKEYHERE"

INPUT_PATH  = "input.lua"
OUTPUT_PATH = "output.lua"

QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

RETRY_DELAY = 5
MAX_WAIT    = 240
MAX_FAILS   = 3

def fail(message : String)
  STDERR.puts message
  exit 1
end

def request(method : String, path : String, body : String? = nil)
  headers = HTTP::Headers{"Key" => API_KEY}
  headers["Content-Type"] = "text/plain" if body
  HTTP::Client.exec(method, BASE_URL + path, headers: headers, body: body)
end

queue_response = request("POST", "/obfuscate?#{QUERY}", File.read(INPUT_PATH))
fail "Unable to queue obfuscation: #{queue_response.status_code}" unless queue_response.success?

queued = JSON.parse(queue_response.body)
puts "Obfuscation started with GUID: #{queued["uploadGuid"]}"

elapsed = 0
fails = 0
wait = 0

loop do
  wait += RETRY_DELAY
  sleep wait.seconds
  elapsed += wait

  status_response = request("GET", queued["statusUrl"].as_s)
  unless status_response.success?
    fails += 1
    puts "Status check failed with status: #{status_response.status_code} (#{fails}/#{MAX_FAILS})"
    fail "Obfuscation failed (fails: #{fails} | elapsed time: #{elapsed})" if fails >= MAX_FAILS || elapsed >= MAX_WAIT
    next
  end

  status = JSON.parse(status_response.body)

  if status["status"] == "completed"
    puts "Obfuscation completed in #{elapsed} seconds"
    download = request("GET", status["downloadUrl"].as_s)
    fail "Download failed with status: #{download.status_code}" unless download.success?
    File.write(OUTPUT_PATH, download.body)
    puts "Saved obfuscated script to #{OUTPUT_PATH}"
    break
  end

  if status["status"] == "failed" || elapsed >= MAX_WAIT
    fail "Obfuscation failed (status: #{status["status"]} | elapsed time: #{elapsed})"
  end

  puts "Obfuscation is still in progress. Elapsed time: #{elapsed} seconds. Checking again in #{RETRY_DELAY + wait} seconds."
end
