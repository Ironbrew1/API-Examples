(* GNU Modula-2. Build and run with:
     gm2 main.mod -o main -lcurl && ./main

   NOTE: the API is HTTPS-only and Modula-2 has no networking library, so this example calls
   libcurl through the definition modules in curl.def and cstdio.def. Request and response
   bodies are streamed through C FILE* handles, so no write callbacks are needed, and the
   small JSON replies are scanned by JsonField below. *)
MODULE main ;

FROM SYSTEM IMPORT ADDRESS, ADR ;
FROM curl IMPORT curl_easy_init, curl_easy_setopt, curl_easy_perform, curl_easy_getinfo,
                 curl_easy_cleanup, curl_slist_append, curl_slist_free_all ;
FROM cstdio IMPORT fopen, fmemopen, fclose, fseek, ftell, rewind ;
FROM libc IMPORT exit, sleep ;
FROM StrIO IMPORT WriteString, WriteLn ;
FROM NumberIO IMPORT WriteCard ;

CONST
   BaseUrl   = "https://ironbrew1.com" ;
   QueuePath = "/obfuscate?platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false" ;
   KeyHeader = "Key: IB1-APIKEYHERE" ;
   TypeHeader = "Content-Type: text/plain" ;
   InputPath  = "input.lua" ;
   OutputPath = "output.lua" ;

   CurlOptWriteData     = 10001 ;
   CurlOptUrl           = 10002 ;
   CurlOptReadData      = 10009 ;
   CurlOptHttpHeader    = 10023 ;
   CurlOptTimeout       = 13 ;
   CurlOptPost          = 47 ;
   CurlOptPostFieldSize = 60 ;
   CurlInfoResponseCode = 2097154 ;
   SeekEnd              = 2 ;

   RetryDelay = 5 ;
   MaxWait    = 240 ;
   MaxFails   = 3 ;

VAR
   response   : ARRAY [0..8191] OF CHAR ;
   url        : ARRAY [0..1023] OF CHAR ;
   guid       : ARRAY [0..127] OF CHAR ;
   statusUrl  : ARRAY [0..255] OF CHAR ;
   jobStatus  : ARRAY [0..63] OF CHAR ;
   downloadUrl: ARRAY [0..255] OF CHAR ;
   keyHeader  : ARRAY [0..63] OF CHAR ;
   typeHeader : ARRAY [0..63] OF CHAR ;
   inputPath  : ARRAY [0..31] OF CHAR ;
   outputPath : ARRAY [0..31] OF CHAR ;
   modeRead   : ARRAY [0..3] OF CHAR ;
   modeWrite  : ARRAY [0..3] OF CHAR ;
   modeMemory : ARRAY [0..3] OF CHAR ;


(* The length of a NUL terminated string held in an ARRAY OF CHAR. *)
PROCEDURE Length (VAR text: ARRAY OF CHAR) : CARDINAL ;
VAR
   index: CARDINAL ;
BEGIN
   index := 0 ;
   WHILE (index <= HIGH (text)) AND (text[index] # 0C) DO
      INC (index)
   END ;
   RETURN index
END Length ;


(* Appends source at offset in dest and returns the offset of the new NUL terminator. *)
PROCEDURE Append (VAR dest: ARRAY OF CHAR; offset: CARDINAL; VAR source: ARRAY OF CHAR) : CARDINAL ;
VAR
   index: CARDINAL ;
BEGIN
   index := 0 ;
   WHILE (index < Length (source)) AND (offset < HIGH (dest)) DO
      dest[offset] := source[index] ;
      INC (index) ;
      INC (offset)
   END ;
   dest[offset] := 0C ;
   RETURN offset
END Append ;


(* Builds the request URL from the base URL and a path. *)
PROCEDURE BuildUrl (VAR path: ARRAY OF CHAR) ;
VAR
   base  : ARRAY [0..31] OF CHAR ;
   offset: CARDINAL ;
BEGIN
   base := BaseUrl ;
   offset := Append (url, 0, base) ;
   offset := Append (url, offset, path)
END BuildUrl ;


PROCEDURE Fail (message: ARRAY OF CHAR) ;
BEGIN
   WriteString (message) ;
   WriteLn ;
   exit (1)
END Fail ;


PROCEDURE Ok (code: CARDINAL) : BOOLEAN ;
BEGIN
   RETURN (code >= 200) AND (code < 300)
END Ok ;


(* Copies the string value of a JSON field out of the response buffer into dest.
   Returns FALSE when the field is absent. *)
PROCEDURE JsonField (name: ARRAY OF CHAR; VAR dest: ARRAY OF CHAR) : BOOLEAN ;
VAR
   pattern    : ARRAY [0..63] OF CHAR ;
   nameLength : CARDINAL ;
   patternLength, index, scan, match, out: CARDINAL ;
   found      : BOOLEAN ;
BEGIN
   nameLength := Length (name) ;
   pattern[0] := '"' ;
   FOR index := 0 TO nameLength - 1 DO
      pattern[index + 1] := name[index]
   END ;
   pattern[nameLength + 1] := '"' ;
   patternLength := nameLength + 2 ;

   found := FALSE ;
   scan := 0 ;
   WHILE (NOT found) AND (scan + patternLength <= Length (response)) DO
      index := 0 ;
      WHILE (index < patternLength) AND (response[scan + index] = pattern[index]) DO
         INC (index)
      END ;
      IF index = patternLength
      THEN
         found := TRUE ;
         match := scan + patternLength
      ELSE
         INC (scan)
      END
   END ;
   IF NOT found
   THEN
      RETURN FALSE
   END ;

   (* Skip the colon and any spaces before the opening quote of the value. *)
   WHILE (match < Length (response)) AND (response[match] # '"') DO
      INC (match)
   END ;
   IF match >= Length (response)
   THEN
      RETURN FALSE
   END ;
   INC (match) ;

   out := 0 ;
   WHILE (match < Length (response)) AND (response[match] # '"') AND (out < HIGH (dest)) DO
      dest[out] := response[match] ;
      INC (out) ;
      INC (match)
   END ;
   dest[out] := 0C ;
   RETURN TRUE
END JsonField ;


PROCEDURE Equal (VAR text: ARRAY OF CHAR; value: ARRAY OF CHAR) : BOOLEAN ;
VAR
   index: CARDINAL ;
BEGIN
   IF Length (text) # Length (value)
   THEN
      RETURN FALSE
   END ;
   FOR index := 0 TO Length (value) DO
      IF text[index] # value[index]
      THEN
         RETURN FALSE
      END
   END ;
   RETURN TRUE
END Equal ;


(* Performs one request. inFile is a FILE* to upload (or NIL), outFile receives the body.
   Returns the HTTP status code, or 0 when the transfer itself failed. *)
PROCEDURE Request (inFile: ADDRESS; inSize: LONGINT; outFile: ADDRESS) : CARDINAL ;
VAR
   handle, headers: ADDRESS ;
   code           : LONGINT ;
   ignored        : INTEGER ;
BEGIN
   handle := curl_easy_init () ;
   IF handle = NIL
   THEN
      Fail ("curl_easy_init failed")
   END ;

   headers := curl_slist_append (NIL, ADR (keyHeader)) ;
   IF inFile # NIL
   THEN
      headers := curl_slist_append (headers, ADR (typeHeader))
   END ;

   ignored := curl_easy_setopt (handle, CurlOptUrl, ADR (url)) ;
   ignored := curl_easy_setopt (handle, CurlOptHttpHeader, headers) ;
   ignored := curl_easy_setopt (handle, CurlOptWriteData, outFile) ;
   ignored := curl_easy_setopt (handle, CurlOptTimeout, VAL (LONGINT, 60)) ;
   IF inFile # NIL
   THEN
      ignored := curl_easy_setopt (handle, CurlOptPost, VAL (LONGINT, 1)) ;
      ignored := curl_easy_setopt (handle, CurlOptPostFieldSize, inSize) ;
      ignored := curl_easy_setopt (handle, CurlOptReadData, inFile)
   END ;

   code := 0 ;
   IF curl_easy_perform (handle) = 0
   THEN
      ignored := curl_easy_getinfo (handle, CurlInfoResponseCode, ADR (code))
   END ;

   curl_slist_free_all (headers) ;
   curl_easy_cleanup (handle) ;
   RETURN VAL (CARDINAL, code)
END Request ;


(* Sends a request whose reply is small JSON, which lands in the response buffer. *)
PROCEDURE RequestJson (inFile: ADDRESS; inSize: LONGINT) : CARDINAL ;
VAR
   stream : ADDRESS ;
   code   : CARDINAL ;
   index  : CARDINAL ;
   ignored: INTEGER ;
BEGIN
   FOR index := 0 TO HIGH (response) DO
      response[index] := 0C
   END ;
   stream := fmemopen (ADR (response), HIGH (response), ADR (modeMemory)) ;
   code := Request (inFile, inSize, stream) ;
   ignored := fclose (stream) ;
   RETURN code
END RequestJson ;


PROCEDURE Queue ;
VAR
   stream : ADDRESS ;
   size   : LONGINT ;
   code   : CARDINAL ;
   path   : ARRAY [0..255] OF CHAR ;
   ignored: INTEGER ;
BEGIN
   stream := fopen (ADR (inputPath), ADR (modeRead)) ;
   IF stream = NIL
   THEN
      Fail ("Unable to open input.lua")
   END ;
   ignored := fseek (stream, 0, SeekEnd) ;
   size := ftell (stream) ;
   rewind (stream) ;

   path := QueuePath ;
   BuildUrl (path) ;
   code := RequestJson (stream, size) ;
   ignored := fclose (stream) ;

   IF NOT Ok (code)
   THEN
      WriteString ("Unable to queue obfuscation: ") ;
      WriteCard (code, 1) ;
      WriteLn ;
      exit (1)
   END ;

   IF NOT JsonField ("uploadGuid", guid)
   THEN
      Fail ("Malformed response from the queue request")
   END ;
   IF NOT JsonField ("statusUrl", statusUrl)
   THEN
      Fail ("Malformed response from the queue request")
   END ;

   WriteString ("Obfuscation started with GUID: ") ;
   WriteString (guid) ;
   WriteLn
END Queue ;


PROCEDURE Download (elapsed: CARDINAL) ;
VAR
   stream : ADDRESS ;
   code   : CARDINAL ;
   ignored: INTEGER ;
BEGIN
   BuildUrl (downloadUrl) ;
   stream := fopen (ADR (outputPath), ADR (modeWrite)) ;
   IF stream = NIL
   THEN
      Fail ("Unable to open output.lua")
   END ;
   code := Request (NIL, 0, stream) ;
   ignored := fclose (stream) ;

   WriteString ("Obfuscation completed in ") ;
   WriteCard (elapsed, 1) ;
   WriteString (" seconds") ;
   WriteLn ;

   IF NOT Ok (code)
   THEN
      WriteString ("Download failed with status: ") ;
      WriteCard (code, 1) ;
      WriteLn ;
      exit (1)
   END ;

   WriteString ("Saved obfuscated script to output.lua") ;
   WriteLn
END Download ;


PROCEDURE Poll ;
VAR
   elapsed, fails, wait, code, slept: CARDINAL ;
BEGIN
   elapsed := 0 ;
   fails := 0 ;
   wait := 0 ;
   LOOP
      INC (wait, RetryDelay) ;
      slept := sleep (wait) ;
      INC (elapsed, wait) ;

      BuildUrl (statusUrl) ;
      code := RequestJson (NIL, 0) ;

      IF NOT Ok (code)
      THEN
         INC (fails) ;
         WriteString ("Status check failed with status: ") ;
         WriteCard (code, 1) ;
         WriteString (" (") ;
         WriteCard (fails, 1) ;
         WriteString ("/") ;
         WriteCard (MaxFails, 1) ;
         WriteString (")") ;
         WriteLn ;
         IF (fails >= MaxFails) OR (elapsed >= MaxWait)
         THEN
            WriteString ("Obfuscation failed (fails: ") ;
            WriteCard (fails, 1) ;
            WriteString (" | elapsed time: ") ;
            WriteCard (elapsed, 1) ;
            WriteString (")") ;
            WriteLn ;
            exit (1)
         END
      ELSE
         IF NOT JsonField ("status", jobStatus)
         THEN
            Fail ("Malformed status response")
         END ;

         IF Equal (jobStatus, "completed")
         THEN
            IF NOT JsonField ("downloadUrl", downloadUrl)
            THEN
               Fail ("Malformed status response")
            END ;
            Download (elapsed) ;
            RETURN
         END ;

         IF Equal (jobStatus, "failed") OR (elapsed >= MaxWait)
         THEN
            WriteString ("Obfuscation failed (status: ") ;
            WriteString (jobStatus) ;
            WriteString (" | elapsed time: ") ;
            WriteCard (elapsed, 1) ;
            WriteString (")") ;
            WriteLn ;
            exit (1)
         END ;

         WriteString ("Obfuscation is still in progress. Elapsed time: ") ;
         WriteCard (elapsed, 1) ;
         WriteString (" seconds. Checking again in ") ;
         WriteCard (RetryDelay + wait, 1) ;
         WriteString (" seconds.") ;
         WriteLn
      END
   END
END Poll ;


BEGIN
   keyHeader := KeyHeader ;
   typeHeader := TypeHeader ;
   inputPath := InputPath ;
   outputPath := OutputPath ;
   modeRead := "rb" ;
   modeWrite := "wb" ;
   modeMemory := "w" ;

   Queue ;
   Poll
END main.
