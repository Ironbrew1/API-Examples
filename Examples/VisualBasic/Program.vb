Imports System.Net.Http
Imports System.Text.Json

Module Program
    Const BaseUrl As String = "https://ironbrew1.com"
    Const ApiKey As String = "IB1-APIKEYHERE"

    Const InputPath As String = "input.lua"
    Const OutputPath As String = "output.lua"

    Const Query As String = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

    Const RetryDelay As Integer = 5
    Const MaxWait As Integer = 240
    Const MaxFails As Integer = 3

    Function Main() As Integer
        Using http As New HttpClient With {.Timeout = TimeSpan.FromSeconds(120)}
            http.DefaultRequestHeaders.Add("Key", ApiKey)

            Dim content As New ByteArrayContent(IO.File.ReadAllBytes(InputPath))
            content.Headers.ContentType = New Headers.MediaTypeHeaderValue("text/plain")

            Dim queueResponse = http.PostAsync($"{BaseUrl}/obfuscate?{Query}", content).Result
            If Not queueResponse.IsSuccessStatusCode Then
                Console.Error.WriteLine($"Unable to queue obfuscation: {CInt(queueResponse.StatusCode)}")
                Return 1
            End If

            Using queued = JsonDocument.Parse(queueResponse.Content.ReadAsStringAsync().Result)
                Dim statusUrl = queued.RootElement.GetProperty("statusUrl").GetString()
                Console.WriteLine($"Obfuscation started with GUID: {queued.RootElement.GetProperty("uploadGuid").GetString()}")

                Dim elapsed As Integer = 0, fails As Integer = 0, wait As Integer = 0

                Do
                    wait += RetryDelay
                    Threading.Thread.Sleep(wait * 1000)
                    elapsed += wait

                    Dim statusResponse = http.GetAsync(BaseUrl & statusUrl).Result
                    If Not statusResponse.IsSuccessStatusCode Then
                        fails += 1
                        Console.WriteLine($"Status check failed with status: {CInt(statusResponse.StatusCode)} ({fails}/{MaxFails})")
                        If fails >= MaxFails OrElse elapsed >= MaxWait Then
                            Console.Error.WriteLine($"Obfuscation failed (fails: {fails} | elapsed time: {elapsed})")
                            Return 1
                        End If
                        Continue Do
                    End If

                    Using status = JsonDocument.Parse(statusResponse.Content.ReadAsStringAsync().Result)
                        Dim state = status.RootElement.GetProperty("status").GetString()

                        If state = "completed" Then
                            Console.WriteLine($"Obfuscation completed in {elapsed} seconds")
                            Dim download = http.GetAsync(BaseUrl & status.RootElement.GetProperty("downloadUrl").GetString()).Result
                            If Not download.IsSuccessStatusCode Then
                                Console.Error.WriteLine($"Download failed with status: {CInt(download.StatusCode)}")
                                Return 1
                            End If
                            IO.File.WriteAllBytes(OutputPath, download.Content.ReadAsByteArrayAsync().Result)
                            Console.WriteLine($"Saved obfuscated script to {OutputPath}")
                            Return 0
                        End If

                        If state = "failed" OrElse elapsed >= MaxWait Then
                            Console.Error.WriteLine($"Obfuscation failed (status: {state} | elapsed time: {elapsed})")
                            Return 1
                        End If

                        Console.WriteLine($"Obfuscation is still in progress. Elapsed time: {elapsed} seconds. Checking again in {RetryDelay + wait} seconds.")
                    End Using
                Loop
            End Using
        End Using
    End Function
End Module
