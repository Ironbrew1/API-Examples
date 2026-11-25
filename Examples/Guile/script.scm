;;; Run with GNU Guile 3 (needs guile-gnutls for https): guile script.scm
(use-modules (web client)
             (web response)
             (ice-9 binary-ports)
             (ice-9 regex)
             (rnrs bytevectors))

(define base-url "https://ironbrew1.com")
(define api-key "IB1-APIKEYHERE")

(define input-path "input.lua")
(define output-path "output.lua")

(define query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(define retry-delay 5)
(define max-wait 240)
(define max-fails 3)

(define (fail message)
  (format (current-error-port) "~a~%" message)
  (exit 1))

(define (ok? code) (and (>= code 200) (< code 300)))

(define (read-bytes path)
  (let* ((port (open-file path "rb"))
         (data (get-bytevector-all port)))
    (close-port port)
    data))

(define (write-bytes path data)
  (let ((port (open-file path "wb")))
    (put-bytevector port data)
    (close-port port)))

;; Returns the HTTP status code and the response body (as a string).
(define (request method path . body)
  (call-with-values
      (lambda ()
        (apply http-request (string-append base-url path)
               #:method method
               #:headers (cons `(key . ,api-key)
                               (if (null? body) '() '((content-type . (text/plain)))))
               #:decode-body? #f
               (if (null? body) '() (list #:body (car body)))))
    (lambda (response data)
      (values (response-code response) (or data #vu8())))))

;; Pulls a string value out of a flat JSON object without needing a JSON library.
(define (field json name)
  (let ((m (string-match (string-append "\"" name "\"[ ]*:[ ]*\"([^\"]*)\"") json)))
    (and m (regexp-substitute/global #f "\\\\/" (match:substring m 1) 'pre "/" 'post))))

(call-with-values
    (lambda () (request 'POST (string-append "/obfuscate?" query) (read-bytes input-path)))
  (lambda (code data)
    (unless (ok? code)
      (fail (format #f "Unable to queue obfuscation: ~a" code)))
    (let* ((queued (utf8->string data))
           (status-url (field queued "statusUrl")))
      (format #t "Obfuscation started with GUID: ~a~%" (field queued "uploadGuid"))
      (let loop ((elapsed 0) (fails 0) (wait 0))
        (let* ((wait (+ wait retry-delay))
               (elapsed (begin (sleep wait) (+ elapsed wait))))
          (call-with-values
              (lambda () (request 'GET status-url))
            (lambda (code data)
              (if (not (ok? code))
                  (let ((fails (+ fails 1)))
                    (format #t "Status check failed with status: ~a (~a/~a)~%" code fails max-fails)
                    (when (or (>= fails max-fails) (>= elapsed max-wait))
                      (fail (format #f "Obfuscation failed (fails: ~a | elapsed time: ~a)" fails elapsed)))
                    (loop elapsed fails wait))
                  (let* ((body (utf8->string data))
                         (state (field body "status")))
                    (cond
                     ((equal? state "completed")
                      (format #t "Obfuscation completed in ~a seconds~%" elapsed)
                      (call-with-values
                          (lambda () (request 'GET (field body "downloadUrl")))
                        (lambda (code script)
                          (unless (ok? code)
                            (fail (format #f "Download failed with status: ~a" code)))
                          (write-bytes output-path script)
                          (format #t "Saved obfuscated script to ~a~%" output-path))))
                     ((or (equal? state "failed") (>= elapsed max-wait))
                      (fail (format #f "Obfuscation failed (status: ~a | elapsed time: ~a)" state elapsed)))
                     (else
                      (format #t "Obfuscation is still in progress. Elapsed time: ~a seconds. Checking again in ~a seconds.~%"
                              elapsed (+ retry-delay wait))
                      (loop elapsed fails wait))))))))))))
