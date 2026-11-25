/* Build and run:
 *   valac --pkg libsoup-3.0 --pkg json-glib-1.0 main.vala -o main && ./main
 * Needs libsoup 3, json-glib and a GIO TLS backend (glib-networking) for https. */

const string BASE_URL = "https://ironbrew1.com";
const string API_KEY = "IB1-APIKEYHERE";

const string INPUT_PATH = "input.lua";
const string OUTPUT_PATH = "output.lua";

const string QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

const int RETRY_DELAY = 5;
const int MAX_WAIT = 240;
const int MAX_FAILS = 3;

Soup.Session session;

void fail (string message) {
    stderr.printf ("%s\n", message);
    Process.exit (1);
}

bool ok (uint code) {
    return code / 100 == 2;
}

/* Returns the HTTP status code (0 on transport errors) and the response body. */
uint request (string method, string path, Bytes? body, out uint8[] response) {
    var message = new Soup.Message (method, BASE_URL + path);
    message.request_headers.append ("Key", API_KEY);
    if (body != null) {
        message.set_request_body_from_bytes ("text/plain", body);
    }
    try {
        Bytes bytes = session.send_and_read (message, null);
        response = bytes.get_data ();
    } catch (Error e) {
        response = new uint8[0];
        return 0;
    }
    return message.status_code;
}

string json_field (uint8[] data, string name) {
    var parser = new Json.Parser ();
    try {
        parser.load_from_data ((string) data, (ssize_t) data.length);
    } catch (Error e) {
        fail ("Unable to decode JSON: " + e.message);
    }
    return parser.get_root ().get_object ().get_string_member (name);
}

int main () {
    session = new Soup.Session ();
    session.timeout = 120;

    uint8[] source;
    try {
        FileUtils.get_data (INPUT_PATH, out source);
    } catch (Error e) {
        fail ("Unable to read " + INPUT_PATH + ": " + e.message);
    }

    uint8[] body;
    uint code = request ("POST", "/obfuscate?" + QUERY, new Bytes (source), out body);
    if (!ok (code)) {
        fail ("Unable to queue obfuscation: %u".printf (code));
    }

    string status_url = json_field (body, "statusUrl");
    print ("Obfuscation started with GUID: %s\n", json_field (body, "uploadGuid"));

    int elapsed = 0;
    int fails = 0;
    int wait = 0;

    while (true) {
        wait += RETRY_DELAY;
        Thread.usleep ((ulong) wait * 1000000);
        elapsed += wait;

        code = request ("GET", status_url, null, out body);
        if (!ok (code)) {
            fails++;
            print ("Status check failed with status: %u (%d/%d)\n", code, fails, MAX_FAILS);
            if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
                fail ("Obfuscation failed (fails: %d | elapsed time: %d)".printf (fails, elapsed));
            }
            continue;
        }

        string state = json_field (body, "status");

        if (state == "completed") {
            print ("Obfuscation completed in %d seconds\n", elapsed);
            uint8[] script;
            code = request ("GET", json_field (body, "downloadUrl"), null, out script);
            if (!ok (code)) {
                fail ("Download failed with status: %u".printf (code));
            }
            try {
                FileUtils.set_data (OUTPUT_PATH, script);
            } catch (Error e) {
                fail ("Unable to write " + OUTPUT_PATH + ": " + e.message);
            }
            print ("Saved obfuscated script to %s\n", OUTPUT_PATH);
            return 0;
        }

        if (state == "failed" || elapsed >= MAX_WAIT) {
            fail ("Obfuscation failed (status: %s | elapsed time: %d)".printf (state, elapsed));
        }

        print ("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n",
               elapsed, RETRY_DELAY + wait);
    }
}
