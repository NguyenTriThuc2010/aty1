repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

repeat task.wait() until lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")

local remotesFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Remotes")
local getRemote = remotesFolder:WaitForChild("GET")
local postRemote = remotesFolder:WaitForChild("POST")
local PlayerGui = lp:WaitForChild("PlayerGui")

-- =====================
-- GLOBAL CONFIG
-- =====================
getgenv().AutoFarm   = false
getgenv().AutoRefill = false
getgenv().AutoEscape = false
getgenv().AutoRetry  = false
getgenv().AutoSkip   = false
getgenv().DeleteMap  = false
getgenv().SoloOnly   = false
getgenv().UseSpear   = false
getgenv().MultiHit = false

local V3_ZERO      = Vector3.new(0, 0, 0)
local HitCount = 10
local AttackRange  = 150
local HeightOffset = 250
local MoveSpeed    = 400
local MovementMode = "Hover"
local AttackRangeSq = AttackRange * AttackRange

-- =====================
-- ANTI-AFK
-- =====================
local vu = game:GetService("VirtualUser")
lp.Idled:Connect(function()
    vu:CaptureController()
    vu:ClickButton2(Vector2.new())
end)

-- =====================
-- ANTI-INJURY
-- =====================
task.spawn(function()
    while true do
        task.wait(1)
        local char = lp.Character
        local inj = char and char:FindFirstChild("Injuries")
        if inj then
            for _, v in ipairs(inj:GetChildren()) do v:Destroy() end
        end
    end
end)

-- =====================
-- HELPERS
-- =====================
local mapData = nil
local lastMapTime = 0
local function getMapData()
    if os.clock() - lastMapTime < 1 and mapData then return mapData end
    local ok, d = pcall(function() return getRemote:InvokeServer("Data", "Copy") end)
    if ok and d then mapData = d; lastMapTime = os.clock() end
    return mapData
end

local function getBladeCount()
    local ok, text = pcall(function()
        return PlayerGui.Interface.HUD.Main.Top["7"].Blades.Sets.Text
    end)
    if ok and text then return tonumber(text:match("(%d+)%s*/")) or 0 end
    return 0
end

local function getSpearCount()
    local ok, text = pcall(function()
        return PlayerGui.Interface.HUD.Main.Top.Spears.Spears.Text
    end)
    if ok and text then return tonumber(text:match("(%d+)%s*/")) or 0 end
    return 99
end

local function getRefillPart()
    local ok, rf = pcall(function()
        return workspace.Unclimbable.Props.HQ.GasTanks.Refill
    end)
    if ok and rf and rf.Parent then return rf end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == "Refill" and v:IsA("BasePart") then return v end
    end
    return nil
end

local function getBlade()
    local char = lp.Character
    if not char then return nil end
    local rig = char:FindFirstChild("Rig_" .. lp.Name)
    if not rig then return nil end
    local lh = rig:FindFirstChild("LeftHand")
    return lh and lh:FindFirstChild("Blade_1")
end

local bossNames = { Attack_Titan = true, Armored_Titan = true, Female_Titan = true }

local function findClosestNape(root)
    local titans = workspace:FindFirstChild("Titans")
    if not titans then return nil, math.huge end
    local best, bestDist = nil, math.huge
    for _, titan in ipairs(titans:GetChildren()) do
        if titan:GetAttribute("Killed") then continue end
        if titan:GetAttribute("Dead")   then continue end
        local hb  = titan:FindFirstChild("Hitboxes")
        local hit = hb and hb:FindFirstChild("Hit")
        local nape = hit and hit:FindFirstChild("Nape")
        if nape then
            local fake = titan:FindFirstChild("Fake")
            if fake and fake:FindFirstChild("Collision")
               and not fake.Collision.CanCollide then continue end
            local d = (nape.Position - root.Position).Magnitude
            if d < bestDist then best = nape; bestDist = d end
        end
    end
    return best, bestDist
end

-- =====================
-- REFILL SYSTEM (độc lập, chạy song song)
-- =====================
local isRefilling    = false
local lastReloadTime = 0
local lastBladeReload = 0

task.spawn(function()
    while true do
        task.wait(0.3)
        if not getgenv().AutoRefill then continue end
        if isRefilling then continue end
        if os.clock() - lastReloadTime < 1 then continue end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then task.wait(1); continue end
        local md = getMapData()
        local slotIndex = lp:GetAttribute("Slot")
        local slotData  = slotIndex and md and md.Slots and md.Slots[slotIndex]
        if not slotData then continue end

        local weaponType = slotData.Weapon or "Blades"
        if getgenv().UseSpear then weaponType = "Spears" end

        if weaponType == "Blades" then
            local blade = getBlade()
            if not blade then continue end
            local sets = getBladeCount()

            if blade.Transparency == 1 and sets == 0 then
			print("sets=" .. sets .. " → vào refill gas tank") -- DEBUG
			local rf = getRefillPart()
			if not rf then continue end

			isRefilling = true
			lastReloadTime = os.clock()
			local savedRfCF = rf.CFrame

			-- Loop tele Refill theo player
			local tracking = true
			task.spawn(function()
				while tracking do
					task.wait()
					local c = lp.Character
					local r = c and c:FindFirstChild("HumanoidRootPart")
					if r then
						rf.CFrame = CFrame.new(r.Position)
					end
				end
			end)

			task.wait(0.3)
			pcall(function() postRemote:FireServer("Attacks", "Reload", rf) end)
			task.wait(0.8)

			-- Dừng tracking, trả Refill về vị trí cũ
			tracking = false
			rf.CFrame = savedRfCF
			task.wait(0.2)
			isRefilling = false

            -- Blade hết nhưng còn sets → reload lưỡi mới
            elseif blade.Transparency == 1 and sets > 0 then
				print("sets=" .. sets .. " → reload set mới") -- DEBUG
                if os.clock() - lastBladeReload < 0.5 then continue end
                lastBladeReload = os.clock()
                pcall(function() getRemote:InvokeServer("Blades", "Reload") end)
                task.wait(0.3)
            end

				elseif weaponType == "Spears" then
				if getSpearCount() == 0 then
				local rf = getRefillPart()
				if not rf then continue end

				isRefilling = true
				lastReloadTime = os.clock()
				local savedRfCF = rf.CFrame

				local tracking = true
				task.spawn(function()
					while tracking do
						task.wait()
						local c = lp.Character
						local r = c and c:FindFirstChild("HumanoidRootPart")
						if r then
							rf.CFrame = CFrame.new(r.Position)
						end
					end
				end)

				task.wait(0.3)
				pcall(function() postRemote:FireServer("Attacks", "Reload", rf) end)
				task.wait(0.8)

				tracking = false
				rf.CFrame = savedRfCF
				task.wait(0.2)
				isRefilling = false
			end
		end
    end
end)

-- =====================
-- AUTO FARM LOOP
-- =====================
local lastAttack = 0

task.spawn(function()
    while true do
        task.wait()
        if not getgenv().AutoFarm or isRefilling then continue end

        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then task.wait(1); continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then task.wait(1); continue end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end

        local md = getMapData()
        local slotIndex = lp:GetAttribute("Slot")
        local slotData  = slotIndex and md and md.Slots and md.Slots[slotIndex]
        if not slotData then task.wait(0.5); continue end

        local weapon = slotData.Weapon or "Blades"
        if getgenv().UseSpear then weapon = "Spears" end

        local nape, dist = findClosestNape(root)
        if not nape then root.AssemblyLinearVelocity = V3_ZERO; task.wait(0.5); continue end

        local titanModel = nape.Parent.Parent.Parent
        local titanHRP = titanModel:FindFirstChild("HumanoidRootPart")
        local targetPos = titanHRP
            and (titanHRP.CFrame * CFrame.new(0, HeightOffset, 30)).Position
            or (nape.Position + Vector3.new(0, HeightOffset, 0))

        if MovementMode == "Hover" then
            local dir = targetPos - root.Position
            root.AssemblyLinearVelocity = dir.Magnitude > 1 and dir.Unit * MoveSpeed or V3_ZERO
        else
            root.AssemblyLinearVelocity = V3_ZERO
            root.CFrame = CFrame.new(targetPos)
        end

        local now = os.clock()
        local dx = root.Position.X - nape.Position.X
        local dz = root.Position.Z - nape.Position.Z
        local cooldown = weapon == "Blades" and 0.15 or 1.0

        if (dx*dx + dz*dz) <= AttackRangeSq and (now - lastAttack) >= cooldown then
            lastAttack = now
            if weapon == "Blades" then
                postRemote:FireServer("Attacks", "Slash", true)
                if getgenv().MultiHit then
                    local count = 0
                    local titans = workspace:FindFirstChild("Titans")
                    if titans then
                        for _, titan in ipairs(titans:GetChildren()) do
                            if count >= HitCount then break end
                            if titan:GetAttribute("Killed") or titan:GetAttribute("Dead") then continue end
                            local hb = titan:FindFirstChild("Hitboxes")
                            local hit = hb and hb:FindFirstChild("Hit")
                            local n = hit and hit:FindFirstChild("Nape")
                            if n then
                                postRemote:FireServer("Hitboxes", "Register", n, math.random(625, 850))
                                count = count + 1
                            end
                        end
                    end
                else
                    postRemote:FireServer("Hitboxes", "Register", nape, math.random(625, 850))
                end
            else
                local ammo = getSpearCount()
                if ammo > 0 then
                    task.spawn(function()
                        getRemote:InvokeServer("Spears", "S_Fire", tostring(ammo))
                        local loops = bossNames[titanModel.Name] and 30 or 1
                        for _ = 1, loops do
                            postRemote:FireServer("Spears", "S_Explode", nape.Position)
                        end
                    end)
                end
            end
        end
    end
end)

-- =====================
-- AUTO ESCAPE
-- =====================
postRemote.OnClientEvent:Connect(function(...)
    local args = {...}
    if getgenv().AutoEscape and args[1] == "Titans" and args[2] == "Grab_Event" then
        pcall(function() PlayerGui.Interface.Buttons.Visible = false end)
        postRemote:FireServer("Attacks", "Slash_Escape")
    end
end)

-- =====================
-- AUTO RETRY / SKIP
-- =====================
task.spawn(function()
    local INTERFACE = PlayerGui:WaitForChild("Interface")
    local vim2 = game:GetService("VirtualInputManager")
    local GuiService = game:GetService("GuiService")

    local function UseButton(btn)
        if not btn or not btn.Parent or not btn.Visible then return false end
        if GuiService.MenuIsOpen then
            vim2:SendKeyEvent(true,  Enum.KeyCode.Escape, false, game)
            vim2:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
            task.wait(0.1)
        end
        GuiService.SelectedObject = btn
        task.wait(0.05)
        vim2:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
        vim2:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        return true
    end

    while true do
        task.wait(0.5)
        if getgenv().AutoSkip then
            local skip = INTERFACE:FindFirstChild("Skip")
            if skip and skip.Visible then
                task.wait(1)
                UseButton(skip:FindFirstChild("Interact"))
            end
        end
        if getgenv().AutoRetry then
            local rewards = INTERFACE:FindFirstChild("Rewards")
            if rewards and rewards.Visible then
                local btn = rewards:FindFirstChild("Main")
                    and rewards.Main:FindFirstChild("Info")
                    and rewards.Main.Info:FindFirstChild("Main")
                    and rewards.Main.Info.Main:FindFirstChild("Buttons")
                    and rewards.Main.Info.Main.Buttons:FindFirstChild("Retry")
                UseButton(btn)
            end
        end
    end
end)

-- =====================
-- DELETE MAP
-- =====================
local _dmRunning = false
local function DeleteMap()
    if _dmRunning or not getgenv().DeleteMap then return end
    local md2 = getMapData()
    if md2 and md2.Map and md2.Map.Type == "Raids" then return end
    task.spawn(function()
        _dmRunning = true
        while getgenv().DeleteMap do
            pcall(function()
                if workspace:FindFirstChild("Climbable") then
                    for _, v in ipairs(workspace.Climbable:GetChildren()) do v:Destroy() end
                end
                if workspace:FindFirstChild("Unclimbable") then
                    for _, v in ipairs(workspace.Unclimbable:GetChildren()) do
                        if v.Name ~= "Reloads" and v.Name ~= "Objective" and v.Name ~= "Cutscene" then
                            v:Destroy()
                        end
                    end
                end
            end)
            task.wait(3)
        end
        _dmRunning = false
    end)
end

-- =====================
-- AUTO REJOIN
-- =====================
getgenv().AutoRejoin = false

game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(state)
    if getgenv().AutoRejoin and state == Enum.TeleportState.Failed then
        task.wait(3)
        TeleportService:Teleport(game.PlaceId, lp)
    end
end)

task.spawn(function()
    while true do
        task.wait(5)
        if getgenv().AutoRejoin and not game:IsLoaded() then
            task.wait(3)
            TeleportService:Teleport(game.PlaceId, lp)
        end
    end
end)

-- =====================
-- UI - OBSIDIAN
-- =====================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local Toggles = Library.Toggles
local Options = Library.Options

local Window = Library:CreateWindow({
    Title = "AOT:R Auto Farm",
    Footer = "Combined Script",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
})

local Tabs = {
    Main     = Window:AddTab("Main",     "house"),
    Settings = Window:AddTab("Settings", "settings"),
}

local FarmBox = Tabs.Main:AddLeftGroupbox("Farm")
local MiscBox = Tabs.Main:AddRightGroupbox("Misc")
local ExtBox = Tabs.Main:AddRightGroupbox("Extensions")

FarmBox:AddToggle("AutoFarmToggle", { Text = "Auto Farm", Default = false })
Toggles.AutoFarmToggle:OnChanged(function()
    getgenv().AutoFarm = Toggles.AutoFarmToggle.Value
end)

FarmBox:AddToggle("UseSpearToggle", { Text = "Dùng Thunder Spear", Default = false })
Toggles.UseSpearToggle:OnChanged(function()
    getgenv().UseSpear = Toggles.UseSpearToggle.Value
end)

MiscBox:AddToggle("AutoExecToggle", { Text = "Auto Exec on Rejoin", Default = false })
Toggles.AutoExecToggle:OnChanged(function()
    if Toggles.AutoExecToggle.Value then
        writefile("autoexec/aotr_farm.lua", game:HttpGet("URL_SCRIPT_CỦA_BẠN"))
    else
        if isfile("autoexec/aotr_farm.lua") then
            delfile("autoexec/aotr_farm.lua")
        end
    end
end)

FarmBox:AddDropdown("MoveModeDropdown", {
    Values = { "Hover", "Teleport" }, Default = 1, Multi = false, Text = "Chế độ di chuyển",
})
Options.MoveModeDropdown:OnChanged(function() MovementMode = Options.MoveModeDropdown.Value end)

FarmBox:AddSlider("HoverSpeedSlider", { Text = "Tốc độ Hover", Default = 400, Min = 50, Max = 600, Rounding = 0 })
Options.HoverSpeedSlider:OnChanged(function() MoveSpeed = Options.HoverSpeedSlider.Value end)

FarmBox:AddSlider("HeightSlider", { Text = "Độ cao bay", Default = 250, Min = 50, Max = 400, Rounding = 0 })
Options.HeightSlider:OnChanged(function() HeightOffset = Options.HeightSlider.Value end)

FarmBox:AddSlider("RangeSlider", { Text = "Tầm đánh", Default = 150, Min = 50, Max = 500, Rounding = 0 })
Options.RangeSlider:OnChanged(function()
    AttackRange = Options.RangeSlider.Value
    AttackRangeSq = AttackRange * AttackRange
end)

FarmBox:AddToggle("AutoRefillToggle", { Text = "Auto Reload / Refill", Default = false })
Toggles.AutoRefillToggle:OnChanged(function()
    getgenv().AutoRefill = Toggles.AutoRefillToggle.Value
end)

FarmBox:AddToggle("AutoEscapeToggle", { Text = "Auto Escape", Default = false })
Toggles.AutoEscapeToggle:OnChanged(function()
    getgenv().AutoEscape = Toggles.AutoEscapeToggle.Value
end)

MiscBox:AddToggle("AutoRetryToggle", { Text = "Auto Retry", Default = false })
Toggles.AutoRetryToggle:OnChanged(function()
    getgenv().AutoRetry = Toggles.AutoRetryToggle.Value
end)

MiscBox:AddToggle("AutoRejoinToggle", { Text = "Auto Rejoin", Default = false })
Toggles.AutoRejoinToggle:OnChanged(function()
    getgenv().AutoRejoin = Toggles.AutoRejoinToggle.Value
end)

MiscBox:AddToggle("AutoSkipToggle", { Text = "Auto Skip Cutscene", Default = false })
Toggles.AutoSkipToggle:OnChanged(function()
    getgenv().AutoSkip = Toggles.AutoSkipToggle.Value
end)

MiscBox:AddToggle("DeleteMapToggle", { Text = "Delete Map (FPS++)", Default = false })
Toggles.DeleteMapToggle:OnChanged(function()
    getgenv().DeleteMap = Toggles.DeleteMapToggle.Value
    if getgenv().DeleteMap then DeleteMap() end
end)

MiscBox:AddToggle("SoloOnlyToggle", { Text = "Solo Only", Default = false })
Toggles.SoloOnlyToggle:OnChanged(function()
    getgenv().SoloOnly = Toggles.SoloOnlyToggle.Value
end)

MiscBox:AddToggle("Disable3DToggle", { Text = "Tắt render 3D (FPS++)", Default = false })
Toggles.Disable3DToggle:OnChanged(function()
    RunService:Set3dRenderingEnabled(not Toggles.Disable3DToggle.Value)
end)

MiscBox:AddButton({
    Text = "Return to Lobby",
    Func = function()
        getRemote:InvokeServer("Functions", "Teleport", "Lobby")
        task.wait(0.5)
        TeleportService:Teleport(14916516914, lp)
    end,
})

MiscBox:AddLabel("Phím ẩn/hiện UI: RightControl"):AddKeyPicker("MenuKeybind", {
    Default = "RightControl", NoUI = true, Text = "Menu keybind"
})
Library.ToggleKeybind = Options.MenuKeybind

ExtBox:AddToggle("MultiHitToggle", { Text = "Multi Hit (risky)", Default = false })
Toggles.MultiHitToggle:OnChanged(function()
    getgenv().MultiHit = Toggles.MultiHitToggle.Value
end)

ExtBox:AddSlider("HitCountSlider", { Text = "Hit Count", Default = 10, Min = 1, Max = 10, Rounding = 0 })
Options.HitCountSlider:OnChanged(function()
    HitCount = Options.HitCountSlider.Value
end)

local SCRIPT_URL = "https://raw.githubusercontent.com/NguyenTriThuc2010/aty1/main/loader.lua"

MiscBox:AddToggle("AutoExecToggle", { Text = "Auto Exec on Rejoin", Default = false })
Toggles.AutoExecToggle:OnChanged(function()
    if Toggles.AutoExecToggle.Value then
        writefile("autoexec/aotr_farm.lua", game:HttpGet(SCRIPT_URL))
        print("Auto Exec: BẬT")
    else
        if isfile("autoexec/aotr_farm.lua") then
            delfile("autoexec/aotr_farm.lua")
            print("Auto Exec: TẮT")
        end
    end
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("AoTRFarm")
SaveManager:SetFolder("AoTRFarm")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
ThemeManager:ApplyTheme("Jester")
SaveManager:LoadAutoloadConfig()


-- Solo-only watcher
task.spawn(function()
    while true do
        task.wait(5)
        if getgenv().SoloOnly and #Players:GetPlayers() > 1 then
            getgenv().AutoFarm = false
            Toggles.AutoFarmToggle:SetValue(false)
            task.spawn(function()
                getRemote:InvokeServer("Functions", "Teleport", "Lobby")
                task.wait(0.5)
                TeleportService:Teleport(14916516914, lp)
            end)
        end
    end
end)

print("[LOADED] AOT:R Auto Farm | RightControl để mở/đóng UI")
