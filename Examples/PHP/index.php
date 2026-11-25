<?php
// Requires PHP 7.4+ with the curl extension.

const BASE_URL = "https://ironbrew1.com";
const API_KEY = "IB1-APIKEYHERE";

const INPUT_PATH = "input.lua";
const OUTPUT_PATH = "output.lua";

const OPTIONS = [
    "platform" => "roblox",
    "aggressiveOptimizations" => "0",
    "intenseVmScrambling" => "false",
    "enableVmCompression" => "false",
];

const RETRY_DELAY = 5;
const MAX_WAIT = 240;
const MAX_FAILS = 3;

function request(string $method, string $path, ?string $body = null): array
{
    $ch = curl_init(BASE_URL . $path);
    $headers = ["Key: " . API_KEY];
    if ($body !== null) {
        $headers[] = "Content-Type: text/plain";
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 120,
    ]);
    $response = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    return [$code, $response];
}

function fail(string $message): never
{
    fwrite(STDERR, $message . PHP_EOL);
    exit(1);
}

$source = file_get_contents(INPUT_PATH);
if ($source === false) {
    fail("Unable to read " . INPUT_PATH);
}

[$code, $body] = request("POST", "/obfuscate?" . http_build_query(OPTIONS), $source);
if ($code < 200 || $code >= 300) {
    fail("Unable to queue obfuscation: $code");
}

$queued = json_decode($body, true);
echo "Obfuscation started with GUID: {$queued['uploadGuid']}\n";

$elapsed = 0;
$fails = 0;
$wait = 0;

while (true) {
    $wait += RETRY_DELAY;
    sleep($wait);
    $elapsed += $wait;

    [$code, $body] = request("GET", $queued["statusUrl"]);
    if ($code < 200 || $code >= 300) {
        $fails++;
        echo "Status check failed with status: $code ($fails/" . MAX_FAILS . ")\n";
        if ($fails >= MAX_FAILS || $elapsed >= MAX_WAIT) {
            fail("Obfuscation failed (fails: $fails | elapsed time: $elapsed)");
        }
        continue;
    }

    $status = json_decode($body, true);

    if ($status["status"] === "completed") {
        echo "Obfuscation completed in $elapsed seconds\n";
        [$code, $script] = request("GET", $status["downloadUrl"]);
        if ($code < 200 || $code >= 300) {
            fail("Download failed with status: $code");
        }
        file_put_contents(OUTPUT_PATH, $script);
        echo "Saved obfuscated script to " . OUTPUT_PATH . "\n";
        break;
    }

    if ($status["status"] === "failed" || $elapsed >= MAX_WAIT) {
        fail("Obfuscation failed (status: {$status['status']} | elapsed time: $elapsed)");
    }

    echo "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in " . (RETRY_DELAY + $wait) . " seconds.\n";
}
