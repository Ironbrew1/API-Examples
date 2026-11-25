// Run with: v run main.v
import json
import net.http
import os
import time

const base_url = 'https://ironbrew1.com'
const api_key = 'IB1-APIKEYHERE'

const input_path = 'input.lua'
const output_path = 'output.lua'

const query = 'platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false'

const retry_delay = 5
const max_wait = 240
const max_fails = 3

struct Queued {
	upload_guid string @[json: 'uploadGuid']
	status_url  string @[json: 'statusUrl']
}

struct Status {
	status       string
	download_url string @[json: 'downloadUrl']
}

fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn request(method http.Method, path string, body string) !http.Response {
	mut header := http.new_header(key: .content_type, value: 'text/plain')
	header.add_custom('Key', api_key)!
	return http.fetch(http.FetchConfig{
		url:    base_url + path
		method: method
		header: header
		data:   body
	})
}

fn ok(code int) bool {
	return code / 100 == 2
}

fn main() {
	source := os.read_file(input_path) or {
		fail('Unable to read ${input_path}')
		return
	}

	queue_response := request(.post, '/obfuscate?${query}', source) or {
		fail('Unable to queue obfuscation: ${err}')
		return
	}
	if !ok(queue_response.status_code) {
		fail('Unable to queue obfuscation: ${queue_response.status_code}')
	}

	queued := json.decode(Queued, queue_response.body) or {
		fail('Unable to decode JSON: ${err}')
		return
	}
	println('Obfuscation started with GUID: ${queued.upload_guid}')

	mut elapsed := 0
	mut fails := 0
	mut wait := 0

	for {
		wait += retry_delay
		time.sleep(wait * time.second)
		elapsed += wait

		response := request(.get, queued.status_url, '') or {
			fails++
			println('Status check failed: ${err} (${fails}/${max_fails})')
			if fails >= max_fails || elapsed >= max_wait {
				fail('Obfuscation failed (fails: ${fails} | elapsed time: ${elapsed})')
			}
			continue
		}
		if !ok(response.status_code) {
			fails++
			println('Status check failed with status: ${response.status_code} (${fails}/${max_fails})')
			if fails >= max_fails || elapsed >= max_wait {
				fail('Obfuscation failed (fails: ${fails} | elapsed time: ${elapsed})')
			}
			continue
		}

		status := json.decode(Status, response.body) or {
			fail('Unable to decode JSON: ${err}')
			return
		}

		if status.status == 'completed' {
			println('Obfuscation completed in ${elapsed} seconds')
			download := request(.get, status.download_url, '') or {
				fail('Download failed: ${err}')
				return
			}
			if !ok(download.status_code) {
				fail('Download failed with status: ${download.status_code}')
			}
			os.write_file(output_path, download.body) or {
				fail('Unable to write ${output_path}: ${err}')
				return
			}
			println('Saved obfuscated script to ${output_path}')
			break
		}

		if status.status == 'failed' || elapsed >= max_wait {
			fail('Obfuscation failed (status: ${status.status} | elapsed time: ${elapsed})')
		}

		println('Obfuscation is still in progress. Elapsed time: ${elapsed} seconds. Checking again in ${retry_delay + wait} seconds.')
	}
}
