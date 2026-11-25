;; CHICKEN Scheme 5. Run with: csi -s script.scm
;; Needs the http-client, medea, srfi-18 and openssl eggs:
;;   chicken-install http-client medea srfi-18 openssl
(import scheme
        (chicken base)
        (chicken io)
        (chicken condition)
        (chicken format)
        (chicken process-context)
        http-client
        intarweb
        uri-common
        medea
        srfi-18)

(define base-url "https://ironbrew1.com")
(define api-key "IB1-APIKEYHERE")

(define input-path "input.lua")
(define output-path "output.lua")

(define query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(define retry-delay 5)
(define max-wait 240)
(define max-fails 3)

(max-retry-attempts 0)

(define (fail message)
  (fprintf (current-error-port) "~a~n" message)
  (exit 1))

(define (ok? code) (and (>= code 200) (< code 300)))

(define (read-file path)
  (call-with-input-file path (lambda (port) (read-string #f port)) #:binary))

;; http-client raises an exception for 4xx and 5xx responses instead of returning them, and
;; the status code only survives in the message ("Client error: 404 Not Found"), so it is
;; pulled back out of there. Returns 0 when no code can be recovered.
(define (code-from-message message)
  (let loop ((index 0))
    (if (> (+ index 3) (string-length message))
        0
        (let ((code (string->number (substring message index (+ index 3)))))
          (if (and code (exact-integer? code) (>= code 100))
              code
              (loop (+ index 1)))))))

;; Returns the HTTP status code and the response body.
(define (request method path #!optional body)
  (let* ((uri (uri-reference (string-append base-url path)))
         (head (headers (append `((key ,api-key))
                                (if body '((content-type #(text/plain ()))) '()))))
         (req (make-request method: method uri: uri headers: head)))
    (condition-case
        ;; call-with-input-request* returns the reader's result followed by extra values,
        ;; so the reader hands back one pair and the extras are dropped here.
        (call-with-values
            (lambda ()
              (call-with-input-request*
               req body
               (lambda (port response)
                 (cons (response-code response) (read-string #f port)))))
          (lambda (result . extra) (values (car result) (cdr result))))
      ((exn http) (exception)
       (let ((message (get-condition-property exception 'exn 'message "")))
         (values (code-from-message message) message))))))

(define (field object name)
  (let ((entry (assq name object)))
    (and entry (cdr entry))))

(let-values (((code body) (request 'POST (string-append "/obfuscate?" query) (read-file input-path))))
  (unless (ok? code) (fail (format "Unable to queue obfuscation: ~a" code)))
  (let ((queued (read-json body)))
    (printf "Obfuscation started with GUID: ~a~n" (field queued 'uploadGuid))
    (let loop ((elapsed 0) (fails 0) (wait 0))
      (let* ((wait (+ wait retry-delay)))
        (thread-sleep! wait)
        (let ((elapsed (+ elapsed wait)))
          (let-values (((code body) (request 'GET (field queued 'statusUrl))))
            (cond
             ((not (ok? code))
              (let ((fails (+ fails 1)))
                (printf "Status check failed with status: ~a (~a/~a)~n" code fails max-fails)
                (when (or (>= fails max-fails) (>= elapsed max-wait))
                  (fail (format "Obfuscation failed (fails: ~a | elapsed time: ~a)" fails elapsed)))
                (loop elapsed fails wait)))
             (else
              (let* ((status (read-json body))
                     (state (field status 'status)))
                (cond
                 ((equal? state "completed")
                  (let-values (((code script) (request 'GET (field status 'downloadUrl))))
                    (printf "Obfuscation completed in ~a seconds~n" elapsed)
                    (unless (ok? code) (fail (format "Download failed with status: ~a" code)))
                    (call-with-output-file output-path
                      (lambda (port) (write-string script #f port)) #:binary)
                    (printf "Saved obfuscated script to ~a~n" output-path)))
                 ((or (equal? state "failed") (>= elapsed max-wait))
                  (fail (format "Obfuscation failed (status: ~a | elapsed time: ~a)" state elapsed)))
                 (else
                  (printf "Obfuscation is still in progress. Elapsed time: ~a seconds. Checking again in ~a seconds.~n"
                          elapsed (+ retry-delay wait))
                  (loop elapsed fails wait))))))))))))
