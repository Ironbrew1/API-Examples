;;; Run with Gauche 0.9.10+ (built with TLS support): gosh script.scm
(use rfc.http)
(use rfc.json)

(define server "ironbrew1.com")
(define api-key "IB1-APIKEYHERE")

(define input-path "input.lua")
(define output-path "output.lua")

(define query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(define retry-delay 5)
(define max-wait 240)
(define max-fails 3)

(define (fail message)
  (format (current-error-port) "~a\n" message)
  (exit 1))

(define (ok? code) (and (>= code 200) (< code 300)))

;; Returns the HTTP status code and the response body.
;; (Gauche sends unknown keyword arguments, such as :Key, as request headers.)
(define (request method path . body)
  (receive (status _ response)
      (if (null? body)
          (http-get server path :secure #t :Key api-key)
          (http-post server path (car body) :secure #t :Key api-key :Content-Type "text/plain"))
    (values (string->number status) response)))

;; JSON objects come back as a vector of pairs on some Gauche versions and as a list on others.
(define (field json name)
  (let1 pairs (if (vector? json) (vector->list json) json)
    (cond ((assoc name pairs) => cdr)
          (else #f))))

(define (read-file path)
  (call-with-input-file path port->string))

(receive (code body) (request 'post (string-append "/obfuscate?" query) (read-file input-path))
  (unless (ok? code) (fail #"Unable to queue obfuscation: ~code"))
  (let* ((queued (parse-json-string body))
         (status-url (field queued "statusUrl")))
    (print #"Obfuscation started with GUID: ~(field queued \"uploadGuid\")")
    (let loop ((elapsed 0) (fails 0) (wait 0))
      (let* ((wait (+ wait retry-delay))
             (elapsed (begin (sys-sleep wait) (+ elapsed wait))))
        (receive (code body) (request 'get status-url)
          (if (not (ok? code))
              (let1 fails (+ fails 1)
                (print #"Status check failed with status: ~code (~|fails|/~|max-fails|)")
                (when (or (>= fails max-fails) (>= elapsed max-wait))
                  (fail #"Obfuscation failed (fails: ~fails | elapsed time: ~elapsed)"))
                (loop elapsed fails wait))
              (let* ((status (parse-json-string body))
                     (state (field status "status")))
                (cond
                 ((equal? state "completed")
                  (print #"Obfuscation completed in ~elapsed seconds")
                  (receive (code script) (request 'get (field status "downloadUrl"))
                    (unless (ok? code) (fail #"Download failed with status: ~code"))
                    (call-with-output-file output-path (cut display script <>))
                    (print #"Saved obfuscated script to ~output-path")))
                 ((or (equal? state "failed") (>= elapsed max-wait))
                  (fail #"Obfuscation failed (status: ~state | elapsed time: ~elapsed)"))
                 (else
                  (print #"Obfuscation is still in progress. Elapsed time: ~elapsed seconds. Checking again in ~(+ retry-delay wait) seconds.")
                  (loop elapsed fails wait))))))))))
