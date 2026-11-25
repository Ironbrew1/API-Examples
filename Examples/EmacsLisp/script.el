;;; script.el --- Ironbrew1 API example  -*- lexical-binding: t; -*-
;; Run with Emacs 27+: emacs --batch -l script.el

(require 'url)
(require 'json)

(defconst base-url "https://ironbrew1.com")
(defconst api-key "IB1-APIKEYHERE")

(defconst input-path "input.lua")
(defconst output-path "output.lua")

(defconst query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(defconst retry-delay 5)
(defconst max-wait 240)
(defconst max-fails 3)

(defun fail (message)
  (princ (concat message "\n") #'external-debugging-output)
  (kill-emacs 1))

(defun ok-p (code) (and (>= code 200) (< code 300)))

;; Returns (STATUS-CODE . BODY).
(defun request (method path &optional body)
  (let* ((url-request-method method)
         (url-request-extra-headers
          (append `(("Key" . ,api-key))
                  (when body '(("Content-Type" . "text/plain")))))
         (url-request-data (when body (encode-coding-string body 'utf-8)))
         (buffer (url-retrieve-synchronously (concat base-url path) t t 120)))
    (with-current-buffer buffer
      (let ((code url-http-response-status)
            (text (decode-coding-string
                   (buffer-substring-no-properties (1+ url-http-end-of-headers) (point-max)) 'utf-8)))
        (kill-buffer buffer)
        (cons code text)))))

(defun field (json name)
  (gethash name (json-parse-string json)))

(let* ((source (with-temp-buffer
                 (insert-file-contents input-path)
                 (buffer-string)))
       (queued (request "POST" (concat "/obfuscate?" query) source)))
  (unless (ok-p (car queued))
    (fail (format "Unable to queue obfuscation: %d" (car queued))))
  (message "Obfuscation started with GUID: %s" (field (cdr queued) "uploadGuid"))
  (let ((status-url (field (cdr queued) "statusUrl"))
        (elapsed 0) (fails 0) (wait 0) (done nil))
    (while (not done)
      (setq wait (+ wait retry-delay))
      (sleep-for wait)
      (setq elapsed (+ elapsed wait))
      (let ((response (request "GET" status-url)))
        (if (not (ok-p (car response)))
            (progn
              (setq fails (1+ fails))
              (message "Status check failed with status: %d (%d/%d)" (car response) fails max-fails)
              (when (or (>= fails max-fails) (>= elapsed max-wait))
                (fail (format "Obfuscation failed (fails: %d | elapsed time: %d)" fails elapsed))))
          (let ((state (field (cdr response) "status")))
            (cond
             ((equal state "completed")
              (message "Obfuscation completed in %d seconds" elapsed)
              (let ((download (request "GET" (field (cdr response) "downloadUrl"))))
                (unless (ok-p (car download))
                  (fail (format "Download failed with status: %d" (car download))))
                (let ((coding-system-for-write 'utf-8))
                  (write-region (cdr download) nil output-path nil 'silent))
                (message "Saved obfuscated script to %s" output-path))
              (setq done t))
             ((or (equal state "failed") (>= elapsed max-wait))
              (fail (format "Obfuscation failed (status: %s | elapsed time: %d)" state elapsed)))
             (t
              (message "Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds."
                       elapsed (+ retry-delay wait))))))))))
