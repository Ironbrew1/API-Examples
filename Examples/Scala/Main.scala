//> using scala 3
// Run with scala-cli: scala-cli run Main.scala
import java.net.URI
import java.net.http.{HttpClient, HttpRequest, HttpResponse}
import java.nio.file.{Files, Path}
import java.time.Duration

val BaseUrl = "https://ironbrew1.com"
val ApiKey = "IB1-APIKEYHERE"

val InputPath = Path.of("input.lua")
val OutputPath = Path.of("output.lua")

val Query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

val RetryDelay = 5
val MaxWait = 240
val MaxFails = 3

val client = HttpClient.newHttpClient()

// Pulls a string value out of a flat JSON object without needing a JSON library.
def field(json: String, name: String): Option[String] =
  s"\"$name\"\\s*:\\s*\"([^\"]*)\"".r.findFirstMatchIn(json).map(_.group(1).replace("\\/", "/"))

def request(path: String): HttpRequest.Builder =
  HttpRequest.newBuilder(URI.create(BaseUrl + path)).timeout(Duration.ofSeconds(120)).header("Key", ApiKey)

def fail(message: String): Nothing =
  System.err.println(message)
  sys.exit(1)

@main def main(): Unit =
  val queueResponse = client.send(
    request(s"/obfuscate?$Query")
      .header("Content-Type", "text/plain")
      .POST(HttpRequest.BodyPublishers.ofFile(InputPath))
      .build(),
    HttpResponse.BodyHandlers.ofString()
  )
  if queueResponse.statusCode() / 100 != 2 then fail(s"Unable to queue obfuscation: ${queueResponse.statusCode()}")

  val statusUrl = field(queueResponse.body(), "statusUrl").getOrElse(fail("Response is missing statusUrl"))
  println(s"Obfuscation started with GUID: ${field(queueResponse.body(), "uploadGuid").getOrElse("")}")

  var elapsed = 0
  var fails = 0
  var wait = 0

  while true do
    wait += RetryDelay
    Thread.sleep(wait * 1000L)
    elapsed += wait

    val statusResponse = client.send(request(statusUrl).GET().build(), HttpResponse.BodyHandlers.ofString())
    if statusResponse.statusCode() / 100 != 2 then
      fails += 1
      println(s"Status check failed with status: ${statusResponse.statusCode()} ($fails/$MaxFails)")
      if fails >= MaxFails || elapsed >= MaxWait then fail(s"Obfuscation failed (fails: $fails | elapsed time: $elapsed)")
    else
      val status = field(statusResponse.body(), "status").getOrElse("")

      if status == "completed" then
        println(s"Obfuscation completed in $elapsed seconds")
        val downloadUrl = field(statusResponse.body(), "downloadUrl").getOrElse(fail("Response is missing downloadUrl"))
        val download = client.send(request(downloadUrl).GET().build(), HttpResponse.BodyHandlers.ofByteArray())
        if download.statusCode() / 100 != 2 then fail(s"Download failed with status: ${download.statusCode()}")
        Files.write(OutputPath, download.body())
        println(s"Saved obfuscated script to $OutputPath")
        sys.exit(0)

      if status == "failed" || elapsed >= MaxWait then fail(s"Obfuscation failed (status: $status | elapsed time: $elapsed)")

      println(s"Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in ${RetryDelay + wait} seconds.")
