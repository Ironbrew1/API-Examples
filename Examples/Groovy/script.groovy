import groovy.json.JsonSlurper
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration

// Run with: groovy script.groovy
final BASE_URL = "https://ironbrew1.com"
final API_KEY = "IB1-APIKEYHERE"

final INPUT_PATH = Path.of("input.lua")
final OUTPUT_PATH = Path.of("output.lua")

final QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

final RETRY_DELAY = 5
final MAX_WAIT = 240
final MAX_FAILS = 3

def client = HttpClient.newHttpClient()
def slurper = new JsonSlurper()

def request = { String path ->
    HttpRequest.newBuilder(URI.create(BASE_URL + path)).timeout(Duration.ofSeconds(120)).header("Key", API_KEY)
}

def fail = { String message ->
    System.err.println(message)
    System.exit(1)
}

def queueResponse = client.send(
    request("/obfuscate?" + QUERY)
        .header("Content-Type", "text/plain")
        .POST(HttpRequest.BodyPublishers.ofFile(INPUT_PATH))
        .build(),
    HttpResponse.BodyHandlers.ofString())
if (queueResponse.statusCode().intdiv(100) != 2) fail("Unable to queue obfuscation: ${queueResponse.statusCode()}")

def queued = slurper.parseText(queueResponse.body())
println "Obfuscation started with GUID: ${queued.uploadGuid}"

int elapsed = 0, fails = 0, wait = 0

while (true) {
    wait += RETRY_DELAY
    sleep(wait * 1000L)
    elapsed += wait

    def statusResponse = client.send(request(queued.statusUrl).GET().build(), HttpResponse.BodyHandlers.ofString())
    if (statusResponse.statusCode().intdiv(100) != 2) {
        fails++
        println "Status check failed with status: ${statusResponse.statusCode()} ($fails/$MAX_FAILS)"
        if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) fail("Obfuscation failed (fails: $fails | elapsed time: $elapsed)")
        continue
    }

    def status = slurper.parseText(statusResponse.body())

    if (status.status == "completed") {
        println "Obfuscation completed in $elapsed seconds"
        def download = client.send(request(status.downloadUrl).GET().build(), HttpResponse.BodyHandlers.ofByteArray())
        if (download.statusCode().intdiv(100) != 2) fail("Download failed with status: ${download.statusCode()}")
        Files.write(OUTPUT_PATH, download.body())
        println "Saved obfuscated script to $OUTPUT_PATH"
        break
    }

    if (status.status == "failed" || elapsed >= MAX_WAIT) {
        fail("Obfuscation failed (status: ${status.status} | elapsed time: $elapsed)")
    }

    println "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in ${RETRY_DELAY + wait} seconds."
}
