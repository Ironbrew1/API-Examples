;;; Run with SBCL and Quicklisp installed: sbcl --non-interactive --load script.lisp
;;; (dexador needs the OpenSSL libraries for https)
(ql:quickload '(:dexador :yason) :silent t)

(defparameter *base-url* "https://ironbrew1.com")
(defparameter *api-key* "IB1-APIKEYHERE")

(defparameter *input-path* "input.lua")
(defparameter *output-path* "output.lua")

(defparameter *query* "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(defparameter *retry-delay* 5)
(defparameter *max-wait* 240)
(defparameter *max-fails* 3)

(defun fail (message)
  (format *error-output* "~a~%" message)
  (uiop:quit 1))

(defun ok-p (code) (<= 200 code 299))

(defun read-file (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

;; Returns the HTTP status code and the response body.
(defun request (method path &optional body)
  (let ((headers (append '(("Key" . #.*api-key*)) (when body '(("Content-Type" . "text/plain"))))))
    (handler-case
        (multiple-value-bind (response code)
            (dex:request (concatenate 'string *base-url* path) :method method :headers headers :content body)
          (values code response))
      (dex:http-request-failed (e)
        (values (dex:response-status e) (dex:response-body e))))))

(defun field (json name)
  (gethash name (yason:parse json)))

(multiple-value-bind (code body) (request :post (concatenate 'string "/obfuscate?" *query*) (read-file *input-path*))
  (unless (ok-p code) (fail (format nil "Unable to queue obfuscation: ~a" code)))
  (format t "Obfuscation started with GUID: ~a~%" (field body "uploadGuid"))
  (let ((status-url (field body "statusUrl")) (elapsed 0) (fails 0) (wait 0))
    (loop
      (incf wait *retry-delay*)
      (sleep wait)
      (incf elapsed wait)
      (multiple-value-bind (code body) (request :get status-url)
        (if (not (ok-p code))
            (progn
              (incf fails)
              (format t "Status check failed with status: ~a (~a/~a)~%" code fails *max-fails*)
              (when (or (>= fails *max-fails*) (>= elapsed *max-wait*))
                (fail (format nil "Obfuscation failed (fails: ~a | elapsed time: ~a)" fails elapsed))))
            (let ((state (field body "status")))
              (cond
                ((equal state "completed")
                 (format t "Obfuscation completed in ~a seconds~%" elapsed)
                 (multiple-value-bind (code script) (request :get (field body "downloadUrl"))
                   (unless (ok-p code) (fail (format nil "Download failed with status: ~a" code)))
                   (with-open-file (out *output-path* :direction :output :if-exists :supersede :external-format :utf-8)
                     (write-string script out))
                   (format t "Saved obfuscated script to ~a~%" *output-path*))
                 (return))
                ((or (equal state "failed") (>= elapsed *max-wait*))
                 (fail (format nil "Obfuscation failed (status: ~a | elapsed time: ~a)" state elapsed)))
                (t
                 (format t "Obfuscation is still in progress. Elapsed time: ~a seconds. Checking again in ~a seconds.~%"
                         elapsed (+ *retry-delay* wait))))))))))
