' Windows Script Host. Run with: cscript //nologo script.vbs
Option Explicit

Const BASE_URL = "https://ironbrew1.com"
Const API_KEY = "IB1-APIKEYHERE"

Const INPUT_PATH = "input.lua"
Const OUTPUT_PATH = "output.lua"

Const QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

Const RETRY_DELAY = 5
Const MAX_WAIT = 240
Const MAX_FAILS = 3

Sub Fail(message)
    WScript.StdErr.WriteLine message
    WScript.Quit 1
End Sub

Function ReadBytes(path)
    Dim stream: Set stream = CreateObject("ADODB.Stream")
    stream.Type = 1 ' binary
    stream.Open
    stream.LoadFromFile path
    ReadBytes = stream.Read
    stream.Close
End Function

Sub WriteBytes(path, bytes)
    Dim stream: Set stream = CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.Write bytes
    stream.SaveToFile path, 2 ' overwrite
    stream.Close
End Sub

' Sends a request and returns the XMLHTTP object (check .Status and .ResponseText / .ResponseBody).
Function Request(method, path, body)
    Dim http: Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 30000, 30000, 120000, 120000
    http.open method, BASE_URL & path, False
    http.setRequestHeader "Key", API_KEY
    If IsEmpty(body) Then
        http.send
    Else
        http.setRequestHeader "Content-Type", "text/plain"
        http.send body
    End If
    Set Request = http
End Function

' Pulls a string value out of a flat JSON object without needing a JSON library.
Function Field(json, name)
    Dim re: Set re = New RegExp
    re.Pattern = """" & name & """\s*:\s*""([^""]*)"""
    Dim matches: Set matches = re.Execute(json)
    If matches.Count > 0 Then Field = Replace(matches(0).SubMatches(0), "\/", "/") Else Field = ""
End Function

Function Ok(code)
    Ok = (code >= 200 And code < 300)
End Function

Dim queued: Set queued = Request("POST", "/obfuscate?" & QUERY, ReadBytes(INPUT_PATH))
If Not Ok(queued.Status) Then Fail "Unable to queue obfuscation: " & queued.Status

Dim statusUrl: statusUrl = Field(queued.ResponseText, "statusUrl")
WScript.Echo "Obfuscation started with GUID: " & Field(queued.ResponseText, "uploadGuid")

Dim elapsed, fails, waitTime, response, state, download
elapsed = 0: fails = 0: waitTime = 0

Do
    waitTime = waitTime + RETRY_DELAY
    WScript.Sleep waitTime * 1000
    elapsed = elapsed + waitTime

    Set response = Request("GET", statusUrl, Empty)
    If Not Ok(response.Status) Then
        fails = fails + 1
        WScript.Echo "Status check failed with status: " & response.Status & " (" & fails & "/" & MAX_FAILS & ")"
        If fails >= MAX_FAILS Or elapsed >= MAX_WAIT Then Fail "Obfuscation failed (fails: " & fails & " | elapsed time: " & elapsed & ")"
    Else
        state = Field(response.ResponseText, "status")

        If state = "completed" Then
            WScript.Echo "Obfuscation completed in " & elapsed & " seconds"
            Set download = Request("GET", Field(response.ResponseText, "downloadUrl"), Empty)
            If Not Ok(download.Status) Then Fail "Download failed with status: " & download.Status
            WriteBytes OUTPUT_PATH, download.ResponseBody
            WScript.Echo "Saved obfuscated script to " & OUTPUT_PATH
            Exit Do
        End If

        If state = "failed" Or elapsed >= MAX_WAIT Then Fail "Obfuscation failed (status: " & state & " | elapsed time: " & elapsed & ")"

        WScript.Echo "Obfuscation is still in progress. Elapsed time: " & elapsed & " seconds. Checking again in " & (RETRY_DELAY + waitTime) & " seconds."
    End If
Loop
