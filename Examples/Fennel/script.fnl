;; Fennel (a Lisp that compiles to Lua). Run with: fennel script.fnl
;; Needs LuaSocket, LuaSec and dkjson (apt install lua-socket lua-sec lua-dkjson).
(local https (require :ssl.https))
(local ltn12 (require :ltn12))
(local socket (require :socket))
(local json (require :dkjson))

(local base-url "https://ironbrew1.com")
(local api-key "IB1-APIKEYHERE")

(local input-path "input.lua")
(local output-path "output.lua")

(local query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(local retry-delay 5)
(local max-wait 240)
(local max-fails 3)

(fn fail [message]
  (io.stderr:write message "\n")
  (os.exit 1))

(fn ok? [code] (and (>= code 200) (< code 300)))

(fn read-file [path]
  (with-open [file (assert (io.open path :rb))]
    (file:read :a)))

;; Returns the HTTP status code (0 on transport errors) and the response body.
(fn request [method path body]
  (let [chunks {}
        headers {:Key api-key}]
    (when body
      (tset headers "Content-Type" "text/plain")
      (tset headers "Content-Length" (tostring (length body))))
    (let [(_ code) (https.request {:url (.. base-url path)
                                   : method
                                   : headers
                                   :source (when body (ltn12.source.string body))
                                   :sink (ltn12.sink.table chunks)})]
      (values (if (= (type code) :number) code 0) (table.concat chunks)))))

(let [(code body) (request :POST (.. "/obfuscate?" query) (read-file input-path))]
  (when (not (ok? code))
    (fail (.. "Unable to queue obfuscation: " code)))
  (let [queued (json.decode body)]
    (print (.. "Obfuscation started with GUID: " queued.uploadGuid))
    (var elapsed 0)
    (var fails 0)
    (var wait 0)
    (var done false)
    (while (not done)
      (set wait (+ wait retry-delay))
      (socket.sleep wait)
      (set elapsed (+ elapsed wait))
      (let [(code body) (request :GET queued.statusUrl)]
        (if (not (ok? code))
            (do
              (set fails (+ fails 1))
              (print (.. "Status check failed with status: " code " (" fails "/" max-fails ")"))
              (when (or (>= fails max-fails) (>= elapsed max-wait))
                (fail (.. "Obfuscation failed (fails: " fails " | elapsed time: " elapsed ")"))))
            (let [status (json.decode body)]
              (if (= status.status :completed)
                  (let [(code script) (request :GET status.downloadUrl)]
                    (print (.. "Obfuscation completed in " elapsed " seconds"))
                    (when (not (ok? code))
                      (fail (.. "Download failed with status: " code)))
                    (with-open [out (assert (io.open output-path :wb))]
                      (out:write script))
                    (print (.. "Saved obfuscated script to " output-path))
                    (set done true))
                  (if (or (= status.status :failed) (>= elapsed max-wait))
                      (fail (.. "Obfuscation failed (status: " (tostring status.status) " | elapsed time: " elapsed ")"))
                      (print (.. "Obfuscation is still in progress. Elapsed time: " elapsed
                                 " seconds. Checking again in " (+ retry-delay wait) " seconds."))))))))))
