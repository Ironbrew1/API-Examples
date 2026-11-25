>>SOURCE FORMAT FREE
*> Build and run:  cobc -x -free main.cob -o main -lcurl && ./main    (GnuCOBOL 3+, libcurl)
*> Calls libcurl directly; the request/response bodies are streamed through C FILE* handles.
IDENTIFICATION DIVISION.
PROGRAM-ID. IRONBREW.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 BASE-URL        PIC X(30) VALUE "https://ironbrew1.com".
01 QUERY-STR       PIC X(120) VALUE "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false".
01 KEY-HEADER      PIC X(120) VALUE "Key: IB1-APIKEYHERE" & X"00".
01 CT-HEADER       PIC X(40) VALUE "Content-Type: text/plain" & X"00".
01 INPUT-FILE      PIC X(20) VALUE "input.lua" & X"00".
01 OUTPUT-FILE     PIC X(20) VALUE "output.lua" & X"00".
01 MODE-RB         PIC X(4) VALUE "rb" & X"00".
01 MODE-WB         PIC X(4) VALUE "wb" & X"00".
01 MODE-W          PIC X(4) VALUE "w" & X"00".

01 RETRY-DELAY     BINARY-LONG VALUE 5.
01 MAX-WAIT        BINARY-LONG VALUE 240.
01 MAX-FAILS       BINARY-LONG VALUE 3.

*> libcurl option codes
01 OPT-WRITEDATA   BINARY-LONG VALUE 10001.
01 OPT-URL         BINARY-LONG VALUE 10002.
01 OPT-READDATA    BINARY-LONG VALUE 10009.
01 OPT-HTTPHEADER  BINARY-LONG VALUE 10023.
01 OPT-TIMEOUT     BINARY-LONG VALUE 13.
01 OPT-POST        BINARY-LONG VALUE 47.
01 OPT-POSTSIZE    BINARY-LONG VALUE 60.
01 INFO-RESPONSE   BINARY-LONG VALUE 2097154.

01 NULL-PTR        USAGE POINTER VALUE NULL.
01 CURL-H          USAGE POINTER.
01 HEADERS         USAGE POINTER.
01 IN-FILE         USAGE POINTER.
01 OUT-FILE        USAGE POINTER.
01 RC              BINARY-LONG.
01 HTTP-CODE       BINARY-C-LONG.
01 INPUT-SIZE      BINARY-C-LONG.
01 BUF-SIZE        BINARY-C-LONG VALUE 65536.
01 TIMEOUT-SECS    BINARY-C-LONG VALUE 120.
01 ONE-L           BINARY-C-LONG VALUE 1.
01 ZERO-L          BINARY-C-LONG VALUE 0.
01 SEEK-END        BINARY-LONG VALUE 2.

01 REQ-URL         PIC X(400).
01 REQ-INPUT       PIC X VALUE "N".
01 JSON-BUF        PIC X(65536).
01 JUNK            PIC X(65536).
01 REST            PIC X(65536).
01 FIELD-NAME      PIC X(20).
01 FIELD-NAME-LEN  BINARY-LONG.
01 FIELD-VALUE     PIC X(256).
01 DELIM-BUF       PIC X(40).
01 DELIM-LEN       BINARY-LONG.
01 PTR             BINARY-LONG.

01 STATUS-URL      PIC X(256).
01 DOWNLOAD-URL    PIC X(256).
01 GUID            PIC X(64).
01 STATE           PIC X(32).

01 ELAPSED         BINARY-LONG VALUE 0.
01 FAILS           BINARY-LONG VALUE 0.
01 WAIT-TIME       BINARY-LONG VALUE 0.
01 NEXT-WAIT       BINARY-LONG.
01 DONE            PIC X VALUE "N".
01 BAD-CODE        PIC X.
01 NUM-A           PIC Z(8)9.
01 NUM-B           PIC Z(8)9.
01 NUM-C           PIC Z(8)9.

PROCEDURE DIVISION.
MAIN-PARA.
    STRING FUNCTION TRIM(BASE-URL) "/obfuscate?" FUNCTION TRIM(QUERY-STR) X"00"
        DELIMITED BY SIZE INTO REQ-URL
    MOVE "Y" TO REQ-INPUT
    PERFORM CALL-API
    PERFORM CHECK-CODE
    IF BAD-CODE = "Y"
        MOVE HTTP-CODE TO NUM-A
        DISPLAY "Unable to queue obfuscation: " FUNCTION TRIM(NUM-A) UPON SYSERR
        PERFORM FAIL-PARA
    END-IF

    MOVE "statusUrl" TO FIELD-NAME
    MOVE 9 TO FIELD-NAME-LEN
    PERFORM GET-FIELD
    MOVE FIELD-VALUE TO STATUS-URL
    MOVE "uploadGuid" TO FIELD-NAME
    MOVE 10 TO FIELD-NAME-LEN
    PERFORM GET-FIELD
    MOVE FIELD-VALUE TO GUID
    DISPLAY "Obfuscation started with GUID: " FUNCTION TRIM(GUID)

    PERFORM UNTIL DONE = "Y"
        ADD RETRY-DELAY TO WAIT-TIME
        CALL "sleep" USING BY VALUE WAIT-TIME RETURNING RC
        ADD WAIT-TIME TO ELAPSED

        STRING FUNCTION TRIM(BASE-URL) FUNCTION TRIM(STATUS-URL) X"00"
            DELIMITED BY SIZE INTO REQ-URL
        MOVE "N" TO REQ-INPUT
        PERFORM CALL-API
        PERFORM CHECK-CODE

        IF BAD-CODE = "Y"
            ADD 1 TO FAILS
            MOVE HTTP-CODE TO NUM-A
            MOVE FAILS TO NUM-B
            MOVE MAX-FAILS TO NUM-C
            DISPLAY "Status check failed with status: " FUNCTION TRIM(NUM-A)
                " (" FUNCTION TRIM(NUM-B) "/" FUNCTION TRIM(NUM-C) ")"
            IF FAILS >= MAX-FAILS OR ELAPSED >= MAX-WAIT
                MOVE FAILS TO NUM-A
                MOVE ELAPSED TO NUM-B
                DISPLAY "Obfuscation failed (fails: " FUNCTION TRIM(NUM-A)
                    " | elapsed time: " FUNCTION TRIM(NUM-B) ")" UPON SYSERR
                PERFORM FAIL-PARA
            END-IF
        ELSE
            MOVE "status" TO FIELD-NAME
            MOVE 6 TO FIELD-NAME-LEN
            PERFORM GET-FIELD
            MOVE FIELD-VALUE TO STATE

            EVALUATE TRUE
                WHEN STATE = "completed"
                    MOVE ELAPSED TO NUM-A
                    DISPLAY "Obfuscation completed in " FUNCTION TRIM(NUM-A) " seconds"
                    MOVE "downloadUrl" TO FIELD-NAME
                    MOVE 11 TO FIELD-NAME-LEN
                    PERFORM GET-FIELD
                    MOVE FIELD-VALUE TO DOWNLOAD-URL
                    PERFORM DOWNLOAD-PARA
                    PERFORM CHECK-CODE
                    IF BAD-CODE = "Y"
                        MOVE HTTP-CODE TO NUM-A
                        DISPLAY "Download failed with status: " FUNCTION TRIM(NUM-A) UPON SYSERR
                        PERFORM FAIL-PARA
                    END-IF
                    DISPLAY "Saved obfuscated script to output.lua"
                    MOVE "Y" TO DONE
                WHEN STATE = "failed" OR ELAPSED >= MAX-WAIT
                    MOVE ELAPSED TO NUM-A
                    DISPLAY "Obfuscation failed (status: " FUNCTION TRIM(STATE)
                        " | elapsed time: " FUNCTION TRIM(NUM-A) ")" UPON SYSERR
                    PERFORM FAIL-PARA
                WHEN OTHER
                    COMPUTE NEXT-WAIT = RETRY-DELAY + WAIT-TIME
                    MOVE ELAPSED TO NUM-A
                    MOVE NEXT-WAIT TO NUM-B
                    DISPLAY "Obfuscation is still in progress. Elapsed time: "
                        FUNCTION TRIM(NUM-A) " seconds. Checking again in "
                        FUNCTION TRIM(NUM-B) " seconds."
            END-EVALUATE
        END-IF
    END-PERFORM
    MOVE 0 TO RETURN-CODE
    STOP RUN.

FAIL-PARA.
    MOVE 1 TO RETURN-CODE
    STOP RUN.

CHECK-CODE.
    IF HTTP-CODE < 200 OR HTTP-CODE > 299
        MOVE "Y" TO BAD-CODE
    ELSE
        MOVE "N" TO BAD-CODE
    END-IF.

*> Pulls a string value out of the (compact) JSON in JSON-BUF: FIELD-NAME -> FIELD-VALUE.
GET-FIELD.
    MOVE SPACES TO FIELD-VALUE REST
    MOVE 1 TO PTR
    STRING '"' FIELD-NAME(1:FIELD-NAME-LEN) '":"' DELIMITED BY SIZE
        INTO DELIM-BUF WITH POINTER PTR
    COMPUTE DELIM-LEN = PTR - 1
    UNSTRING JSON-BUF DELIMITED BY DELIM-BUF(1:DELIM-LEN) INTO JUNK REST
    UNSTRING REST DELIMITED BY '"' INTO FIELD-VALUE.

*> Request into an in-memory buffer (JSON-BUF) via fmemopen.
CALL-API.
    MOVE LOW-VALUES TO JSON-BUF
    CALL "fmemopen" USING BY REFERENCE JSON-BUF BY VALUE BUF-SIZE
        BY REFERENCE MODE-W RETURNING OUT-FILE
    PERFORM REQUEST-PARA
    CALL "fclose" USING BY VALUE OUT-FILE RETURNING RC.

*> Request that streams the response straight into output.lua.
DOWNLOAD-PARA.
    STRING FUNCTION TRIM(BASE-URL) FUNCTION TRIM(DOWNLOAD-URL) X"00"
        DELIMITED BY SIZE INTO REQ-URL
    MOVE "N" TO REQ-INPUT
    CALL "fopen" USING BY REFERENCE OUTPUT-FILE MODE-WB RETURNING OUT-FILE
    PERFORM REQUEST-PARA
    CALL "fclose" USING BY VALUE OUT-FILE RETURNING RC.

*> One libcurl request: REQ-URL, POSTing input.lua when REQ-INPUT = "Y", body written to OUT-FILE.
REQUEST-PARA.
    MOVE 0 TO HTTP-CODE
    CALL "curl_easy_init" RETURNING CURL-H
    CALL "curl_slist_append" USING BY VALUE NULL-PTR BY REFERENCE KEY-HEADER
        RETURNING HEADERS
    CALL "curl_slist_append" USING BY VALUE HEADERS BY REFERENCE CT-HEADER
        RETURNING HEADERS
    CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-URL
        BY REFERENCE REQ-URL RETURNING RC
    CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-HTTPHEADER
        BY VALUE HEADERS RETURNING RC
    CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-TIMEOUT
        BY VALUE TIMEOUT-SECS RETURNING RC
    CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-WRITEDATA
        BY VALUE OUT-FILE RETURNING RC

    IF REQ-INPUT = "Y"
        CALL "fopen" USING BY REFERENCE INPUT-FILE MODE-RB RETURNING IN-FILE
        CALL "fseek" USING BY VALUE IN-FILE BY VALUE ZERO-L BY VALUE SEEK-END
            RETURNING RC
        CALL "ftell" USING BY VALUE IN-FILE RETURNING INPUT-SIZE
        CALL "rewind" USING BY VALUE IN-FILE
        CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-POST
            BY VALUE ONE-L RETURNING RC
        CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-POSTSIZE
            BY VALUE INPUT-SIZE RETURNING RC
        CALL "curl_easy_setopt" USING BY VALUE CURL-H BY VALUE OPT-READDATA
            BY VALUE IN-FILE RETURNING RC
    END-IF

    CALL "curl_easy_perform" USING BY VALUE CURL-H RETURNING RC
    IF RC = 0
        CALL "curl_easy_getinfo" USING BY VALUE CURL-H BY VALUE INFO-RESPONSE
            BY REFERENCE HTTP-CODE RETURNING RC
    END-IF

    CALL "curl_easy_cleanup" USING BY VALUE CURL-H
    CALL "curl_slist_free_all" USING BY VALUE HEADERS
    IF REQ-INPUT = "Y"
        CALL "fclose" USING BY VALUE IN-FILE RETURNING RC
    END-IF.
