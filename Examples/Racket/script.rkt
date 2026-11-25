#lang racket/base
;; Run with: racket script.rkt   (no extra packages needed)
(require json
         net/http-client
         racket/file
         racket/port
         racket/string)

(define host "ironbrew1.com")
(define api-key "IB1-APIKEYHERE")

(define input-path "input.lua")
(define output-path "output.lua")

(define query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(define retry-delay 5)
(define max-wait 240)
(define max-fails 3)

(define (fail message)
  (eprintf "~a\n" message)
  (exit 1))

;; Returns the HTTP status code and the response body (bytes).
(define (request method path [body #f])
  (define-values (status headers in)
    (http-sendrecv host path
                   #:ssl? #t
                   #:method method
                   #:headers (append (list (string-append "Key: " api-key))
                                     (if body '("Content-Type: text/plain") '()))
                   #:data body))
  (values (string->number (cadr (string-split (bytes->string/utf-8 status))))
          (port->bytes in)))

(define (ok? code) (and (>= code 200) (< code 300)))

(define-values (queue-code queue-body)
  (request "POST" (string-append "/obfuscate?" query) (file->bytes input-path)))
(unless (ok? queue-code) (fail (format "Unable to queue obfuscation: ~a" queue-code)))

(define queued (bytes->jsexpr queue-body))
(printf "Obfuscation started with GUID: ~a\n" (hash-ref queued 'uploadGuid))

(let loop ([elapsed 0] [fails 0] [wait 0])
  (define next-wait (+ wait retry-delay))
  (sleep next-wait)
  (define next-elapsed (+ elapsed next-wait))
  (define-values (code body) (request "GET" (hash-ref queued 'statusUrl)))
  (cond
    [(not (ok? code))
     (define next-fails (add1 fails))
     (printf "Status check failed with status: ~a (~a/~a)\n" code next-fails max-fails)
     (when (or (>= next-fails max-fails) (>= next-elapsed max-wait))
       (fail (format "Obfuscation failed (fails: ~a | elapsed time: ~a)" next-fails next-elapsed)))
     (loop next-elapsed next-fails next-wait)]
    [else
     (define status (bytes->jsexpr body))
     (define state (hash-ref status 'status))
     (cond
       [(equal? state "completed")
        (printf "Obfuscation completed in ~a seconds\n" next-elapsed)
        (define-values (download-code script) (request "GET" (hash-ref status 'downloadUrl)))
        (unless (ok? download-code) (fail (format "Download failed with status: ~a" download-code)))
        (call-with-output-file output-path #:exists 'truncate (lambda (out) (write-bytes script out)))
        (printf "Saved obfuscated script to ~a\n" output-path)]
       [(or (equal? state "failed") (>= next-elapsed max-wait))
        (fail (format "Obfuscation failed (status: ~a | elapsed time: ~a)" state next-elapsed))]
       [else
        (printf "Obfuscation is still in progress. Elapsed time: ~a seconds. Checking again in ~a seconds.\n"
                next-elapsed (+ retry-delay next-wait))
        (loop next-elapsed fails next-wait)])]))
