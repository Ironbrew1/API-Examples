# Requires at least PS 5.1
$ErrorActionPreference = "Stop"

$BaseUrl = "https://ironbrew1.com"
$ApiKey = "IB1-APIKEYHERE"

$InputPath = "input.lua"
$OutputPath = "output.lua"

$Query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

$RetryDelay = 5
$MaxWait = 240
$MaxFails = 3

$Headers = @{ Key = $ApiKey }

$Queued = Invoke-RestMethod -Method Post -Uri "$BaseUrl/obfuscate?$Query" -Headers $Headers `
    -ContentType "text/plain" -InFile $InputPath
Write-Host "Obfuscation started with GUID: $($Queued.uploadGuid)"

$Elapsed = 0
$Fails = 0
$Wait = 0

while ($true) {
    $Wait += $RetryDelay
    Start-Sleep -Seconds $Wait
    $Elapsed += $Wait

    try {
        $Status = Invoke-RestMethod -Uri ($BaseUrl + $Queued.statusUrl) -Headers $Headers
    } catch {
        $Fails++
        Write-Host "Status check failed ($Fails/$MaxFails): $($_.Exception.Message)"
        if ($Fails -ge $MaxFails -or $Elapsed -ge $MaxWait) {
            throw "Obfuscation failed (fails: $Fails | elapsed time: $Elapsed)"
        }
        continue
    }

    if ($Status.status -eq "completed") {
        Write-Host "Obfuscation completed in $Elapsed seconds"
        Invoke-WebRequest -Uri ($BaseUrl + $Status.downloadUrl) -Headers $Headers -OutFile $OutputPath | Out-Null
        Write-Host "Saved obfuscated script to $OutputPath"
        break
    }

    if ($Status.status -eq "failed" -or $Elapsed -ge $MaxWait) {
        throw "Obfuscation failed (status: $($Status.status) | elapsed time: $Elapsed)"
    }

    Write-Host "Obfuscation is still in progress. Elapsed time: $Elapsed seconds. Checking again in $($RetryDelay + $Wait) seconds."
}
