using System.Net;
using System.Text;
using System.Text.Json;

const string BaseUrl = "https://ironbrew1.com";
const string ApiKey = "IB1-APIKEYHERE";

const string InputPath = "input.lua";
const string OutputPath = "output.lua";

const int RetryDelay = 5;
const int MaxWait = 240;
const int MaxFails = 3;

var query = new Dictionary<string, string>
{
    ["platform"] = "roblox",
    ["aggressiveOptimizations"] = "0",
    ["intenseVmScrambling"] = "false",
    ["enableVmCompression"] = "false",
};

using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(120) };
http.DefaultRequestHeaders.Add("Key", ApiKey);

var queryString = string.Join("&", query.Select(p => $"{p.Key}={Uri.EscapeDataString(p.Value)}"));
var content = new ByteArrayContent(await File.ReadAllBytesAsync(InputPath));
content.Headers.ContentType = new("text/plain");

var queueResponse = await http.PostAsync($"{BaseUrl}/obfuscate?{queryString}", content);
if (!queueResponse.IsSuccessStatusCode)
{
    Console.Error.WriteLine($"Unable to queue obfuscation: {(int)queueResponse.StatusCode}");
    return 1;
}

using var queued = JsonDocument.Parse(await queueResponse.Content.ReadAsStringAsync());
var statusUrl = queued.RootElement.GetProperty("statusUrl").GetString();
Console.WriteLine($"Obfuscation started with GUID: {queued.RootElement.GetProperty("uploadGuid").GetString()}");

int elapsed = 0, fails = 0, wait = 0;

while (true)
{
    wait += RetryDelay;
    await Task.Delay(wait * 1000);
    elapsed += wait;

    var statusResponse = await http.GetAsync(BaseUrl + statusUrl);
    if (!statusResponse.IsSuccessStatusCode)
    {
        fails++;
        Console.WriteLine($"Status check failed with status: {(int)statusResponse.StatusCode} ({fails}/{MaxFails})");
        if (fails >= MaxFails || elapsed >= MaxWait)
        {
            Console.Error.WriteLine($"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})");
            return 1;
        }
        continue;
    }

    using var status = JsonDocument.Parse(await statusResponse.Content.ReadAsStringAsync());
    var state = status.RootElement.GetProperty("status").GetString();

    if (state == "completed")
    {
        Console.WriteLine($"Obfuscation completed in {elapsed} seconds");
        var download = await http.GetAsync(BaseUrl + status.RootElement.GetProperty("downloadUrl").GetString());
        if (!download.IsSuccessStatusCode)
        {
            Console.Error.WriteLine($"Download failed with status: {(int)download.StatusCode}");
            return 1;
        }
        await File.WriteAllBytesAsync(OutputPath, await download.Content.ReadAsByteArrayAsync());
        Console.WriteLine($"Saved obfuscated script to {OutputPath}");
        return 0;
    }

    if (state == "failed" || elapsed >= MaxWait)
    {
        Console.Error.WriteLine($"Obfuscation failed (status: {state} | elapsed time: {elapsed})");
        return 1;
    }

    Console.WriteLine($"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {RetryDelay + wait} seconds.");
}
