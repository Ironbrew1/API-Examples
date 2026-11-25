import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let baseURL = "https://ironbrew1.com"
let apiKey = "IB1-APIKEYHERE"

let inputPath = "input.lua"
let outputPath = "output.lua"

let query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

let retryDelay = 5
let maxWait = 240
let maxFails = 3

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

// Blocking request helper: returns the HTTP status code and body.
func send(_ method: String, _ path: String, body: Data? = nil) -> (Int, Data) {
    var request = URLRequest(url: URL(string: baseURL + path)!)
    request.httpMethod = method
    request.timeoutInterval = 120
    request.setValue(apiKey, forHTTPHeaderField: "Key")
    if let body = body {
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: (Int, Data) = (0, Data())
    URLSession.shared.dataTask(with: request) { data, response, _ in
        result = ((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data())
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return result
}

func json(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

guard let source = FileManager.default.contents(atPath: inputPath) else { fail("Unable to read \(inputPath)") }

let (queueCode, queueBody) = send("POST", "/obfuscate?\(query)", body: source)
guard queueCode / 100 == 2 else { fail("Unable to queue obfuscation: \(queueCode)") }

let queued = json(queueBody)
guard let statusUrl = queued["statusUrl"] as? String else { fail("Response is missing statusUrl") }
print("Obfuscation started with GUID: \(queued["uploadGuid"] as? String ?? "")")

var elapsed = 0
var fails = 0
var wait = 0

while true {
    wait += retryDelay
    sleep(UInt32(wait))
    elapsed += wait

    let (code, body) = send("GET", statusUrl)
    if code / 100 != 2 {
        fails += 1
        print("Status check failed with status: \(code) (\(fails)/\(maxFails))")
        if fails >= maxFails || elapsed >= maxWait { fail("Obfuscation failed (fails: \(fails) | elapsed time: \(elapsed))") }
        continue
    }

    let status = json(body)
    let state = status["status"] as? String ?? ""

    if state == "completed" {
        print("Obfuscation completed in \(elapsed) seconds")
        guard let downloadUrl = status["downloadUrl"] as? String else { fail("Response is missing downloadUrl") }
        let (downloadCode, script) = send("GET", downloadUrl)
        guard downloadCode / 100 == 2 else { fail("Download failed with status: \(downloadCode)") }
        FileManager.default.createFile(atPath: outputPath, contents: script)
        print("Saved obfuscated script to \(outputPath)")
        break
    }

    if state == "failed" || elapsed >= maxWait { fail("Obfuscation failed (status: \(state) | elapsed time: \(elapsed))") }

    print("Obfuscation is still in progress. Elapsed time: \(elapsed) seconds. Checking again in \(retryDelay + wait) seconds.")
}
