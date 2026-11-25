\ Gforth. Run with: gforth main.fs   (tested with gforth 0.7.3)
\
\ NOTE: the API is HTTPS-only and Forth has no standard networking, so this example calls
\ libcurl (and a few libc functions) through gforth's libcc FFI. Building it needs gforth,
\ gcc, GNU libtool and the libcurl development headers
\ (apt install gforth gcc libtool-bin libcurl4-openssl-dev).
\ Request and response bodies are streamed through C FILE* handles, so no callbacks are
\ needed, and the small JSON replies are scanned with the string words below.

c-library curl
    s" curl" add-lib
    \c #include <curl/curl.h>
    \c #include <stdio.h>
    \c #include <stdlib.h>
    \c #include <unistd.h>
    c-function curl-init curl_easy_init -- a
    c-function curl-setopt-ptr curl_easy_setopt a n a -- n
    c-function curl-setopt-long curl_easy_setopt a n n -- n
    c-function curl-perform curl_easy_perform a -- n
    c-function curl-getinfo curl_easy_getinfo a n a -- n
    c-function curl-cleanup curl_easy_cleanup a -- void
    c-function slist-append curl_slist_append a a -- a
    c-function slist-free curl_slist_free_all a -- void
    c-function c-fopen fopen a a -- a
    c-function c-fclose fclose a -- n
    c-function c-fseek fseek a n n -- n
    c-function c-ftell ftell a -- n
    c-function c-rewind rewind a -- void
    c-function c-fmemopen fmemopen a n a -- a
    c-function c-sleep sleep n -- n
    c-function libc-exit exit n -- void
end-c-library

10002 constant CURLOPT_URL
10001 constant CURLOPT_WRITEDATA
10009 constant CURLOPT_READDATA
10023 constant CURLOPT_HTTPHEADER
   13 constant CURLOPT_TIMEOUT
   47 constant CURLOPT_POST
   60 constant CURLOPT_POSTFIELDSIZE
2097154 constant CURLINFO_RESPONSE_CODE
    2 constant SEEK_END

5 constant retry-delay
240 constant max-wait
3 constant max-fails

\ Copies a Forth string into the dictionary as a NUL terminated C string.
: cstring { addr u -- a }
    here dup addr swap u move
    dup u + 0 swap c!
    u 1+ allot ;

s" https://ironbrew1.com" cstring constant base-url
s" /obfuscate?platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false" cstring constant queue-path
s" Key: IB1-APIKEYHERE" cstring constant key-header
s" Content-Type: text/plain" cstring constant type-header
s" input.lua" cstring constant input-path
s" output.lua" cstring constant output-path
s" rb" cstring constant mode-rb
s" wb" cstring constant mode-wb
s" w" cstring constant mode-w
s" uploadGuid" cstring constant f-guid
s" statusUrl" cstring constant f-status-url
s" status" cstring constant f-status
s" downloadUrl" cstring constant f-download

create response 8192 allot
create url 1024 allot
create pattern 64 allot
create guid 128 allot
create status-url 256 allot
create job-status 64 allot
create download-url 256 allot

variable http-code       \ the long that curl_easy_getinfo writes into
variable pattern-length
variable cursor            \ position while scanning a JSON reply
variable elapsed
variable fails
variable wait

: zlen ( za -- u ) dup begin dup c@ while 1+ repeat swap - ;

: zprint ( za -- ) dup zlen type ;

: fail ( za -- ) zprint cr 1 libc-exit ;

: ok? ( code -- f ) dup 200 >= swap 300 < and ;

\ Copies a C string to dest and returns the address of its NUL terminator.
: zcat { dest src -- end }
    begin src c@ while
        src c@ dest c!  dest 1 + to dest  src 1 + to src
    repeat
    0 dest c!  dest ;

\ Joins two C strings into dest, so URLs can be built from the base URL and a path.
: zpair ( dest za zb -- ) >r zcat r> zcat drop ;

\ Returns the address of pat inside hay, or 0 when it does not occur.
: zfind { hay pat -- a }
    pat zlen pattern-length !
    hay zlen pattern-length @ - 1+ 0 max 0 ?do
        hay i + pattern-length @  pat pattern-length @  compare 0= if
            hay i + unloop exit
        then
    loop
    0 ;

: at-value-end? ( -- f ) cursor @ c@ dup 0<> swap [char] " <> and ;

\ Copies the string value of a JSON field out of the response buffer into dest.
\ Returns false when the field is absent.
: json-field { dest name -- f }
    pattern [char] " over c! 1+ name zcat [char] " over c! 1+ 0 swap c!
    response pattern zfind dup 0= if drop false exit then
    pattern zlen + cursor !
    begin at-value-end? while cursor @ 1 + cursor ! repeat
    cursor @ c@ 0= if false exit then
    cursor @ 1 + cursor !
    begin at-value-end? while
        cursor @ c@ dest c!  dest 1 + to dest  cursor @ 1 + cursor !
    repeat
    0 dest c!  true ;

\ Performs one request. in-file is a FILE* to upload (or 0), out-file receives the body.
\ Returns the HTTP status code, or 0 when the transfer itself failed.
: request { zurl in-file in-size out-file -- code }
    curl-init { handle }
    handle 0= if s" curl_easy_init failed" cstring fail then
    0 key-header slist-append { headers }
    in-file if headers type-header slist-append to headers then
    handle CURLOPT_URL zurl curl-setopt-ptr drop
    handle CURLOPT_HTTPHEADER headers curl-setopt-ptr drop
    handle CURLOPT_WRITEDATA out-file curl-setopt-ptr drop
    handle CURLOPT_TIMEOUT 60 curl-setopt-long drop
    in-file if
        handle CURLOPT_POST 1 curl-setopt-long drop
        handle CURLOPT_POSTFIELDSIZE in-size curl-setopt-long drop
        handle CURLOPT_READDATA in-file curl-setopt-ptr drop
    then
    0 http-code !
    handle curl-perform 0= if
        handle CURLINFO_RESPONSE_CODE http-code curl-getinfo drop
    then
    headers slist-free
    handle curl-cleanup
    http-code @ ;

\ Sends a request whose reply is small JSON, which lands in the response buffer.
: request-json ( zurl in-file in-size -- code )
    response 8192 erase
    response 8192 mode-w c-fmemopen { out }
    out request
    out c-fclose drop ;

: queue ( -- )
    input-path mode-rb c-fopen { f }
    f 0= if s" Unable to open input.lua" cstring fail then
    f 0 SEEK_END c-fseek drop
    f c-ftell { size }
    f c-rewind
    url base-url queue-path zpair
    url f size request-json { code }
    f c-fclose drop
    code ok? 0= if
        ." Unable to queue obfuscation: " code . cr 1 libc-exit
    then
    guid f-guid json-field 0= if s" Malformed response from the queue request" cstring fail then
    status-url f-status-url json-field 0= if s" Malformed response from the queue request" cstring fail then
    ." Obfuscation started with GUID: " guid zprint cr ;

: download ( -- )
    url base-url download-url zpair
    output-path mode-wb c-fopen { f }
    f 0= if s" Unable to open output.lua" cstring fail then
    url 0 0 f request { code }
    f c-fclose drop
    ." Obfuscation completed in " elapsed @ . ." seconds" cr
    code ok? 0= if
        ." Download failed with status: " code . cr 1 libc-exit
    then
    ." Saved obfuscated script to " output-path zprint cr ;

: status-failed ( code -- )
    1 fails +!
    ." Status check failed with status: " . ." (" fails @ . ." /" max-fails . ." )" cr
    fails @ max-fails >= elapsed @ max-wait >= or if
        ." Obfuscation failed (fails: " fails @ . ." | elapsed time: " elapsed @ . ." )" cr
        1 libc-exit
    then ;

: poll ( -- )
    0 elapsed !  0 fails !  0 wait !
    begin
        retry-delay wait +!
        wait @ c-sleep drop
        wait @ elapsed +!
        url base-url status-url zpair
        url 0 0 request-json dup ok? 0= if
            status-failed
        else
            drop
            job-status f-status json-field 0= if s" Malformed status response" cstring fail then
            job-status dup zlen s" completed" compare 0= if
                download-url f-download json-field 0= if s" Malformed status response" cstring fail then
                download exit
            then
            job-status dup zlen s" failed" compare 0= elapsed @ max-wait >= or if
                ." Obfuscation failed (status: " job-status zprint ." | elapsed time: " elapsed @ . ." )" cr
                1 libc-exit
            then
            ." Obfuscation is still in progress. Elapsed time: " elapsed @ .
            ." seconds. Checking again in " retry-delay wait @ + . ." seconds." cr
        then
    again ;

queue
poll
bye
