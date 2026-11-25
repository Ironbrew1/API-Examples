# Run with: raku script.raku
# Needs: zef install HTTP::UserAgent JSON::Fast IO::Socket::SSL   (and the OpenSSL libraries)
# Note: HTTP::UserAgent handles request and response bodies as text, which is fine for Lua scripts.
use HTTP::UserAgent;
use JSON::Fast;

constant BASE_URL = 'https://ironbrew1.com';
constant API_KEY = 'IB1-APIKEYHERE';

constant INPUT_PATH = 'input.lua';
constant OUTPUT_PATH = 'output.lua';

constant QUERY = 'platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false';

constant RETRY_DELAY = 5;
constant MAX_WAIT = 240;
constant MAX_FAILS = 3;

my $ua = HTTP::UserAgent.new(timeout => 120);

sub fail(Str $message) {
    note $message;
    exit 1;
}

sub ok(Int $code) { 200 <= $code < 300 }

sub request(Str $method, Str $path, Str $body?) {
    my $request = HTTP::Request.new(|($method => BASE_URL ~ $path));
    $request.header.field(Key => API_KEY);
    if $body {
        $request.header.field(Content-Type => 'text/plain');
        $request.header.field(Content-Length => $body.encode.bytes);
        $request.content = $body;
    }
    my $response = $ua.request($request);
    ($response.code, $response.content);
}

my ($code, $body) = request('POST', "/obfuscate?{QUERY}", INPUT_PATH.IO.slurp);
fail "Unable to queue obfuscation: $code" unless ok($code);

my %queued = from-json($body.Str);
say "Obfuscation started with GUID: %queued<uploadGuid>";

my ($elapsed, $fails, $wait) = 0, 0, 0;

loop {
    $wait += RETRY_DELAY;
    sleep $wait;
    $elapsed += $wait;

    ($code, $body) = request('GET', %queued<statusUrl>);
    unless ok($code) {
        $fails++;
        say "Status check failed with status: $code ($fails/{MAX_FAILS})";
        fail "Obfuscation failed (fails: $fails | elapsed time: $elapsed)" if $fails >= MAX_FAILS || $elapsed >= MAX_WAIT;
        next;
    }

    my %status = from-json($body.Str);

    if %status<status> eq 'completed' {
        say "Obfuscation completed in $elapsed seconds";
        my ($download-code, $script) = request('GET', %status<downloadUrl>);
        fail "Download failed with status: $download-code" unless ok($download-code);
        OUTPUT_PATH.IO.spurt($script);
        say "Saved obfuscated script to {OUTPUT_PATH}";
        last;
    }

    if %status<status> eq 'failed' || $elapsed >= MAX_WAIT {
        fail "Obfuscation failed (status: %status<status> | elapsed time: $elapsed)";
    }

    say "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in {RETRY_DELAY + $wait} seconds.";
}
