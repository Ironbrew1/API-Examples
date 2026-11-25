# Run with: tclsh script.tcl   (needs Tcl 8.6, tcllib and the TclTLS package)
package require http
package require tls
package require json

http::register https 443 [list ::tls::socket -autoservername true]

set baseUrl "https://ironbrew1.com"
set apiKey "IB1-APIKEYHERE"

set inputPath "input.lua"
set outputPath "output.lua"

set query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

set retryDelay 5
set maxWait 240
set maxFails 3

proc fail {message} {
    puts stderr $message
    exit 1
}

# Returns a {status-code body} pair.
proc request {method path {body ""}} {
    global baseUrl apiKey
    set args [list -method $method -headers [list Key $apiKey] -timeout 120000 -binary 1]
    if {$method eq "POST"} {
        lappend args -type text/plain -query $body
    }
    set token [http::geturl $baseUrl$path {*}$args]
    set result [list [http::ncode $token] [http::data $token]]
    http::cleanup $token
    return $result
}

proc ok {code} {
    expr {$code >= 200 && $code < 300}
}

set file [open $inputPath rb]
set source [read $file]
close $file

lassign [request POST "/obfuscate?$query" $source] code body
if {![ok $code]} {
    fail "Unable to queue obfuscation: $code"
}

set queued [json::json2dict $body]
puts "Obfuscation started with GUID: [dict get $queued uploadGuid]"

set elapsed 0
set fails 0
set wait 0

while {true} {
    incr wait $retryDelay
    after [expr {$wait * 1000}]
    incr elapsed $wait

    lassign [request GET [dict get $queued statusUrl]] code body
    if {![ok $code]} {
        incr fails
        puts "Status check failed with status: $code ($fails/$maxFails)"
        if {$fails >= $maxFails || $elapsed >= $maxWait} {
            fail "Obfuscation failed (fails: $fails | elapsed time: $elapsed)"
        }
        continue
    }

    set status [json::json2dict $body]
    set state [dict get $status status]

    if {$state eq "completed"} {
        puts "Obfuscation completed in $elapsed seconds"
        lassign [request GET [dict get $status downloadUrl]] code script
        if {![ok $code]} {
            fail "Download failed with status: $code"
        }
        set out [open $outputPath wb]
        puts -nonewline $out $script
        close $out
        puts "Saved obfuscated script to $outputPath"
        break
    }

    if {$state eq "failed" || $elapsed >= $maxWait} {
        fail "Obfuscation failed (status: $state | elapsed time: $elapsed)"
    }

    puts "Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in [expr {$retryDelay + $wait}] seconds."
}
