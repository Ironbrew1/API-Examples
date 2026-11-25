import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import simplifile

const base_url = "https://ironbrew1.com"

const api_key = "IB1-APIKEYHERE"

const input_path = "input.lua"

const output_path = "output.lua"

const query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

const retry_delay = 5

const max_wait = 240

const max_fails = 3

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> a

fn fail(message: String) -> a {
  io.println_error(message)
  halt(1)
}

fn ok(code: Int) -> Bool {
  code >= 200 && code < 300
}

// Returns the HTTP status code (0 on transport errors) and the response body.
fn send(method: http.Method, path: String, body: BitArray) -> #(Int, BitArray) {
  let assert Ok(base) = request.to(base_url <> path)
  let req =
    base
    |> request.set_method(method)
    |> request.set_header("key", api_key)
    |> request.set_body(body)
  let req = case method {
    http.Post -> request.set_header(req, "content-type", "text/plain")
    _ -> req
  }
  case httpc.send_bits(req) {
    Ok(response) -> #(response.status, response.body)
    Error(_) -> #(0, <<>>)
  }
}

fn string_field(body: BitArray, name: String) -> String {
  let assert Ok(text) = bit_array.to_string(body)
  let decoder = decode.field(name, decode.string, decode.success)
  case json.parse(text, decoder) {
    Ok(value) -> value
    Error(_) -> fail("Unable to decode JSON")
  }
}

fn poll(status_url: String, elapsed: Int, fails: Int, wait: Int) -> Nil {
  let wait = wait + retry_delay
  process.sleep(wait * 1000)
  let elapsed = elapsed + wait

  let #(code, body) = send(http.Get, status_url, <<>>)
  case ok(code) {
    False -> {
      let fails = fails + 1
      io.println(
        "Status check failed with status: "
        <> int.to_string(code)
        <> " ("
        <> int.to_string(fails)
        <> "/"
        <> int.to_string(max_fails)
        <> ")",
      )
      case fails >= max_fails || elapsed >= max_wait {
        True ->
          fail(
            "Obfuscation failed (fails: "
            <> int.to_string(fails)
            <> " | elapsed time: "
            <> int.to_string(elapsed)
            <> ")",
          )
        False -> poll(status_url, elapsed, fails, wait)
      }
    }
    True -> {
      let state = string_field(body, "status")
      case state == "completed", state == "failed" || elapsed >= max_wait {
        True, _ -> {
          io.println(
            "Obfuscation completed in " <> int.to_string(elapsed) <> " seconds",
          )
          let #(code, script) =
            send(http.Get, string_field(body, "downloadUrl"), <<>>)
          case ok(code) {
            False ->
              fail("Download failed with status: " <> int.to_string(code))
            True -> {
              let assert Ok(_) = simplifile.write_bits(output_path, script)
              io.println("Saved obfuscated script to " <> output_path)
            }
          }
        }
        _, True ->
          fail(
            "Obfuscation failed (status: "
            <> state
            <> " | elapsed time: "
            <> int.to_string(elapsed)
            <> ")",
          )
        _, _ -> {
          io.println(
            "Obfuscation is still in progress. Elapsed time: "
            <> int.to_string(elapsed)
            <> " seconds. Checking again in "
            <> int.to_string(retry_delay + wait)
            <> " seconds.",
          )
          poll(status_url, elapsed, fails, wait)
        }
      }
    }
  }
}

pub fn main() -> Nil {
  let assert Ok(source) = simplifile.read_bits(input_path)
  let #(code, body) = send(http.Post, "/obfuscate?" <> query, source)
  case ok(code) {
    False -> fail("Unable to queue obfuscation: " <> int.to_string(code))
    True -> {
      io.println(
        "Obfuscation started with GUID: " <> string_field(body, "uploadGuid"),
      )
      poll(string_field(body, "statusUrl"), 0, 0, 0)
    }
  }
}
