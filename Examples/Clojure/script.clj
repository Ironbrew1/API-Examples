;; Run with the Clojure CLI: clojure -M script.clj   (no dependencies needed)
(import '(java.net URI)
        '(java.net.http HttpClient HttpRequest HttpRequest$BodyPublishers HttpResponse$BodyHandlers)
        '(java.nio.file Files Path)
        '(java.time Duration))

(def base-url "https://ironbrew1.com")
(def api-key "IB1-APIKEYHERE")

(def input-path (Path/of "input.lua" (make-array String 0)))
(def output-path (Path/of "output.lua" (make-array String 0)))

(def query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false")

(def retry-delay 5)
(def max-wait 240)
(def max-fails 3)

(def client (HttpClient/newHttpClient))

;; Pulls a string value out of a flat JSON object without needing a JSON library.
(defn field [json name]
  (some-> (re-find (re-pattern (str "\"" name "\"\\s*:\\s*\"([^\"]*)\"")) json)
          second
          (clojure.string/replace "\\/" "/")))

(defn fail [message]
  (binding [*out* *err*] (println message))
  (System/exit 1))

(defn send-request [method path body handler]
  (let [builder (-> (HttpRequest/newBuilder (URI/create (str base-url path)))
                    (.timeout (Duration/ofSeconds 120))
                    (.header "Key" api-key))
        request (if body
                  (-> builder
                      (.header "Content-Type" "text/plain")
                      (.POST (HttpRequest$BodyPublishers/ofFile body))
                      .build)
                  (-> builder .GET .build))
        response (.send client request handler)]
    {:code (.statusCode response) :body (.body response)}))

(defn ok? [{:keys [code]}] (= 2 (quot code 100)))

(let [queued (send-request :post (str "/obfuscate?" query) input-path (HttpResponse$BodyHandlers/ofString))]
  (when-not (ok? queued) (fail (str "Unable to queue obfuscation: " (:code queued))))
  (println "Obfuscation started with GUID:" (field (:body queued) "uploadGuid"))
  (let [status-url (field (:body queued) "statusUrl")]
    (loop [elapsed 0 fails 0 wait 0]
      (let [wait (+ wait retry-delay)
            _ (Thread/sleep (* wait 1000))
            elapsed (+ elapsed wait)
            response (send-request :get status-url nil (HttpResponse$BodyHandlers/ofString))]
        (if-not (ok? response)
          (let [fails (inc fails)]
            (println (str "Status check failed with status: " (:code response) " (" fails "/" max-fails ")"))
            (when (or (>= fails max-fails) (>= elapsed max-wait))
              (fail (str "Obfuscation failed (fails: " fails " | elapsed time: " elapsed ")")))
            (recur elapsed fails wait))
          (let [status (field (:body response) "status")]
            (cond
              (= status "completed")
              (do (println (str "Obfuscation completed in " elapsed " seconds"))
                  (let [download (send-request :get (field (:body response) "downloadUrl") nil
                                               (HttpResponse$BodyHandlers/ofByteArray))]
                    (when-not (ok? download) (fail (str "Download failed with status: " (:code download))))
                    (Files/write output-path ^bytes (:body download) (make-array java.nio.file.OpenOption 0))
                    (println "Saved obfuscated script to output.lua")))

              (or (= status "failed") (>= elapsed max-wait))
              (fail (str "Obfuscation failed (status: " status " | elapsed time: " elapsed ")"))

              :else
              (do (println (str "Obfuscation is still in progress. Elapsed time: " elapsed
                                " seconds. Checking again in " (+ retry-delay wait) " seconds."))
                  (recur elapsed fails wait)))))))))
