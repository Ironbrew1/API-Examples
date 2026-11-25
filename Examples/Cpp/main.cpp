// Build: g++ -std=c++17 main.cpp -o main -lcurl    (needs libcurl, e.g. libcurl4-openssl-dev)
#include <curl/curl.h>

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <thread>

const std::string BASE_URL = "https://ironbrew1.com";
const std::string API_KEY = "IB1-APIKEYHERE";

const std::string INPUT_PATH = "input.lua";
const std::string OUTPUT_PATH = "output.lua";

const std::string QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

constexpr int RETRY_DELAY = 5;
constexpr int MAX_WAIT = 240;
constexpr int MAX_FAILS = 3;

struct Response {
    long code = 0;
    std::string body;
};

static size_t on_write(char* chunk, size_t size, size_t count, void* user) {
    static_cast<std::string*>(user)->append(chunk, size * count);
    return size * count;
}

[[noreturn]] static void fail(const std::string& message) {
    std::cerr << message << "\n";
    std::exit(1);
}

// Sends a request; `body` is only set for POST requests.
static Response request(const std::string& method, const std::string& path, const std::optional<std::string>& body = std::nullopt) {
    Response response;
    CURL* curl = curl_easy_init();
    curl_slist* headers = curl_slist_append(nullptr, ("Key: " + API_KEY).c_str());
    if (body) headers = curl_slist_append(headers, "Content-Type: text/plain");

    curl_easy_setopt(curl, CURLOPT_URL, (BASE_URL + path).c_str());
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 120L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, on_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response.body);
    if (body) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body->data());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body->size()));
    }

    if (curl_easy_perform(curl) == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response.code);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return response;
}

// Pulls a string value out of a flat JSON object without needing a JSON library.
static std::string field(const std::string& json, const std::string& name) {
    auto key = json.find("\"" + name + "\"");
    if (key == std::string::npos) return "";
    auto start = json.find('"', json.find(':', key));
    if (start == std::string::npos) return "";
    auto end = json.find('"', start + 1);
    std::string value = json.substr(start + 1, end - start - 1);
    for (auto pos = value.find("\\/"); pos != std::string::npos; pos = value.find("\\/")) value.replace(pos, 2, "/");
    return value;
}

static bool ok(long code) { return code >= 200 && code < 300; }

int main() {
    std::ifstream in(INPUT_PATH, std::ios::binary);
    if (!in) fail("Unable to read " + INPUT_PATH);
    std::stringstream source;
    source << in.rdbuf();

    curl_global_init(CURL_GLOBAL_DEFAULT);

    Response queued = request("POST", "/obfuscate?" + QUERY, source.str());
    if (!ok(queued.code)) fail("Unable to queue obfuscation: " + std::to_string(queued.code));

    std::string status_url = field(queued.body, "statusUrl");
    std::cout << "Obfuscation started with GUID: " << field(queued.body, "uploadGuid") << "\n";

    int elapsed = 0, fails = 0, wait = 0;

    while (true) {
        wait += RETRY_DELAY;
        std::this_thread::sleep_for(std::chrono::seconds(wait));
        elapsed += wait;

        Response response = request("GET", status_url);
        if (!ok(response.code)) {
            fails++;
            std::cout << "Status check failed with status: " << response.code << " (" << fails << "/" << MAX_FAILS << ")\n";
            if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
                fail("Obfuscation failed (fails: " + std::to_string(fails) + " | elapsed time: " + std::to_string(elapsed) + ")");
            }
            continue;
        }

        std::string status = field(response.body, "status");

        if (status == "completed") {
            std::cout << "Obfuscation completed in " << elapsed << " seconds\n";
            Response download = request("GET", field(response.body, "downloadUrl"));
            if (!ok(download.code)) fail("Download failed with status: " + std::to_string(download.code));
            std::ofstream(OUTPUT_PATH, std::ios::binary) << download.body;
            std::cout << "Saved obfuscated script to " << OUTPUT_PATH << "\n";
            return 0;
        }

        if (status == "failed" || elapsed >= MAX_WAIT) {
            fail("Obfuscation failed (status: " + status + " | elapsed time: " + std::to_string(elapsed) + ")");
        }

        std::cout << "Obfuscation is still in progress. Elapsed time: " << elapsed
                  << " seconds. Checking again in " << RETRY_DELAY + wait << " seconds.\n";
    }
}
