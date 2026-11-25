require "json"
require "net/http"
require "uri"

BASE_URL = "https://ironbrew1.com"
API_KEY = "IB1-APIKEYHERE"

INPUT_PATH = "input.lua"
OUTPUT_PATH = "output.lua"

OPTIONS = {
  "platform" => "roblox",
  "aggressiveOptimizations" => "0",
  "intenseVmScrambling" => "false",
  "enableVmCompression" => "false",
}.freeze

RETRY_DELAY = 5
MAX_WAIT = 240
MAX_FAILS = 3

def request(klass, path, body = nil)
  uri = URI(BASE_URL + path)
  req = klass.new(uri)
  req["Key"] = API_KEY
  if body
    req["Content-Type"] = "text/plain"
    req.body = body
  end
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) { |http| http.request(req) }
end

def fail_with(message)
  warn message
  exit 1
end

queue_response = request(Net::HTTP::Post, "/obfuscate?#{URI.encode_www_form(OPTIONS)}", File.binread(INPUT_PATH))
fail_with "Unable to queue obfuscation: #{queue_response.code}" unless queue_response.is_a?(Net::HTTPSuccess)

queued = JSON.parse(queue_response.body)
puts "Obfuscation started with GUID: #{queued["uploadGuid"]}"

elapsed = 0
fails = 0
wait = 0

loop do
  wait += RETRY_DELAY
  sleep wait
  elapsed += wait

  status_response = request(Net::HTTP::Get, queued["statusUrl"])
  unless status_response.is_a?(Net::HTTPSuccess)
    fails += 1
    puts "Status check failed with status: #{status_response.code} (#{fails}/#{MAX_FAILS})"
    fail_with "Obfuscation failed (fails: #{fails} | elapsed time: #{elapsed})" if fails >= MAX_FAILS || elapsed >= MAX_WAIT
    next
  end

  status = JSON.parse(status_response.body)

  if status["status"] == "completed"
    puts "Obfuscation completed in #{elapsed} seconds"
    download = request(Net::HTTP::Get, status["downloadUrl"])
    fail_with "Download failed with status: #{download.code}" unless download.is_a?(Net::HTTPSuccess)
    File.binwrite(OUTPUT_PATH, download.body)
    puts "Saved obfuscated script to #{OUTPUT_PATH}"
    break
  end

  if status["status"] == "failed" || elapsed >= MAX_WAIT
    fail_with "Obfuscation failed (status: #{status["status"]} | elapsed time: #{elapsed})"
  end

  puts "Obfuscation is still in progress. Elapsed time: #{elapsed} seconds. Checking again in #{RETRY_DELAY + wait} seconds."
end
