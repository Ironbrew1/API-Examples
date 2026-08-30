------------------------------------------------------
--------------------- [Variables] --------------------
------------------------------------------------------

local baseurl = "https://ironbrew1.com"
local retrydelay = 5
local maxwait = 240
local maxfails = 3
local breakconditions = {"failed", "completed"}
local options = {
	["platform"] = {"luau", "universal"},
	["aggressiveOptimizations"] = {"0", "1", "2"},
	["intenseVmScrambling"] = {"false", "true"},
	["enableVmCompression"] = {"false", "true"},
}

------------------------------------------------------
------ [DO NOT CHANGE ANYTHING BELOW THIS LINE] ------
------------------------------------------------------

local ScriptEditorService = game:GetService("ScriptEditorService")
local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local toolbar = plugin:CreateToolbar("ironbrew1")
local obfuscatebutton = toolbar:CreateButton("Ironbrew1", "Use Ironbrew1 to obfuscate scripts.", "rbxassetid://79130854450972")
obfuscatebutton.ClickableWhenViewportHidden = true

local obfmenu = plugin:CreatePluginMenu(math.random(), "Options", "")
local obfaction = obfmenu:AddNewAction(math.random(), "Obfuscate", "")
obfmenu:AddSeparator()

if not plugin:GetSetting("PreviouslyUsed") then
	warn("WARNING: DO NOT USE THIS PLUGIN TO DISTRIBUTE OFBUSCATED CODE ON THE CREATOR MARKETPLACE. That would be a violation of Roblox's TOS. Only use this plugin to secure your client/server scripts. You will no longer receive this warning.")
	for i,v in pairs(options) do plugin:SetSetting(i, v[1]) end
	plugin:SetSetting("PreviouslyUsed", true)
end

for I,V in pairs(options) do
	local treemenu = plugin:CreatePluginMenu(math.random(), I, "")
	obfmenu:AddMenu(treemenu)
	for i,v in pairs(V) do
		treemenu:AddNewAction(math.random(), v, "").Triggered:Connect(function()
			local oldsetting = plugin:GetSetting(I)
			if oldsetting == v then return end
			print("Set "..I.." to "..v.." (previous setting was "..oldsetting..")")
			plugin:SetSetting(I, v)
		end)
	end
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
	obfmenu:ShowAsync()
end)

obfaction.Triggered:Connect(function()
	local active = StudioService.ActiveScript
	if not plugin:GetSetting("IB1KEY") then warn("You must insert a valid API key before using this plugin") openapikeyprompt() return end
	if not active then warn("Open a script before obfuscating.") return end
	if active:IsA("ModuleScript") then warn("ModuleScripts are not supported.") return end
	
	local optionsstring = "?"
	for i,v in pairs(options) do optionsstring = optionsstring..i.."="..plugin:GetSetting(i).."&" end
	optionsstring = optionsstring:sub(1, #optionsstring-1)
	local queueSuccess, queueResponse = pcall(reqasync, "/obfuscate"..optionsstring, "POST", active.Source)

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
				if response["status"] == "processing" then if elapsedtime <= maxwait then print("Obfuscation is still in progress. Elapsed time: "..elapsedtime.." seconds. Checking again in "..waittime + retrydelay.." seconds.") else warn("Obfuscation timed out (>"..maxwait.." seconds)") end end
			else
				failcount += 1
				warn("Request failed "..failcount.." time(s). Error data: "..data)
			end
		until failcount >= maxfails or table.find(breakconditions, response["status"])
		if response["status"] ~= "completed" then warn("Obfuscation failed. Please try again later. ("..elapsedtime.."/"..failcount.."/"..response["status"]..")") return end
		local succ, download = pcall(reqasync, response["downloadUrl"], "GET")
		local newscript = active:Clone()
		ScriptEditorService:UpdateSourceAsync(newscript, function()
			return download.Body
		end)
		newscript.Parent = active.Parent
		newscript.Name = active.Name.." (OBFUSCATED)"
		warn("Obfuscation completed successfully in "..elapsedtime.." seconds.")
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
