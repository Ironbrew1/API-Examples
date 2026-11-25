/* Build: gcc main.c -o main -lcurl    (needs libcurl, e.g. libcurl4-openssl-dev) */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BASE_URL "https://ironbrew1.com"
#define API_KEY "IB1-APIKEYHERE"

#define INPUT_PATH "input.lua"
#define OUTPUT_PATH "output.lua"

#define QUERY "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

#define RETRY_DELAY 5
#define MAX_WAIT 240
#define MAX_FAILS 3

typedef struct {
    char *data;
    size_t len;
} Buffer;

static size_t on_write(char *chunk, size_t size, size_t count, void *user) {
    Buffer *buf = user;
    size_t total = size * count;
    char *grown = realloc(buf->data, buf->len + total + 1);
    if (!grown) return 0;
    buf->data = grown;
    memcpy(buf->data + buf->len, chunk, total);
    buf->len += total;
    buf->data[buf->len] = '\0';
    return total;
}

static void fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(1);
}

/* Sends a request and returns the HTTP status code (0 on transport errors). */
static long request(const char *method, const char *path, const char *body, size_t body_len, Buffer *out) {
    char url[2048];
    snprintf(url, sizeof url, "%s%s", BASE_URL, path);

    CURL *curl = curl_easy_init();
    struct curl_slist *headers = curl_slist_append(NULL, "Key: " API_KEY);
    if (body) headers = curl_slist_append(headers, "Content-Type: text/plain");

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 120L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, on_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);
    if (body) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body_len);
    }

    long code = 0;
    if (curl_easy_perform(curl) == CURLE_OK) curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return code;
}

/* Pulls a string value out of a flat JSON object without needing a JSON library. */
static char *field(const char *json, const char *name) {
    char needle[64];
    snprintf(needle, sizeof needle, "\"%s\"", name);
    const char *p = strstr(json, needle);
    if (!p) return NULL;
    p = strchr(p + strlen(needle), ':');
    if (!p) return NULL;
    p = strchr(p, '"');
    if (!p) return NULL;
    p++;
    const char *end = strchr(p, '"');
    if (!end) return NULL;

    char *value = malloc((size_t)(end - p) + 1), *w = value;
    for (; p < end; p++) {
        if (p[0] == '\\' && p[1] == '/') p++; /* unescape \/ */
        *w++ = *p;
    }
    *w = '\0';
    return value;
}

int main(void) {
    FILE *in = fopen(INPUT_PATH, "rb");
    if (!in) fail("Unable to read " INPUT_PATH);
    fseek(in, 0, SEEK_END);
    long size = ftell(in);
    rewind(in);
    char *source = malloc((size_t)size + 1);
    if (fread(source, 1, (size_t)size, in) != (size_t)size) fail("Unable to read " INPUT_PATH);
    fclose(in);

    curl_global_init(CURL_GLOBAL_DEFAULT);

    Buffer queued = {0};
    long code = request("POST", "/obfuscate?" QUERY, source, (size_t)size, &queued);
    if (code / 100 != 2) {
        fprintf(stderr, "Unable to queue obfuscation: %ld\n", code);
        return 1;
    }

    char *status_url = field(queued.data, "statusUrl");
    char *guid = field(queued.data, "uploadGuid");
    if (!status_url) fail("Response is missing statusUrl");
    printf("Obfuscation started with GUID: %s\n", guid ? guid : "");

    int elapsed = 0, fails = 0, wait = 0;

    for (;;) {
        wait += RETRY_DELAY;
        sleep((unsigned)wait);
        elapsed += wait;

        Buffer response = {0};
        code = request("GET", status_url, NULL, 0, &response);
        if (code / 100 != 2) {
            fails++;
            printf("Status check failed with status: %ld (%d/%d)\n", code, fails, MAX_FAILS);
            if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
                fprintf(stderr, "Obfuscation failed (fails: %d | elapsed time: %d)\n", fails, elapsed);
                return 1;
            }
            continue;
        }

        char *status = field(response.data, "status");

        if (status && strcmp(status, "completed") == 0) {
            printf("Obfuscation completed in %d seconds\n", elapsed);
            char *download_url = field(response.data, "downloadUrl");
            if (!download_url) fail("Response is missing downloadUrl");

            Buffer script = {0};
            code = request("GET", download_url, NULL, 0, &script);
            if (code / 100 != 2) {
                fprintf(stderr, "Download failed with status: %ld\n", code);
                return 1;
            }
            FILE *out = fopen(OUTPUT_PATH, "wb");
            if (!out) fail("Unable to write " OUTPUT_PATH);
            fwrite(script.data, 1, script.len, out);
            fclose(out);
            printf("Saved obfuscated script to " OUTPUT_PATH "\n");
            return 0;
        }

        if ((status && strcmp(status, "failed") == 0) || elapsed >= MAX_WAIT) {
            fprintf(stderr, "Obfuscation failed (status: %s | elapsed time: %d)\n", status ? status : "unknown", elapsed);
            return 1;
        }

        printf("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n",
               elapsed, RETRY_DELAY + wait);
    }
}
