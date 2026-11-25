# Requires Elixir 1.17+ on Erlang/OTP 27+ (uses the built-in :httpc and :json modules, no dependencies).
defmodule Ironbrew do
  @base_url "https://ironbrew1.com"
  @api_key "IB1-APIKEYHERE"

  @input_path "input.lua"
  @output_path "output.lua"

  @query "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

  @retry_delay 5
  @max_wait 240
  @max_fails 3

  def run do
    :inets.start()
    :ssl.start()

    {code, body} = request(:post, "/obfuscate?" <> @query, File.read!(@input_path))
    if code not in 200..299, do: fail("Unable to queue obfuscation: #{code}")

    queued = :json.decode(body)
    IO.puts("Obfuscation started with GUID: #{queued["uploadGuid"]}")

    poll(queued["statusUrl"], 0, 0, 0)
  end

  defp poll(status_url, elapsed, fails, wait) do
    wait = wait + @retry_delay
    Process.sleep(wait * 1000)
    elapsed = elapsed + wait

    {code, body} = request(:get, status_url)

    if code in 200..299 do
      status = :json.decode(body)

      cond do
        status["status"] == "completed" ->
          IO.puts("Obfuscation completed in #{elapsed} seconds")
          {download_code, script} = request(:get, status["downloadUrl"])
          if download_code not in 200..299, do: fail("Download failed with status: #{download_code}")
          File.write!(@output_path, script)
          IO.puts("Saved obfuscated script to #{@output_path}")

        status["status"] == "failed" or elapsed >= @max_wait ->
          fail("Obfuscation failed (status: #{status["status"]} | elapsed time: #{elapsed})")

        true ->
          IO.puts("Obfuscation is still in progress. Elapsed time: #{elapsed} seconds. Checking again in #{@retry_delay + wait} seconds.")
          poll(status_url, elapsed, fails, wait)
      end
    else
      fails = fails + 1
      IO.puts("Status check failed with status: #{code} (#{fails}/#{@max_fails})")

      if fails >= @max_fails or elapsed >= @max_wait,
        do: fail("Obfuscation failed (fails: #{fails} | elapsed time: #{elapsed})")

      poll(status_url, elapsed, fails, wait)
    end
  end

  defp request(method, path, body \\ nil) do
    url = String.to_charlist(@base_url <> path)
    headers = [{~c"Key", String.to_charlist(@api_key)}]

    request =
      if body, do: {url, headers, ~c"text/plain", body}, else: {url, headers}

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(method, request, [ssl: ssl, timeout: 120_000], body_format: :binary) do
      {:ok, {{_, code, _}, _headers, response_body}} -> {code, response_body}
      {:error, reason} -> fail("Request failed: #{inspect(reason)}")
    end
  end

  defp fail(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Ironbrew.run()
