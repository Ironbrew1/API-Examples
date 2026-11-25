use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP;

my $BASE_URL = "https://ironbrew1.com";
my $API_KEY  = "IB1-APIKEYHERE";

my $INPUT_PATH  = "input.lua";
my $OUTPUT_PATH = "output.lua";

my $QUERY = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

my $RETRY_DELAY = 5;
my $MAX_WAIT    = 240;
my $MAX_FAILS   = 3;

my $http = HTTP::Tiny->new(timeout => 120);

sub slurp {
    my ($path) = @_;
    open my $fh, "<:raw", $path or die "Unable to read $path: $!\n";
    local $/;
    return <$fh>;
}

my $queue = $http->post("$BASE_URL/obfuscate?$QUERY", {
    headers => { Key => $API_KEY, "Content-Type" => "text/plain" },
    content => slurp($INPUT_PATH),
});
die "Unable to queue obfuscation: $queue->{status} $queue->{content}\n" unless $queue->{success};

my $queued = decode_json($queue->{content});
print "Obfuscation started with GUID: $queued->{uploadGuid}\n";

my ($elapsed, $fails, $wait) = (0, 0, 0);

while (1) {
    $wait += $RETRY_DELAY;
    sleep $wait;
    $elapsed += $wait;

    my $response = $http->get($BASE_URL . $queued->{statusUrl}, { headers => { Key => $API_KEY } });
    unless ($response->{success}) {
        $fails++;
        print "Status check failed with status: $response->{status} ($fails/$MAX_FAILS)\n";
        die "Obfuscation failed (fails: $fails | elapsed time: $elapsed)\n" if $fails >= $MAX_FAILS || $elapsed >= $MAX_WAIT;
        next;
    }

    my $status = decode_json($response->{content});

    if ($status->{status} eq "completed") {
        print "Obfuscation completed in $elapsed seconds\n";
        my $download = $http->get($BASE_URL . $status->{downloadUrl}, { headers => { Key => $API_KEY } });
        die "Download failed with status: $download->{status}\n" unless $download->{success};
        open my $out, ">:raw", $OUTPUT_PATH or die "Unable to write $OUTPUT_PATH: $!\n";
        print $out $download->{content};
        close $out;
        print "Saved obfuscated script to $OUTPUT_PATH\n";
        last;
    }

    if ($status->{status} eq "failed" || $elapsed >= $MAX_WAIT) {
        die "Obfuscation failed (status: $status->{status} | elapsed time: $elapsed)\n";
    }

    print "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in " . ($RETRY_DELAY + $wait) . " seconds.\n";
}
