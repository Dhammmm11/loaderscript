if _G._owehubGakuranUnload then
    pcall(_G._owehubGakuranUnload)
    _G._owehubGakuranUnload = nil
end
local obsidianRepo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(obsidianRepo .. "Library.lua"))()
local ThemeManager
local SaveManager
local okTheme, themeFunc = pcall(function() return loadstring(game:HttpGet(obsidianRepo .. "addons/ThemeManager.lua"))() end)
if okTheme and themeFunc then
    ThemeManager = themeFunc
else
    ThemeManager = {
        SetLibrary = function() end,
        SetFolder = function() end,
        ApplyToTab = function() end
    }
end
local okSave, saveFunc = pcall(function() return loadstring(game:HttpGet(obsidianRepo .. "addons/SaveManager.lua"))() end)
if okSave and saveFunc then
    SaveManager = saveFunc
else
    SaveManager = {
        SetLibrary = function() end,
        IgnoreThemeSettings = function() end,
        SetIgnoreIndexes = function() end,
        SetFolder = function() end,
        BuildConfigSection = function() end,
        LoadAutoloadConfig = function() end
    }
end
local Toggles           = Library.Toggles
local Options           = Library.Options
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local LocalPlayer       = Players.LocalPlayer
local CONFIG_FILE       = "GakuranAutoParry.json"
local Config            = {
    parries   = {
        ["76236532060812"] = { name = "Hakari/1stM1", delay = 0.35, hold = 0.30, kind = "M1" },
        ["74206130671324"] = { name = "Hakari/2ndM1", delay = 0.35, hold = 0.30, kind = "M1" },
        ["92851992709496"] = { name = "Hakari/M2", delay = 0.45, hold = 0.30, kind = "M2" },
    },
    blacklist = {},
}
local canWrite          = (typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function")
local configDirty       = false
local function saveCustomConfig()
    if not canWrite then return end
    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
    end)
end
task.spawn(function()
    while true do
        task.wait(5)
        if configDirty then
            configDirty = false
            saveCustomConfig()
        end
    end
end)
local function markConfigDirty()
    configDirty = true
end
local function loadCustomConfig()
    if not canWrite then return end
    pcall(function()
        if isfile(CONFIG_FILE) then
            local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
            if typeof(data) == "table" then
                for k, v in pairs(data) do
                    if Config[k] ~= nil then
                        if k == "parries" and type(v) == "table" then
                            for pid, pdata in pairs(v) do
                                Config.parries[pid] = pdata
                            end
                        else
                            Config[k] = v
                        end
                    end
                end
            end
        end
    end)
end
loadCustomConfig()
local function parseAnimId(text)
    if typeof(text) ~= "string" then text = tostring(text or "") end
    local id = text:match("%d+")
    return id
end
local function classifyAnim(track, anim)
    local name = anim.Name or "Animation"
    local animations = ReplicatedStorage:FindFirstChild("Animations")
    local combatFolder = animations and animations:FindFirstChild("Combat")
    if combatFolder and anim:IsDescendantOf(combatFolder) then
        local parts = {}
        local node = anim
        while node and node ~= combatFolder do
            table.insert(parts, 1, node.Name)
            node = node.Parent
        end
        if #parts >= 2 then
            local style = parts[1]:gsub("Anims$", "")
            return "Combat", style .. " * " .. table.concat(parts, "/", 2)
        end
        return "Combat", "Combat * " .. name
    end
    local pr = track.Priority
    if pr == Enum.AnimationPriority.Action
        or pr == Enum.AnimationPriority.Action2
        or pr == Enum.AnimationPriority.Action3
        or pr == Enum.AnimationPriority.Action4 then
        return "Action", name
    end
    return "Movement", name
end
local _cachedBlockMod = nil
local function _resolveCombatStyle()
    local style = "Base"
    local char = LocalPlayer.Character
    if char then
        local pd = char:FindFirstChild("PlayerData")
        if pd then
            local ct = pd:GetAttribute("CombatType")
            if typeof(ct) == "string" and ct ~= "" then style = ct end
        end
    end
    return style
end
local function _getCombatFolder()
    local combatClient = ReplicatedStorage:FindFirstChild("CombatSystemClient")
    if not combatClient then return nil end
    local combat = combatClient:FindFirstChild("Combat")
    if not combat then return nil end
    local style = _resolveCombatStyle()
    return combat:FindFirstChild(style) or combat:FindFirstChild("Base")
end
local function getBlockModule()
    if _cachedBlockMod then return _cachedBlockMod end
    local ok, mod = pcall(function()
        local folder = _getCombatFolder()
        if not folder then return nil end
        local blockScript = folder:FindFirstChild("Block")
        if blockScript and blockScript:IsA("ModuleScript") then
            return require(blockScript)
        end
        return nil
    end)
    if ok and mod then
        _cachedBlockMod = mod
        return mod
    end
    if typeof(getgc) == "function" then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and rawget(v, "Block") and rawget(v, "Unblock")
                    and rawget(v, "SuppressBlocking") and typeof(rawget(v, "Block")) == "function" then
                    _cachedBlockMod = v
                    break
                end
            end
        end)
    end
    return _cachedBlockMod
end
local isMobile = UserInputService.TouchEnabled
local function parryViaFallback(hold)
    local ok, VIM = pcall(game.GetService, game, "VirtualInputManager")
    if not ok or not VIM then return end
    VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait(math.max(hold, 0.05))
    VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
end
local _authService = nil
local function getAuthService()
    if _authService then return _authService end
    pcall(function()
        _authService = require(ReplicatedStorage.Shared.Services.AuthService.AuthServiceClient)
    end)
    if not _authService and typeof(getgc) == "function" then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and rawget(v, "NextForKey") and typeof(rawget(v, "NextForKey")) == "function" then
                    _authService = v
                    break
                end
            end
        end)
    end
    return _authService
end
local function directBlock()
    local char = LocalPlayer.Character
    if not char then return false end
    if char:GetAttribute("Equip") ~= true then return false end
    if char:GetAttribute("Ragdoll") == true then return false end
    if char:GetAttribute("Stunned") == true then return false end
    if char:GetAttribute("CantAnything") == true then return false end
    if char:GetAttribute("BlockCooldown") == true then return false end
    local auth = getAuthService()
    if not auth then return false end
    local server = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Server")
    if not server then return false end
    local t = Workspace:GetServerTimeNow()
    local a, b, c = auth:NextForKey("Combat.Block.Activated")
    if c == 0 then return false end
    char:SetAttribute("Blocking", true)
    server:FireServer({}, t, a, b, c)
    return true
end
local function directUnblock()
    local char = LocalPlayer.Character
    if not char then return end
    local auth = getAuthService()
    if not auth then return end
    local server = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Server")
    if not server then return end
    char:SetAttribute("Blocking", nil)
    local a, b, c = auth:NextForKey("Combat.Block.Deactivated")
    server:FireServer({}, a, b, c)
end
local State = {
    parryActive = false,
    dodgeActive = false,
    lastTrigger = {},
}
local function doParry(hold)
    if State.parryActive then return end
    State.parryActive = true
    task.spawn(function()
        local blockMod = getBlockModule()
        if blockMod and typeof(blockMod.Block) == "function" and typeof(blockMod.Unblock) == "function" then
            local stopAt = os.clock() + math.max(hold, 0.05)
            while os.clock() < stopAt do
                pcall(blockMod.Block)
                task.wait()
            end
            pcall(blockMod.Unblock)
        elseif directBlock() then
            task.wait(math.max(hold, 0.05))
            directUnblock()
        else
            parryViaFallback(hold)
        end
        State.parryActive = false
    end)
end
local _cachedEvasiveMod = nil
local function getEvasiveModule()
    if _cachedEvasiveMod then return _cachedEvasiveMod end
    local ok, mod = pcall(function()
        local folder = _getCombatFolder()
        if not folder then return nil end
        local evScript = folder:FindFirstChild("Evasive")
        if evScript and evScript:IsA("ModuleScript") then
            return require(evScript)
        end
        return nil
    end)
    if ok and mod then
        _cachedEvasiveMod = mod
        return mod
    end
    if typeof(getgc) == "function" then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and typeof(rawget(v, "Evasive")) == "function"
                    and rawget(v, "CancelDash") and rawget(v, "IsDashActive") then
                    _cachedEvasiveMod = v
                    break
                end
            end
        end)
    end
    return _cachedEvasiveMod
end
local function directDodge()
    local char = LocalPlayer.Character
    if not char then return false end
    if char:GetAttribute("Ragdoll") == true then return false end
    if char:GetAttribute("Stunned") == true then return false end
    if char:GetAttribute("Downed") == true then return false end
    if char:GetAttribute("IFRAMECD") == true then return false end
    local auth = getAuthService()
    if not auth then return false end
    local server = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Server")
    if not server then return false end
    local a, b, c = auth:NextForKey("Combat.Evasive.Evasive")
    if c == 0 then return false end
    server:FireServer({}, a, b, c)
    return true
end
local function threatField(myRoot, range)
    local away = Vector3.new(0, 0, 0)
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if r and hum and hum.Health > 0 then
                local flat = Vector3.new(r.Position.X - myRoot.Position.X, 0, r.Position.Z - myRoot.Position.Z)
                local d = flat.Magnitude
                if d > 0.001 and d <= range then
                    count += 1
                    away -= flat.Unit * (1.15 - math.clamp(d / range, 0, 1))
                end
            end
        end
    end
    return count, away
end
local function sideDodgeDir(model)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local right = myRoot.CFrame.RightVector
    local range = (Options.MaxRangeDodge and Options.MaxRangeDodge.Value) or 20
    local _, away = threatField(myRoot, range)
    local theirRoot = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    if theirRoot then
        local flat = Vector3.new(theirRoot.Position.X - myRoot.Position.X, 0, theirRoot.Position.Z - myRoot.Position.Z)
        if flat.Magnitude > 0.001 then away -= flat.Unit end
    end
    local awayFlat = Vector3.new(away.X, 0, away.Z)
    local dir
    if awayFlat.Magnitude < 0.001 then
        dir = (math.random() < 0.5) and right or -right
    else
        local rd = right:Dot(awayFlat.Unit)
        if math.abs(rd) < 0.15 then
            dir = (math.random() < 0.5) and right or -right
        else
            dir = (rd >= 0) and right or -right
        end
    end
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.001 then return nil end
    return flat.Unit
end
local function backDodgeDir(model)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local theirRoot = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    local dir
    if theirRoot then
        local diff = myRoot.Position - theirRoot.Position
        local flat = Vector3.new(diff.X, 0, diff.Z)
        if flat.Magnitude > 0.001 then dir = flat.Unit end
    end
    if not dir then
        local look = myRoot.CFrame.LookVector
        dir = Vector3.new(-look.X, 0, -look.Z).Unit
    end
    return dir
end
local function doDodge(model, mode)
    if State.dodgeActive then
        directBlock()
        return
    end
    State.dodgeActive = true
    task.spawn(function()
        local ev = getEvasiveModule()
        if ev and typeof(ev.Evasive) == "function" then
            pcall(ev.Evasive)
            if mode then
                local dir = (mode == "back") and backDodgeDir(model) or sideDodgeDir(model)
                if dir then
                    local myChar = LocalPlayer.Character
                    local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local lv = hrp and hrp:FindFirstChild("EvasiveDashLinearVelocity")
                    if lv then
                        local speed = lv.VectorVelocity.Magnitude
                        if speed < 1 then speed = 65 end
                        lv.VectorVelocity = dir * speed
                    end
                end
            end
        else
            directDodge()
        end
        task.wait(0.18)
        State.dodgeActive = false
    end)
end
local function isBehind(model, thresh)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local theirRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not (myRoot and theirRoot) then return false end
    local to = theirRoot.Position - myRoot.Position
    local flat = Vector3.new(to.X, 0, to.Z)
    if flat.Magnitude < 0.001 then return false end
    local dot = myRoot.CFrame.LookVector:Dot(flat.Unit)
    return dot < (thresh or 0)
end
local CombatConfig = nil
pcall(function()
    CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
end)
local AttackDB = {}
local AttackDBCount = 0
local function buildAttackDB()
    AttackDB = {}
    AttackDBCount = 0
    if not CombatConfig then return end
    local anims = ReplicatedStorage:FindFirstChild("Animations")
    local combat = anims and anims:FindFirstChild("Combat")
    if not combat then return end
    local m1idx = { ["1stM1"] = 1, ["2ndM1"] = 2, ["3rdM1"] = 3, ["4thM1"] = 4 }
    for _, styleFolder in ipairs(combat:GetChildren()) do
        if styleFolder:IsA("Folder") then
            local styleName = styleFolder.Name:gsub("Anims$", "")
            local styleKey = string.lower(styleName)
            for _, a in ipairs(styleFolder:GetChildren()) do
                if a:IsA("Animation") then
                    local id = a.AnimationId:match("%d+")
                    local delay, kind, idx
                    idx = m1idx[a.Name]
                    if idx and typeof(CombatConfig.GetScaledStyleM1HitboxDelay) == "function" then
                        kind = "M1"
                        local ok, v = pcall(CombatConfig.GetScaledStyleM1HitboxDelay, styleKey, idx, 1)
                        if ok and typeof(v) == "number" and v > 0 then delay = v else delay = 0.35 end
                    elseif a.Name == "M2" and typeof(CombatConfig.GetStyleM2HitboxDelay) == "function" then
                        kind = "M2"
                        local ok, raw = pcall(CombatConfig.GetStyleM2HitboxDelay, styleKey)
                        if ok and typeof(CombatConfig.GetScaledHitboxDelay) == "function" then
                            local ok2, v = pcall(CombatConfig.GetScaledHitboxDelay, raw, 1)
                            if ok2 and typeof(v) == "number" and v > 0 then delay = v else delay = 0.45 end
                        elseif ok and typeof(raw) == "number" and raw > 0 then
                            delay = raw
                        else
                            delay = 0.45
                        end
                    elseif a.Name == "MomentumM2" and typeof(CombatConfig.GetStyleM2HitboxDelay) == "function" then
                        kind = "M2M"
                        local ok, raw = pcall(CombatConfig.GetStyleM2HitboxDelay, styleKey, true)
                        if ok and typeof(CombatConfig.GetScaledHitboxDelay) == "function" then
                            local ok2, v = pcall(CombatConfig.GetScaledHitboxDelay, raw, 1)
                            if ok2 and typeof(v) == "number" and v > 0 then delay = v else delay = 0.45 end
                        elseif ok and typeof(raw) == "number" and raw > 0 then
                            delay = raw
                        else
                            delay = 0.45
                        end
                    end
                    if id and typeof(delay) == "number" and delay > 0 and not AttackDB[id] then
                        AttackDB[id] = { name = styleName .. "/" .. a.Name, delay = delay, kind = kind, style = styleKey, idx = (idx ~= nil and idx or nil) }
                        AttackDBCount += 1
                    end
                end
            end
        end
    end
end
buildAttackDB()
local _combatUtils = nil
local function getCombatUtils()
    if _combatUtils and typeof(rawget(_combatUtils, "GetAttackSpeedMultiplier")) == "function" then
        return _combatUtils
    end
    _combatUtils = nil
    if typeof(getgc) == "function" then
        pcall(function()
            for _, o in ipairs(getgc(true)) do
                if type(o) == "table" and typeof(rawget(o, "GetAttackSpeedMultiplier")) == "function"
                    and typeof(rawget(o, "GetCharacterHeight")) == "function" then
                    _combatUtils = o; break
                end
            end
        end)
    end
    return _combatUtils
end
local function attackSpeedFor(model)
    local cu = getCombatUtils()
    if not cu then return 1 end
    local ok, spd = pcall(function()
        local h = cu.GetCharacterHeight(model)
        if not h then return 1 end
        return cu.GetAttackSpeedMultiplier(h)
    end)
    if ok and typeof(spd) == "number" and spd > 0 then return spd end
    return 1
end
local updateDBStatus
do
    local function hookCombat(combatFolder)
        local pending = false
        combatFolder.DescendantAdded:Connect(function(d)
            if not (d:IsA("Animation") or d:IsA("Folder")) then return end
            if pending then return end
            pending = true
            task.delay(1, function()
                pending = false
                buildAttackDB()
                if updateDBStatus then pcall(updateDBStatus) end
            end)
        end)
    end
    local anims = ReplicatedStorage:FindFirstChild("Animations")
    local combat = anims and anims:FindFirstChild("Combat")
    if combat then
        hookCombat(combat)
    else
        task.spawn(function()
            local a = ReplicatedStorage:WaitForChild("Animations", 30)
            local c = a and a:WaitForChild("Combat", 30)
            if c then
                buildAttackDB()
                if updateDBStatus then pcall(updateDBStatus) end
                hookCombat(c)
            end
        end)
    end
end
local function styleOf(model)
    local pd = model:FindFirstChild("PlayerData")
    local s = pd and pd:GetAttribute("CombatStyle")
    if typeof(s) == "string" and s ~= "" then return string.lower(s) end
    return "default"
end
local function getPing()
    local ok, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
    if ok and typeof(ping) == "number" then return ping end
    return 0
end
local Logger, Preview
local openPreview, createLoggerWindow, createPreviewWindow, refreshSavedDropdown
local startInfStamina, stopInfStamina
local startAutoSprint, stopAutoSprint
local startNoStun, stopNoStun
local startNoDodgeCD, stopNoDodgeCD
local startAutoRespawn, stopAutoRespawn
local startNoRagdoll, stopNoRagdoll
local startNoBlur, stopNoBlur
local startNoParryCD, stopNoParryCD
local startFollow, stopFollow
local startNoclip, stopNoclip
local blockedBySafeMode
local Window = Library:CreateWindow({
    Title = "Foyihub | Gakuran",
    Footer = "https://discord.gg/r6esycEPar",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
    NotifySide = "Right",
})
local Tabs = {
    Main            = Window:AddTab("Auto Parry"),
    Parries         = Window:AddTab("Parries"),
    Players         = Window:AddTab("Players"),
    Minigames       = Window:AddTab("Minigames"),
    Visuals         = Window:AddTab("Visuals"),
    World           = Window:AddTab("World"),
    ["UI Settings"] = Window:AddTab("UI Settings"),
}
local _parryAdornee = nil
local _dodgeAdornee = nil
local _rangeConn = nil
local function _updateRangeCircles()
    local myChar = LocalPlayer.Character
    local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local showParry = Toggles.ShowParryRange and Toggles.ShowParryRange.Value
    local showDodge = Toggles.ShowDodgeRange and Toggles.ShowDodgeRange.Value
    if showParry and hrp then
        if not _parryAdornee then
            _parryAdornee = Instance.new("CylinderHandleAdornment")
            _parryAdornee.Name = "GKParryRange"
            _parryAdornee.Height = 0.05
            _parryAdornee.Transparency = 0.55
            _parryAdornee.AlwaysOnTop = false
            _parryAdornee.CFrame = CFrame.new(0, -2.9, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            pcall(function()
                _parryAdornee.Parent = (typeof(gethui) == "function" and gethui()) or
                    game:GetService("CoreGui")
            end)
        end
        _parryAdornee.Adornee = hrp
        local r = (Options.MaxRange and Options.MaxRange.Value) or 15
        _parryAdornee.Radius = r
        if Options.ParryRangeColorPicker then
            _parryAdornee.Color3 = Options.ParryRangeColorPicker.Value
        else
            _parryAdornee.Color3 = Color3.fromRGB(0, 230, 180)
        end
        _parryAdornee.Visible = true
    else
        if _parryAdornee then _parryAdornee.Visible = false end
    end
    if showDodge and hrp then
        if not _dodgeAdornee then
            _dodgeAdornee = Instance.new("CylinderHandleAdornment")
            _dodgeAdornee.Name = "GKDodgeRange"
            _dodgeAdornee.Height = 0.05
            _dodgeAdornee.Transparency = 0.65
            _dodgeAdornee.AlwaysOnTop = false
            _dodgeAdornee.CFrame = CFrame.new(0, -2.85, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            pcall(function()
                _dodgeAdornee.Parent = (typeof(gethui) == "function" and gethui()) or
                    game:GetService("CoreGui")
            end)
        end
        _dodgeAdornee.Adornee = hrp
        local r = (Options.MaxRangeDodge and Options.MaxRangeDodge.Value) or 20
        _dodgeAdornee.Radius = r
        if Options.DodgeRangeColorPicker then
            _dodgeAdornee.Color3 = Options.DodgeRangeColorPicker.Value
        else
            _dodgeAdornee.Color3 = Color3.fromRGB(240, 140, 40)
        end
        _dodgeAdornee.Visible = true
    else
        if _dodgeAdornee then _dodgeAdornee.Visible = false end
    end
end
local function _startRangeVisualizer()
    if _rangeConn then return end
    _rangeConn = RunService.Heartbeat:Connect(_updateRangeCircles)
end
local function _stopRangeVisualizer()
    if _rangeConn then
        _rangeConn:Disconnect()
        _rangeConn = nil
    end
    if _parryAdornee then _parryAdornee.Visible = false end
    if _dodgeAdornee then _dodgeAdornee.Visible = false end
end
local function _checkRangeToggles()
    local p = Toggles.ShowParryRange and Toggles.ShowParryRange.Value
    local d = Toggles.ShowDodgeRange and Toggles.ShowDodgeRange.Value
    if p or d then _startRangeVisualizer() else _stopRangeVisualizer() end
end
local _origMaxZoom = LocalPlayer.CameraMaxZoomDistance
local _zoomConn = nil
local function _enableInfiniteZoom()
    _origMaxZoom = LocalPlayer.CameraMaxZoomDistance
    LocalPlayer.CameraMaxZoomDistance = 100000
    _zoomConn = RunService.Heartbeat:Connect(function()
        if LocalPlayer.CameraMaxZoomDistance < 99999 then
            LocalPlayer.CameraMaxZoomDistance = 100000
        end
    end)
end
local function _disableInfiniteZoom()
    if _zoomConn then
        _zoomConn:Disconnect()
        _zoomConn = nil
    end
    LocalPlayer.CameraMaxZoomDistance = _origMaxZoom or 128
end
local ParryGroup = Tabs.Main:AddLeftGroupbox("Parry")
ParryGroup:AddToggle("AutoParry", {
    Text = "Auto Parry (master)",
    Default = true,
})
ParryGroup:AddToggle("AutoAll", {
    Text = string.format("Auto-Parry ALL attacks (%d)", AttackDBCount),
    Default = true,
    Tooltip = "Automatically parry every known game attack",
})
ParryGroup:AddToggle("AutoDodge", {
    Text = "Auto-Dodge rear attacks",
    Default = false,
    Tooltip = "When an attacker is behind you (can't be parried), dash instead of blocking",
})
ParryGroup:AddToggle("M2DodgeBack", {
    Text = "M2 Dodge (backward)",
    Default = false,
    Tooltip = "When a heavy attack is incoming, dash BACKWARD out of its range instead of blocking.",
})
ParryGroup:AddToggle("ShowParryRange", {
    Text = "Show Parry Distance Circle",
    Default = false,
    Tooltip = "Draw a visual ring under your feet showing the max auto-parry distance",
    Callback = _checkRangeToggles,
}):AddColorPicker("ParryRangeColorPicker", {
    Default = Color3.fromRGB(0, 230, 180),
    Title = "Circle Color",
})
ParryGroup:AddToggle("ShowDodgeRange", {
    Text = "Show Dodge Distance Circle",
    Default = false,
    Tooltip = "Draw a visual ring under your feet showing the max auto-dodge distance",
    Callback = _checkRangeToggles,
}):AddColorPicker("DodgeRangeColorPicker", {
    Default = Color3.fromRGB(240, 140, 40),
    Title = "Circle Color",
})
ParryGroup:AddToggle("ExcludeFriends", {
    Text = "Don't parry Roblox friends",
    Default = true,
    Tooltip = "Skip auto-parry/dodge against attackers who are your Roblox friends",
})
ParryGroup:AddToggle("ExcludeContacts", {
    Text = "Don't parry game contacts",
    Default = true,
    Tooltip = "Skip auto-parry/dodge against attackers saved in your in-game phone contacts",
})
local TimingGroup = Tabs.Main:AddRightGroupbox("Timing")
TimingGroup:AddSlider("TimingOffset", {
    Text = "Timing Offset (ms)",
    Default = -75,
    Min = -200,
    Max = 200,
    Rounding = 0,
    Suffix = "ms",
    Tooltip = "earlier (-) or later (+) from computed hit time",
})
TimingGroup:AddSlider("BlockHold", {
    Text = "Block Hold (ms)",
    Default = 400,
    Min = 100,
    Max = 700,
    Rounding = 0,
    Suffix = "ms",
    Tooltip = "How long to hold each block to cover the hit",
})
TimingGroup:AddSlider("MaxRange", {
    Text = "Max Range (studs)",
    Default = 15,
    Min = 10,
    Max = 30,
    Rounding = 0,
    Suffix = " studs",
    Tooltip = "Only parry enemies within this distance",
})
TimingGroup:AddSlider("MaxRangeDodge", {
    Text = "Max Range (Dodge)",
    Default = 20,
    Min = 10,
    Max = 40,
    Rounding = 0,
    Suffix = " studs",
    Tooltip = "Only auto-dodge attackers within this distance",
})
TimingGroup:AddSlider("DodgeAngle", {
    Text = "Dodge Angle",
    Default = 60,
    Min = 30,
    Max = 135,
    Rounding = 0,
    Suffix = "°",
    Tooltip =
    "Attacks more than this many degrees off your facing (left/right/rear) can't be parried, so dodge them. Lower = dodge more side attacks; higher = only dodge near-rear",
})
local NotifGroup = Tabs.Main:AddLeftGroupbox("Notifs")
NotifGroup:AddToggle("Notifications", {
    Text = "Notifications",
    Default = true,
})
Tabs.Main:AddRightGroupbox("Status"):AddLabel("DBLoaded", {
    Text = string.format("Attack DB: %d attacks loaded  |  Ping: %dms  |  Block: %s",
        AttackDBCount, math.floor(getPing() * 1000 + 0.5),
        getBlockModule() and "hooked" or "fallback (F)"),
    DoesWrap = true,
})
updateDBStatus = function()
    if not Options.DBLoaded then return end
    pcall(function()
        Options.DBLoaded:SetText(string.format("Attack DB: %d attacks loaded  |  Ping: %dms  |  Block: %s",
            AttackDBCount, math.floor(getPing() * 1000 + 0.5),
            getBlockModule() and "hooked" or "fallback (F)"))
    end)
end
local BGroup = Tabs.Parries:AddLeftGroupbox("Parry Builder")
BGroup:AddInput("BuilderAnimId", {
    Text = "Animation ID",
    Default = "",
    Placeholder = "e.g. 72352073483435",
    ClearTextOnFocus = false,
})
BGroup:AddInput("BuilderName", {
    Text = "Name",
    Default = "",
    Placeholder = "e.g. M1 Combo Hit 3",
    ClearTextOnFocus = false,
})
BGroup:AddInput("BuilderDelay", {
    Text = "Hit Time (s)",
    Default = "0.35",
    Numeric = true,
    ClearTextOnFocus = false,
})
BGroup:AddInput("BuilderHold", {
    Text = "Hold (s)",
    Default = "0.30",
    Numeric = true,
    ClearTextOnFocus = false,
})
BGroup:AddButton({
    Text = "Add / Update Parry",
    Func = function()
        local id = parseAnimId(Options.BuilderAnimId.Value)
        if not id then
            Library:Notify({ Title = "Parry Builder", Description = "Invalid Animation ID", Time = 3 })
            return
        end
        local name = Options.BuilderName.Value
        if not name or name:gsub("%s+", "") == "" then name = "Custom/" .. id end
        local delay = tonumber(Options.BuilderDelay.Value) or 0.35
        local hold = tonumber(Options.BuilderHold.Value) or 0.30
        Config.parries[id] = { name = name, delay = delay, hold = hold }
        markConfigDirty()
        refreshSavedDropdown()
        Library:Notify({ Title = "Parry Builder", Description = "Saved parry for ID " .. id, Time = 3 })
    end,
})
local SGroup = Tabs.Parries:AddRightGroupbox("Saved Parries")
SGroup:AddDropdown("SavedDropdown", {
    Text = "Select Parry",
    Values = { "(none)" },
    Default = "(none)",
})
refreshSavedDropdown = function()
    local list = {}
    for id, p in pairs(Config.parries) do
        table.insert(list, string.format("%s (%s)", p.name, id))
    end
    table.sort(list)
    if #list == 0 then list = { "(none)" } end
    pcall(function() Options.SavedDropdown:SetValues(list) end)
end
refreshSavedDropdown()
SGroup:AddButton({
    Text = "Remove Selected",
    Func = function()
        local sel = Options.SavedDropdown.Value
        if not sel or sel == "(none)" then return end
        local id = sel:match("%((%d+)%)$")
        if id and Config.parries[id] then
            Config.parries[id] = nil
            markConfigDirty()
            refreshSavedDropdown()
            Library:Notify({ Title = "Parry Builder", Description = "Removed parry for ID " .. id, Time = 3 })
        end
    end,
})
local PlayerGroup = Tabs.Players:AddLeftGroupbox("Player Exploits")
PlayerGroup:AddToggle("AutoSprint", {
    Text = "Auto Sprint",
    Default = false,
    Callback = function(val)
        if val then startAutoSprint() else stopAutoSprint() end
    end,
})
PlayerGroup:AddToggle("Noclip", {
    Text = "Noclip",
    Default = false,
    Tooltip = "Walk through walls and obstacles",
    Callback = function(val)
        if val then startNoclip() else stopNoclip() end
    end,
})
PlayerGroup:AddToggle("InfStamina", {
    Text = "Infinite Stamina",
    Default = false,
    Callback = function(val)
        if val then startInfStamina() else stopInfStamina() end
    end,
})
PlayerGroup:AddToggle("NoStun", {
    Text = "No Stun [RISK]",
    Default = false,
    Callback = function(val)
        if val and blockedBySafeMode("NoStun") then return end
        if val then startNoStun() else stopNoStun() end
    end,
})
PlayerGroup:AddToggle("NoDodgeCD", {
    Text = "No Dodge Cooldown [RISK]",
    Default = false,
    Callback = function(val)
        if val and blockedBySafeMode("NoDodgeCD") then return end
        if val then startNoDodgeCD() else stopNoDodgeCD() end
    end,
})
PlayerGroup:AddToggle("NoRagdoll", {
    Text = "No Ragdoll [RISK]",
    Default = false,
    Callback = function(val)
        if val and blockedBySafeMode("NoRagdoll") then return end
        if val then startNoRagdoll() else stopNoRagdoll() end
    end,
})
PlayerGroup:AddToggle("NoParryCD", {
    Text = "No Parry Cooldown [RISK]",
    Default = false,
    Callback = function(val)
        if val and blockedBySafeMode("NoParryCD") then return end
        if val then startNoParryCD() else stopNoParryCD() end
    end,
})
local RespawnGroup = Tabs.Players:AddRightGroupbox("Respawn & Death")
RespawnGroup:AddToggle("AutoRespawn", {
    Text = "Auto Respawn & Fast Skip",
    Default = false,
    Tooltip = "Bypass death UI and trigger instant spawn server remote upon dying",
    Callback = function(val)
        if val then startAutoRespawn() else stopAutoRespawn() end
    end,
})
RespawnGroup:AddDropdown("SpawnSpot", {
    Text = "Auto Spawn Spot",
    Values = { "Default", "Courtyard", "Roof", "Gym", "Gate" },
    Default = "Default",
    Tooltip = "Select location where your character will instantly teleport after fast respawning",
})
RespawnGroup:AddToggle("NoBlur", {
    Text = "No Blur",
    Default = false,
    Tooltip = "Strip Blur/ColorCorrection effects from Lighting and Camera every Heartbeat",
    Callback = function(val)
        if val then startNoBlur() else stopNoBlur() end
    end,
})
local TeleportGroup = Tabs.Players:AddLeftGroupbox("Teleport")
local function refreshTeleportDropdown()
    local values = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(values, p.Name)
        end
    end
    if #values == 0 then
        table.insert(values, "(no players)")
        pcall(function()
            Options.TeleportTarget:SetValues(values)
            Options.TeleportTarget:SetDisabledValues({ "(no players)" })
        end)
    else
        pcall(function()
            Options.TeleportTarget:SetValues(values)
            Options.TeleportTarget:SetDisabledValues({})
        end)
    end
end
TeleportGroup:AddDropdown("TeleportTarget", {
    Text = "Target Player",
    Values = { "(no players)" },
    Default = "(no players)",
})
refreshTeleportDropdown()
Players.PlayerAdded:Connect(refreshTeleportDropdown)
Players.PlayerRemoving:Connect(refreshTeleportDropdown)
TeleportGroup:AddButton({
    Text = "Refresh Player List",
    Func = refreshTeleportDropdown,
})
TeleportGroup:AddSlider("TeleportOffset", {
    Text = "Teleport Distance",
    Default = 3,
    Min = 0,
    Max = 15,
    Rounding = 1,
    Suffix = " studs",
})
TeleportGroup:AddButton({
    Text = "Teleport To Target",
    Func = function()
        local sel = Options.TeleportTarget and Options.TeleportTarget.Value
        if not sel or sel == "(no players)" then return end
        local target = Players:FindFirstChild(sel)
        if not target or not target.Character then return end
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (tRoot and myRoot) then return end
        local offset = (Options.TeleportOffset and Options.TeleportOffset.Value) or 3
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 0, offset)
    end,
})
TeleportGroup:AddToggle("FollowTarget", {
    Text = "Loop Teleport (Follow)",
    Default = false,
    Callback = function(val)
        if val then startFollow() else stopFollow() end
    end,
})
local SafeGroup = Tabs.Players:AddRightGroupbox("Safety")
SafeGroup:AddToggle("SafeMode", {
    Text = "Safe Mode",
    Default = true,
    Tooltip = "Disables toggles tagged [RISK] that have a high chance of detection on strict servers",
})
blockedBySafeMode = function(featureName)
    if Toggles.SafeMode and Toggles.SafeMode.Value then
        Library:Notify({
            Title = "Safe Mode Active",
            Description = featureName .. " is blocked to prevent bans. Turn off Safe Mode on the Players tab to use it.",
            Time = 4,
        })
        return true
    end
    return false
end
local SAFE_BLOCKED = {
    NoStun = true,
    NoDodgeCD = true,
    NoRagdoll = true,
    NoParryCD = true,
}
Options.SafeMode:OnChanged(function()
    if Toggles.SafeMode.Value then
        for key in pairs(SAFE_BLOCKED) do
            local t = Toggles[key]
            if t and t.Value then
                pcall(function() t:SetValue(false) end)
            end
        end
    end
end)
local RhythmGroup = Tabs.Minigames:AddLeftGroupbox("Auto Rhythm")
RhythmGroup:AddToggle("AutoRhythm", {
    Text = "Auto Rhythm (Instrument / Karaoke)",
    Default = false,
    Tooltip = "Auto-play rhythm mini-game notes with customizable judgment timing",
})
RhythmGroup:AddDropdown("RhythmJudgment", {
    Text = "Timing Quality",
    Values = { "Legit (mix)", "Rage (100% Perfect)", "Good Only", "Okay Only" },
    Default = "Legit (mix)",
    Tooltip = "Controls which hit-windows the bot targets. Legit adds random human-like variance",
})
RhythmGroup:AddSlider("RhythmLegitPercent", {
    Text = "Legit Perfect Ratio",
    Default = 85,
    Min = 50,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Tooltip = "Percentage of notes hit as PERFECT (remainder hit as GOOD/OKAY)",
})
RhythmGroup:AddLabel("RhythmStatus", {
    Text = "idle -- enable Auto Rhythm to begin",
    DoesWrap = true,
})
local BballGroup = Tabs.Minigames:AddRightGroupbox("Basketball Auto-Green")
BballGroup:AddToggle("AutoBasketball", {
    Text = "Auto-Green Shot Release",
    Default = false,
    Tooltip = "Hooks shot-charging to automatically release your shoot key inside the green/perfect zone",
})
BballGroup:AddDropdown("BballJudgment", {
    Text = "Shot Timing Quality",
    Values = { "Perfect (Green)", "Good", "Legit Mix" },
    Default = "Perfect (Green)",
})
BballGroup:AddSlider("BballLegitPercent", {
    Text = "Legit Green Ratio",
    Default = 90,
    Min = 50,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
})
BballGroup:AddLabel("Hold your shoot key/button as normal, the shot is released for you at the perfect moment.", true)
local ESPGroup = Tabs.Visuals:AddLeftGroupbox("Enemy ESP")
ESPGroup:AddToggle("EnemyESP", {
    Text = "Enemy ESP",
    Default = false,
    Tooltip = "Show name, HP and stamina above every other player",
})
ESPGroup:AddToggle("ESPShowStamina", {
    Text = "Show stamina bar",
    Default = true,
})
ESPGroup:AddToggle("Chams", {
    Text = "Chams (Highlight)",
    Default = false,
    Tooltip = "Show see-through body highlight on enemy players",
}):AddColorPicker("ChamsFillColorPicker", {
    Default = Color3.fromRGB(255, 60, 60),
    Title = "Fill Color",
}):AddColorPicker("ChamsOutlineColorPicker", {
    Default = Color3.fromRGB(255, 255, 255),
    Title = "Outline Color",
})
ESPGroup:AddSlider("ChamsFillTrans", {
    Text = "Chams Transparency",
    Default = 0.5,
    Min = 0,
    Max = 1,
    Rounding = 2,
})
ESPGroup:AddSlider("ESPRange", {
    Text = "ESP / Chams Range",
    Default = 300,
    Min = 50,
    Max = 1000,
    Rounding = 0,
    Suffix = " studs",
    Tooltip = "Only draw ESP & Chams for players within this distance",
})
local _visDefaults = {
    Ambient        = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness     = Lighting.Brightness,
    FogEnd         = Lighting.FogEnd,
    FogStart       = Lighting.FogStart,
    FogColor       = Lighting.FogColor,
    GlobalShadows  = Lighting.GlobalShadows,
    Technology     = Lighting.Technology,
}
local _skyboxPresets = {
    ["None"] = nil,
    ["Cloudy Blue"] = {
        "rbxassetid://12064107", "rbxassetid://12064152", "rbxassetid://12064121",
        "rbxassetid://12063984", "rbxassetid://12064115", "rbxassetid://12064131",
    },
    ["Nebula"] = {
        "rbxassetid://12635309703", "rbxassetid://12635311686", "rbxassetid://12635312870",
        "rbxassetid://12635313718", "rbxassetid://12635315817", "rbxassetid://12635316856",
    },
    ["Solid Grey"] = {
        "rbxassetid://599982473", "rbxassetid://599982473", "rbxassetid://599982473",
        "rbxassetid://599982473", "rbxassetid://599982473", "rbxassetid://599982473",
    },
    ["Sunset"] = {
        "rbxassetid://116758234", "rbxassetid://116758314", "rbxassetid://116758367",
        "rbxassetid://116758446", "rbxassetid://116758478", "rbxassetid://116758496",
    },
    ["Aurora"] = {
        "rbxassetid://1233158420", "rbxassetid://1233158838", "rbxassetid://1233157105",
        "rbxassetid://1233157640", "rbxassetid://1233157995", "rbxassetid://1233159158",
    },
    ["Cartoon"] = {
        "rbxassetid://1327358", "rbxassetid://1327359", "rbxassetid://1327355",
        "rbxassetid://1327357", "rbxassetid://1327356", "rbxassetid://1327360",
    },
    ["Starfield"] = {
        "rbxassetid://570555736", "rbxassetid://570555964", "rbxassetid://570555800",
        "rbxassetid://570555840", "rbxassetid://570555882", "rbxassetid://570555929",
    },
    ["Vaporwave"] = {
        "rbxassetid://95020137072033", "rbxassetid://92862258103959", "rbxassetid://107665368823185",
        "rbxassetid://126542804346203", "rbxassetid://103716549795832", "rbxassetid://131036626982613",
    },
    ["Overcast"] = {
        "rbxassetid://1013852", "rbxassetid://1013849", "rbxassetid://1013850",
        "rbxassetid://1013851", "rbxassetid://1013847", "rbxassetid://1013848",
    },
}
local _skyboxNames = {}
for k in pairs(_skyboxPresets) do table.insert(_skyboxNames, k) end
table.sort(_skyboxNames)
local function _applySkybox(name)
    local urls = _skyboxPresets[name]
    local existing = Lighting:FindFirstChild("GakuranSky")
    if not urls then
        if existing then existing:Destroy() end
        return
    end
    local sky = existing or Instance.new("Sky")
    sky.Name = "GakuranSky"
    sky.SkyboxBk = urls[1]
    sky.SkyboxDn = urls[2]
    sky.SkyboxFt = urls[3]
    sky.SkyboxLf = urls[4]
    sky.SkyboxRt = urls[5]
    sky.SkyboxUp = urls[6]
    sky.Parent = Lighting
end
local function _getOrCreateEffect(className, name)
    local existing = Lighting:FindFirstChild(name)
    if existing and existing:IsA(className) then
        return existing
    end
    if existing then existing:Destroy() end
    local obj = Instance.new(className)
    obj.Name = name
    obj.Parent = Lighting
    return obj
end
local SkyboxGroup = Tabs.World:AddLeftGroupbox("Skybox")
SkyboxGroup:AddDropdown("SkyboxPreset", {
    Text = "Skybox Preset",
    Values = _skyboxNames,
    Default = "None",
    Tooltip = "Replace the game skybox with a custom preset",
    Callback = function(val)
        _applySkybox(val)
    end,
})
SkyboxGroup:AddToggle("RemoveExistingSky", {
    Text = "Remove Game Sky",
    Default = false,
    Tooltip = "Destroy any Sky instances the game added (except the custom Gakuran one)",
    Callback = function(val)
        if val then
            for _, obj in ipairs(Lighting:GetChildren()) do
                if obj:IsA("Sky") and obj.Name ~= "GakuranSky" then
                    obj:Destroy()
                end
            end
        end
    end,
})
local CameraGroup = Tabs.World:AddLeftGroupbox("Camera")
CameraGroup:AddToggle("InfiniteZoom", {
    Text = "Infinite Zoom Out",
    Default = false,
    Tooltip = "Unlock maximum camera zoom distance so you can zoom out infinitely",
    Callback = function(val)
        if val then _enableInfiniteZoom() else _disableInfiniteZoom() end
    end,
})
local LightLeftGroup = Tabs.World:AddRightGroupbox("Lighting")
local _fullbrightConn = nil
local function _enableFullbright()
    Lighting.Ambient = Color3.fromRGB(255, 255, 255)
    Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    Lighting.Brightness = 2
    Lighting.GlobalShadows = false
    _fullbrightConn = RunService.RenderStepped:Connect(function()
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 2
        Lighting.GlobalShadows = false
    end)
end
local function _disableFullbright()
    if _fullbrightConn then
        _fullbrightConn:Disconnect()
        _fullbrightConn = nil
    end
    Lighting.Ambient = _visDefaults.Ambient
    Lighting.OutdoorAmbient = _visDefaults.OutdoorAmbient
    Lighting.Brightness = _visDefaults.Brightness
    Lighting.GlobalShadows = _visDefaults.GlobalShadows
end
LightLeftGroup:AddToggle("Fullbright", {
    Text = "Fullbright",
    Default = false,
    Tooltip = "Lift Ambient/OutdoorAmbient/Brightness and disable Global Shadows every frame",
    Callback = function(val)
        if val then _enableFullbright() else _disableFullbright() end
    end,
})
LightLeftGroup:AddToggle("NoShadows", {
    Text = "No Shadows",
    Default = false,
    Tooltip = "Disable Lighting.GlobalShadows (only when Fullbright is off)",
    Callback = function(val)
        if not (Toggles.Fullbright and Toggles.Fullbright.Value) then
            Lighting.GlobalShadows = not val
        end
    end,
})
local FogGroup = Tabs.World:AddLeftGroupbox("Fog")
local _fogConn = nil
local _origAtmo = nil
local function _enableNoFog()
    Lighting.FogEnd = 9e9
    Lighting.FogStart = 9e9
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo and not _origAtmo then
        _origAtmo    = {
            Density = atmo.Density,
            Offset  = atmo.Offset,
            Glare   = atmo.Glare,
            Haze    = atmo.Haze,
        }
        atmo.Density = 0
        atmo.Haze    = 0
        atmo.Glare   = 0
    end
    _fogConn = RunService.RenderStepped:Connect(function()
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 9e9
        local a = Lighting:FindFirstChildOfClass("Atmosphere")
        if a then
            a.Density = 0
            a.Haze = 0
            a.Glare = 0
        end
    end)
end
local function _disableNoFog()
    if _fogConn then
        _fogConn:Disconnect()
        _fogConn = nil
    end
    Lighting.FogEnd = _visDefaults.FogEnd
    Lighting.FogStart = _visDefaults.FogStart
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo and _origAtmo then
        atmo.Density = _origAtmo.Density
        atmo.Offset  = _origAtmo.Offset
        atmo.Glare   = _origAtmo.Glare
        atmo.Haze    = _origAtmo.Haze
    end
    _origAtmo = nil
end
FogGroup:AddToggle("NoFog", {
    Text = "No Fog",
    Default = false,
    Tooltip = "Push fog to infinity every frame",
    Callback = function(val)
        if val then _enableNoFog() else _disableNoFog() end
    end,
})
FogGroup:AddToggle("CustomFog", {
    Text = "Custom Fog",
    Default = false,
    Tooltip = "Customize fog color and start/end distance (no-op when No Fog is on)",
}):AddColorPicker("FogColorPicker", {
    Default = Lighting.FogColor,
    Title = "Fog Color",
})
FogGroup:AddSlider("FogStart", {
    Text = "Fog Start",
    Default = 0,
    Min = 0,
    Max = 5000,
    Rounding = 0,
})
FogGroup:AddSlider("FogEnd", {
    Text = "Fog End",
    Default = 1000,
    Min = 0,
    Max = 10000,
    Rounding = 0,
})
local _customFogConn = nil
local function _enableCustomFog()
    if _customFogConn then return end
    _customFogConn = RunService.Heartbeat:Connect(function()
        if Toggles.NoFog and Toggles.NoFog.Value then return end
        Lighting.FogColor = Options.FogColorPicker.Value
        Lighting.FogStart = Options.FogStart.Value
        Lighting.FogEnd   = Options.FogEnd.Value
    end)
end
local function _disableCustomFog()
    if _customFogConn then
        _customFogConn:Disconnect()
        _customFogConn = nil
    end
    Lighting.FogColor = _visDefaults.FogColor
    Lighting.FogStart = _visDefaults.FogStart
    Lighting.FogEnd   = _visDefaults.FogEnd
end
Options.CustomFog:OnChanged(function()
    if Toggles.CustomFog.Value then _enableCustomFog() else _disableCustomFog() end
end)
local BloomGroup = Tabs.World:AddRightGroupbox("Bloom")
BloomGroup:AddToggle("EnableBloom", {
    Text = "Enable Bloom",
    Default = false,
    Callback = function(val)
        local bloom = _getOrCreateEffect("BloomEffect", "GakuranBloom")
        bloom.Enabled = val
        bloom.Intensity = Options.BloomIntensity.Value
        bloom.Size = Options.BloomSize.Value
        bloom.Threshold = Options.BloomThreshold.Value
    end,
})
BloomGroup:AddSlider("BloomIntensity", {
    Text = "Intensity",
    Default = 0.5,
    Min = 0,
    Max = 3,
    Rounding = 2,
})
Options.BloomIntensity:OnChanged(function()
    local bloom = Lighting:FindFirstChild("GakuranBloom")
    if bloom then bloom.Intensity = Options.BloomIntensity.Value end
end)
BloomGroup:AddSlider("BloomSize", {
    Text = "Size",
    Default = 24,
    Min = 0,
    Max = 56,
    Rounding = 0,
})
Options.BloomSize:OnChanged(function()
    local bloom = Lighting:FindFirstChild("GakuranBloom")
    if bloom then bloom.Size = Options.BloomSize.Value end
end)
BloomGroup:AddSlider("BloomThreshold", {
    Text = "Threshold",
    Default = 2,
    Min = 0,
    Max = 4,
    Rounding = 2,
})
Options.BloomThreshold:OnChanged(function()
    local bloom = Lighting:FindFirstChild("GakuranBloom")
    if bloom then bloom.Threshold = Options.BloomThreshold.Value end
end)
local EffectsGroup = Tabs.World:AddRightGroupbox("Blur & Effects")
EffectsGroup:AddToggle("EnableBlur", {
    Text = "Enable Blur",
    Default = false,
    Tooltip = "Apply a stylistic blur effect. NOTE: this conflicts with the No Blur exploit toggle on the Players tab",
    Callback = function(val)
        local blur = _getOrCreateEffect("BlurEffect", "GakuranBlur")
        blur.Enabled = val
        blur.Size = Options.BlurSize.Value
    end,
})
EffectsGroup:AddSlider("BlurSize", {
    Text = "Blur Size",
    Default = 10,
    Min = 0,
    Max = 56,
    Rounding = 0,
})
Options.BlurSize:OnChanged(function()
    local blur = Lighting:FindFirstChild("GakuranBlur")
    if blur then blur.Size = Options.BlurSize.Value end
end)
EffectsGroup:AddToggle("EnableSunRays", {
    Text = "Enable Sun Rays",
    Default = false,
    Callback = function(val)
        local rays = _getOrCreateEffect("SunRaysEffect", "GakuranSunRays")
        rays.Enabled = val
        rays.Intensity = Options.SunRaysIntensity.Value
        rays.Spread = Options.SunRaysSpread.Value
    end,
})
EffectsGroup:AddSlider("SunRaysIntensity", {
    Text = "Ray Intensity",
    Default = 0.25,
    Min = 0,
    Max = 1,
    Rounding = 2,
})
Options.SunRaysIntensity:OnChanged(function()
    local rays = Lighting:FindFirstChild("GakuranSunRays")
    if rays then rays.Intensity = Options.SunRaysIntensity.Value end
end)
EffectsGroup:AddSlider("SunRaysSpread", {
    Text = "Ray Spread",
    Default = 0.25,
    Min = 0,
    Max = 1,
    Rounding = 2,
})
Options.SunRaysSpread:OnChanged(function()
    local rays = Lighting:FindFirstChild("GakuranSunRays")
    if rays then rays.Spread = Options.SunRaysSpread.Value end
end)
EffectsGroup:AddToggle("EnableCC", {
    Text = "Color Correction",
    Default = false,
    Callback = function(val)
        local cc = _getOrCreateEffect("ColorCorrectionEffect", "GakuranCC")
        cc.Enabled = val
        cc.Brightness = Options.CCBrightness.Value
        cc.Contrast = Options.CCContrast.Value
        cc.Saturation = Options.CCSaturation.Value
    end,
})
EffectsGroup:AddSlider("CCBrightness", {
    Text = "CC Brightness",
    Default = 0,
    Min = -1,
    Max = 1,
    Rounding = 2,
})
Options.CCBrightness:OnChanged(function()
    local cc = Lighting:FindFirstChild("GakuranCC")
    if cc then cc.Brightness = Options.CCBrightness.Value end
end)
EffectsGroup:AddSlider("CCContrast", {
    Text = "CC Contrast",
    Default = 0,
    Min = -2,
    Max = 2,
    Rounding = 2,
})
Options.CCContrast:OnChanged(function()
    local cc = Lighting:FindFirstChild("GakuranCC")
    if cc then cc.Contrast = Options.CCContrast.Value end
end)
EffectsGroup:AddSlider("CCSaturation", {
    Text = "CC Saturation",
    Default = 0,
    Min = -1,
    Max = 2,
    Rounding = 2,
})
Options.CCSaturation:OnChanged(function()
    local cc = Lighting:FindFirstChild("GakuranCC")
    if cc then cc.Saturation = Options.CCSaturation.Value end
end)
local _lowGraphicsConn = nil
local _origMaterials = {}
local _origTextures = {}
local function _enableLowGraphics()
    pcall(function()
        local t = Workspace:FindFirstChildOfClass("Terrain")
        if t then
            t.WaterWaveSize = 0
            t.WaterWaveSpeed = 0
            t.WaterReflectance = 0
            t.WaterTransparency = 0
        end
    end)
    Lighting.GlobalShadows = false
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj:IsA("MeshPart") then
            if not _origMaterials[obj] then _origMaterials[obj] = obj.Material end
            obj.Material = Enum.Material.SmoothPlastic
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            if not _origTextures[obj] then _origTextures[obj] = obj.Transparency end
            obj.Transparency = 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            if not _origTextures[obj] then _origTextures[obj] = obj.Enabled end
            obj.Enabled = false
        end
    end
    if not _lowGraphicsConn then
        _lowGraphicsConn = Workspace.DescendantAdded:Connect(function(obj)
            if not (Toggles.LowGraphics and Toggles.LowGraphics.Value) then return end
            if obj:IsA("BasePart") and not obj:IsA("MeshPart") then
                obj.Material = Enum.Material.SmoothPlastic
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                obj.Enabled = false
            end
        end)
    end
end
local function _disableLowGraphics()
    if _lowGraphicsConn then
        _lowGraphicsConn:Disconnect()
        _lowGraphicsConn = nil
    end
    for obj, mat in pairs(_origMaterials) do
        if obj and obj.Parent then pcall(function() obj.Material = mat end) end
    end
    _origMaterials = {}
    for obj, val in pairs(_origTextures) do
        if obj and obj.Parent then
            pcall(function()
                if obj:IsA("Decal") or obj:IsA("Texture") then
                    obj.Transparency = val
                else
                    obj.Enabled = val
                end
            end)
        end
    end
    _origTextures = {}
end
local PerformanceGroup = Tabs.World:AddRightGroupbox("Performance Boost")
PerformanceGroup:AddToggle("LowGraphics", {
    Text = "Low Graphics (Potato Mode)",
    Default = false,
    Tooltip = "Disable textures, shadows, particle effects & simplify materials to maximize FPS",
    Callback = function(val)
        if val then _enableLowGraphics() else _disableLowGraphics() end
    end,
})
local HUDGroup = Tabs.Visuals:AddRightGroupbox("Combat HUD")
local _hudGui = nil
local _hudConn = nil
local function _buildHUD()
    if _hudGui then return _hudGui end
    local gui = Instance.new("ScreenGui")
    gui.Name = "GakuranHUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    pcall(function() gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)
    local function makeThinBar(yOffset, fillColor)
        local container = Instance.new("Frame")
        container.BackgroundTransparency = 1
        container.Position = UDim2.new(1, -150, 1, yOffset)
        container.Size = UDim2.new(0, 130, 0, 14)
        container.Parent = gui
        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        bg.BorderColor3 = Color3.fromRGB(50, 50, 50)
        bg.Parent = container
        Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 3)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(1, 0, 1, 0)
        fill.BackgroundColor3 = fillColor
        fill.BorderSizePixel = 0
        fill.Parent = bg
        Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Code
        label.TextSize = 10
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.5
        label.Parent = bg
        return fill, label, container
    end
    local hpFill, hpLabel, hpContainer = makeThinBar(-40, Color3.fromRGB(255, 60, 60))
    local spFill, spLabel, spContainer = makeThinBar(-22, Color3.fromRGB(60, 180, 255))
    _hudGui = { hpFill = hpFill, hpLabel = hpLabel, hpContainer = hpContainer, spFill = spFill, spLabel = spLabel, spContainer = spContainer, gui = gui }
    return _hudGui
end
local function _updateHUD()
    if not (Toggles.CombatHUD and Toggles.CombatHUD.Value) then
        if _hudGui then _hudGui.gui.Enabled = false end
        return
    end
    local h = _buildHUD()
    h.gui.Enabled = true
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        local hp = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        h.hpFill.Size = UDim2.new(hp, 0, 1, 0)
        h.hpLabel.Text = string.format("HP  %d / %d", math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5))
        local stam = char:GetAttribute("Stamina")
        local maxStam = char:GetAttribute("MaxStamina") or 100
        if typeof(stam) ~= "number" then stam = 100 end
        local sp = math.clamp(stam / maxStam, 0, 1)
        h.spFill.Size = UDim2.new(sp, 0, 1, 0)
        h.spLabel.Text = string.format("SP  %d / %d", math.floor(stam + 0.5), math.floor(maxStam + 0.5))
    else
        h.hpFill.Size = UDim2.new(0, 0, 1, 0)
        h.hpLabel.Text = "HP  0"
        h.spFill.Size = UDim2.new(0, 0, 1, 0)
        h.spLabel.Text = "SP  0"
    end
end
HUDGroup:AddToggle("CombatHUD", {
    Text = "Enable Combat HUD",
    Default = false,
    Tooltip = "Show minimal HP / Stamina bars at the bottom right corner",
    Callback = function(val)
        if val then
            if not _hudConn then
                _hudConn = RunService.Heartbeat:Connect(_updateHUD)
            end
        else
            if _hudConn then _hudConn:Disconnect(); _hudConn = nil end
            if _hudGui then _hudGui.gui.Enabled = false end
        end
    end,
})
local _visUnload = function()
    if _fullbrightConn then _fullbrightConn:Disconnect(); _fullbrightConn = nil end
    if _fogConn then _fogConn:Disconnect(); _fogConn = nil end
    if _customFogConn then _customFogConn:Disconnect(); _customFogConn = nil end
    if _hudConn then _hudConn:Disconnect(); _hudConn = nil end
    if _hudGui then pcall(function() _hudGui.gui:Destroy() end); _hudGui = nil end
    local b = Lighting:FindFirstChild("GakuranBloom")
    if b then b:Destroy() end
    local bl = Lighting:FindFirstChild("GakuranBlur")
    if bl then bl:Destroy() end
    local sr = Lighting:FindFirstChild("GakuranSunRays")
    if sr then sr:Destroy() end
    local cc = Lighting:FindFirstChild("GakuranCC")
    if cc then cc:Destroy() end
    _disableNoFog()
    _disableFullbright()
    _applySkybox("None")
end
local LoggerFrame, LoggerTable, LoggerSearch, LoggerClear, LoggerCopy
local LoggerRows = {}
local LoggerMaxRows = 100
local recentLog = {}
local function makeSelectableText(parent, text, size, pos, width)
    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(width.Scale, width.Offset, 1, 0)
    tb.Position = pos
    tb.BackgroundTransparency = 1
    tb.Font = Enum.Font.Code
    tb.TextSize = 12
    tb.TextColor3 = Color3.fromRGB(220, 220, 220)
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.ClearTextOnFocus = false
    tb.TextEditable = false
    tb.Text = text
    tb.Parent = parent
    return tb
end
Logger = {
    gui = nil,
    addRow = function(self, animId, animName, sourceLabel, sourceType, category)
        if not (self.gui and self.gui.Parent and LoggerTable) then return end
        local rowFrame = Instance.new("Frame")
        rowFrame.Size = UDim2.new(1, 0, 0, 22)
        rowFrame.BackgroundColor3 = (#LoggerRows % 2 == 0) and Color3.fromRGB(22, 22, 22) or Color3.fromRGB(18, 18, 18)
        rowFrame.BorderSizePixel = 0
        rowFrame.Parent = LoggerTable
        local timeStr = os.date("%H:%M:%S")
        makeSelectableText(rowFrame, timeStr, 12, UDim2.new(0, 4, 0, 0), UDim2.new(0.12, 0))
        makeSelectableText(rowFrame, animId, 12, UDim2.new(0.12, 4, 0, 0), UDim2.new(0.26, 0))
        makeSelectableText(rowFrame, animName, 12, UDim2.new(0.38, 4, 0, 0), UDim2.new(0.24, 0))
        makeSelectableText(rowFrame, sourceLabel, 12, UDim2.new(0.62, 4, 0, 0), UDim2.new(0.22, 0))
        makeSelectableText(rowFrame, category, 12, UDim2.new(0.84, 4, 0, 0), UDim2.new(0.16, 0))
        table.insert(LoggerRows, { frame = rowFrame, animId = animId, animName = animName, sourceLabel = sourceLabel, category = category })
        if #LoggerRows > LoggerMaxRows then
            local old = table.remove(LoggerRows, 1)
            if old and old.frame then old.frame:Destroy() end
        end
        LoggerTable.CanvasSize = UDim2.new(0, 0, 0, #LoggerRows * 22)
    end,
    clear = function(self)
        for _, r in ipairs(LoggerRows) do
            if r.frame then r.frame:Destroy() end
        end
        LoggerRows = {}
        if LoggerTable then LoggerTable.CanvasSize = UDim2.new(0, 0, 0, 0) end
    end
}
Preview = {
    gui = nil,
    currentTrack = nil,
    currentAnimObj = nil,
}
createPreviewWindow = function()
    local prevGui = Instance.new("ScreenGui")
    prevGui.Name = "GKPreview"
    prevGui.ResetOnSpawn = false
    prevGui.IgnoreGuiInset = true
    prevGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() prevGui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
    local frame = Instance.new("Frame")
    frame.Name = "PreviewFrame"
    frame.Size = UDim2.new(0, 420, 0, 260)
    frame.Position = UDim2.new(0.5, -210, 0.5, -130)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.Visible = false
    frame.Parent = prevGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    local s1 = Instance.new("UIStroke", frame)
    s1.Color = Color3.new(0, 0, 0); s1.Thickness = 1.5; s1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundTransparency = 1
    titleBar.Parent = frame
    local title = Instance.new("TextLabel")
    title.Text = "Animation Previewer"
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0, 200, 1, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.BackgroundTransparency = 1
    title.Parent = titleBar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.Code
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
    closeBtn.Size = UDim2.new(0, 36, 0, 36)
    closeBtn.Position = UDim2.new(1, -36, 0, 0)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function()
        if Preview.currentTrack then
            pcall(function() Preview.currentTrack:Stop() end)
            Preview.currentTrack = nil
        end
        frame.Visible = false
    end)
    local dragging, dStart, sPos
    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dStart = inp.Position; sPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dStart
            frame.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -24, 1, -48)
    body.Position = UDim2.new(0, 12, 0, 36)
    body.BackgroundTransparency = 1
    body.Parent = frame
    local idLabel = Instance.new("TextLabel")
    idLabel.Name = "IdLabel"
    idLabel.Size = UDim2.new(1, 0, 0, 20)
    idLabel.Font = Enum.Font.Code
    idLabel.TextSize = 12
    idLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    idLabel.TextXAlignment = Enum.TextXAlignment.Left
    idLabel.Text = "Animation ID: -"
    idLabel.BackgroundTransparency = 1
    idLabel.Parent = body
    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(0, 90, 0, 28)
    playBtn.Position = UDim2.new(0, 0, 0, 30)
    playBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    playBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
    playBtn.Font = Enum.Font.Code
    playBtn.TextSize = 12
    playBtn.TextColor3 = Color3.new(1, 1, 1)
    playBtn.Text = "Play"
    playBtn.Parent = body
    Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 3)
    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0, 90, 0, 28)
    stopBtn.Position = UDim2.new(0, 100, 0, 30)
    stopBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    stopBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
    stopBtn.Font = Enum.Font.Code
    stopBtn.TextSize = 12
    stopBtn.TextColor3 = Color3.new(1, 1, 1)
    stopBtn.Text = "Stop"
    stopBtn.Parent = body
    Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 3)
    local addParryBtn = Instance.new("TextButton")
    addParryBtn.Size = UDim2.new(0, 130, 0, 28)
    addParryBtn.Position = UDim2.new(0, 200, 0, 30)
    addParryBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 40)
    addParryBtn.BorderColor3 = Color3.fromRGB(50, 120, 70)
    addParryBtn.Font = Enum.Font.Code
    addParryBtn.TextSize = 11
    addParryBtn.TextColor3 = Color3.new(1, 1, 1)
    addParryBtn.Text = "Send to Builder"
    addParryBtn.Parent = body
    Instance.new("UICorner", addParryBtn).CornerRadius = UDim.new(0, 3)
    local timeLbl = Instance.new("TextLabel")
    timeLbl.Name = "TimeLbl"
    timeLbl.Size = UDim2.new(1, 0, 0, 20)
    timeLbl.Position = UDim2.new(0, 0, 0, 70)
    timeLbl.Font = Enum.Font.Code
    timeLbl.TextSize = 12
    timeLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    timeLbl.TextXAlignment = Enum.TextXAlignment.Left
    timeLbl.Text = "Time: 0.00 / 0.00s"
    timeLbl.BackgroundTransparency = 1
    timeLbl.Parent = body
    local trackId = nil
    playBtn.MouseButton1Click:Connect(function()
        if not trackId then return end
        local myChar = LocalPlayer.Character
        local hum = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        if Preview.currentTrack then pcall(function() Preview.currentTrack:Stop() end) end
        local animObj = Instance.new("Animation")
        animObj.AnimationId = "rbxassetid://" .. trackId
        local track = animator:LoadAnimation(animObj)
        Preview.currentTrack = track
        Preview.currentAnimObj = animObj
        track:Play()
    end)
    stopBtn.MouseButton1Click:Connect(function()
        if Preview.currentTrack then
            pcall(function() Preview.currentTrack:Stop() end)
            Preview.currentTrack = nil
        end
    end)
    addParryBtn.MouseButton1Click:Connect(function()
        if not trackId then return end
        pcall(function()
            Options.BuilderAnimId:SetValue(trackId)
            Options.BuilderName:SetValue("Logged/" .. trackId)
        end)
        Library:Notify({ Title = "Parry Builder", Description = "Loaded ID " .. trackId .. " into Builder", Time = 3 })
    end)
    task.spawn(function()
        while true do
            if frame.Visible and Preview.currentTrack and Preview.currentTrack.IsPlaying then
                pcall(function()
                    timeLbl.Text = string.format("Time: %.2f / %.2fs", Preview.currentTrack.TimePosition, Preview.currentTrack.Length)
                end)
            end
            task.wait(0.05)
        end
    end)
    Preview.gui = prevGui
    Preview.frame = frame
    Preview.idLabel = idLabel
    Preview.setTrackId = function(id) trackId = id; idLabel.Text = "Animation ID: " .. id end
end
openPreview = function(animId)
    if not Preview.gui then createPreviewWindow() end
    Preview.setTrackId(animId)
    Preview.frame.Visible = true
end
createLoggerWindow = function()
    local logGui = Instance.new("ScreenGui")
    logGui.Name = "GKLogger"
    logGui.ResetOnSpawn = false
    logGui.IgnoreGuiInset = true
    logGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() logGui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
    local frame = Instance.new("Frame")
    frame.Name = "LoggerFrame"
    frame.Size = UDim2.new(0, 560, 0, 440)
    frame.Position = UDim2.new(0.5, -280, 0.5, -220)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.Parent = logGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    local s1 = Instance.new("UIStroke", frame)
    s1.Color = Color3.new(0, 0, 0); s1.Thickness = 1.5; s1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    Instance.new("UIStroke", frame).Color = Color3.fromRGB(40, 40, 40); Instance.new("UIStroke", frame).Thickness = 1; Instance.new("UIStroke", frame).ApplyStrokeMode =
        Enum.ApplyStrokeMode.Border
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundTransparency = 1
    titleBar.Parent = frame
    local title = Instance.new("TextLabel")
    title.Text = "Animation Logger"
    title.Font = Enum.Font.Code
    title.TextSize = 15
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0, 200, 1, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.BackgroundTransparency = 1
    title.Parent = titleBar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.Code
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
    closeBtn.Size = UDim2.new(0, 40, 0, 40)
    closeBtn.Position = UDim2.new(1, -40, 0, 0)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function() frame.Visible = false end)
    local dragging, dStart, sPos
    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dStart = inp.Position; sPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dStart
            frame.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    local toolbar = Instance.new("Frame")
    toolbar.Size = UDim2.new(1, -24, 0, 30)
    toolbar.Position = UDim2.new(0, 12, 0, 40)
    toolbar.BackgroundTransparency = 1
    toolbar.Parent = frame
    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0, 80, 1, 0)
    clearBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    clearBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
    clearBtn.Font = Enum.Font.Code
    clearBtn.TextSize = 12
    clearBtn.TextColor3 = Color3.new(1, 1, 1)
    clearBtn.Text = "Clear"
    clearBtn.Parent = toolbar
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 3)
    clearBtn.MouseButton1Click:Connect(function() Logger:clear() end)
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, -24, 0, 24)
    header.Position = UDim2.new(0, 12, 0, 78)
    header.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    header.BorderSizePixel = 0
    header.Parent = frame
    local function makeHeaderLabel(text, pos, width)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(width.Scale, width.Offset, 1, 0)
        l.Position = pos
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Code
        l.TextSize = 11
        l.TextColor3 = Color3.fromRGB(150, 150, 150)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = header
    end
    makeHeaderLabel("Time", UDim2.new(0, 4, 0, 0), UDim2.new(0.12, 0))
    makeHeaderLabel("Anim ID", UDim2.new(0.12, 4, 0, 0), UDim2.new(0.26, 0))
    makeHeaderLabel("Name", UDim2.new(0.38, 4, 0, 0), UDim2.new(0.24, 0))
    makeHeaderLabel("Source", UDim2.new(0.62, 4, 0, 0), UDim2.new(0.22, 0))
    makeHeaderLabel("Category", UDim2.new(0.84, 4, 0, 0), UDim2.new(0.16, 0))
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -24, 1, -114)
    scroll.Position = UDim2.new(0, 12, 0, 102)
    scroll.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    scroll.BorderColor3 = Color3.fromRGB(30, 30, 30)
    scroll.ScrollBarThickness = 6
    scroll.Parent = frame
    LoggerTable = scroll
    Logger.gui = logGui
    Logger.frame = frame
end
local LogGroup = Tabs.Parries:AddRightGroupbox("Animation Logger")
LogGroup:AddToggle("LoggerRangeOn", {
    Text = "Distance Limit",
    Default = true,
    Tooltip = "Only log animations from models within range",
})
LogGroup:AddSlider("LoggerRange", {
    Text = "Max Range",
    Default = 150,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Suffix = " studs",
})
LogGroup:AddButton({
    Text = "Open Logger Window",
    Func = function()
        if not Logger.gui then createLoggerWindow() end
        Logger.frame.Visible = true
    end,
})
LogGroup:AddButton({
    Text = "Open Preview Window",
    Func = function()
        if not Preview.gui then createPreviewWindow() end
        Preview.frame.Visible = true
    end,
})
local watched = {}
local function getSourceInfo(model)
    if not model then return "Unknown", "Unknown" end
    if model == LocalPlayer.Character then return "LocalPlayer", "Self" end
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then
        return plr.DisplayName or plr.Name, "Player"
    end
    return model.Name, "NPC"
end
local function distanceToModel(model)
    if not model then return nil end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local tRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if myRoot and tRoot then
        return (myRoot.Position - tRoot.Position).Magnitude
    end
    return nil
end
local function watchAnimator(animator, model)
    if not animator then return end
    if watched[model] and watched[model].animator == animator then return end
    if watched[model] and watched[model].conns then
        for _, c in ipairs(watched[model].conns) do pcall(function() c:Disconnect() end) end
    end
    local conns = {}
    local function hookTrack(track)
        if not track or not track.Animation then return end
        onAnimationPlayed(model, track)
    end
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            hookTrack(track)
        end
    end)
    local c1 = animator.AnimationPlayed:Connect(hookTrack)
    table.insert(conns, c1)
    watched[model] = { animator = animator, conns = conns }
end
local function watchModel(model)
    if not model or not model:IsA("Model") then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            watchAnimator(animator, model)
        else
            local c = hum.ChildAdded:Connect(function(child)
                if child:IsA("Animator") then watchAnimator(child, model) end
            end)
            watched[model] = watched[model] or { conns = {} }
            table.insert(watched[model].conns, c)
        end
    end
end
local function unwatchModel(model)
    local data = watched[model]
    if data then
        for _, c in ipairs(data.conns or {}) do pcall(function() c:Disconnect() end) end
        watched[model] = nil
    end
end
for _, p in ipairs(Players:GetPlayers()) do
    if p.Character then watchModel(p.Character) end
    p.CharacterAdded:Connect(function(c) watchModel(c) end)
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c) watchModel(c) end)
end)
Players.PlayerRemoving:Connect(function(p)
    if p.Character then unwatchModel(p.Character) end
end)
Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then
        watchModel(d)
    end
end)
local isExcludedAttacker = function(model)
    if not model then return false end
    local plr = Players:GetPlayerFromCharacter(model)
    if not plr then return false end
    if Toggles.ExcludeFriends and Toggles.ExcludeFriends.Value then
        local ok, isFr = pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end)
        if ok and isFr then return true end
    end
    if Toggles.ExcludeContacts and Toggles.ExcludeContacts.Value then
        local ok, isCon = pcall(function()
            local pd = LocalPlayer:FindFirstChild("PlayerData")
            local contacts = pd and pd:FindFirstChild("PhoneContacts")
            if contacts then
                for _, c in ipairs(contacts:GetChildren()) do
                    if c.Value == plr.UserId or c.Name == tostring(plr.UserId) then return true end
                end
            end
            return false
        end)
        if ok and isCon then return true end
    end
    return false
end
local notifyQueue = {}
local notifyLoopAlive = true
local function enqueueNotify(data)
    table.insert(notifyQueue, data)
end
task.spawn(function()
    while notifyLoopAlive do
        if #notifyQueue > 0 then
            local batch = notifyQueue
            notifyQueue = {}
            for _, n in ipairs(batch) do
                pcall(function() Library:Notify(n) end)
            end
        end
        task.wait(0.05)
    end
end)
local function onAnimationPlayed(model, track)
    local anim = track.Animation
    if not anim then return end
    local id = parseAnimId(anim.AnimationId)
    if not id then return end
    local sourceLabel, sourceType = getSourceInfo(model)
    local category, animName = classifyAnim(track, anim)
    local dist = distanceToModel(model)
    local rangeOn = Toggles.LoggerRangeOn
    local captureRange = (Options.LoggerRange and Options.LoggerRange.Value) or 150
    local inCaptureRange = (not rangeOn or not rangeOn.Value) or dist == nil or dist <= captureRange
    if inCaptureRange and not Config.blacklist[id] then
        local key = tostring(model) .. "|" .. id
        local now = os.clock()
        if not recentLog[key] or now - recentLog[key] > 0.5 then
            recentLog[key] = now
            Logger:addRow(id, animName, sourceLabel, sourceType, category)
        end
    end
    local ap = Toggles.AutoParry
    if not ap or not ap.Value then return end
    if track.Looped then return end
    if category == "Movement" then return end
    local myChar = LocalPlayer.Character
    if not (myChar and myChar:GetAttribute("Equip") == true) then return end
    if isExcludedAttacker(model) then return end
    local entry = Config.parries[id]
    local info = AttackDB[id]
    local hitTime, pname
    if info then
        local aspd = attackSpeedFor(model)
        if info.kind == "M1" and info.idx and typeof(CombatConfig.GetScaledStyleM1HitboxDelay) == "function" then
            local ok, v = pcall(CombatConfig.GetScaledStyleM1HitboxDelay, info.style, info.idx, aspd)
            if ok and typeof(v) == "number" and v > 0 then hitTime = v end
        elseif (info.kind == "M2" or info.kind == "M2M") and typeof(CombatConfig.GetStyleM2HitboxDelay) == "function" then
            local isMomentum = (info.kind == "M2M")
            local okRaw, raw = pcall(CombatConfig.GetStyleM2HitboxDelay, info.style, isMomentum)
            if okRaw and typeof(raw) == "number" then
                if typeof(CombatConfig.GetScaledHitboxDelay) == "function" then
                    local ok, v = pcall(CombatConfig.GetScaledHitboxDelay, raw, aspd)
                    if ok and typeof(v) == "number" and v > 0 then hitTime = v end
                else
                    hitTime = raw
                end
            end
        end
        if not hitTime then hitTime = info.delay end
        pname = (entry and entry.name) or info.name
    elseif entry then
        hitTime = entry.delay
        pname = entry.name
    else
        local aa = Toggles.AutoAll
        if not (aa and aa.Value) then return end
    end
    if not hitTime then return end
    local now = os.clock()
    if State.lastTrigger[id] and now - State.lastTrigger[id] < 0.25 then return end
    local hold = (entry and entry.hold) or ((Options.BlockHold and Options.BlockHold.Value or 350) / 1000)
    local remaining = hitTime - track.TimePosition
    local ping = getPing()
    local timingOffset = Options.TimingOffset and Options.TimingOffset.Value or -40
    local delay = math.max(remaining - ping * 0.5 + (timingOffset / 1000), 0)
    local m2d = Toggles.M2DodgeBack
    if m2d and m2d.Value then
        local isM2 = (info and (info.kind == "M2" or info.kind == "M2M"))
            or (entry and (entry.kind == "M2" or entry.kind == "M2M"))
            or (pname and (pname:find("/M2") or pname:find("M2")))
        if isM2 then
            local dodgeRange = Options.MaxRangeDodge and Options.MaxRangeDodge.Value or 20
            if dist ~= nil and dist <= dodgeRange then
                State.lastTrigger[id] = now
                task.delay(delay, function() doDodge(model, "back") end)
                local nt = Toggles.Notifications
                if nt and nt.Value then
                    enqueueNotify({
                        Title = "M2 Dodge",
                        Description = string.format("%s  ->  %s (M2), back-dash in %dms",
                            sourceLabel, pname, math.floor(delay * 1000 + 0.5)),
                        Time = 2
                    })
                end
                return
            end
        end
    end
    local dodgeToggle = Toggles.AutoDodge
    if dodgeToggle and dodgeToggle.Value then
        local dodgeRange = Options.MaxRangeDodge and Options.MaxRangeDodge.Value or 20
        local myRootLocal = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local threatCount = myRootLocal and threatField(myRootLocal, dodgeRange) or 0
        local angle = Options.DodgeAngle and Options.DodgeAngle.Value or 60
        if threatCount >= 2 then
            angle = math.max(40, angle - 20)
        end
        local dodgeDot = math.cos(math.rad(angle))
        if dist ~= nil and dist <= dodgeRange and isBehind(model, dodgeDot) then
            State.lastTrigger[id] = now
            task.delay(delay, function()
                if isBehind(model, dodgeDot) then
                    doDodge(model, "side")
                else
                    doParry(hold)
                end
            end)
            local nt = Toggles.Notifications
            if nt and nt.Value then
                enqueueNotify({
                    Title = "Auto Dodge",
                    Description = string.format("%s  ->  %s (rear), dash in %dms",
                        sourceLabel, pname, math.floor(delay * 1000 + 0.5)),
                    Time = 2
                })
            end
            return
        end
    end
    local maxRange = Options.MaxRange and Options.MaxRange.Value or 60
    if dist == nil or dist > maxRange then return end
    State.lastTrigger[id] = now
    task.delay(delay, function() doParry(hold) end)
    local nt = Toggles.Notifications
    if nt and nt.Value then
        enqueueNotify({
            Title = "Auto Parry",
            Description = string.format("%s  ->  %s, block in %dms", sourceLabel, pname,
                math.floor(delay * 1000 + 0.5)),
            Time = 2
        })
    end
end
local rhythmEngineRunning = false
local function startRhythmEngine()
    if rhythmEngineRunning then return end
    rhythmEngineRunning = true
    local function _collectGC()
        if typeof(getgc) == "function" then
            local ok, res = pcall(getgc, true)
            if ok and type(res) == "table" then return res end
        end
        return nil
    end
    local svc = nil
    local grm = getrawmetatable or (debug and debug.getmetatable)
    local function findService()
        if svc and typeof(rawget(svc, "_onPressLane")) == "function" then return svc end
        svc = nil
        local all = _collectGC()
        if not all then return nil end
        for _, o in ipairs(all) do
            if type(o) == "table" and rawget(o, "_laneCount") ~= nil
                and typeof(rawget(o, "_onPressLane")) == "function"
                and typeof(rawget(o, "_onReleaseLane")) == "function" then
                if typeof(grm) == "function" then
                    local ok, mt = pcall(grm, o)
                    if ok and type(mt) == "table" and typeof(rawget(mt, "_onPressLane")) == "function" then
                        svc = o; break
                    end
                else
                    svc = o; break
                end
            end
        end
        return svc
    end
    local function pickJudgment()
        local mode = Options.RhythmJudgment and Options.RhythmJudgment.Value or "Legit (mix)"
        if mode == "Rage (100% Perfect)" then return "PERFECT" end
        if mode == "Good Only" then return "GOOD" end
        if mode == "Okay Only" then return "OKAY" end
        local pct = Options.RhythmLegitPercent and Options.RhythmLegitPercent.Value or 85
        local roll = math.random(1, 100)
        if roll <= pct then return "PERFECT" end
        if roll <= pct + 12 then return "GOOD" end
        return "OKAY"
    end
    local function earlyOffsetFor(judg, W)
        local perfMS = W.PERFECT or 43
        local goodMS = W.GOOD or 76
        local okayMS = W.OKAY or 106
        if judg == "PERFECT" then
            return math.random(5, math.max(6, perfMS - 5)) / 1000
        elseif judg == "GOOD" then
            return math.random(perfMS + 3, math.max(perfMS + 5, goodMS - 5)) / 1000
        elseif judg == "OKAY" then
            return math.random(goodMS + 3, math.max(goodMS + 5, okayMS - 5)) / 1000
        end
        return 0.02
    end
    task.spawn(function()
        while rhythmEngineRunning do
            local rt = Toggles.AutoRhythm
            if not rt or not rt.Value then
                local status = Options.RhythmStatus
                if status then pcall(status.SetText, status, "idle (toggle Auto Rhythm on)") end
                task.wait(0.4)
                continue
            end
            local s = findService()
            if not s then
                local status = Options.RhythmStatus
                if status then pcall(status.SetText, status, "RhythmService not found -- equip an instrument on a stage") end
                task.wait(3)
                continue
            end
            local session = rawget(s, "_session")
            if not session or rawget(session, "_destroyed") or type(rawget(session, "_liveNotes")) ~= "table" then
                local status = Options.RhythmStatus
                if status then pcall(status.SetText, status, "waiting for a song to start...") end
                if session and rawget(session, "_destroyed") then
                    svc = nil
                    task.wait(2)
                else
                    task.wait(0.25)
                end
                continue
            end
            if rawget(session, "_autoplayEnabled") == true then
                session._autoplayEnabled = false
            end
            local okNow, now = pcall(session._now, session)
            if not okNow or type(now) ~= "number" then
                RunService.Heartbeat:Wait()
                continue
            end
            local W = rawget(session, "_windows") or { PERFECT = 43, GOOD = 76, OKAY = 106, BAD = 140 }
            local badSec = (W.BAD or 140) / 1000
            local active = rawget(session, "_active")
            if type(active) ~= "table" then
                RunService.Heartbeat:Wait()
                continue
            end
            local view = rawget(session, "_view")
            local callbacks = rawget(session, "_onLanePressedCallbacks")
            local activeCount = 0
            for _, note in pairs(active) do
                if type(note) == "table" and note.t then
                    activeCount += 1
                    if not (note.hit or note.attempted or note._ap) then
                        local dt = note.t - now
                        if dt <= -badSec then
                            note._ap = true
                        elseif dt < 1.0 then
                            if note._apJudg == nil then
                                note._apJudg = pickJudgment()
                                note._apOff = earlyOffsetFor(note._apJudg, W)
                            end
                            if note._apJudg == "MISS" then
                            elseif note._apOff and now >= (note.t - note._apOff) then
                                local lane = note.lane
                                pcall(session._onPressLane, session, lane, note.t - note._apOff)
                                if view then pcall(view.PressReceptor, view, lane) end
                                if callbacks then
                                    for _, cb in pairs(callbacks) do
                                        if cb then pcall(cb, lane) end
                                    end
                                end
                                note._ap = true
                                if (note.len or 0) > 0 then
                                    local releaseAt = note.t + note.len
                                    task.delay(math.max(releaseAt - now, 0.05) + 0.03, function()
                                        pcall(session._onReleaseLane, session, lane, releaseAt)
                                        if view then pcall(view.ReleaseReceptor, view, lane) end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
            local combo = rawget(session, "_combo") or 0
            local jc = rawget(session, "_judgeCounts") or {}
            local status = Options.RhythmStatus
            if status then
                pcall(status.SetText, status, string.format("playing -- combo %d | active %d\nP%d G%d O%d B%d M%d",
                    combo, activeCount,
                    jc.PERFECT or 0, jc.GOOD or 0, jc.OKAY or 0, jc.BAD or 0, jc.MISS or 0))
            end
            RunService.Heartbeat:Wait()
        end
    end)
    local status = Options.RhythmStatus
    if status then pcall(status.SetText, status, "toggle Auto Rhythm, then play a song") end
end
startRhythmEngine()
local bballEngineRunning = false
local function startBasketballEngine()
    if bballEngineRunning then return end
    bballEngineRunning = true
    local DEFAULT_CENTER = 0.76
    local ZERO_CONTEST = function() return 0 end
    local grm = getrawmetatable or (debug and debug.getmetatable)
    local moduleCache, instCache, classCache = nil, nil, nil
    local function gcScan()
        if typeof(getgc) == "function" then
            local ok, res = pcall(getgc, true)
            if ok and type(res) == "table" then return res end
        end
        return {}
    end
    local function findModule()
        if moduleCache and rawget(moduleCache, "ZONES") then return moduleCache end
        moduleCache = nil
        for _, o in ipairs(gcScan()) do
            if type(o) == "table" and rawget(o, "ZONES")
                and typeof(rawget(o, "applyContestToZones")) == "function"
                and typeof(rawget(o, "getZonesForDistance")) == "function" then
                moduleCache = o; break
            end
        end
        return moduleCache
    end
    local function findClassRelease()
        if classCache then return rawget(classCache, "_releaseShot") end
        for _, o in ipairs(gcScan()) do
            if type(o) == "table"
                and typeof(rawget(o, "_releaseShot")) == "function"
                and typeof(rawget(o, "_beginShotCharge")) == "function"
                and rawget(o, "_shootRemote") == nil then
                classCache = o
                return rawget(o, "_releaseShot")
            end
        end
        return nil
    end
    local function findActiveInstance()
        if instCache and not rawget(instCache, "_destroyed") and rawget(instCache, "_charging") then
            return instCache
        end
        instCache = nil
        for _, o in ipairs(gcScan()) do
            if type(o) == "table" and rawget(o, "_charging") == true
                and rawget(o, "_shotDistance") ~= nil
                and typeof(rawget(o, "_releaseShot")) == "function" then
                instCache = o; break
            end
        end
        return instCache
    end
    local function targetTFor(inst)
        local mode = Options.BballJudgment and Options.BballJudgment.Value or "Perfect (Green)"
        local greenCenter = DEFAULT_CENTER
        local mod = findModule()
        if mod then
            local dist = rawget(inst, "_shotDistance") or 15
            local okZ, zones = pcall(mod.getZonesForDistance, dist)
            if okZ and type(zones) == "table" then
                local okC, zC = pcall(mod.applyContestToZones, zones, ZERO_CONTEST)
                local targetZones = okC and type(zC) == "table" and zC or zones
                local green = targetZones.GREEN or targetZones.PERFECT or targetZones[1]
                if type(green) == "table" and type(green.s) == "number" and type(green.e) == "number" then
                    greenCenter = (green.s + green.e) / 2
                end
            end
        end
        if mode == "Good" then
            return greenCenter + 0.05
        end
        if mode == "Legit Mix" then
            local pct = Options.BballLegitPercent and Options.BballLegitPercent.Value or 90
            if math.random(1, 100) <= pct then
                return greenCenter
            else
                return greenCenter + (math.random() < 0.5 and 0.04 or -0.04)
            end
        end
        return greenCenter
    end
    local origRelease = nil
    local function realReleaseOf(h)
        if typeof(grm) == "function" then
            local ok, mt = pcall(grm, h)
            if ok and type(mt) == "table" and typeof(rawget(mt, "_releaseShot")) == "function" then
                return rawget(mt, "_releaseShot")
            end
        end
        return findClassRelease()
    end
    local function tryHook()
        local inst = findActiveInstance()
        if not inst then return false end
        local fn = realReleaseOf(inst)
        if not fn or fn == origRelease then return false end
        origRelease = fn
        return true
    end
    task.spawn(function()
        while bballEngineRunning do
            local toggle = Toggles.AutoBasketball
            if toggle and toggle.Value then
                tryHook()
                local inst = findActiveInstance()
                if inst and not rawget(inst, "_botHandled") then
                    inst._botHandled = true
                    local chargeStart = rawget(inst, "_chargeStartTime") or os.clock()
                    local tTarget = targetTFor(inst)
                    local releaseTime = chargeStart + tTarget
                    task.spawn(function()
                        local delaySec = releaseTime - os.clock()
                        if delaySec > 0 then task.wait(delaySec) end
                        if not rawget(inst, "_destroyed") and rawget(inst, "_charging") then
                            pcall(inst._releaseShot, inst)
                        end
                    end)
                end
            end
            task.wait(0.02)
        end
    end)
end
startBasketballEngine()
local espAlive = true
local espObjects = {}
local chamsObjects = {}
local espParent = (typeof(gethui) == "function" and gethui())
    or (typeof(get_hidden_gui) == "function" and get_hidden_gui())
    or game:GetService("CoreGui")
local function makeESP(player, head)
    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_" .. player.Name
    bb.Size = UDim2.new(0, 200, 0, 54)
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.AlwaysOnTop = true
    bb.ClipsDescendants = false
    bb.Adornee = head
    bb.Parent = espParent
    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.new(1, 0, 0, 36)
    text.Font = Enum.Font.Gotham
    text.TextSize = 12
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextStrokeTransparency = 0.5
    text.TextYAlignment = Enum.TextYAlignment.Bottom
    text.RichText = true
    text.Text = player.DisplayName or player.Name
    text.Parent = bb
    local stunFrame = Instance.new("Frame")
    stunFrame.Name = "StunFrame"
    stunFrame.Size = UDim2.new(0, 100, 0, 12)
    stunFrame.Position = UDim2.new(0.5, -50, 0, 38)
    stunFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    stunFrame.BorderColor3 = Color3.fromRGB(60, 60, 60)
    stunFrame.Visible = false
    stunFrame.Parent = bb
    Instance.new("UICorner", stunFrame).CornerRadius = UDim.new(0, 3)
    local stunBar = Instance.new("Frame")
    stunBar.Name = "StunBar"
    stunBar.Size = UDim2.new(1, 0, 1, 0)
    stunBar.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
    stunBar.BorderSizePixel = 0
    stunBar.Parent = stunFrame
    Instance.new("UICorner", stunBar).CornerRadius = UDim.new(0, 3)
    local stunLbl = Instance.new("TextLabel")
    stunLbl.Name = "StunLabel"
    stunLbl.Size = UDim2.new(1, 0, 1, 0)
    stunLbl.BackgroundTransparency = 1
    stunLbl.Font = Enum.Font.Code
    stunLbl.TextSize = 10
    stunLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    stunLbl.TextStrokeTransparency = 0.5
    stunLbl.Text = "STUNNED"
    stunLbl.Parent = stunFrame
    espObjects[player] = { gui = bb, text = text, stunFrame = stunFrame, stunBar = stunBar, stunLbl = stunLbl }
end
local function removeESP(player)
    local o = espObjects[player]
    if o then
        pcall(function() o.gui:Destroy() end)
        espObjects[player] = nil
    end
end
local function makeChams(player, char)
    local hl = Instance.new("Highlight")
    hl.Name = "GKChams_" .. player.Name
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = (Options.ChamsFillColorPicker and Options.ChamsFillColorPicker.Value) or Color3.fromRGB(255, 60, 60)
    hl.OutlineColor = (Options.ChamsOutlineColorPicker and Options.ChamsOutlineColorPicker.Value) or
        Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = (Options.ChamsFillTrans and Options.ChamsFillTrans.Value) or 0.5
    hl.OutlineTransparency = 0
    hl.Adornee = char
    pcall(function() hl.Parent = espParent end)
    chamsObjects[player] = hl
end
local function removeChams(player)
    local hl = chamsObjects[player]
    if hl then
        pcall(function() hl:Destroy() end)
        chamsObjects[player] = nil
    end
end
task.spawn(function()
    while espAlive do
        local tg = Toggles.EnemyESP
        local on = tg and tg.Value
        local chamsToggle = Toggles.Chams
        local chamsOn = chamsToggle and chamsToggle.Value
        local showStam = Toggles.ESPShowStamina and Toggles.ESPShowStamina.Value
        local range = (Options.ESPRange and Options.ESPRange.Value) or 300
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
                local alive = hum and hum.Health > 0
                local inRange = true
                if myRoot and head then
                    inRange = (myRoot.Position - head.Position).Magnitude <= range
                end
                if on and char and hum and head and alive and inRange then
                    local o = espObjects[player]
                    if not o or o.gui.Adornee ~= head then
                        if o then removeESP(player) end
                        makeESP(player, head)
                        o = espObjects[player]
                    end
                    local name = player.DisplayName or player.Name
                    local hp = string.format("HP %d", math.floor(hum.Health + 0.5))
                    if showStam then
                        local stam = char:GetAttribute("Stamina")
                        if typeof(stam) ~= "number" then stam = 100 end
                        o.text.Text = string.format("%s\n%s  SP %d", name, hp, math.floor(stam + 0.5))
                    else
                        o.text.Text = string.format("%s\n%s", name, hp)
                    end
                    local isStunned = char:GetAttribute("Stunned") == true or char:GetAttribute("Stun") == true or char:GetAttribute("CantAnything") == true
                    local isRagdoll = char:GetAttribute("Ragdoll") == true or char:GetAttribute("Knocked") == true or char:GetAttribute("Down") == true
                    if isStunned or isRagdoll then
                        if o.stunFrame then
                            o.stunFrame.Visible = true
                            if isRagdoll then
                                o.stunBar.BackgroundColor3 = Color3.fromRGB(235, 60, 60)
                                o.stunLbl.Text = "DOWN / RAGDOLL"
                            else
                                o.stunBar.BackgroundColor3 = Color3.fromRGB(255, 150, 30)
                                o.stunLbl.Text = "STUNNED"
                            end
                        end
                    else
                        if o and o.stunFrame then o.stunFrame.Visible = false end
                    end
                else
                    if espObjects[player] then removeESP(player) end
                end
                if chamsOn and char and hum and alive and inRange then
                    local hl = chamsObjects[player]
                    if not hl or hl.Adornee ~= char then
                        if hl then removeChams(player) end
                        makeChams(player, char)
                        hl = chamsObjects[player]
                    end
                    if hl then
                        hl.FillColor = (Options.ChamsFillColorPicker and Options.ChamsFillColorPicker.Value) or
                            Color3.fromRGB(255, 60, 60)
                        hl.OutlineColor = (Options.ChamsOutlineColorPicker and Options.ChamsOutlineColorPicker.Value) or
                            Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency = (Options.ChamsFillTrans and Options.ChamsFillTrans.Value) or 0.5
                        hl.Enabled = true
                    end
                else
                    if chamsObjects[player] then removeChams(player) end
                end
            end
        end
        for player in pairs(espObjects) do
            if not player.Parent then removeESP(player) end
        end
        for player in pairs(chamsObjects) do
            if not player.Parent then removeChams(player) end
        end
        task.wait(0.08)
    end
end)
local function removePlayerVisuals(player)
    removeESP(player)
    removeChams(player)
end
Players.PlayerRemoving:Connect(removePlayerVisuals)
local m2HudAlive = true
local m2HudGui
do
    local gui = Instance.new("ScreenGui")
    m2HudGui = gui
    gui.Name = "OweHubM2Hud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9998
    pcall(function() gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)
    local frame = Instance.new("TextLabel")
    frame.Size = UDim2.new(0, 120, 0, 30)
    frame.Position = UDim2.new(0.5, -60, 0.78, 0)
    frame.BackgroundTransparency = 1
    frame.Font = Enum.Font.GothamBold
    frame.TextSize = 15
    frame.TextColor3 = Color3.fromRGB(255, 255, 255)
    frame.TextStrokeTransparency = 0.4
    frame.Text = "M2 READY"
    frame.Visible = false
    frame.Parent = gui
    local label = frame
    local dragging, dStart, sPos
    frame.Active = true
    frame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dStart = inp.Position; sPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dStart
            frame.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    local cdStart, cdDur = 0, 0
    local function styleCooldown()
        local ch = LocalPlayer.Character
        local pd = ch and ch:FindFirstChild("PlayerData")
        local style = pd and pd:GetAttribute("CombatStyle")
        if typeof(style) == "string" and style ~= "" then
            local key = string.lower(style)
            if typeof(CombatConfig.GetStyleM2Cooldown) == "function" then
                local ok, cd = pcall(CombatConfig.GetStyleM2Cooldown, key)
                if ok and typeof(cd) == "number" and cd > 0 then return cd end
            end
        end
        return 4
    end
    local heavyLabel = nil
    local heavyOrig = nil
    local function findHeavyAttackLabel()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return nil end
        for _, desc in ipairs(pg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Text:find("Heavy Attack") then
                return desc
            end
        end
        return nil
    end
    local function restoreHeavyLabel()
        if heavyLabel and heavyOrig then
            pcall(function() heavyLabel.Text = heavyOrig end)
        end
    end
    task.spawn(function()
        while m2HudAlive do
            local ch = LocalPlayer.Character
            if not ch then
                frame.Visible = false
                restoreHeavyLabel()
                heavyLabel = nil
                task.wait(0.3)
                continue
            end
            local wasOn = (cdStart > 0 and os.clock() - cdStart < cdDur)
            local isNowOn = ch:GetAttribute("M2Cooldown") == true
            if isNowOn and not wasOn then
                cdStart = os.clock()
                cdDur = styleCooldown()
            end
            local onCd = isNowOn or (cdStart > 0 and os.clock() - cdStart < cdDur)
            local remaining = onCd and math.max(cdDur - (os.clock() - cdStart), 0) or 0
            local usedLabel = false
            if not isMobile then
                if not (heavyLabel and heavyLabel.Parent) then
                    heavyLabel = findHeavyAttackLabel()
                    heavyOrig = heavyLabel and heavyLabel.Text or nil
                end
                if heavyLabel and heavyOrig then
                    local suffix = onCd and string.format("  (%.1fs)", remaining) or "  (Ready)"
                    pcall(function() heavyLabel.Text = heavyOrig .. suffix end)
                    usedLabel = true
                end
            end
            frame.Visible = not usedLabel
            if not usedLabel then
                if onCd then
                    label.Text = string.format("M2  %.1fs", remaining)
                    label.TextColor3 = Color3.fromRGB(255, 120, 90)
                else
                    label.Text = "M2 READY"
                    label.TextColor3 = Color3.fromRGB(90, 235, 120)
                end
            end
            task.wait(0.1)
        end
        restoreHeavyLabel()
    end)
end
local autoRespawnConn = nil
local _spawnSvcCache = nil
local function findSpawnService()
    if _spawnSvcCache and rawget(_spawnSvcCache, "_spawnRemote") ~= nil then
        return _spawnSvcCache
    end
    _spawnSvcCache = nil
    if typeof(getgc) ~= "function" then return nil end
    local grm = getrawmetatable or (debug and debug.getmetatable)
    pcall(function()
        local class
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table"
                and typeof(rawget(o, "_doRespawn")) == "function"
                and typeof(rawget(o, "_completeRespawnTransition")) == "function"
                and typeof(rawget(o, "_clearEffects")) == "function"
                and rawget(o, "_spawnRemote") == nil then
                class = o; break
            end
        end
        if not class then return end
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" and rawget(o, "_spawnRemote") ~= nil then
                if typeof(grm) == "function" then
                    local ok, mt = pcall(grm, o)
                    if ok and mt == class then
                        _spawnSvcCache = o; break
                    end
                elseif rawget(o, "_player") ~= nil and rawget(o, "_heartBtn") ~= nil then
                    _spawnSvcCache = o; break
                end
            end
        end
    end)
    return _spawnSvcCache
end
local _spawnCFrames = {
    ["Courtyard"] = CFrame.new(12, 10, -85),
    ["Roof"]      = CFrame.new(0, 75, -20),
    ["Gym"]       = CFrame.new(140, 15, -120),
    ["Gate"]      = CFrame.new(-100, 10, 50),
}
startAutoRespawn = function()
    if autoRespawnConn then return end
    autoRespawnConn = RunService.Heartbeat:Connect(function()
        local dead = LocalPlayer:GetAttribute("Dead") == true
        local char = LocalPlayer.Character
        if not dead and char and char:GetAttribute("Dead") == true then dead = true end
        if not dead and char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then dead = true end
        end
        if not dead then return end
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local dui = pg and pg:FindFirstChild("DeathUI")
        if dui then dui.Enabled = false end
        local svc = findSpawnService()
        if svc then
            pcall(function() svc:_doRespawn() end)
        else
            local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local sr = Remotes and Remotes:FindFirstChild("SpawnRequest")
            if sr then pcall(function() sr:FireServer() end) end
        end
        local spot = Options.SpawnSpot and Options.SpawnSpot.Value
        if spot and spot ~= "Default" and _spawnCFrames[spot] then
            task.delay(0.2, function()
                local nChar = LocalPlayer.Character
                local nRoot = nChar and nChar:FindFirstChild("HumanoidRootPart")
                if nRoot then
                    nRoot.CFrame = _spawnCFrames[spot]
                end
            end)
        end
    end)
end
stopAutoRespawn = function()
    if autoRespawnConn then
        autoRespawnConn:Disconnect()
        autoRespawnConn = nil
    end
end
local function removeBlurs()
    local hasBlur = false
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") then
            if obj.Enabled then
                obj.Enabled = false; hasBlur = true
            end
        end
    end
    local cam = Workspace.CurrentCamera
    if cam then
        for _, obj in ipairs(cam:GetChildren()) do
            if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") then
                if obj.Enabled then
                    obj.Enabled = false; hasBlur = true
                end
            end
        end
    end
    return hasBlur
end
local noBlurConn = nil
startNoBlur = function()
    if noBlurConn then return end
    noBlurConn = RunService.Heartbeat:Connect(function()
        removeBlurs()
    end)
end
stopNoBlur = function()
    if noBlurConn then
        noBlurConn:Disconnect()
        noBlurConn = nil
    end
end
local _attrStripActive = {
    noStun = false,
    noDodgeCD = false,
    noRagdoll = false,
    noBlur = false,
}
local _attrStripConn = nil
local function _updateAttrStripConn()
    local anyActive = false
    for _, active in pairs(_attrStripActive) do
        if active then anyActive = true; break end
    end
    if anyActive and not _attrStripConn then
        _attrStripConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            if _attrStripActive.noStun then
                if char:GetAttribute("Stunned") == true then char:SetAttribute("Stunned", nil) end
                if char:GetAttribute("CantAnything") == true then char:SetAttribute("CantAnything", nil) end
            end
            if _attrStripActive.noDodgeCD then
                if char:GetAttribute("DodgeCooldown") == true then char:SetAttribute("DodgeCooldown", nil) end
                if char:GetAttribute("IFRAMECD") == true then char:SetAttribute("IFRAMECD", nil) end
            end
            if _attrStripActive.noRagdoll then
                if char:GetAttribute("Ragdoll") == true then char:SetAttribute("Ragdoll", nil) end
                if char:GetAttribute("Downed") == true then char:SetAttribute("Downed", nil) end
            end
        end)
    elseif not anyActive and _attrStripConn then
        _attrStripConn:Disconnect()
        _attrStripConn = nil
    end
end
startNoStun = function()
    _attrStripActive.noStun = true
    _updateAttrStripConn()
end
stopNoStun = function()
    _attrStripActive.noStun = false
    _updateAttrStripConn()
end
startNoDodgeCD = function()
    _attrStripActive.noDodgeCD = true
    _updateAttrStripConn()
end
stopNoDodgeCD = function()
    _attrStripActive.noDodgeCD = false
    _updateAttrStripConn()
end
startNoRagdoll = function()
    _attrStripActive.noRagdoll = true
    _updateAttrStripConn()
end
stopNoRagdoll = function()
    _attrStripActive.noRagdoll = false
    _updateAttrStripConn()
end
startNoBlur = function()
    _attrStripActive.noBlur = true
    _updateAttrStripConn()
end
stopNoBlur = function()
    _attrStripActive.noBlur = false
    _updateAttrStripConn()
end
local followConn = nil
startFollow = function()
    if followConn then return end
    followConn = RunService.Heartbeat:Connect(function()
        local sel = Options.TeleportTarget and Options.TeleportTarget.Value
        if not sel or sel == "(no players)" then return end
        local target = Players:FindFirstChild(sel)
        if not target or not target.Character then return end
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (tRoot and myRoot) then return end
        local offset = (Options.TeleportOffset and Options.TeleportOffset.Value) or 3
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 0, offset)
    end)
end
stopFollow = function()
    if followConn then
        followConn:Disconnect()
        followConn = nil
    end
end
local noParryCDConn = nil
local _parryCDAttrs = { "BlockCooldown", "Stunned", "CantAnything" }
startNoParryCD = function()
    if noParryCDConn then return end
    noParryCDConn = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, attr in ipairs(_parryCDAttrs) do
            if char:GetAttribute(attr) == true then
                char:SetAttribute(attr, nil)
            end
        end
    end)
end
stopNoParryCD = function()
    if noParryCDConn then
        noParryCDConn:Disconnect()
        noParryCDConn = nil
    end
end
local autoSprintConn = nil
local _isSprintingActive = false
local function triggerMobileSprintBtn(state)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg or typeof(getconnections) ~= "function" then return end
    for _, gui in ipairs(pg:GetDescendants()) do
        if (gui:IsA("ImageButton") or gui:IsA("TextButton")) and (gui.Name == "Sprint" or gui.Name == "Run") then
            if state then
                for _, conn in ipairs(getconnections(gui.InputBegan)) do
                    pcall(conn.Function,
                        { UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin })
                end
                for _, conn in ipairs(getconnections(gui.MouseButton1Down)) do
                    pcall(conn.Function)
                end
            else
                for _, conn in ipairs(getconnections(gui.InputEnded)) do
                    pcall(conn.Function,
                        { UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.End })
                end
                for _, conn in ipairs(getconnections(gui.MouseButton1Up)) do
                    pcall(conn.Function)
                end
            end
        end
    end
end
startAutoSprint = function()
    if autoSprintConn then return end
    _isSprintingActive = true
    autoSprintConn = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if hum.MoveDirection.Magnitude > 0.1 then
            if char:GetAttribute("Sprinting") ~= true then
                char:SetAttribute("Sprinting", true)
            end
            if isMobile then
                triggerMobileSprintBtn(true)
            end
        else
            if char:GetAttribute("Sprinting") == true then
                char:SetAttribute("Sprinting", nil)
            end
            if isMobile then
                triggerMobileSprintBtn(false)
            end
        end
    end)
end
stopAutoSprint = function()
    if autoSprintConn then
        autoSprintConn:Disconnect()
        autoSprintConn = nil
    end
    _isSprintingActive = false
    local char = LocalPlayer.Character
    if char then char:SetAttribute("Sprinting", nil) end
    if isMobile then triggerMobileSprintBtn(false) end
end
startInfStamina = function()
    local char = LocalPlayer.Character
    if char then
        local maxStam = char:GetAttribute("MaxStamina") or 100
        char:SetAttribute("Stamina", maxStam)
    end
end
stopInfStamina = function()
end
local noclipConn = nil
startNoclip = function()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
end
stopNoclip = function()
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" or part.Name == "Torso" or part.Name == "UpperTorso" or part.Name == "LowerTorso" then
                    part.CanCollide = true
                end
            end
        end
    end
end
local mobileToggleGui = nil
local function _fullUnload()
    rhythmEngineRunning = false
    bballEngineRunning = false
    notifyLoopAlive = false
    espAlive = false
    m2HudAlive = false
    if m2HudGui then pcall(function() m2HudGui:Destroy() end) end
    stopNoclip()
    stopAutoSprint()
    stopInfStamina()
    stopNoStun()
    stopNoDodgeCD()
    stopAutoRespawn()
    stopNoRagdoll()
    stopNoBlur()
    stopNoParryCD()
    stopFollow()
    if _attrStripConn then
        _attrStripConn:Disconnect(); _attrStripConn = nil
    end
    if _visUnload then _visUnload() end
    if _disableLowGraphics then _disableLowGraphics() end
    for p in pairs(espObjects) do removeESP(p) end
    for p in pairs(chamsObjects) do removeChams(p) end
    for model, data in pairs(watched) do
        for _, c in ipairs(data.conns or {}) do
            pcall(function() c:Disconnect() end)
        end
    end
    if Logger and Logger.gui then pcall(function() Logger.gui:Destroy() end) end
    if Preview and Preview.gui then pcall(function() Preview.gui:Destroy() end) end
    if mobileToggleGui then pcall(function() mobileToggleGui:Destroy() end) end
    if _G._owehubGakuranUnload == _fullUnload then _G._owehubGakuranUnload = nil end
end
_G._owehubGakuranUnload = _fullUnload
Library:OnUnload(_fullUnload)
do
    local sg = Instance.new("ScreenGui")
    mobileToggleGui = sg
    sg.Name = "FoyiHubToggleBtn"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 99999
    pcall(function() sg.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 55, 0, 30)
    btn.Position = UDim2.new(0.5, -27, 0, 8)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    btn.BorderColor3 = Color3.fromRGB(80, 80, 90)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = "FoyiHub"
    btn.Font = Enum.Font.Code
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.Parent = sg
    btn.MouseButton1Click:Connect(function()
        if Library and typeof(Library.Toggle) == "function" then
            Library:Toggle()
        end
    end)
    local dragBtn, dStart, dPos
    btn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragBtn = true; dStart = inp.Position; dPos = btn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragBtn and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local delta = inp.Position - dStart
            btn.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + delta.X, dPos.Y.Scale, dPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragBtn = false end
    end)
end
pcall(function() SaveManager:LoadAutoloadConfig() end)
task.defer(function()
    if Toggles.SafeMode and Toggles.SafeMode.Value and SAFE_BLOCKED then
        for key in pairs(SAFE_BLOCKED) do
            local t = Toggles[key]
            if t and t.Value then pcall(function() t:SetValue(false) end) end
        end
    end
end)
Library:Notify({
    Title = "FoyiHub",
    Description =
    "Loaded: RightShift toggles the UI (or tap the FoyiHub button on mobile)",
    Time = 4
})
