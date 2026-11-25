;; Hy (a Lisp on Python). Run with: pip install hy requests && hy script.hy
(import sys)
(import time)
(import requests)
(import pathlib [Path])

(setv BASE-URL "https://ironbrew1.com")
(setv API-KEY "IB1-APIKEYHERE")

(setv INPUT-PATH "input.lua")
(setv OUTPUT-PATH "output.lua")

(setv QUERY "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(setv RETRY-DELAY 5)
(setv MAX-WAIT 240)
(setv MAX-FAILS 3)

(defn fail [message]
  (print message :file sys.stderr)
  (sys.exit 1))

(defn ok [code]
  (<= 200 code 299))

(defn request [method path [body None]]
  (setv headers {"Key" API-KEY})
  (when (is-not body None)
    (setv (get headers "Content-Type") "text/plain"))
  (requests.request method (+ BASE-URL path) :headers headers :data body :timeout 120))

(setv queue-response (request "POST" f"/obfuscate?{QUERY}" (.read-bytes (Path INPUT-PATH))))
(when (not (ok queue-response.status-code))
  (fail f"Unable to queue obfuscation: {queue-response.status-code}"))

(setv queued (.json queue-response))
(setv guid (get queued "uploadGuid"))
(print f"Obfuscation started with GUID: {guid}")

(setv elapsed 0)
(setv fails 0)
(setv wait 0)

(while True
  (+= wait RETRY-DELAY)
  (time.sleep wait)
  (+= elapsed wait)

  (setv response (request "GET" (get queued "statusUrl")))
  (if (not (ok response.status-code))
      (do
        (+= fails 1)
        (print f"Status check failed with status: {response.status-code} ({fails}/{MAX-FAILS})")
        (when (or (>= fails MAX-FAILS) (>= elapsed MAX-WAIT))
          (fail f"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})")))
      (do
        (setv status (.json response))
        (setv state (get status "status"))
        (if (= state "completed")
            (do
              (print f"Obfuscation completed in {elapsed} seconds")
              (setv download (request "GET" (get status "downloadUrl")))
              (when (not (ok download.status-code))
                (fail f"Download failed with status: {download.status-code}"))
              (.write-bytes (Path OUTPUT-PATH) download.content)
              (print f"Saved obfuscated script to {OUTPUT-PATH}")
              (break))
            (if (or (= state "failed") (>= elapsed MAX-WAIT))
                (fail f"Obfuscation failed (status: {state} | elapsed time: {elapsed})")
                (print f"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {(+ RETRY-DELAY wait)} seconds."))))))
