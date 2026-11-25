(* Build and run:
     opam install dune cohttp-lwt-unix tls-lwt ca-certs mirage-crypto-rng digestif yojson
     dune exec ./main.exe *)
open Lwt.Infix

let base_url = "https://ironbrew1.com"
let api_key = "IB1-APIKEYHERE"

let input_path = "input.lua"
let output_path = "output.lua"

let query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

let retry_delay = 5
let max_wait = 240
let max_fails = 3

let fail message =
  prerr_endline message;
  exit 1

let read_file path = In_channel.with_open_bin path In_channel.input_all

(* Returns the HTTP status code and the response body. *)
let request ?body meth path =
  let headers =
    Cohttp.Header.of_list
      (("Key", api_key) :: (if body = None then [] else [ ("Content-Type", "text/plain") ]))
  in
  Cohttp_lwt_unix.Client.call ~headers ?body:(Option.map Cohttp_lwt.Body.of_string body) meth
    (Uri.of_string (base_url ^ path))
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun text ->
  (Cohttp.Code.code_of_status (Cohttp.Response.status response), text)

let ok code = code / 100 = 2
let field json name = Yojson.Safe.Util.(json |> member name |> to_string)

let rec poll status_url elapsed fails wait =
  let wait = wait + retry_delay in
  Lwt_unix.sleep (float_of_int wait) >>= fun () ->
  let elapsed = elapsed + wait in
  request `GET status_url >>= fun (code, text) ->
  if not (ok code) then begin
    let fails = fails + 1 in
    Printf.printf "Status check failed with status: %d (%d/%d)\n%!" code fails max_fails;
    if fails >= max_fails || elapsed >= max_wait then
      fail (Printf.sprintf "Obfuscation failed (fails: %d | elapsed time: %d)" fails elapsed);
    poll status_url elapsed fails wait
  end
  else begin
    let status = Yojson.Safe.from_string text in
    let state = field status "status" in
    if state = "completed" then begin
      Printf.printf "Obfuscation completed in %d seconds\n%!" elapsed;
      request `GET (field status "downloadUrl") >|= fun (code, script) ->
      if not (ok code) then fail (Printf.sprintf "Download failed with status: %d" code);
      Out_channel.with_open_bin output_path (fun out -> output_string out script);
      Printf.printf "Saved obfuscated script to %s\n%!" output_path
    end
    else if state = "failed" || elapsed >= max_wait then
      fail (Printf.sprintf "Obfuscation failed (status: %s | elapsed time: %d)" state elapsed)
    else begin
      Printf.printf
        "Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n%!"
        elapsed (retry_delay + wait);
      poll status_url elapsed fails wait
    end
  end

let () =
  Mirage_crypto_rng_unix.use_default ();
  Lwt_main.run
    ( request ~body:(read_file input_path) `POST ("/obfuscate?" ^ query) >>= fun (code, text) ->
      if not (ok code) then fail (Printf.sprintf "Unable to queue obfuscation: %d" code);
      let queued = Yojson.Safe.from_string text in
      Printf.printf "Obfuscation started with GUID: %s\n%!" (field queued "uploadGuid");
      poll (field queued "statusUrl") 0 0 0 )
