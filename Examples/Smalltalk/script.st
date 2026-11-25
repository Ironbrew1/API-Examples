"Pharo Smalltalk script. Run headless with Pharo 10+ (the Zinc HTTP client and STON are built in):
   pharo --headless Pharo.image eval ""$(cat script.st)"" "
| baseUrl apiKey inputPath outputPath query retryDelay maxWait maxFails
  fail request ok queued statusUrl elapsed fails wait done response status state download |

baseUrl := 'https://ironbrew1.com'.
apiKey := 'IB1-APIKEYHERE'.
inputPath := 'input.lua'.
outputPath := 'output.lua'.
query := 'platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false'.
retryDelay := 5.
maxWait := 240.
maxFails := 3.

fail := [ :message |
	Stdio stderr nextPutAll: message; lf; flush.
	Smalltalk exitFailure ].

ok := [ :code | code >= 200 and: [ code < 300 ] ].

"Returns { status code. response body } (status 0 on transport errors)."
request := [ :method :path :body |
	| client |
	client := ZnClient new
		url: baseUrl , path;
		headerAt: 'Key' put: apiKey;
		timeout: 120;
		yourself.
	body ifNotNil: [ client entity: (ZnEntity with: body type: ZnMimeType textPlain) ].
	[ method = #POST ifTrue: [ client post ] ifFalse: [ client get ].
	  { client response code. client response contents } ]
		on: Error
		do: [ :error | { 0. '' } ] ].

response := request value: #POST value: '/obfuscate?' , query value: inputPath asFileReference contents.
(ok value: response first) ifFalse: [ fail value: 'Unable to queue obfuscation: ' , response first printString ].

queued := STONJSON fromString: response second.
Stdio stdout nextPutAll: 'Obfuscation started with GUID: ' , (queued at: 'uploadGuid'); lf; flush.
statusUrl := queued at: 'statusUrl'.

elapsed := 0.
fails := 0.
wait := 0.
done := false.

[ done ] whileFalse: [
	wait := wait + retryDelay.
	(Delay forSeconds: wait) wait.
	elapsed := elapsed + wait.

	response := request value: #GET value: statusUrl value: nil.
	(ok value: response first)
		ifFalse: [
			fails := fails + 1.
			Stdio stdout nextPutAll: 'Status check failed with status: ' , response first printString , ' (' , fails printString , '/' , maxFails printString , ')'; lf; flush.
			(fails >= maxFails or: [ elapsed >= maxWait ])
				ifTrue: [ fail value: 'Obfuscation failed (fails: ' , fails printString , ' | elapsed time: ' , elapsed printString , ')' ] ]
		ifTrue: [
			status := STONJSON fromString: response second.
			state := status at: 'status'.
			state = 'completed'
				ifTrue: [
					Stdio stdout nextPutAll: 'Obfuscation completed in ' , elapsed printString , ' seconds'; lf; flush.
					download := request value: #GET value: (status at: 'downloadUrl') value: nil.
					(ok value: download first) ifFalse: [ fail value: 'Download failed with status: ' , download first printString ].
					outputPath asFileReference ensureDelete; writeStreamDo: [ :stream | stream nextPutAll: download second ].
					Stdio stdout nextPutAll: 'Saved obfuscated script to ' , outputPath; lf; flush.
					done := true ]
				ifFalse: [
					(state = 'failed' or: [ elapsed >= maxWait ])
						ifTrue: [ fail value: 'Obfuscation failed (status: ' , state , ' | elapsed time: ' , elapsed printString , ')' ]
						ifFalse: [ Stdio stdout nextPutAll: 'Obfuscation is still in progress. Elapsed time: ' , elapsed printString , ' seconds. Checking again in ' , (retryDelay + wait) printString , ' seconds.'; lf; flush ] ] ] ].
Smalltalk exitSuccess
