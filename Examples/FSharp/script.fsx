// Run with: dotnet fsi script.fsx
open System
open System.IO
open System.Net.Http
open System.Text.Json
open System.Threading

let baseUrl = "https://ironbrew1.com"
let apiKey = "IB1-APIKEYHERE"

let inputPath = "input.lua"
let outputPath = "output.lua"

let query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

let retryDelay = 5
let maxWait = 240
let maxFails = 3

let fail (message: string) : 'a =
    eprintfn "%s" message
    exit 1

let http = new HttpClient(Timeout = TimeSpan.FromSeconds 120.0)
http.DefaultRequestHeaders.Add("Key", apiKey)

let queueContent = new ByteArrayContent(File.ReadAllBytes inputPath)
queueContent.Headers.ContentType <- Headers.MediaTypeHeaderValue("text/plain")

let queueResponse = http.PostAsync($"{baseUrl}/obfuscate?{query}", queueContent).Result
if not queueResponse.IsSuccessStatusCode then
    fail $"Unable to queue obfuscation: {int queueResponse.StatusCode}"

let queued = JsonDocument.Parse(queueResponse.Content.ReadAsStringAsync().Result).RootElement
let statusUrl = queued.GetProperty("statusUrl").GetString()
printfn "Obfuscation started with GUID: %s" (queued.GetProperty("uploadGuid").GetString())

let rec poll elapsed fails wait =
    let wait = wait + retryDelay
    Thread.Sleep(wait * 1000)
    let elapsed = elapsed + wait

    let response = http.GetAsync(baseUrl + statusUrl).Result
    if not response.IsSuccessStatusCode then
        let fails = fails + 1
        printfn "Status check failed with status: %d (%d/%d)" (int response.StatusCode) fails maxFails
        if fails >= maxFails || elapsed >= maxWait then
            fail $"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})"
        poll elapsed fails wait
    else
        let status = JsonDocument.Parse(response.Content.ReadAsStringAsync().Result).RootElement
        let state = status.GetProperty("status").GetString()

        if state = "completed" then
            printfn "Obfuscation completed in %d seconds" elapsed
            let download = http.GetAsync(baseUrl + status.GetProperty("downloadUrl").GetString()).Result
            if not download.IsSuccessStatusCode then
                fail $"Download failed with status: {int download.StatusCode}"
            File.WriteAllBytes(outputPath, download.Content.ReadAsByteArrayAsync().Result)
            printfn "Saved obfuscated script to %s" outputPath
        elif state = "failed" || elapsed >= maxWait then
            fail $"Obfuscation failed (status: {state} | elapsed time: {elapsed})"
        else
            printfn "Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds." elapsed (retryDelay + wait)
            poll elapsed fails wait

poll 0 0 0
