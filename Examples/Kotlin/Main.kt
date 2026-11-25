import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration
import kotlin.system.exitProcess

const val BASE_URL = "https://ironbrew1.com"
const val API_KEY = "IB1-APIKEYHERE"

val INPUT_PATH: Path = Path.of("input.lua")
val OUTPUT_PATH: Path = Path.of("output.lua")

const val QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

const val RETRY_DELAY = 5
const val MAX_WAIT = 240
const val MAX_FAILS = 3

val client: HttpClient = HttpClient.newHttpClient()

// Pulls a string value out of a flat JSON object without needing a JSON library.
fun field(json: String, name: String): String? =
    Regex("\"$name\"\\s*:\\s*\"([^\"]*)\"").find(json)?.groupValues?.get(1)?.replace("\\/", "/")

fun request(path: String): HttpRequest.Builder =
    HttpRequest.newBuilder(URI.create(BASE_URL + path))
        .timeout(Duration.ofSeconds(120))
        .header("Key", API_KEY)

fun fail(message: String): Nothing {
    System.err.println(message)
    exitProcess(1)
}

fun main() {
    val queueResponse = client.send(
        request("/obfuscate?$QUERY")
            .header("Content-Type", "text/plain")
            .POST(HttpRequest.BodyPublishers.ofFile(INPUT_PATH))
            .build(),
        HttpResponse.BodyHandlers.ofString(),
    )
    if (queueResponse.statusCode() / 100 != 2) fail("Unable to queue obfuscation: ${queueResponse.statusCode()}")

    val statusUrl = field(queueResponse.body(), "statusUrl") ?: fail("Response is missing statusUrl")
    println("Obfuscation started with GUID: ${field(queueResponse.body(), "uploadGuid")}")

    var elapsed = 0
    var fails = 0
    var wait = 0

    while (true) {
        wait += RETRY_DELAY
        Thread.sleep(wait * 1000L)
        elapsed += wait

        val statusResponse = client.send(request(statusUrl).GET().build(), HttpResponse.BodyHandlers.ofString())
        if (statusResponse.statusCode() / 100 != 2) {
            fails++
            println("Status check failed with status: ${statusResponse.statusCode()} ($fails/$MAX_FAILS)")
            if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) fail("Obfuscation failed (fails: $fails | elapsed time: $elapsed)")
            continue
        }

        val status = field(statusResponse.body(), "status")

        if (status == "completed") {
            println("Obfuscation completed in $elapsed seconds")
            val downloadUrl = field(statusResponse.body(), "downloadUrl") ?: fail("Response is missing downloadUrl")
            val download = client.send(request(downloadUrl).GET().build(), HttpResponse.BodyHandlers.ofByteArray())
            if (download.statusCode() / 100 != 2) fail("Download failed with status: ${download.statusCode()}")
            Files.write(OUTPUT_PATH, download.body())
            println("Saved obfuscated script to $OUTPUT_PATH")
            return
        }

        if (status == "failed" || elapsed >= MAX_WAIT) fail("Obfuscation failed (status: $status | elapsed time: $elapsed)")

        println("Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in ${RETRY_DELAY + wait} seconds.")
    }
}
