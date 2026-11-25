% Run with SWI-Prolog 9+: swipl script.pl
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(readutil)).

base_url('https://ironbrew1.com').
api_key('IB1-APIKEYHERE').

input_path('input.lua').
output_path('output.lua').

query('platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false').

retry_delay(5).
max_wait(240).
max_fails(3).

fail(Message) :-
    format(user_error, "~w~n", [Message]),
    halt(1).

ok(Code) :- Code >= 200, Code < 300.

% request(+Method, +Path, +Body, -Code, -Text): Body is the request body or [] for none.
request(Method, Path, Body, Code, Text) :-
    base_url(Base),
    atom_concat(Base, Path, Url),
    api_key(Key),
    (   Body == []
    ->  Options = [method(Method), request_header('Key'=Key)]
    ;   Options = [method(Method), request_header('Key'=Key), post(string('text/plain', Body))]
    ),
    setup_call_cleanup(
        http_open(Url, In, [status_code(Code), timeout(120)|Options]),
        read_string(In, _, Text),
        close(In)).

main :-
    input_path(Input),
    read_file_to_string(Input, Source, []),
    query(Query),
    atom_concat('/obfuscate?', Query, Path),
    request(post, Path, Source, Code, Body),
    (   ok(Code) -> true ; format(atom(M), "Unable to queue obfuscation: ~w", [Code]), fail(M) ),
    atom_json_dict(Body, Queued, []),
    format("Obfuscation started with GUID: ~w~n", [Queued.uploadGuid]),
    poll(Queued.statusUrl, 0, 0, 0).

poll(StatusUrl, Elapsed0, Fails0, Wait0) :-
    retry_delay(Delay),
    Wait is Wait0 + Delay,
    sleep(Wait),
    Elapsed is Elapsed0 + Wait,
    request(get, StatusUrl, [], Code, Body),
    (   ok(Code)
    ->  atom_json_dict(Body, Status, []),
        handle(Status, StatusUrl, Elapsed, Fails0, Wait)
    ;   Fails is Fails0 + 1,
        max_fails(MaxFails),
        max_wait(MaxWait),
        format("Status check failed with status: ~w (~w/~w)~n", [Code, Fails, MaxFails]),
        (   ( Fails >= MaxFails ; Elapsed >= MaxWait )
        ->  format(atom(M), "Obfuscation failed (fails: ~w | elapsed time: ~w)", [Fails, Elapsed]),
            fail(M)
        ;   poll(StatusUrl, Elapsed, Fails, Wait)
        )
    ).

handle(Status, _, Elapsed, _, _) :-
    Status.status == "completed", !,
    format("Obfuscation completed in ~w seconds~n", [Elapsed]),
    request(get, Status.downloadUrl, [], Code, Script),
    (   ok(Code) -> true ; format(atom(M), "Download failed with status: ~w", [Code]), fail(M) ),
    output_path(Output),
    setup_call_cleanup(open(Output, write, Out, [encoding(utf8)]), write(Out, Script), close(Out)),
    format("Saved obfuscated script to ~w~n", [Output]).
handle(Status, _, Elapsed, _, _) :-
    max_wait(MaxWait),
    (   Status.status == "failed" ; Elapsed >= MaxWait ), !,
    format(atom(M), "Obfuscation failed (status: ~w | elapsed time: ~w)", [Status.status, Elapsed]),
    fail(M).
handle(_, StatusUrl, Elapsed, Fails, Wait) :-
    retry_delay(Delay),
    Next is Delay + Wait,
    format("Obfuscation is still in progress. Elapsed time: ~w seconds. Checking again in ~w seconds.~n", [Elapsed, Next]),
    poll(StatusUrl, Elapsed, Fails, Wait).

:- initialization(main, main).
