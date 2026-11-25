import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Requires Java 11+. Run with: java Main.java
public class Main {
    static final String BASE_URL = "https://ironbrew1.com";
    static final String API_KEY = "IB1-APIKEYHERE";

    static final Path INPUT_PATH = Path.of("input.lua");
    static final Path OUTPUT_PATH = Path.of("output.lua");

    static final String QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

    static final int RETRY_DELAY = 5;
    static final int MAX_WAIT = 240;
    static final int MAX_FAILS = 3;

    static final HttpClient CLIENT = HttpClient.newHttpClient();

    // Pulls a string value out of a flat JSON object without needing a JSON library.
    static String field(String json, String name) {
        Matcher m = Pattern.compile("\"" + name + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1).replace("\\/", "/") : null;
    }

    static HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(Duration.ofSeconds(120))
                .header("Key", API_KEY);
    }

    public static void main(String[] args) throws Exception {
        HttpResponse<String> queueResponse = CLIENT.send(
                request("/obfuscate?" + QUERY)
                        .header("Content-Type", "text/plain")
                        .POST(HttpRequest.BodyPublishers.ofFile(INPUT_PATH))
                        .build(),
                HttpResponse.BodyHandlers.ofString());
        if (queueResponse.statusCode() / 100 != 2) {
            System.err.println("Unable to queue obfuscation: " + queueResponse.statusCode());
            System.exit(1);
        }

        String statusUrl = field(queueResponse.body(), "statusUrl");
        System.out.println("Obfuscation started with GUID: " + field(queueResponse.body(), "uploadGuid"));

        int elapsed = 0, fails = 0, wait = 0;

        while (true) {
            wait += RETRY_DELAY;
            Thread.sleep(wait * 1000L);
            elapsed += wait;

            HttpResponse<String> statusResponse = CLIENT.send(request(statusUrl).GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            if (statusResponse.statusCode() / 100 != 2) {
                fails++;
                System.out.println("Status check failed with status: " + statusResponse.statusCode() + " (" + fails + "/" + MAX_FAILS + ")");
                if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
                    System.err.println("Obfuscation failed (fails: " + fails + " | elapsed time: " + elapsed + ")");
                    System.exit(1);
                }
                continue;
            }

            String status = field(statusResponse.body(), "status");

            if ("completed".equals(status)) {
                System.out.println("Obfuscation completed in " + elapsed + " seconds");
                HttpResponse<byte[]> download = CLIENT.send(
                        request(field(statusResponse.body(), "downloadUrl")).GET().build(),
                        HttpResponse.BodyHandlers.ofByteArray());
                if (download.statusCode() / 100 != 2) {
                    System.err.println("Download failed with status: " + download.statusCode());
                    System.exit(1);
                }
                Files.write(OUTPUT_PATH, download.body());
                System.out.println("Saved obfuscated script to " + OUTPUT_PATH);
                return;
            }

            if ("failed".equals(status) || elapsed >= MAX_WAIT) {
                System.err.println("Obfuscation failed (status: " + status + " | elapsed time: " + elapsed + ")");
                System.exit(1);
            }

            System.out.println("Obfuscation is still in progress. Elapsed time: " + elapsed + " seconds. Checking again in " + (RETRY_DELAY + wait) + " seconds.");
        }
    }
}
