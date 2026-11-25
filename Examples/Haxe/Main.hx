// Build and run with the Python target (which has TLS support):
//   haxe --main Main --python main.py && python3 main.py
import haxe.Http;
import haxe.Json;
import sys.io.File;

class Main {
	static inline var BASE_URL = "https://ironbrew1.com";
	static inline var API_KEY = "IB1-APIKEYHERE";

	static inline var INPUT_PATH = "input.lua";
	static inline var OUTPUT_PATH = "output.lua";

	static inline var QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

	static inline var RETRY_DELAY = 5;
	static inline var MAX_WAIT = 240;
	static inline var MAX_FAILS = 3;

	static function fail(message:String):Void {
		Sys.stderr().writeString(message + "\n");
		Sys.exit(1);
	}

	static function ok(code:Int):Bool {
		return code >= 200 && code < 300;
	}

	// Returns the HTTP status code (0 on transport errors) and the response body.
	static function request(post:Bool, path:String, ?body:String):{code:Int, body:String} {
		var code = 0;
		var response = "";
		var http = new Http(BASE_URL + path);
		http.addHeader("Key", API_KEY);
		if (body != null) {
			http.addHeader("Content-Type", "text/plain");
			http.setPostData(body);
		}
		http.onStatus = function(status) code = status;
		http.onData = function(data) response = data;
		http.onError = function(error) response = error;
		http.request(post);
		return {code: code, body: response};
	}

	static function main() {
		var queueResponse = request(true, '/obfuscate?$QUERY', File.getContent(INPUT_PATH));
		if (!ok(queueResponse.code))
			fail('Unable to queue obfuscation: ${queueResponse.code}');

		var queued = Json.parse(queueResponse.body);
		Sys.println('Obfuscation started with GUID: ${queued.uploadGuid}');

		var elapsed = 0;
		var fails = 0;
		var wait = 0;

		while (true) {
			wait += RETRY_DELAY;
			Sys.sleep(wait);
			elapsed += wait;

			var response = request(false, queued.statusUrl);
			if (!ok(response.code)) {
				fails++;
				Sys.println('Status check failed with status: ${response.code} ($fails/$MAX_FAILS)');
				if (fails >= MAX_FAILS || elapsed >= MAX_WAIT)
					fail('Obfuscation failed (fails: $fails | elapsed time: $elapsed)');
				continue;
			}

			var status = Json.parse(response.body);

			if (status.status == "completed") {
				Sys.println('Obfuscation completed in $elapsed seconds');
				var download = request(false, status.downloadUrl);
				if (!ok(download.code))
					fail('Download failed with status: ${download.code}');
				File.saveContent(OUTPUT_PATH, download.body);
				Sys.println('Saved obfuscated script to $OUTPUT_PATH');
				break;
			}

			if (status.status == "failed" || elapsed >= MAX_WAIT)
				fail('Obfuscation failed (status: ${status.status} | elapsed time: $elapsed)');

			Sys.println('Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in ${RETRY_DELAY + wait} seconds.');
		}
	}
}
