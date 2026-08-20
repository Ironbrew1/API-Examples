local ScriptEditorService = game:GetService("ScriptEditorService")
local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")
const CoreGui = game:GetService("CoreGui")
local toolbar = plugin:CreateToolbar("ironbrew1")
local obfuscatebutton = toolbar:CreateButton("Ironbrew1", "Use Ironbrew1 to obfuscate scripts.", "rbxassetid://79130854450972")
obfuscatebutton.ClickableWhenViewportHidden = true

local baseurl = "https://ironbrew1.com"
local retrydelay = 5
local maxwait = 240
local maxfails = 3
local breakconditions = {"failed", "completed"}

if plugin:GetSetting("FristTime") == nil then
	warn("WARNING: DO NOT USE THIS PLUGIN TO DISTRIBUTE OFBUSCATED CODE ON THE CREATOR MARKETPLACE. That would be a violation of Roblox's TOS. Only use this plugin to secure your client/server scripts. You will no longer get this warning.")
	plugin:SetSetting("FristTime", false)
end

local function openapikeyprompt()
	if CoreGui:FindFirstChild("PluginUi") then warn("Authentication GUI already open") return else print("Authentication GUI opened") end
	apiprompt = script.PluginUi:Clone()
	apiprompt.Archivable = false
	local holder = apiprompt.ScreenSize.Holder
	holder.Submit.MouseButton1Click:Connect(function()
		plugin:SetSetting("IB1KEY", holder.TextBox.Text)
		apiprompt:Destroy()
	end)
	apiprompt.Parent = CoreGui
end

local function reqasync(url, method, body)
	return HttpService:RequestAsync({
		Url = baseurl..url,
		Method = method,
		Headers = {["Key"] = plugin:GetSetting("IB1KEY"), ["Content-Type"] = "text/plain"},
		Body = body
	})
end

obfuscatebutton.Click:Connect(function()
	local active = StudioService.ActiveScript
	if not plugin:GetSetting("IB1KEY") then warn("You must insert a valid API key before using this plugin") openapikeyprompt() return end
	if not active then warn("Open a script before obfuscating.") return end
	if active:IsA("ModuleScript") then warn("ModuleScripts are not supported.") return end
	
	local queueSuccess, queueResponse = pcall(reqasync, "/obfuscate", "POST", active.Source)
	
	if queueSuccess and queueResponse.Success then
		local decoded = HttpService:JSONDecode(queueResponse.Body)
		local elapsedtime = 0
		local failcount = 0
		local waittime = 0
		local response = ""
		repeat
			waittime += retrydelay
			task.wait(waittime)
			elapsedtime += waittime
			local completion, data = pcall(reqasync, decoded["statusUrl"], "GET")
			if completion and data.Success then
				response = HttpService:JSONDecode(data.Body)
				if response["status"] == "processing" then
					if elapsedtime <= maxwait/2 then
						print("Obfuscation is still in progress. Elapsed time: "..elapsedtime.." seconds. Checking again in "..waittime + retrydelay.." seconds.")
					elseif elapsedtime > maxwait/2 and elapsedtime <= maxwait then
						warn("Obfuscation is still in progress. Elapsed time: "..elapsedtime.." seconds (timeout at "..maxwait.." seconds). Checking again in "..waittime + retrydelay.." seconds.")
					else
						warn("Obfuscation timed out (>"..maxwait.." seconds)")
					end
				end
			else
				failcount += 1
				warn("Request failed "..failcount.." time(s). Error data: "..data)
			end
		until failcount >= maxfails or table.find(breakconditions, response["status"])
		if response["status"] == "completed" then
			local succ, download = pcall(reqasync, response["downloadUrl"], "GET")
			local newscript = active:Clone()
			ScriptEditorService:UpdateSourceAsync(newscript, function()
				return download.Body
			end)
			newscript.Parent = active.Parent
			newscript.Name = active.Name.." (OBFUSCATED)"
			warn("Obfuscation completed successfully in "..elapsedtime.." seconds.")
		else
			warn("Obfuscation failed. Please try again later. ("..elapsedtime.."/"..failcount.."/"..response["status"]..")")
		end
	else
		local statuscode = queueResponse.StatusCode
		warn("Unable to queue (" .. tostring(statuscode) .. ") " .. tostring(queueResponse.Body))
		if statuscode == 401 then
			plugin:SetSetting("IB1KEY", nil)
			openapikeyprompt()
		end
	end
end)

plugin.Unloading:Connect(function()
	if apiprompt then apiprompt:Destroy() end
end)
