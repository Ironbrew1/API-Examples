// Run with: ldc2 -run main.d   (or: dmd -run main.d). Uses std.net.curl, so libcurl must be installed.
import core.thread : Thread;
import core.time : seconds;
import std.file : read, write;
import std.json : parseJSON;
import std.net.curl : HTTP;
import std.stdio : stderr, writefln, writeln;
import std.conv : to;
import core.stdc.stdlib : exit;

enum BASE_URL = "https://ironbrew1.com";
enum API_KEY = "IB1-APIKEYHERE";

enum INPUT_PATH = "input.lua";
enum OUTPUT_PATH = "output.lua";

enum QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

enum RETRY_DELAY = 5;
enum MAX_WAIT = 240;
enum MAX_FAILS = 3;

struct Response
{
    int code;
    ubyte[] body;
}

void fail(string message)
{
    stderr.writeln(message);
    exit(1);
}

Response request(HTTP.Method method, string path, const(void)[] body = null)
{
    auto http = HTTP(BASE_URL ~ path);
    http.addRequestHeader("Key", API_KEY);
    http.method = method;
    if (body !is null)
        http.setPostData(body, "text/plain");

    Response response;
    http.onReceive = (ubyte[] data) { response.body ~= data; return data.length; };
    http.perform(); // throws on transport errors
    response.code = http.statusLine.code;
    return response;
}

bool ok(int code) { return code / 100 == 2; }

void main()
{
    auto queueResponse = request(HTTP.Method.post, "/obfuscate?" ~ QUERY, read(INPUT_PATH));
    if (!ok(queueResponse.code))
        fail("Unable to queue obfuscation: " ~ queueResponse.code.to!string);

    auto queued = parseJSON(cast(string) queueResponse.body);
    writefln("Obfuscation started with GUID: %s", queued["uploadGuid"].str);

    int elapsed, fails, wait;

    while (true)
    {
        wait += RETRY_DELAY;
        Thread.sleep(wait.seconds);
        elapsed += wait;

        auto response = request(HTTP.Method.get, queued["statusUrl"].str);
        if (!ok(response.code))
        {
            fails++;
            writefln("Status check failed with status: %s (%s/%s)", response.code, fails, MAX_FAILS);
            if (fails >= MAX_FAILS || elapsed >= MAX_WAIT)
                fail("Obfuscation failed (fails: " ~ fails.to!string ~ " | elapsed time: " ~ elapsed.to!string ~ ")");
            continue;
        }

        auto status = parseJSON(cast(string) response.body);
        auto state = status["status"].str;

        if (state == "completed")
        {
            writefln("Obfuscation completed in %s seconds", elapsed);
            auto download = request(HTTP.Method.get, status["downloadUrl"].str);
            if (!ok(download.code))
                fail("Download failed with status: " ~ download.code.to!string);
            write(OUTPUT_PATH, download.body);
            writefln("Saved obfuscated script to %s", OUTPUT_PATH);
            return;
        }

        if (state == "failed" || elapsed >= MAX_WAIT)
            fail("Obfuscation failed (status: " ~ state ~ " | elapsed time: " ~ elapsed.to!string ~ ")");

        writefln("Obfuscation is still in progress. Elapsed time: %s seconds. Checking again in %s seconds.", elapsed, RETRY_DELAY + wait);
    }
}
