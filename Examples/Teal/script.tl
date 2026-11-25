-- Teal (typed Lua). Run with: tl run script.tl
-- Needs LuaSocket, LuaSec and dkjson (apt install lua-socket lua-sec lua-dkjson) plus tl (luarocks install tl).
-- The Lua libraries have no Teal type definitions, so load them untyped.
local untyped_require = (_G as {string:any})["require"] as function(string): any
local https = untyped_require("ssl.https") as {string:any}
local ltn12 = untyped_require("ltn12") as {string:any}
local socket = untyped_require("socket") as {string:any}
local json = untyped_require("dkjson") as {string:any}

local base_url = "https://ironbrew1.com"
local api_key = "IB1-APIKEYHERE"

local input_path = "input.lua"
local output_path = "output.lua"

local query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

local retry_delay = 5
local max_wait = 240
local max_fails = 3

local function fail(message: string)
   io.stderr:write(message, "\n")
   os.exit(1)
end

local function ok(code: integer): boolean
   return code >= 200 and code < 300
end

local function read_file(path: string): string
   local file = assert(io.open(path, "rb"))
   local data = file:read("a") as string
   file:close()
   return data
end

local function decode(text: string): {string:any}
   return (json.decode as function(string): {string:any})(text)
end

-- Returns the HTTP status code (0 on transport errors) and the response body.
local function request(method: string, path: string, body?: string): integer, string
   local chunks: {string} = {}
   local headers: {string:string} = { Key = api_key }
   local source: any = nil
   if body then
      headers["Content-Type"] = "text/plain"
      headers["Content-Length"] = tostring(#body)
      source = (ltn12.source as {string:function(string): any}).string(body)
   end
   local _, code = (https.request as function({string:any}): any, any)({
      url = base_url .. path,
      method = method,
      headers = headers,
      source = source,
      sink = (ltn12.sink as {string:function({string}): any}).table(chunks),
   })
   return code is integer and code or 0, table.concat(chunks)
end

local code, body = request("POST", "/obfuscate?" .. query, read_file(input_path))
if not ok(code) then
   fail("Unable to queue obfuscation: " .. code)
end
local queued = decode(body)
print("Obfuscation started with GUID: " .. tostring(queued.uploadGuid))

local elapsed, fails, wait = 0, 0, 0
while true do
   wait = wait + retry_delay
   (socket.sleep as function(number))(wait)
   elapsed = elapsed + wait
   code, body = request("GET", queued.statusUrl as string)
   if not ok(code) then
      fails = fails + 1
      print("Status check failed with status: " .. code .. " (" .. fails .. "/" .. max_fails .. ")")
      if fails >= max_fails or elapsed >= max_wait then
         fail("Obfuscation failed (fails: " .. fails .. " | elapsed time: " .. elapsed .. ")")
      end
   else
      local status = decode(body)
      if status.status == "completed" then
         local script: string
         code, script = request("GET", status.downloadUrl as string)
         print("Obfuscation completed in " .. elapsed .. " seconds")
         if not ok(code) then
            fail("Download failed with status: " .. code)
         end
         local out = assert(io.open(output_path, "wb"))
         out:write(script)
         out:close()
         print("Saved obfuscated script to " .. output_path)
         break
      elseif status.status == "failed" or elapsed >= max_wait then
         fail("Obfuscation failed (status: " .. tostring(status.status) .. " | elapsed time: " .. elapsed .. ")")
      else
         print("Obfuscation is still in progress. Elapsed time: " .. elapsed .. " seconds. Checking again in " .. (retry_delay + wait) .. " seconds.")
      end
   end
end
