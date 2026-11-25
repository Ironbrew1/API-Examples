# Run with Nushell 0.90+: nu script.nu
const base_url = "https://ironbrew1.com"
const api_key = "IB1-APIKEYHERE"

const input_path = "input.lua"
const output_path = "output.lua"

const query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

const retry_delay = 5
const max_wait = 240
const max_fails = 3

def fail [message: string] {
    print --stderr $message
    exit 1
}

def ok [response: record] {
    $response.status >= 200 and $response.status < 300
}

let queue_response = (http post --full --allow-errors --headers [Key $api_key] --content-type "text/plain" $"($base_url)/obfuscate?($query)" (open --raw $input_path))
if not (ok $queue_response) { fail $"Unable to queue obfuscation: ($queue_response.status)" }

let queued = $queue_response.body
print $"Obfuscation started with GUID: ($queued.uploadGuid)"

mut elapsed = 0
mut fails = 0
mut wait = 0

loop {
    $wait += $retry_delay
    sleep ($wait * 1sec)
    $elapsed += $wait

    let response = (http get --full --allow-errors --headers [Key $api_key] $"($base_url)($queued.statusUrl)")
    if not (ok $response) {
        $fails += 1
        print $"Status check failed with status: ($response.status) \(($fails)/($max_fails)\)"
        if $fails >= $max_fails or $elapsed >= $max_wait {
            fail $"Obfuscation failed \(fails: ($fails) | elapsed time: ($elapsed)\)"
        }
        continue
    }

    let status = $response.body

    if $status.status == "completed" {
        print $"Obfuscation completed in ($elapsed) seconds"
        let download = (http get --full --allow-errors --raw --headers [Key $api_key] $"($base_url)($status.downloadUrl)")
        if not (ok $download) { fail $"Download failed with status: ($download.status)" }
        $download.body | save --raw --force $output_path
        print $"Saved obfuscated script to ($output_path)"
        break
    }

    if $status.status == "failed" or $elapsed >= $max_wait {
        fail $"Obfuscation failed \(status: ($status.status) | elapsed time: ($elapsed)\)"
    }

    print $"Obfuscation is still in progress. Elapsed time: ($elapsed) seconds. Checking again in ($retry_delay + $wait) seconds."
}
