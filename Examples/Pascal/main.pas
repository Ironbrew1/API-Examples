{ Build and run with Free Pascal 3.2+: fpc main.pas && ./main
  Needs the OpenSSL development libraries at runtime (e.g. libssl-dev). }
program Main;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, fphttpclient, opensslsockets, fpjson, jsonparser;

const
  BaseUrl = 'https://ironbrew1.com';
  ApiKey = 'IB1-APIKEYHERE';

  InputPath = 'input.lua';
  OutputPath = 'output.lua';

  Query = 'platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false';

  RetryDelay = 5;
  MaxWait = 240;
  MaxFails = 3;

procedure Fail(const Message: string);
begin
  WriteLn(StdErr, Message);
  Halt(1);
end;

{ Sends a request and returns the HTTP status code; raises on transport errors. }
function Request(const Method, Path: string; Body, Response: TStream): Integer;
var
  Client: TFPHTTPClient;
begin
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AddHeader('Key', ApiKey);
    if Body <> nil then
    begin
      Client.AddHeader('Content-Type', 'text/plain');
      Client.RequestBody := Body;
    end;
    try
      Client.HTTPMethod(Method, BaseUrl + Path, Response, []);
    except
      on EHTTPClient do ; { non-2xx statuses are reported through the status code }
    end;
    Result := Client.ResponseStatusCode;
  finally
    Client.Free;
  end;
end;

function Parse(Stream: TStream): TJSONObject;
begin
  Stream.Position := 0;
  Result := GetJSON(Stream) as TJSONObject;
end;

var
  Source, Response: TStream;
  Queued, Status: TJSONObject;
  StatusUrl, State: string;
  Code, Elapsed, Fails, Wait: Integer;
  Output: TFileStream;
begin
  Source := TFileStream.Create(InputPath, fmOpenRead);
  Response := TMemoryStream.Create;
  Code := Request('POST', '/obfuscate?' + Query, Source, Response);
  if (Code div 100) <> 2 then
    Fail('Unable to queue obfuscation: ' + IntToStr(Code));

  Queued := Parse(Response);
  StatusUrl := Queued.Strings['statusUrl'];
  WriteLn('Obfuscation started with GUID: ', Queued.Strings['uploadGuid']);

  Elapsed := 0;
  Fails := 0;
  Wait := 0;

  while True do
  begin
    Inc(Wait, RetryDelay);
    Sleep(Wait * 1000);
    Inc(Elapsed, Wait);

    Response := TMemoryStream.Create;
    Code := Request('GET', StatusUrl, nil, Response);
    if (Code div 100) <> 2 then
    begin
      Inc(Fails);
      WriteLn('Status check failed with status: ', Code, ' (', Fails, '/', MaxFails, ')');
      if (Fails >= MaxFails) or (Elapsed >= MaxWait) then
        Fail('Obfuscation failed (fails: ' + IntToStr(Fails) + ' | elapsed time: ' + IntToStr(Elapsed) + ')');
      Continue;
    end;

    Status := Parse(Response);
    State := Status.Strings['status'];

    if State = 'completed' then
    begin
      WriteLn('Obfuscation completed in ', Elapsed, ' seconds');
      Response := TMemoryStream.Create;
      Code := Request('GET', Status.Strings['downloadUrl'], nil, Response);
      if (Code div 100) <> 2 then
        Fail('Download failed with status: ' + IntToStr(Code));
      Output := TFileStream.Create(OutputPath, fmCreate);
      Response.Position := 0;
      Output.CopyFrom(Response, Response.Size);
      Output.Free;
      WriteLn('Saved obfuscated script to ', OutputPath);
      Break;
    end;

    if (State = 'failed') or (Elapsed >= MaxWait) then
      Fail('Obfuscation failed (status: ' + State + ' | elapsed time: ' + IntToStr(Elapsed) + ')');

    WriteLn('Obfuscation is still in progress. Elapsed time: ', Elapsed, ' seconds. Checking again in ', RetryDelay + Wait, ' seconds.');
  end;
end.
