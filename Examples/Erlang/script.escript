#!/usr/bin/env escript
%% Requires Erlang/OTP 27+ (uses the built-in httpc and json modules, no dependencies).
%% Run with: escript script.escript

-define(BASE_URL, "https://ironbrew1.com").
-define(API_KEY, "IB1-APIKEYHERE").
-define(INPUT_PATH, "input.lua").
-define(OUTPUT_PATH, "output.lua").
-define(QUERY, "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false").
-define(RETRY_DELAY, 5).
-define(MAX_WAIT, 240).
-define(MAX_FAILS, 3).

main(_) ->
    inets:start(),
    ssl:start(),
    {ok, Source} = file:read_file(?INPUT_PATH),
    {Code, Body} = request(post, "/obfuscate?" ++ ?QUERY, Source),
    ok = check(Code, "Unable to queue obfuscation"),
    Queued = json:decode(Body),
    io:format("Obfuscation started with GUID: ~s~n", [maps:get(<<"uploadGuid">>, Queued)]),
    poll(binary_to_list(maps:get(<<"statusUrl">>, Queued)), 0, 0, 0).

poll(StatusUrl, Elapsed0, Fails0, Wait0) ->
    Wait = Wait0 + ?RETRY_DELAY,
    timer:sleep(Wait * 1000),
    Elapsed = Elapsed0 + Wait,
    {Code, Body} = request(get, StatusUrl, undefined),
    case Code div 100 of
        2 ->
            Status = json:decode(Body),
            State = maps:get(<<"status">>, Status),
            if
                State =:= <<"completed">> ->
                    io:format("Obfuscation completed in ~p seconds~n", [Elapsed]),
                    {DownloadCode, Script} = request(get, binary_to_list(maps:get(<<"downloadUrl">>, Status)), undefined),
                    ok = check(DownloadCode, "Download failed"),
                    ok = file:write_file(?OUTPUT_PATH, Script),
                    io:format("Saved obfuscated script to ~s~n", [?OUTPUT_PATH]);
                State =:= <<"failed">> orelse Elapsed >= ?MAX_WAIT ->
                    fail(io_lib:format("Obfuscation failed (status: ~s | elapsed time: ~p)", [State, Elapsed]));
                true ->
                    io:format("Obfuscation is still in progress. Elapsed time: ~p seconds. Checking again in ~p seconds.~n",
                              [Elapsed, ?RETRY_DELAY + Wait]),
                    poll(StatusUrl, Elapsed, Fails0, Wait)
            end;
        _ ->
            Fails = Fails0 + 1,
            io:format("Status check failed with status: ~p (~p/~p)~n", [Code, Fails, ?MAX_FAILS]),
            if
                Fails >= ?MAX_FAILS orelse Elapsed >= ?MAX_WAIT ->
                    fail(io_lib:format("Obfuscation failed (fails: ~p | elapsed time: ~p)", [Fails, Elapsed]));
                true ->
                    poll(StatusUrl, Elapsed, Fails, Wait)
            end
    end.

request(Method, Path, Body) ->
    Url = ?BASE_URL ++ Path,
    Headers = [{"Key", ?API_KEY}],
    Request = case Body of
        undefined -> {Url, Headers};
        _ -> {Url, Headers, "text/plain", Body}
    end,
    Ssl = [{verify, verify_peer},
           {cacerts, public_key:cacerts_get()},
           {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}],
    case httpc:request(Method, Request, [{ssl, Ssl}, {timeout, 120000}], [{body_format, binary}]) of
        {ok, {{_, Code, _}, _, ResponseBody}} -> {Code, ResponseBody};
        {error, Reason} -> fail(io_lib:format("Request failed: ~p", [Reason]))
    end.

check(Code, Message) when Code >= 200, Code < 300 -> ok;
check(Code, Message) -> fail(io_lib:format("~s: ~p", [Message, Code])).

fail(Message) ->
    io:format(standard_error, "~s~n", [Message]),
    halt(1).
