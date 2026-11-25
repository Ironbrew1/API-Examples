// Odin. Run with: odin run .
//
// NOTE: Odin's core:net has no TLS, so this example calls libcurl through Odin's foreign
// import support (apt install libcurl4-openssl-dev). JSON parsing and everything else uses
// the standard library.
package main

import "core:c"
import "core:c/libc"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

BASE_URL :: "https://ironbrew1.com"
API_KEY :: "IB1-APIKEYHERE"

INPUT_PATH :: "input.lua"
OUTPUT_PATH :: "output.lua"

QUERY :: "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

RETRY_DELAY :: 5
MAX_WAIT :: 240
MAX_FAILS :: 3

CURLOPT_WRITEDATA :: 10001
CURLOPT_URL :: 10002
CURLOPT_POSTFIELDS :: 10015
CURLOPT_HTTPHEADER :: 10023
CURLOPT_TIMEOUT :: 13
CURLOPT_POST :: 47
CURLOPT_POSTFIELDSIZE :: 60
CURLINFO_RESPONSE_CODE :: 2097154

foreign import curl_lib "system:curl"

@(default_calling_convention = "c")
foreign curl_lib {
	curl_easy_init :: proc() -> rawptr ---
	curl_easy_perform :: proc(handle: rawptr) -> c.int ---
	curl_easy_cleanup :: proc(handle: rawptr) ---
	curl_slist_append :: proc(list: rawptr, value: cstring) -> rawptr ---
	curl_slist_free_all :: proc(list: rawptr) ---

	// Both of these are variadic in C: the option decides what the value must be.
	curl_easy_setopt :: proc(handle: rawptr, option: c.int, #c_vararg values: ..any) -> c.int ---
	curl_easy_getinfo :: proc(handle: rawptr, info: c.int, #c_vararg values: ..any) -> c.int ---
}

foreign import libc_lib "system:c"

@(default_calling_convention = "c")
foreign libc_lib {
	fmemopen :: proc(buffer: rawptr, size: c.size_t, mode: cstring) -> ^libc.FILE ---
}

fail :: proc(message: string, args: ..any) -> ! {
	fmt.eprintfln(message, ..args)
	os.exit(1)
}

ok :: proc(code: int) -> bool {
	return code >= 200 && code < 300
}

// Performs one request. body is uploaded when it is not empty, and the response is written
// to out_file. Returns the HTTP status code, or 0 when the transfer itself failed.
request :: proc(url: string, body: []byte, out_file: ^libc.FILE) -> int {
	handle := curl_easy_init()
	if handle == nil {
		fail("curl_easy_init failed")
	}
	defer curl_easy_cleanup(handle)

	headers := curl_slist_append(nil, "Key: " + API_KEY)
	if len(body) > 0 {
		headers = curl_slist_append(headers, "Content-Type: text/plain")
	}
	defer curl_slist_free_all(headers)

	c_url := strings.clone_to_cstring(url)
	defer delete(c_url)

	curl_easy_setopt(handle, CURLOPT_URL, c_url)
	curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers)
	curl_easy_setopt(handle, CURLOPT_WRITEDATA, out_file)
	curl_easy_setopt(handle, CURLOPT_TIMEOUT, c.long(60))
	if len(body) > 0 {
		curl_easy_setopt(handle, CURLOPT_POST, c.long(1))
		curl_easy_setopt(handle, CURLOPT_POSTFIELDS, raw_data(body))
		curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE, c.long(len(body)))
	}

	code: c.long = 0
	if curl_easy_perform(handle) == 0 {
		curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code)
	}
	return int(code)
}

// Sends a request whose reply is small JSON and parses it.
request_json :: proc(url: string, body: []byte) -> (json.Object, int) {
	buffer := make([]byte, 8192)
	defer delete(buffer)

	stream := fmemopen(raw_data(buffer), c.size_t(len(buffer)), "w")
	if stream == nil {
		fail("fmemopen failed")
	}
	code := request(url, body, stream)
	libc.fclose(stream)

	if !ok(code) {
		return nil, code
	}

	text := string(buffer[:strings.index_byte(string(buffer), 0)])
	value, error := json.parse_string(text)
	if error != nil {
		fail("Unable to parse the response: %v", error)
	}
	object, is_object := value.(json.Object)
	if !is_object {
		fail("The response is not a JSON object")
	}
	return object, code
}

field :: proc(object: json.Object, name: string) -> string {
	value, found := object[name]
	if !found {
		return ""
	}
	text, is_string := value.(json.String)
	if !is_string {
		return ""
	}
	return string(text)
}

main :: proc() {
	script, read_error := os.read_entire_file_from_path(INPUT_PATH, context.allocator)
	if read_error != nil {
		fail("Unable to read %s: %v", INPUT_PATH, read_error)
	}

	queued, queue_code := request_json(BASE_URL + "/obfuscate?" + QUERY, script)
	if !ok(queue_code) {
		fail("Unable to queue obfuscation: %d", queue_code)
	}
	fmt.printfln("Obfuscation started with GUID: %s", field(queued, "uploadGuid"))
	status_url := strings.clone(field(queued, "statusUrl"))

	elapsed := 0
	fails := 0
	wait := 0

	for {
		wait += RETRY_DELAY
		time.sleep(time.Duration(wait) * time.Second)
		elapsed += wait

		status, code := request_json(strings.concatenate({BASE_URL, status_url}), nil)
		if !ok(code) {
			fails += 1
			fmt.printfln("Status check failed with status: %d (%d/%d)", code, fails, MAX_FAILS)
			if fails >= MAX_FAILS || elapsed >= MAX_WAIT {
				fail("Obfuscation failed (fails: %d | elapsed time: %d)", fails, elapsed)
			}
			continue
		}

		state := field(status, "status")

		if state == "completed" {
			fmt.printfln("Obfuscation completed in %d seconds", elapsed)

			out_file := libc.fopen(OUTPUT_PATH, "wb")
			if out_file == nil {
				fail("Unable to open %s", OUTPUT_PATH)
			}
			download_code := request(strings.concatenate({BASE_URL, field(status, "downloadUrl")}), nil, out_file)
			libc.fclose(out_file)
			if !ok(download_code) {
				fail("Download failed with status: %d", download_code)
			}

			fmt.printfln("Saved obfuscated script to %s", OUTPUT_PATH)
			return
		}

		if state == "failed" || elapsed >= MAX_WAIT {
			fail("Obfuscation failed (status: %s | elapsed time: %d)", state, elapsed)
		}

		fmt.printfln(
			"Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.",
			elapsed,
			RETRY_DELAY + wait,
		)
	}
}
