; AutoHotkey v2 (Windows). Run with: AutoHotkey64.exe /ErrorStdOut script.ahk
#Requires AutoHotkey v2.0

BASE_URL := "https://ironbrew1.com"
API_KEY := "IB1-APIKEYHERE"

INPUT_PATH := "input.lua"
OUTPUT_PATH := "output.lua"

QUERY := "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

RETRY_DELAY := 5
MAX_WAIT := 240
MAX_FAILS := 3

Fail(message) {
    FileAppend(message "`n", "**") ; stderr
    ExitApp(1)
}

Ok(code) => code >= 200 && code < 300

; Returns the WinHttp request object (check .Status and .ResponseText).
Request(method, path, body := "") {
    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.SetTimeouts(30000, 30000, 120000, 120000)
    http.Open(method, BASE_URL path, false)
    http.SetRequestHeader("Key", API_KEY)
    if (body != "") {
        http.SetRequestHeader("Content-Type", "text/plain")
        http.Send(body)
    } else {
        http.Send()
    }
    return http
}

; Pulls a string value out of a flat JSON object without needing a JSON library.
Field(json, name) {
    if RegExMatch(json, '"' name '"\s*:\s*"([^"]*)"', &match)
        return StrReplace(match[1], "\/", "/")
    return ""
}

queued := Request("POST", "/obfuscate?" QUERY, FileRead(INPUT_PATH, "UTF-8"))
if !Ok(queued.Status)
    Fail("Unable to queue obfuscation: " queued.Status)

statusUrl := Field(queued.ResponseText, "statusUrl")
FileAppend("Obfuscation started with GUID: " Field(queued.ResponseText, "uploadGuid") "`n", "*")

elapsed := 0
fails := 0
wait := 0

Loop {
    wait += RETRY_DELAY
    Sleep(wait * 1000)
    elapsed += wait

    response := Request("GET", statusUrl)
    if !Ok(response.Status) {
        fails += 1
        FileAppend("Status check failed with status: " response.Status " (" fails "/" MAX_FAILS ")`n", "*")
        if (fails >= MAX_FAILS || elapsed >= MAX_WAIT)
            Fail("Obfuscation failed (fails: " fails " | elapsed time: " elapsed ")")
        continue
    }

    state := Field(response.ResponseText, "status")

    if (state = "completed") {
        FileAppend("Obfuscation completed in " elapsed " seconds`n", "*")
        downloadResponse := Request("GET", Field(response.ResponseText, "downloadUrl"))
        if !Ok(downloadResponse.Status)
            Fail("Download failed with status: " downloadResponse.Status)
        if FileExist(OUTPUT_PATH)
            FileDelete(OUTPUT_PATH)
        FileAppend(downloadResponse.ResponseText, OUTPUT_PATH, "UTF-8-RAW")
        FileAppend("Saved obfuscated script to " OUTPUT_PATH "`n", "*")
        break
    }

    if (state = "failed" || elapsed >= MAX_WAIT)
        Fail("Obfuscation failed (status: " state " | elapsed time: " elapsed ")")

    FileAppend("Obfuscation is still in progress. Elapsed time: " elapsed " seconds. Checking again in " (RETRY_DELAY + wait) " seconds.`n", "*")
}
