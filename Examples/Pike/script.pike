// Run with Pike 8: pike script.pike   (needs Pike built with SSL support)
constant BASE_URL = "https://ironbrew1.com";
constant API_KEY = "IB1-APIKEYHERE";

constant INPUT_PATH = "input.lua";
constant OUTPUT_PATH = "output.lua";

constant QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

constant RETRY_DELAY = 5;
constant MAX_WAIT = 240;
constant MAX_FAILS = 3;

void fail(string message)
{
  werror("%s\n", message);
  exit(1);
}

int ok(int code)
{
  return code >= 200 && code < 300;
}

// Returns ({ status code, body }); the status is 0 on transport errors.
array(mixed) request(string method, string path, void|string body)
{
  mapping headers = ([ "Key": API_KEY ]);
  if (body) headers["Content-Type"] = "text/plain";

  Protocols.HTTP.Query query = Protocols.HTTP.do_method(method, BASE_URL + path, 0, headers, 0, body);
  if (!query) return ({ 0, "" });
  return ({ query->status, query->data() });
}

int main()
{
  [int code, string body] = request("POST", "/obfuscate?" + QUERY, Stdio.read_file(INPUT_PATH));
  if (!ok(code)) fail("Unable to queue obfuscation: " + code);

  mapping queued = Standards.JSON.decode(body);
  write("Obfuscation started with GUID: %s\n", queued->uploadGuid);

  int elapsed, fails, wait;

  while (1) {
    wait += RETRY_DELAY;
    sleep(wait);
    elapsed += wait;

    [code, body] = request("GET", queued->statusUrl);
    if (!ok(code)) {
      fails++;
      write("Status check failed with status: %d (%d/%d)\n", code, fails, MAX_FAILS);
      if (fails >= MAX_FAILS || elapsed >= MAX_WAIT)
        fail(sprintf("Obfuscation failed (fails: %d | elapsed time: %d)", fails, elapsed));
      continue;
    }

    mapping status = Standards.JSON.decode(body);

    if (status->status == "completed") {
      write("Obfuscation completed in %d seconds\n", elapsed);
      [code, string script] = request("GET", status->downloadUrl);
      if (!ok(code)) fail("Download failed with status: " + code);
      Stdio.write_file(OUTPUT_PATH, script);
      write("Saved obfuscated script to %s\n", OUTPUT_PATH);
      return 0;
    }

    if (status->status == "failed" || elapsed >= MAX_WAIT)
      fail(sprintf("Obfuscation failed (status: %s | elapsed time: %d)", status->status, elapsed));

    write("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n",
          elapsed, RETRY_DELAY + wait);
  }
}
