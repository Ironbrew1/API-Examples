// Ballerina 2201 (Swan Lake). Run with: bal run
import ballerina/http;
import ballerina/io;
import ballerina/lang.runtime;

const string BASE_URL = "https://ironbrew1.com";
const string API_KEY = "IB1-APIKEYHERE";

const string INPUT_PATH = "input.lua";
const string OUTPUT_PATH = "output.lua";

const string QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

const decimal RETRY_DELAY = 5;
const int MAX_WAIT = 240;
const int MAX_FAILS = 3;

type Queued record {
    string uploadGuid;
    string statusUrl;
};

type Status record {
    string status;
    string? downloadUrl;
};

function ok(int code) returns boolean => code >= 200 && code < 300;

public function main() returns error? {
    // Calls that return http:Response hand back 4xx and 5xx responses instead of turning them
    // into errors, so the status code can be checked here.
    http:Client api = check new (BASE_URL, {timeout: 60, httpVersion: http:HTTP_1_1});
    map<string> headers = {"Key": API_KEY};

    string script = check io:fileReadString(INPUT_PATH);

    http:Response queueResponse = check api->post("/obfuscate?" + QUERY, script, headers, mediaType = "text/plain");
    if !ok(queueResponse.statusCode) {
        return error(string `Unable to queue obfuscation: ${queueResponse.statusCode}`);
    }
    Queued queued = check (check queueResponse.getJsonPayload()).cloneWithType();
    io:println("Obfuscation started with GUID: " + queued.uploadGuid);

    int elapsed = 0;
    int fails = 0;
    decimal waitTime = 0;

    while true {
        waitTime += RETRY_DELAY;
        runtime:sleep(waitTime);
        elapsed += <int>waitTime;

        http:Response statusResponse = check api->get(queued.statusUrl, headers);
        if !ok(statusResponse.statusCode) {
            fails += 1;
            io:println(string `Status check failed with status: ${statusResponse.statusCode} (${fails}/${MAX_FAILS})`);
            if fails >= MAX_FAILS || elapsed >= MAX_WAIT {
                return error(string `Obfuscation failed (fails: ${fails} | elapsed time: ${elapsed})`);
            }
            continue;
        }

        Status status = check (check statusResponse.getJsonPayload()).cloneWithType();

        if status.status == "completed" {
            io:println(string `Obfuscation completed in ${elapsed} seconds`);
            string? downloadUrl = status.downloadUrl;
            if downloadUrl is () {
                return error("The completed status response has no downloadUrl");
            }
            http:Response download = check api->get(downloadUrl, headers);
            if !ok(download.statusCode) {
                return error(string `Download failed with status: ${download.statusCode}`);
            }
            check io:fileWriteBytes(OUTPUT_PATH, check download.getBinaryPayload());
            io:println("Saved obfuscated script to " + OUTPUT_PATH);
            return;
        }

        if status.status == "failed" || elapsed >= MAX_WAIT {
            return error(string `Obfuscation failed (status: ${status.status} | elapsed time: ${elapsed})`);
        }

        io:println(string `Obfuscation is still in progress. Elapsed time: ${elapsed} seconds. Checking again in ${RETRY_DELAY + waitTime} seconds.`);
    }
}
