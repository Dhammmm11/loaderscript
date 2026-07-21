-- Cracked by Int3rtia

--// ============================ Load Obsidian ============================
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

--// Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")

local LocalPlayer       = Players.LocalPlayer

--// ============================ Custom Config (non-UI data) ============================
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

--// ============================ Parry engine ============================
local _cachedBlockMod = nil

-- Shared combat style resolver used by block and evasive module lookups
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
    -- GC fallback: find the Block module if require() failed (common on mobile executors)
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
    -- Mobile and desktop use the same VirtualInputManager F-key path
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

--// ============================ Dodge engine (auto-dodge unparryable rear attacks) ============================
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

-- when there's genuinely no lateral preference.
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

-- Flat backward world direction: dash straight back relative to facing, away from
-- the attack. Falls back to "directly away from the attacker" if facing is degenerate.
local function backDodgeDir(model)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local look = myRoot.CFrame.LookVector
    local flat = Vector3.new(-look.X, 0, -look.Z)
    if flat.Magnitude < 0.001 then
        local theirRoot = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        if not theirRoot then return nil end
        flat = Vector3.new(myRoot.Position.X - theirRoot.Position.X, 0, myRoot.Position.Z - theirRoot.Position.Z)
        if flat.Magnitude < 0.001 then return nil end
    end
    return flat.Unit
end

-- mode: nil = plain dash, "side" = side-step away from the threat cluster,
-- "back" = dash straight backward (M2 dodge).
local function doDodge(model, mode)
    if State.dodgeActive then return end
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
                        if speed < 1 then speed = 60 end
                        lv.VectorVelocity = dir * speed
                    end
                end
            end
        else
            directDodge()
        end
        task.wait(0.2)
        State.dodgeActive = false
    end)
end

-- Returns true when `model` is far enough off the local player's frontal arc to be
-- unparryable. `thresh` is the LookVector dot cutoff; dot < thresh means the attacker
-- is to the side/rear (higher thresh = triggers at a narrower angle off the front).
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

--// ============================ Attack database ============================
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

-- CombatUtils holds the attacker's attack-speed math (scales with character height).
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

--// ============================ Forward declarations ============================
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
local blockedBySafeMode -- assigned in the Players tab; guards ban-risky toggles

--// ============================ Obsidian Window ============================
local Window = Library:CreateWindow({
    Title = "Foyihub | Gakuran",
    Footer = "https://discord.gg/r6esycEPar",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
    NotifySide = "Right",
})

--// ============================ Tabs ============================
local Tabs = {
    Main            = Window:AddTab("Auto Parry"),
    Parries         = Window:AddTab("Parries"),
    Players         = Window:AddTab("Players"),
    Minigames       = Window:AddTab("Minigames"),
    Visuals         = Window:AddTab("Visuals"),
    World           = Window:AddTab("World"),
    ["UI Settings"] = Window:AddTab("UI Settings"),
}

--// ============================ Parry Distance Circle Visualizer ============================
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
            pcall(function() _parryAdornee.Parent = (typeof(gethui) == "function" and gethui()) or
                game:GetService("CoreGui") end)
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
            pcall(function() _dodgeAdornee.Parent = (typeof(gethui) == "function" and gethui()) or
                game:GetService("CoreGui") end)
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

--// ============================ Infinite Zoom Out ============================
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

--// -------------------------------------------------------
--// Auto Parry tab
--// -------------------------------------------------------
do
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
end
do
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
    Suffix = " deg",
    Tooltip =
    "Attacks more than this many degrees off your facing (left/right/rear) can't be parried, so dodge them. Lower = dodge more side attacks; higher = only dodge near-rear",
})

end
do
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

--// -------------------------------------------------------
--// Parries tab: Builder + Saved IDs + Logger (all in one)
--// -------------------------------------------------------
end
do
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
BGroup:AddLabel("HitTimeLabel", {
    Text =
    "Hit Time = seconds into the animation when the hit lands.\nMost attacks are already in the DB -- use Auto-fill.",
    DoesWrap = true,
})

BGroup:AddButton({
    Text = "Auto-fill hit time from game DB",
    Func = function()
        local id = parseAnimId(Options.BuilderAnimId.Value)
        local db = id and AttackDB[id]
        if db then
            Options.BuilderDelay:SetValue(string.format("%.3f", db.delay))
            if Options.BuilderName.Value == "" then
                Options.BuilderName:SetValue(db.name)
            end
            Library:Notify({
                Title = "Parry Builder",
                Description = "Hit time " ..
                    string.format("%.3fs", db.delay) .. " (" .. db.name .. ")",
                Time = 2
            })
        else
            Library:Notify({ Title = "Parry Builder", Description = "Not in game DB -- set Hit Time manually", Time = 2 })
        end
    end,
})

BGroup:AddButton({
    Text = "Preview Animation",
    Func = function()
        openPreview(Options.BuilderAnimId.Value)
    end,
})

BGroup:AddButton({
    Text = "Save / Update ID",
    Func = function()
        local id = parseAnimId(Options.BuilderAnimId.Value)
        if not id then
            Library:Notify({ Title = "Parry Builder", Description = "Enter a valid animation ID", Time = 2 })
            return
        end
        local delay = tonumber(Options.BuilderDelay.Value) or 0.35
        local hold = tonumber(Options.BuilderHold.Value) or 0.3
        local name = Options.BuilderName.Value ~= "" and Options.BuilderName.Value or
            (AttackDB[id] and AttackDB[id].name) or ("Anim " .. id)
        local isUpdate = Config.parries[id] ~= nil
        local kind = (AttackDB[id] and AttackDB[id].kind) or (name:find("M2") and "M2" or "M1")
        Config.parries[id] = { name = name, delay = math.max(delay, 0), hold = math.max(hold, 0.05), kind = kind }
        saveCustomConfig()
        refreshSavedDropdown()
        Library:Notify({ Title = "Parry Builder", Description = (isUpdate and "Updated " or "Saved ") .. name, Time = 2 })
    end,
})

--// -------------------------------------------------------
--// Saved IDs (right groupbox of the merged Parries tab)
--// -------------------------------------------------------
end
do
local SavedGroup = Tabs.Parries:AddRightGroupbox("Saved Parry IDs")

local savedDropdown
refreshSavedDropdown = function()
    if not savedDropdown then return end
    local values = {}
    local disabled = {}
    for id, entry in pairs(Config.parries) do
        table.insert(values, string.format("%s (%s)", entry.name, id))
    end
    if #values == 0 then
        table.insert(values, "(no saved IDs)")
        table.insert(disabled, "(no saved IDs)")
    end
    pcall(function()
        savedDropdown:SetValues(values)
        savedDropdown:SetDisabledValues(disabled)
    end)
end

savedDropdown = SavedGroup:AddDropdown("SavedDropdown", {
    Values = { "(no saved IDs)" },
    DisabledValues = { "(no saved IDs)" },
    Default = "(no saved IDs)",
    Text = "Select saved animation",
    Tooltip = "Click to load into the Builder for editing",
    Callback = function(value)
        for id, entry in pairs(Config.parries) do
            if value == string.format("%s (%s)", entry.name, id) then
                Options.BuilderAnimId:SetValue(id)
                Options.BuilderName:SetValue(entry.name)
                Options.BuilderDelay:SetValue(string.format("%.3f", entry.delay or 0.35))
                Options.BuilderHold:SetValue(string.format("%.2f", entry.hold or 0.3))
                break
            end
        end
    end,
})

SavedGroup:AddButton({
    Text = "Delete Selected ID",
    Func = function()
        local val = Options.SavedDropdown.Value
        for id, entry in pairs(Config.parries) do
            if val == string.format("%s (%s)", entry.name, id) then
                Config.parries[id] = nil
                saveCustomConfig()
                refreshSavedDropdown()
                Library:Notify({ Title = "Saved IDs", Description = "Deleted " .. entry.name, Time = 2 })
                return
            end
        end
        Library:Notify({ Title = "Saved IDs", Description = "Select an ID first", Time = 2 })
    end,
})

SavedGroup:AddButton({
    Text = "Delete All IDs",
    Func = function()
        Config.parries = {}
        saveCustomConfig()
        refreshSavedDropdown()
        Library:Notify({ Title = "Saved IDs", Description = "Deleted all parry IDs", Time = 2 })
    end,
})

refreshSavedDropdown()

--// -------------------------------------------------------
--// Animation Logger (left groupbox, below the Builder)
--// -------------------------------------------------------
end
do
local LoggerGroup = Tabs.Parries:AddLeftGroupbox("Animation Logger")
LoggerGroup:AddToggle("LoggerVisible", {
    Text = "Show Logger Window",
    Default = false,
    Tooltip = "Toggle the floating Animation Logger window",
    Callback = function(val) if Logger then Logger.frame.Visible = val end end,
})
LoggerGroup:AddToggle("LoggerRangeOn", {
    Text = "Limit capture range",
    Default = true,
    Tooltip = "Only log animations from sources within the capture range below",
})
LoggerGroup:AddSlider("LoggerRange", {
    Text = "Capture Range (studs)",
    Default = 50,
    Min = 10,
    Max = 500,
    Rounding = 0,
    Suffix = " studs",
    Tooltip = "Animations from sources beyond this distance are ignored by the logger",
})
LoggerGroup:AddButton({
    Text = "Clear Log",
    Func = function() Logger:clear() end,
})
LoggerGroup:AddLabel(
    "The logger records every animation from sources within the capture range. Use its window to browse, add to the builder, or blacklist entries.",
    true)

--// -------------------------------------------------------
--// Minigames tab
--// -------------------------------------------------------
end
do
local RhythmGroup = Tabs.Minigames:AddLeftGroupbox("Auto Rhythm")

RhythmGroup:AddToggle("AutoRhythmToggle", {
    Text = "Auto Rhythm",
    Default = false,
    Tooltip = "Autoplay the rhythm minigame with hit chances",
})

RhythmGroup:AddLabel("RhythmStatus", {
    Text = "toggle Auto Rhythm, then play a song",
    DoesWrap = true,
})

end
do
local rhythmSliderGroup = Tabs.Minigames:AddRightGroupbox("Hit Chance")
local rhythmOrder = { "Perfect", "Good", "Okay", "Bad", "Miss" }
local rhythmDefaults = { 70, 15, 10, 4, 1 }
for i, name in ipairs(rhythmOrder) do
    rhythmSliderGroup:AddSlider("Rhythm" .. name, {
        Text = name .. " %",
        Default = rhythmDefaults[i],
        Min = 0,
        Max = 100,
        Rounding = 0,
        Suffix = "%",
    })
end

end
do
local BballGroup = Tabs.Minigames:AddLeftGroupbox("Basketball")
BballGroup:AddToggle("AutoGreenShot", {
    Text = "Auto Green Shot",
    Default = false,
    Tooltip = "Auto-release every basketball shot dead-center in the green (Perfect) zone",
})
BballGroup:AddToggle("BballIgnoreDefense", {
    Text = "Ignore Defense [RISK]",
    Default = false,
    Callback = function(val)
        if val then blockedBySafeMode("BballIgnoreDefense") end
    end,
})
BballGroup:AddLabel("BballStatus", {
    Text = "toggle on, then equip a basketball and shoot",
    DoesWrap = true,
})
BballGroup:AddLabel("Hold your shoot key/button as normal, the shot is released for you at the perfect moment.", true)

--// -------------------------------------------------------
--// Visuals tab - ESP group
--// -------------------------------------------------------
end
do
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

--// -------------------------------------------------------
--// Visuals tab - Skybox group
--// -------------------------------------------------------
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
        "rbxassetid://169210090", "rbxassetid://169210108", "rbxassetid://169210121",
        "rbxassetid://169210133", "rbxassetid://169210143", "rbxassetid://169210149",
    },
    ["Void"] = {
        "rbxassetid://4832115161", "rbxassetid://4832115161", "rbxassetid://4832115161",
        "rbxassetid://4832115161", "rbxassetid://4832115161", "rbxassetid://4832115161",
    },
}

local _skyboxNames = {
    "None", "Cloudy Blue", "Nebula", "Solid Grey", "Sunset", "Aurora",
    "Cartoon", "Starfield", "Vaporwave", "Overcast", "Void",
}

local _currentSky = nil
local function _applySkybox(name)
    if _currentSky then
        _currentSky:Destroy()
        _currentSky = nil
    end
    local faces = _skyboxPresets[name]
    if not faces then return end
    local sky = Instance.new("Sky")
    sky.Name = "GakuranSky"
    sky.SkyboxBk = faces[1]
    sky.SkyboxDn = faces[2]
    sky.SkyboxFt = faces[3]
    sky.SkyboxLf = faces[4]
    sky.SkyboxRt = faces[5]
    sky.SkyboxUp = faces[6]
    sky.StarCount = 0
    sky.SunAngularSize = 0
    sky.MoonAngularSize = 0
    sky.Parent = Lighting
    _currentSky = sky
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

end
do
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

end
do
local CameraGroup = Tabs.World:AddLeftGroupbox("Camera")
CameraGroup:AddToggle("InfiniteZoom", {
    Text = "Infinite Zoom Out",
    Default = false,
    Tooltip = "Unlock maximum camera zoom distance so you can zoom out infinitely",
    Callback = function(val)
        if val then _enableInfiniteZoom() else _disableInfiniteZoom() end
    end,
})

--// -------------------------------------------------------
--// Visuals tab - Lighting group
--// -------------------------------------------------------
end
do
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

--// -------------------------------------------------------
--// Visuals tab - Fog group
--// -------------------------------------------------------
end
do
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

Toggles.CustomFog:OnChanged(function()
    if Toggles.NoFog and Toggles.NoFog.Value then return end
    if Toggles.CustomFog.Value then
        _enableCustomFog()
    else
        _disableCustomFog()
    end
end)

--// -------------------------------------------------------
--// Visuals tab - Post-FX group
--// -------------------------------------------------------
end
do
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
    Default = 0.8,
    Min = 0,
    Max = 2,
    Rounding = 2,
})
Options.BloomThreshold:OnChanged(function()
    local bloom = Lighting:FindFirstChild("GakuranBloom")
    if bloom then bloom.Threshold = Options.BloomThreshold.Value end
end)

--// -------------------------------------------------------
--// Visuals tab - Effects group
--// -------------------------------------------------------
end
do
local EffectsGroup = Tabs.World:AddLeftGroupbox("Effects")

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
    Default = 0.1,
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
    Default = 0.5,
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
    Max = 1,
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



do
    local PerformanceGroup = Tabs.World:AddRightGroupbox("Performance Boost")
    PerformanceGroup:AddToggle("LowGraphics", {
        Text = "Low Graphics (Potato Mode)",
        Default = false,
        Tooltip = "Disable textures, shadows, particle effects & simplify materials to maximize FPS",
        Callback = function(val)
            if val then _enableLowGraphics() else _disableLowGraphics() end
        end,
    })
end



--// -------------------------------------------------------
--// Visuals tab - Combat HUD group (health/stamina bars, M2 cooldown)
--// -------------------------------------------------------
end
do
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

    -- Thin minimal bars: positioned bottom-right, above the controls hint rows.
    -- Each bar is 120 wide, 3 tall, with a tiny number on the right.
    local function makeThinBar(yOffset, fillColor)
        local container = Instance.new("Frame")
        container.BackgroundTransparency = 1
        container.Position = UDim2.new(1, -150, 1, yOffset)
        container.Size = UDim2.new(0, 130, 0, 14)
        container.Parent = gui

        local track = Instance.new("Frame")
        track.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        track.Position = UDim2.new(0, 0, 0.5, -1)
        track.Size = UDim2.new(1, -38, 0, 2)
        track.Parent = container
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.BackgroundColor3 = fillColor
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.Parent = track
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local num = Instance.new("TextLabel")
        num.BackgroundTransparency = 1
        num.Position = UDim2.new(1, -36, 0, 0)
        num.Size = UDim2.new(0, 36, 1, 0)
        num.Font = Enum.Font.Code
        num.TextSize = 11
        num.TextColor3 = Color3.fromRGB(210, 210, 215)
        num.TextXAlignment = Enum.TextXAlignment.Right
        num.TextYAlignment = Enum.TextYAlignment.Center
        num.Text = ""
        num.Parent = container

        return { container = container, fill = fill, num = num, color = fillColor }
    end

    local hp = makeThinBar(-78, Color3.fromRGB(225, 110, 110))
    local stam = makeThinBar(-60, Color3.fromRGB(165, 220, 170))

    _hudGui = { gui = gui, hp = hp, stam = stam }
    return _hudGui
end

local function _destroyHUD()
    if _hudConn then
        _hudConn:Disconnect()
        _hudConn = nil
    end
    if _hudGui then
        _hudGui.gui:Destroy()
        _hudGui = nil
    end
end

local function _startHUD()
    if _hudConn then return end
    _buildHUD()
    _hudConn = RunService.Heartbeat:Connect(function()
        if not _hudGui then return end
        local char = LocalPlayer.Character
        if not char then return end

        local showHp = Toggles.HudHealthBar and Toggles.HudHealthBar.Value
        local showStam = Toggles.HudStaminaBar and Toggles.HudStaminaBar.Value

        -- Stamina (attribute, max 100)
        local stam = _hudGui.stam
        stam.container.Visible = showStam == true
        if showStam then
            local s = char:GetAttribute("Stamina")
            if typeof(s) ~= "number" then s = 100 end
            local sPct = math.clamp(s / 100, 0, 1)
            stam.fill.Size = UDim2.new(sPct, 0, 1, 0)
            stam.num.Text = string.format("%d", math.floor(s + 0.5))
            if s < 25 then
                stam.fill.BackgroundColor3 = Color3.fromRGB(225, 175, 90)
            else
                stam.fill.BackgroundColor3 = stam.color
            end
        end

        -- Health (Humanoid)
        local hpInfo = _hudGui.hp
        hpInfo.container.Visible = showHp == true
        if showHp then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                local hp = hum.Health
                local maxHp = hum.MaxHealth
                if maxHp <= 0 then maxHp = 100 end
                local hpPct = math.clamp(hp / maxHp, 0, 1)
                hpInfo.fill.Size = UDim2.new(hpPct, 0, 1, 0)
                hpInfo.num.Text = string.format("%d", math.floor(hp + 0.5))
                if hpPct < 0.25 then
                    hpInfo.fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
                else
                    hpInfo.fill.BackgroundColor3 = hpInfo.color
                end
            end
        end
    end)
end

local function _stopHUD()
    _destroyHUD()
end

-- One loop drives both bars; run it while either bar toggle is on.
local function _updateBarsHud()
    local anyOn = (Toggles.HudHealthBar and Toggles.HudHealthBar.Value)
        or (Toggles.HudStaminaBar and Toggles.HudStaminaBar.Value)
    if anyOn then _startHUD() else _stopHUD() end
end

HUDGroup:AddToggle("HudHealthBar", {
    Text = "Health Bar",
    Default = false,
    Tooltip = "Thin health bar in the bottom-right corner",
    Callback = _updateBarsHud,
})
HUDGroup:AddToggle("HudStaminaBar", {
    Text = "Stamina Bar",
    Default = false,
    Tooltip = "Thin stamina bar in the bottom-right corner",
    Callback = _updateBarsHud,
})
HUDGroup:AddToggle("HudM2Cooldown", {
    Text = "M2 Cooldown" .. (isMobile and " (Mobile display)" or " (PC display)"),
    Default = false,
    Tooltip = isMobile
        and
        "On-screen Heavy Attack (M2) cooldown countdown, draggable text display (mobile has no cooldown feedback for it). Only shows while combat is equipped."
        or
        "Appends the Heavy Attack (M2) cooldown timer to the game's 'Heavy Attack' controls hint. Only active while combat is equipped (the hint only exists then).",
})

local _visUnload = function()
    _disableFullbright()
    _disableNoFog()
    _disableCustomFog()
    _disableInfiniteZoom()
    _stopRangeVisualizer()
    if _parryAdornee then
        _parryAdornee:Destroy(); _parryAdornee = nil
    end
    if _dodgeAdornee then
        _dodgeAdornee:Destroy(); _dodgeAdornee = nil
    end
    _stopHUD()
    if _currentSky then
        _currentSky:Destroy(); _currentSky = nil
    end
    for _, name in ipairs({ "GakuranBloom", "GakuranBlur", "GakuranSunRays", "GakuranCC" }) do
        local fx = Lighting:FindFirstChild(name)
        if fx then fx:Destroy() end
    end
end

--// -------------------------------------------------------
--// Players tab
--// -------------------------------------------------------
end
do
local PlayerGroup = Tabs.Players:AddLeftGroupbox("Player Exploits")

-- These toggles make the SERVER observe impossible actions (acting through a
-- server-enforced cooldown/stun, teleporting, or landing always-perfect shots).
-- That is what gets accounts banned - not the core auto-parry/dodge, which only
-- fire legitimate remotes at good timing (indistinguishable from a skilled human).
local SAFE_BLOCKED = {
    NoParryCD          = "No Parry Cooldown",
    NoDodgeCD          = "No Dodge Cooldown",
    NoStun             = "No Stun",
    NoRagdoll          = "No Ragdoll",
    FollowPlayer       = "Follow Player (teleport)",
    BballIgnoreDefense = "Basketball Ignore Defense",
}

PlayerGroup:AddToggle("SafeMode", {
    Text = "Safe Mode",
    Default = true,
    Callback = function(val)
        if val then
            for key in pairs(SAFE_BLOCKED) do
                local t = Toggles[key]
                if t and t.Value then pcall(function() t:SetValue(false) end) end
            end
            Library:Notify({
                Title = "Safe Mode ON",
                Description =
                "Ban-risky toggles disabled. Auto-Parry/Dodge still work.",
                Time = 4
            })
        end
    end,
})
PlayerGroup:AddLabel(
    "Features are not detected by game, but remember that u still can be banned from getting reported! Turn OFF only if you personally accept the ban risk.",
    true)

-- Reverts a risky toggle and warns when Safe Mode is on. Returns true if blocked.
blockedBySafeMode = function(key)
    if not (Toggles.SafeMode and Toggles.SafeMode.Value) then return false end
    if not SAFE_BLOCKED[key] then return false end
    local t = Toggles[key]
    if t then task.defer(function() pcall(function() t:SetValue(false) end) end) end
    Library:Notify({
        Title = "Blocked by Safe Mode",
        Description = (SAFE_BLOCKED[key] or key) ..
            " is a ban risk. Disable Safe Mode to use it.",
        Time = 5
    })
    return true
end

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

--// -------------------------------------------------------
--// Players tab - Respawn/death group
--// -------------------------------------------------------
end
do
local RespawnGroup = Tabs.Players:AddRightGroupbox("Respawn & Death")

RespawnGroup:AddToggle("AutoRespawn", {
    Text = "Auto Respawn",
    Default = false,
    Tooltip = "Hide the Death UI and fire SpawnRequest remote automatically so you respawn instantly",
    Callback = function(val)
        if val then startAutoRespawn() else stopAutoRespawn() end
    end,
})

RespawnGroup:AddToggle("NoBlur", {
    Text = "No Blur",
    Default = false,
    Tooltip = "Strip Blur/ColorCorrection effects from Lighting and Camera every Heartbeat",
    Callback = function(val)
        if val then startNoBlur() else stopNoBlur() end
    end,
})

--// -------------------------------------------------------
--// Players tab - Teleport group
--// -------------------------------------------------------
end
do
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
    Values = { "(no players)" },
    DisabledValues = { "(no players)" },
    Default = "(no players)",
    Text = "Target Player",
    Tooltip = "Select a player to teleport to",
})

TeleportGroup:AddSlider("TeleportOffset", {
    Text = "Distance (studs)",
    Default = 3,
    Min = 0,
    Max = 30,
    Rounding = 1,
    Suffix = " studs",
    Tooltip = "How far behind the target to land while following (0 = exact same position)",
})

TeleportGroup:AddButton({
    Text = "Teleport",
    Func = function()
        local sel = Options.TeleportTarget and Options.TeleportTarget.Value
        if not sel or sel == "(no players)" then
            Library:Notify({ Title = "Teleport", Description = "Select a player first", Time = 2 })
            return
        end
        local target = Players:FindFirstChild(sel)
        if not target or not target.Character then
            Library:Notify({ Title = "Teleport", Description = sel .. " has no character", Time = 2 })
            return
        end
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (tRoot and myRoot) then return end
        myRoot.CFrame = tRoot.CFrame
        Library:Notify({ Title = "Teleport", Description = "Teleported to " .. sel, Time = 2 })
    end,
})

TeleportGroup:AddToggle("FollowPlayer", {
    Text = "Follow Player [RISK]",
    Default = false,
    Tooltip = "[BAN RISK] Teleports your character behind player",
    Callback = function(val)
        if val and blockedBySafeMode("FollowPlayer") then return end
        if val then startFollow() else stopFollow() end
    end,
})

refreshTeleportDropdown()
Players.PlayerAdded:Connect(function() refreshTeleportDropdown() end)
Players.PlayerRemoving:Connect(function() refreshTeleportDropdown() end)

--// -------------------------------------------------------
--// UI Settings tab
--// -------------------------------------------------------
end
do
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddButton({
    Text = "Unload",
    Func = function()
        Library:Unload()
    end,
})

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind",
    { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

--// Addon integration
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "BuilderAnimId", "BuilderName", "BuilderDelay", "BuilderHold",
    "SavedDropdown", "TeleportTarget" })
ThemeManager:SetFolder("Owehub/Gakuran")
SaveManager:SetFolder("Owehub/Gakuran")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

end
--// ============================ Animation Logger (custom window) ============================
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
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 14, 0, 0)
    title.Size = UDim2.new(0, 180, 1, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "x"
    closeBtn.Font = Enum.Font.Code
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -38, 0, 6)
    closeBtn.Parent = titleBar
    closeBtn.MouseButton1Click:Connect(function() frame.Visible = false end)

    local searchBox = Instance.new("TextBox")
    searchBox.PlaceholderText = "Search id / name / source..."
    searchBox.Text = ""
    searchBox.Font = Enum.Font.Code
    searchBox.TextSize = 13
    searchBox.TextColor3 = Color3.new(1, 1, 1)
    searchBox.PlaceholderColor3 = Color3.fromRGB(160, 160, 170)
    searchBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    searchBox.Position = UDim2.new(0, 10, 0, 46)
    searchBox.Size = UDim2.new(1, -20, 0, 34)
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = frame
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", searchBox).Color = Color3.fromRGB(40, 40, 40); Instance.new("UIStroke", searchBox).Thickness = 1; Instance.new("UIStroke", searchBox).ApplyStrokeMode =
        Enum.ApplyStrokeMode.Border

    local sourceBtn = Instance.new("TextButton")
    sourceBtn.Text = "Source: All"
    sourceBtn.Font = Enum.Font.Code
    sourceBtn.TextSize = 13
    sourceBtn.TextColor3 = Color3.new(1, 1, 1)
    sourceBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    sourceBtn.Size = UDim2.new(0, 130, 0, 34)
    sourceBtn.Position = UDim2.new(0, 10, 0, 86)
    sourceBtn.AutoButtonColor = false
    sourceBtn.Parent = frame
    Instance.new("UICorner", sourceBtn).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", sourceBtn).Color = Color3.fromRGB(40, 40, 40); Instance.new("UIStroke", sourceBtn).Thickness = 1; Instance.new("UIStroke", sourceBtn).ApplyStrokeMode =
        Enum.ApplyStrokeMode.Border

    local applyLogFilters
    local sourceState = "All"
    sourceBtn.MouseButton1Click:Connect(function()
        sourceState = (sourceState == "All" and "Players") or (sourceState == "Players" and "NPCs") or "All"
        sourceBtn.Text = "Source: " .. sourceState
        if applyLogFilters then applyLogFilters() end
    end)

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.BackgroundTransparency = 1
    logScroll.Size = UDim2.new(1, -14, 1, -134)
    logScroll.Position = UDim2.new(0, 10, 0, 126)
    logScroll.ScrollBarThickness = 4
    logScroll.ScrollBarImageColor3 = Color3.fromRGB(35, 35, 35)
    logScroll.BorderSizePixel = 0
    logScroll.CanvasSize = UDim2.new()
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = frame

    local logList = Instance.new("UIListLayout", logScroll)
    logList.Padding = UDim.new(0, 8)
    logList.SortOrder = Enum.SortOrder.LayoutOrder

    local logRows = {}
    local logCount = 0
    local logOrder = 0

    local categoryColors = {
        Combat   = Color3.fromRGB(224, 92, 92),
        Action   = Color3.fromRGB(240, 168, 82),
        Movement = Color3.fromRGB(92, 92, 104),
    }

    local function rowMatchesFilters(row)
        local q = string.lower(searchBox.Text or "")
        local key = string.lower(row:GetAttribute("SearchKey") or "")
        local matchesSearch = (q == "") or string.find(key, q, 1, true)
        local src = row:GetAttribute("SourceType") or "NPCs"
        local matchesSource = (sourceState == "All") or (sourceState == src)
        return matchesSearch and matchesSource
    end

    applyLogFilters = function()
        for _, row in ipairs(logScroll:GetChildren()) do
            if row:IsA("Frame") then
                row.Visible = rowMatchesFilters(row)
            end
        end
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(applyLogFilters)

    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale,
                startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    local logger = { gui = logGui, frame = frame, scroll = logScroll }

    function logger:clear()
        for _, row in ipairs(logScroll:GetChildren()) do
            if row:IsA("Frame") then row:Destroy() end
        end
        logRows = {}
        logCount = 0
    end

    function logger:addRow(animId, animName, sourceLabel, sourceType, category)
        category = category or "Combat"
        logOrder -= 1

        local existing = logRows[animId]
        if existing and existing.Parent then
            existing.LayoutOrder = logOrder
            existing:SetAttribute("SearchKey",
                string.lower(animId .. " " .. animName .. " " .. sourceLabel .. " " .. (category or "")))
            existing:SetAttribute("SourceType", sourceType)
            existing.Visible = rowMatchesFilters(existing)
            return
        end

        logCount += 1
        local row = Instance.new("Frame")
        row.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        row.Size = UDim2.new(1, -6, 0, 78)
        row.LayoutOrder = logOrder
        row.Parent = logScroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", row).Color = Color3.fromRGB(40, 40, 40); Instance.new("UIStroke", row).Thickness = 1; Instance.new("UIStroke", row).ApplyStrokeMode =
            Enum.ApplyStrokeMode.Border

        row:SetAttribute("SearchKey",
            string.lower(animId .. " " .. animName .. " " .. sourceLabel .. " " .. (category or "")))
        row:SetAttribute("SourceType", sourceType)
        logRows[animId] = row

        local bar = Instance.new("Frame")
        bar.BackgroundColor3 = categoryColors[category] or Color3.fromRGB(35, 35, 35)
        bar.Size = UDim2.new(0, 3, 1, -16)
        bar.Position = UDim2.new(0, 6, 0, 8)
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

        local pill = Instance.new("Frame")
        pill.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        pill.Size = UDim2.new(0, 74, 0, 22)
        pill.Position = UDim2.new(0, 16, 0, 8)
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 4)

        local pillLabel = Instance.new("TextLabel")
        pillLabel.Text = sourceLabel
        pillLabel.Font = Enum.Font.Code
        pillLabel.TextSize = 11
        pillLabel.TextColor3 = Color3.new(1, 1, 1)
        pillLabel.BackgroundTransparency = 1
        pillLabel.Size = UDim2.new(1, 0, 1, 0)
        pillLabel.Parent = pill

        local idLabel = Instance.new("TextLabel")
        idLabel.Text = animId
        idLabel.Font = Enum.Font.Code
        idLabel.TextSize = 14
        idLabel.TextColor3 = Color3.new(1, 1, 1)
        idLabel.BackgroundTransparency = 1
        idLabel.Size = UDim2.new(1, -220, 0, 18)
        idLabel.Position = UDim2.new(0, 100, 0, 5)
        idLabel.TextXAlignment = Enum.TextXAlignment.Left
        idLabel.Parent = row

        local sub = Instance.new("TextLabel")
        sub.Text = sourceLabel .. "  -  " .. animName
        sub.Font = Enum.Font.Code
        sub.TextSize = 11
        sub.TextColor3 = Color3.fromRGB(160, 160, 170)
        sub.BackgroundTransparency = 1
        sub.Size = UDim2.new(1, -120, 0, 14)
        sub.Position = UDim2.new(0, 100, 0, 24)
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.Parent = row

        local catLabel = Instance.new("TextLabel")
        catLabel.Text = category
        catLabel.Font = Enum.Font.Code
        catLabel.TextSize = 10
        catLabel.TextColor3 = categoryColors[category] or Color3.fromRGB(160, 160, 170)
        catLabel.BackgroundTransparency = 1
        catLabel.Size = UDim2.new(0, 64, 0, 14)
        catLabel.Position = UDim2.new(1, -76, 0, 7)
        catLabel.TextXAlignment = Enum.TextXAlignment.Right
        catLabel.Parent = row

        local btnRow = Instance.new("Frame")
        btnRow.BackgroundTransparency = 1
        btnRow.Size = UDim2.new(1, -24, 0, 26)
        btnRow.Position = UDim2.new(0, 16, 1, -32)
        btnRow.Parent = row
        local btnList = Instance.new("UIListLayout", btnRow)
        btnList.FillDirection = Enum.FillDirection.Horizontal
        btnList.Padding = UDim.new(0, 6)

        local function makeTinyBtn(text, callback)
            local btn = Instance.new("TextButton")
            btn.Text = text
            btn.Font = Enum.Font.Code
            btn.TextSize = 12
            btn.TextColor3 = Color3.new(1, 1, 1)
            btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            btn.Size = UDim2.new(0, 68, 1, 0)
            btn.AutoButtonColor = false
            btn.Parent = btnRow
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", btn).Color = Color3.fromRGB(40, 40, 40); Instance.new("UIStroke", btn).Thickness = 1; Instance.new("UIStroke", btn).ApplyStrokeMode =
                Enum.ApplyStrokeMode.Border
            btn.MouseButton1Click:Connect(callback)
            return btn
        end

        makeTinyBtn("Preview", function()
            openPreview(animId)
        end)

        makeTinyBtn("+ Parry", function()
            local db = AttackDB[animId]
            local pname = (db and db.name) or ((animName ~= "Animation" and animName ~= "") and animName) or
                (sourceLabel .. " " .. animId:sub(-5))
            local prev = Config.parries[animId]
            Config.parries[animId] = {
                name = (prev and prev.name) or pname,
                delay = (prev and prev.delay) or (db and db.delay) or 0.35,
                hold = (prev and prev.hold) or ((Options.BlockHold and Options.BlockHold.Value or 350) / 1000),
            }
            saveCustomConfig()
            refreshSavedDropdown()
            Library:Notify({ Title = "Auto Parry", Description = (prev and "Updated " or "Added ") .. pname, Time = 2 })
        end)

        makeTinyBtn("Blacklist", function()
            Config.blacklist[animId] = true
            saveCustomConfig()
            if row.Parent then row:Destroy() end
            logRows[animId] = nil
            Library:Notify({ Title = "Logger", Description = "Blacklisted " .. animId, Time = 2 })
        end)

        row.Visible = rowMatchesFilters(row)

        local allRows = {}
        for _, r in ipairs(logScroll:GetChildren()) do
            if r:IsA("Frame") then table.insert(allRows, r) end
        end
        if #allRows > 120 then
            table.sort(allRows, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
            for i = 121, #allRows do allRows[i]:Destroy() end
        end
    end

    return logger
end

--// ============================ Animation Preview (custom window) ============================
createPreviewWindow = function()
    local prevGui = Instance.new("ScreenGui")
    prevGui.Name = "GKPreview"
    prevGui.ResetOnSpawn = false
    prevGui.IgnoreGuiInset = true
    prevGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() prevGui.Parent = gethui and gethui() or game:GetService("CoreGui") end)

    local frame = Instance.new("Frame")
    frame.Name = "PreviewFrame"
    frame.Size = UDim2.new(0, 380, 0, 420)
    frame.Position = UDim2.new(0.5, -190, 0.5, -210)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.Visible = false
    frame.Parent = prevGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    local outerStroke = Instance.new("UIStroke", frame)
    outerStroke.Color = Color3.fromRGB(40, 40, 40)
    outerStroke.Thickness = 1
    outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 34)
    titleBar.BackgroundTransparency = 1
    titleBar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Text = "Animation Preview"
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextColor3 = Color3.new(1, 1, 1)
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "x"
    closeBtn.Font = Enum.Font.Code
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -32, 0, 3)
    closeBtn.Parent = titleBar

    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale,
                startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    local viewport = Instance.new("ViewportFrame")
    viewport.BackgroundColor3 = Color3.fromRGB(5, 5, 7)
    viewport.Size = UDim2.new(1, -20, 1, -130)
    viewport.Position = UDim2.new(0, 10, 0, 38)
    viewport.Ambient = Color3.fromRGB(180, 180, 190)
    viewport.LightColor = Color3.new(1, 1, 1)
    viewport.Parent = frame
    Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 4)

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Text = "0.00 / 0.00s | x1"
    timeLabel.Font = Enum.Font.Code
    timeLabel.TextSize = 13
    timeLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Size = UDim2.new(1, -20, 0, 18)
    timeLabel.Position = UDim2.new(0, 10, 1, -86)
    timeLabel.TextXAlignment = Enum.TextXAlignment.Center
    timeLabel.Parent = frame

    local controlsRow = Instance.new("Frame")
    controlsRow.BackgroundTransparency = 1
    controlsRow.Size = UDim2.new(1, -20, 0, 30)
    controlsRow.Position = UDim2.new(0, 10, 1, -52)
    controlsRow.Parent = frame
    local controlsList = Instance.new("UIListLayout", controlsRow)
    controlsList.FillDirection = Enum.FillDirection.Horizontal
    controlsList.Padding = UDim.new(0, 4)
    controlsList.SortOrder = Enum.SortOrder.LayoutOrder

    local function makeCtrlBtn(text, width)
        local btn = Instance.new("TextButton")
        btn.Text = text
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        btn.Size = UDim2.new(0, width, 1, 0)
        btn.AutoButtonColor = false
        btn.Parent = controlsRow
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        return btn
    end

    local pauseBtn   = makeCtrlBtn("Pause", 56)
    local backBtn    = makeCtrlBtn("<|", 30)
    local fwdBtn     = makeCtrlBtn("|>", 30)
    local loopBtn    = makeCtrlBtn("Loop:On", 62)
    local speedBtn   = makeCtrlBtn("x1", 38)
    local rotLBtn    = makeCtrlBtn("<<", 30)
    local rotRBtn    = makeCtrlBtn(">>", 30)

    local preview    = {
        gui = prevGui,
        frame = frame,
        viewport = viewport,
        timeLabel = timeLabel,
        pauseBtn = pauseBtn,
        loopBtn = loopBtn,
        speedBtn = speedBtn,
        _track = nil,
        _paused = false,
        _speedIndex = 2,
        _speedOptions = { 0.5, 1, 2 },
        _camAngle = 0,
        _updateCamera = nil,
    }

    local FRAME_STEP = 2 / 60

    pauseBtn.MouseButton1Click:Connect(function()
        if not preview._track then return end
        preview._paused = not preview._paused
        preview._track:AdjustSpeed(preview._paused and 0 or preview._speedOptions[preview._speedIndex])
        pauseBtn.Text = preview._paused and "Play" or "Pause"
    end)

    backBtn.MouseButton1Click:Connect(function()
        if not preview._track then return end
        preview._track.TimePosition = math.max(0, preview._track.TimePosition - FRAME_STEP)
    end)

    fwdBtn.MouseButton1Click:Connect(function()
        if not preview._track or preview._track.Length <= 0 then return end
        preview._track.TimePosition = math.min(preview._track.Length - 0.001, preview._track.TimePosition + FRAME_STEP)
    end)

    loopBtn.MouseButton1Click:Connect(function()
        if not preview._track then return end
        preview._track.Looped = not preview._track.Looped
        loopBtn.Text = preview._track.Looped and "Loop:On" or "Loop:Off"
    end)

    speedBtn.MouseButton1Click:Connect(function()
        if not preview._track then return end
        preview._speedIndex = (preview._speedIndex % #preview._speedOptions) + 1
        speedBtn.Text = "x" .. tostring(preview._speedOptions[preview._speedIndex])
        if not preview._paused then
            preview._track:AdjustSpeed(preview._speedOptions[preview._speedIndex])
        end
    end)

    rotLBtn.MouseButton1Click:Connect(function()
        preview._camAngle = preview._camAngle - math.rad(30)
        if preview._updateCamera then preview._updateCamera() end
    end)

    rotRBtn.MouseButton1Click:Connect(function()
        preview._camAngle = preview._camAngle + math.rad(30)
        if preview._updateCamera then preview._updateCamera() end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        if preview._track then
            pcall(function() preview._track:Stop() end)
            preview._track = nil
        end
        if viewport:FindFirstChildOfClass("WorldModel") then
            viewport:FindFirstChildOfClass("WorldModel"):Destroy()
        end
        frame.Visible = false
    end)

    return preview
end

openPreview = function(animId)
    animId = parseAnimId(animId)
    if not animId then return end
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return end

    if Preview._track then
        pcall(function() Preview._track:Stop() end)
        Preview._track = nil
    end

    local world = Preview.viewport:FindFirstChildOfClass("WorldModel")
    if world then world:Destroy() end

    local rig
    do
        local oldArch = char.Archivable
        char.Archivable = true
        rig = char:Clone()
        char.Archivable = oldArch
    end
    if not rig then return end
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("ForceField") then
            d:Destroy()
        end
    end
    local rigHum = rig:FindFirstChildOfClass("Humanoid")
    local rigRoot = rig:FindFirstChild("HumanoidRootPart")
    if not (rigHum and rigRoot) then return end

    world = Instance.new("WorldModel", Preview.viewport)
    rig:PivotTo(CFrame.new(0, 0, 0))
    rigRoot.Anchored = true
    rigHum.EvaluateStateMachine = false
    rig.Parent = world

    Preview._camAngle = 0
    Preview._paused = false
    Preview._speedIndex = 2
    Preview.pauseBtn.Text = "Pause"
    Preview.loopBtn.Text = "Loop:On"
    Preview.speedBtn.Text = "x1"

    local camera = Instance.new("Camera", Preview.viewport)
    Preview.viewport.CurrentCamera = camera
    Preview._updateCamera = function()
        local cf = CFrame.new(rigRoot.Position) * CFrame.Angles(0, Preview._camAngle, 0)
        camera.CFrame = CFrame.new((cf * CFrame.new(0, 1.2, -7)).Position, rigRoot.Position)
    end
    Preview._updateCamera()

    local animator = rigHum:FindFirstChildOfClass("Animator") or Instance.new("Animator", rigHum)
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. animId
    local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
    if not ok or not track then return end
    track.Looped = true
    track:Play()
    Preview._track = track

    Preview.frame.Visible = true

    local hb
    hb = RunService.RenderStepped:Connect(function()
        if not Preview.frame.Visible or not Preview.frame.Parent then
            hb:Disconnect()
            return
        end
        if Preview._track ~= track then
            hb:Disconnect()
            return
        end
        local spd = Preview._paused and 0 or Preview._speedOptions[Preview._speedIndex]
        local db = AttackDB[animId]
        local hit = db and (" * Hit @ %.2fs"):format(db.delay) or ""
        Preview.timeLabel.Text = string.format("%.2f / %.2fs | x%g%s", track.TimePosition, track.Length, spd, hit)
    end)
end

--// ============================ Logger/Preview instantiation ============================
Preview = createPreviewWindow()
Logger = createLoggerWindow()
if Toggles.LoggerVisible then
    Logger.frame.Visible = Toggles.LoggerVisible.Value
end

--// ============================ Animation watcher ============================
local watched = {}

local function getSourceInfo(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then return plr.Name, "Players" end
    return "Enemy", "NPCs"
end

local recentLog = {}
-- recentLog is keyed by "tostring(model)|animId" for the 0.5s log throttle. Each model
-- respawn makes a fresh key that's never reused, so prune old entries periodically to
-- stop unbounded memory growth on long sessions (mobile OOM risk).
task.spawn(function()
    while true do
        task.wait(30)
        local now = os.clock()
        for k, t in pairs(recentLog) do
            if now - t > 5 then recentLog[k] = nil end
        end
    end
end)

local function distanceToModel(model)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local theirRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not (myRoot and theirRoot) then return nil end
    return (myRoot.Position - theirRoot.Position).Magnitude
end

--// ============================ Friend / contact exclusion ============================
local _friendCache = {}
local function cacheFriend(plr)
    if not plr or plr == LocalPlayer then return end
    task.spawn(function()
        local ok, res = pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end)
        if ok then _friendCache[plr.UserId] = res == true end
    end)
end
for _, p in ipairs(Players:GetPlayers()) do cacheFriend(p) end
Players.PlayerAdded:Connect(cacheFriend)

local _contactIds = {}
local _phoneTableRef = nil
local function readContactsFrom(o)
    local contacts = rawget(o, "Contacts")
    if type(contacts) ~= "table" then return nil end
    if contacts[1] ~= nil and (type(contacts[1]) ~= "table" or rawget(contacts[1], "UserId") == nil) then
        return nil
    end
    local set = {}
    for _, c in ipairs(contacts) do
        local uid = tonumber(type(c) == "table" and c.UserId)
        if uid then set[uid] = true end
    end
    return set
end
local function scanForPhoneTable()
    if typeof(getgc) ~= "function" then return end
    pcall(function()
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" and rawget(o, "Contacts") ~= nil then
                local set = readContactsFrom(o)
                if set then
                    _phoneTableRef = o; _contactIds = set; return
                end
            end
        end
    end)
end
local function refreshContacts()
    if _phoneTableRef then
        local ok, set = pcall(readContactsFrom, _phoneTableRef)
        if ok and set then
            _contactIds = set; return
        end
        _phoneTableRef = nil
    end
    scanForPhoneTable()
end
task.spawn(function()
    scanForPhoneTable()
    local since = 0
    while true do
        task.wait(20)
        since += 20
        if since >= 120 then
            since = 0; scanForPhoneTable()
        else
            refreshContacts()
        end
    end
end)

local function isExcludedAttacker(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if not plr then return false end
    local uid = plr.UserId
    local exFriends = Toggles.ExcludeFriends and Toggles.ExcludeFriends.Value
    if exFriends and _friendCache[uid] then return true end
    local exContacts = Toggles.ExcludeContacts and Toggles.ExcludeContacts.Value
    if exContacts and _contactIds[uid] then return true end
    return false
end

-- Notifications must be created from a thread that has GUI capabilities. Game signal
-- callbacks (Animator.AnimationPlayed) run on a restricted thread that lacks the
-- "Plugin" capability, so calling Library:Notify directly from onAnimationPlayed
-- throws "cannot access 'Instance' (lacking capability Plugin)". Queue them instead.
local notifyQueue = {}
local notifyLoopAlive = true
local function enqueueNotify(data)
    notifyQueue[#notifyQueue + 1] = data
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

    -- Log, gated by the capture range. Same-source spam throttled to 2x/sec.
    -- Blacklisted animations are hidden from the logger ONLY.
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

    -- Auto parry
    local ap = Toggles.AutoParry
    if not ap or not ap.Value then return end

    if track.Looped then return end
    if category == "Movement" then return end

    -- Don't parry/dodge while combat is holstered (game requires Equip to block anyway).
    local myChar = LocalPlayer.Character
    if not (myChar and myChar:GetAttribute("Equip") == true) then return end

    -- Don't auto-defend against Roblox friends or saved in-game contacts.
    if isExcludedAttacker(model) then return end

    local entry = Config.parries[id]
    local hitTime, pname
    if entry then
        hitTime = entry.delay
        pname = entry.name
    else
        local aa = Toggles.AutoAll
        if aa and aa.Value and AttackDB[id] then
            local info = AttackDB[id]
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
            pname = info.name
        else
            return
        end
    end
    if not hitTime then return end

    local now = os.clock()
    if State.lastTrigger[id] and now - State.lastTrigger[id] < 0.25 then return end

    local hold = (entry and entry.hold) or ((Options.BlockHold and Options.BlockHold.Value or 350) / 1000)

    local remaining = hitTime - track.TimePosition
    local ping = getPing()
    local timingOffset = Options.TimingOffset and Options.TimingOffset.Value or -40
    local delay = math.max(remaining - ping * 0.5 + (timingOffset / 1000), 0)

    -- M2 Dodge: heavies are guardbreakers, so instead of blocking, i-frame dash
    -- BACKWARD out of the attack's reach.
    local m2d = Toggles.M2DodgeBack
    if m2d and m2d.Value then
        local info = AttackDB[id]
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

    -- Auto-Dodge: if the attacker is beyond our parry arc, i-frame side-dash.
    -- DodgeAngle controls how far off the front counts as unparryable.
    -- When outnumbered (2+ enemies close), widen the dodge cone.
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

    -- Auto-Parry range gate
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

local function unwatch(model)
    local data = watched[model]
    if data then
        for _, c in ipairs(data.conns) do
            pcall(function() c:Disconnect() end)
        end
        watched[model] = nil
    end
end

local function watchModel(model)
    if watched[model] then return end
    if model == LocalPlayer.Character then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local conns = {}
    watched[model] = { conns = conns, playing = {} }

    local function hookAnimator(animator)
        table.insert(conns, animator.AnimationPlayed:Connect(function(track)
            onAnimationPlayed(model, track)
        end))
    end

    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        hookAnimator(animator)
    else
        table.insert(conns, hum.ChildAdded:Connect(function(child)
            if child:IsA("Animator") then hookAnimator(child) end
        end))
    end
    table.insert(conns, hum.AnimationPlayed:Connect(function(track)
        onAnimationPlayed(model, track)
    end))

    table.insert(conns, model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            unwatch(model)
        end
    end))
end

local function tryWatchFromDescendant(desc)
    if desc:IsA("Humanoid") then
        local model = desc.Parent
        if model and model:IsA("Model") then
            task.defer(watchModel, model)
        end
    end
end

for _, desc in ipairs(Workspace:GetDescendants()) do
    tryWatchFromDescendant(desc)
end
Workspace.DescendantAdded:Connect(tryWatchFromDescendant)

task.spawn(function()
    while true do
        for model, data in pairs(watched) do
            if model.Parent then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local animator = hum and hum:FindFirstChildOfClass("Animator")
                local nowPlaying = {}
                local nowIds = {}
                if animator then
                    local ok, tracks = pcall(animator.GetPlayingAnimationTracks, animator)
                    if ok then
                        for _, tr in ipairs(tracks) do
                            nowPlaying[tr] = true
                            local aid = tr.Animation and tr.Animation.AnimationId
                            if aid then nowIds[aid] = true end
                            -- Only fire for tracks we haven't seen yet (catches animations
                            -- that started between AnimationPlayed events on mobile/restricted threads)
                            if not data.playing[tr] and not (aid and data.playingIds and data.playingIds[aid]) then
                                task.spawn(onAnimationPlayed, model, tr)
                            end
                        end
                    end
                end
                data.playing = nowPlaying
                data.playingIds = nowIds
            else
                -- Model was removed, clean up
                unwatch(model)
            end
        end
        task.wait(0.15) -- Slightly slower poll since AnimationPlayed handles most cases
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.defer(function()
        unwatch(char)
    end)
end)

--// ============================ Shared GC Helper ============================
-- Used by both Rhythm and Basketball engines to avoid duplicate getgc scans
local function _collectGC()
    local gc = getgc or (getgenv and getgenv().getgc)
    if typeof(gc) ~= "function" then return nil end
    local out
    pcall(function() out = gc(true) end)
    if type(out) ~= "table" or #out == 0 then
        pcall(function() out = gc(false) end)
    end
    if type(out) ~= "table" or #out == 0 then
        pcall(function() out = gc() end)
    end
    return (type(out) == "table") and out or nil
end

--// ============================ Auto Rhythm engine ============================
local rhythmEngineRunning = false

local function startRhythmEngine()
    if rhythmEngineRunning then return end
    rhythmEngineRunning = true

    local ORDER         = { "Perfect", "Good", "Okay", "Bad", "Miss" }
    local JMAP          = { Perfect = "PERFECT", Good = "GOOD", Okay = "OKAY", Bad = "BAD", Miss = "MISS" }

    local setId         = setthreadidentity or setidentity
        or (getgenv and (getgenv().setthreadidentity or getgenv().setidentity))
    local function elevate()
        if setId then pcall(setId, 8) end
    end

    local function collectGC()
        return _collectGC()
    end

    local function findViaModules()
        local glm = getloadedmodules or (getgenv and getgenv().getloadedmodules)
        local guv = debug and debug.getupvalues
        if typeof(glm) ~= "function" or typeof(guv) ~= "function" then return nil end
        local found
        pcall(function()
            for _, m in ipairs(glm()) do
                if typeof(m) == "Instance" and m.Parent ~= nil and (m:IsA("ModuleScript") or m:IsA("Script")) then
                    local okReq, mod = pcall(require, m)
                    if okReq and type(mod) == "table" then
                        for _, fn in pairs(mod) do
                            if type(fn) == "function" then
                                local okUv, ups = pcall(guv, fn)
                                if okUv and type(ups) == "table" then
                                    for _, u in pairs(ups) do
                                        if type(u) == "table" and rawget(u, "_startPlayGateUntil") ~= nil
                                            and rawget(u, "_startPlaySeq") ~= nil then
                                            found = u
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        return found
    end

    local svc = nil
    local function findService()
        if svc and rawget(svc, "_startPlaySeq") ~= nil then return svc end
        svc = nil
        local gc = collectGC()
        if gc then
            for _, o in ipairs(gc) do
                if type(o) == "table" and rawget(o, "_startPlayGateUntil") ~= nil and rawget(o, "_startPlaySeq") ~= nil then
                    svc = o; break
                end
            end
        end
        if not svc then
            svc = findViaModules()
        end
        return svc
    end

    local function pickJudgment()
        local r = {}
        for _, n in ipairs(ORDER) do
            local opt = Options["Rhythm" .. n]
            r[n] = (opt and opt.Value) or 0
        end
        local total = 0
        for _, n in ipairs(ORDER) do total += (r[n] or 0) end
        if total <= 0 then return "PERFECT" end
        local roll = math.random() * total
        local cum = 0
        for _, n in ipairs(ORDER) do
            cum += (r[n] or 0)
            if roll <= cum then return JMAP[n] end
        end
        return "PERFECT"
    end

    local function earlyOffsetFor(judg, W)
        local function band(lo, hi) return (lo + math.random() * math.max(hi - lo, 0)) / 1000 end
        if judg == "PERFECT" then
            return band(0, (W.PERFECT or 43) * 0.8)
        elseif judg == "GOOD" then
            return band((W.PERFECT or 43) + 3, (W.GOOD or 76) * 0.9)
        elseif judg == "OKAY" then
            return band((W.GOOD or 76) + 3, (W.OKAY or 106) * 0.9)
        elseif judg == "BAD" then
            return band((W.OKAY or 106) + 3, (W.BAD or 140) * 0.9)
        end
        return nil
    end

    task.spawn(function()
        elevate()
        while rhythmEngineRunning do
            elevate()
            local rt = Toggles.AutoRhythmToggle
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
                                        elevate()
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

--// ============================ Basketball Auto-Green engine ============================
local bballEngineRunning = false

local function startBasketballEngine()
    if bballEngineRunning then return end
    bballEngineRunning = true

    local DEFAULT_CENTER = 0.76
    local ZERO_CONTEST = function() return 0 end
    local grm = getrawmetatable or (debug and debug.getmetatable)

    local moduleCache, instCache, classCache = nil, nil, nil

    -- getgc(true) is expensive; call it ONLY when we don't already have what we need.
    local function gcScan() return _collectGC() or {} end
    local function hasGCFn()
        return typeof(getgc) == "function"
            or (typeof(getgenv) == "function" and typeof(getgenv().getgc) == "function")
    end

    -- Module + class are module-level tables that never change/GC during play, so they
    -- are scanned for AT MOST once each, then cached forever.
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
                classCache = o; return rawget(o, "_releaseShot")
            end
        end
        return nil
    end

    -- The live green window (center, half-width) for this shot. Reads the distance/contest
    -- zones when available; otherwise the base green center (0.76). The game centers every
    -- zone on 0.76, so the center is always green.
    local function greenWindow(h)
        local center, halfW = DEFAULT_CENTER, 0.03
        local mod = findModule()
        if mod then
            local base = rawget(mod, "ZONES")
            if type(base) == "table" then
                for _, z in ipairs(base) do
                    if z.id == "Perfect" then center = (z.min + z.max) * 0.5 end
                end
            end
            local zones = rawget(h, "_activeZones")
            if type(zones) == "table" then
                local contest = 0
                pcall(function()
                    local c = h:_computeContestPct()
                    if type(c) == "number" then contest = c end
                end)
                local ok, final = pcall(mod.applyContestToZones, zones, contest)
                if ok and type(final) == "table" then zones = final end
                for _, z in ipairs(zones) do
                    if z.id == "Perfect" then
                        center = (z.min + z.max) * 0.5; halfW = (z.max - z.min) * 0.5
                    end
                end
            end
        end
        return center, halfW
    end

    -- Dead-center green power (slightly jittered so it isn't a robotic identical value).
    local function perfectPower(h)
        local center, halfW = greenWindow(h)
        return math.clamp(center + (math.random() - 0.5) * 2 * halfW * 0.55,
            center - halfW * 0.75, center + halfW * 0.75)
    end

    -- Live meter length (seconds) so we know real charge progress; cached via findModule.
    local function getMeter()
        local mod = findModule()
        local m = mod and rawget(mod, "METER_DURATION")
        return (type(m) == "number" and m > 0) and m or 0.6578947368421053
    end

    -- The live handler instance for our character. Uses the cache unless it's stale.
    local function findInstance()
        if instCache and rawget(instCache, "_shootRemote") ~= nil
            and rawget(instCache, "_character") == LocalPlayer.Character then
            return instCache
        end
        instCache = nil
        for _, o in ipairs(gcScan()) do
            if type(o) == "table" and rawget(o, "_shootRemote") ~= nil
                and rawget(o, "_character") == LocalPlayer.Character
                and rawget(o, "_isCharging") ~= nil then -- instance (not the class)
                instCache = o; break
            end
        end
        return instCache
    end

    -- Capture the ORIGINAL _releaseShot to call through. Prefer the instance's metatable
    -- (no extra GC scan); fall back to a one-time class scan on executors without grm.
    local function realReleaseOf(h)
        if typeof(grm) == "function" then
            local ok, mt = pcall(grm, h)
            if ok and type(mt) == "table" then
                local r = rawget(mt, "_releaseShot")
                if typeof(r) == "function" then return r end
                local idx = rawget(mt, "__index")
                if type(idx) == "table" and typeof(rawget(idx, "_releaseShot")) == "function" then
                    return rawget(idx, "_releaseShot")
                end
            end
        end
        return findClassRelease()
    end

    local function setStatus(text)
        local st = Options.BballStatus
        if st then pcall(st.SetText, st, text) end
    end

    -- Install a one-time _releaseShot hook that forces EVERY release (tap or hold, PC or
    -- mobile) to dead-center green. Returns hooked?, statusText.
    local function tryHook()
        local h = findInstance()
        if not h then
            return false, (findModule() and "handler not found -- re-equip" or "module not found (updated?)")
        end
        if rawget(h, "_owehubHooked") then return true, "auto-green active -- shoot as normal" end
        local realRelease = realReleaseOf(h)
        if typeof(realRelease) ~= "function" then return false, "release fn not found" end
        rawset(h, "_owehubHooked", true)
        rawset(h, "_releaseShot", function(self, power)
            local tgg = Toggles.AutoGreenShot
            if tgg and tgg.Value then
                local ignoreDef = Toggles.BballIgnoreDefense and Toggles.BballIgnoreDefense.Value
                if ignoreDef then rawset(self, "_computeContestPct", ZERO_CONTEST) end
                local ok, p = pcall(perfectPower, self)
                if ignoreDef then rawset(self, "_computeContestPct", nil) end
                if ok and type(p) == "number" then power = p end
            end
            return realRelease(self, power)
        end)
        return true, "hooked -- every shot lands green"
    end

    local lastCharge = nil
    local chargeCenterFor, releaseAt = nil, DEFAULT_CENTER

    task.spawn(function()
        while bballEngineRunning do
            local tg = Toggles.AutoGreenShot
            if not tg or not tg.Value then
                setStatus("idle (toggle Auto Green Shot on)")
                task.wait(0.6)
            elseif not hasGCFn() then
                setStatus("unsupported: this executor has no getgc")
                task.wait(2)
            else
                local ch = LocalPlayer.Character
                if not ch or ch:GetAttribute("ItemEquipped") ~= "Basketball" then
                    instCache = nil -- drop the handler cache so re-equip re-finds cleanly
                    setStatus("equip a basketball to start")
                    task.wait(0.6)
                else
                    -- Once hooked, tryHook short-circuits with no GC scan.
                    local hooked, msg = tryHook()
                    local h = hooked and instCache
                    if h and rawget(h, "_isCharging") == true and rawget(h, "_targetRim") ~= nil then
                        -- Auto-release: fire the shot the instant the meter reaches the
                        -- green center so the bar visually STOPS in green (instead of you
                        -- holding it to the end). The hook still forces a perfect result.
                        local cs = rawget(h, "_chargeStart")
                        if type(cs) == "number" then
                            -- Compute the green center once per charge (not per frame),
                            -- since _computeContestPct raycasts.
                            if cs ~= chargeCenterFor then
                                chargeCenterFor = cs
                                releaseAt = select(1, greenWindow(h))
                            end
                            if cs ~= lastCharge then
                                local power = (tick() - cs) / getMeter()
                                if power >= releaseAt then
                                    lastCharge = cs
                                    pcall(function() h:_releaseShot(power) end)
                                    setStatus("shot released in green")
                                end
                            end
                        end
                        RunService.Heartbeat:Wait() -- tight loop only while charging
                    else
                        setStatus(msg)
                        task.wait(hooked and 0.15 or 0.4)
                    end
                end
            end
        end
    end)
end

startBasketballEngine()

--// ============================ Enemy ESP & Chams ============================
local espAlive = true
local espObjects = {}
local chamsObjects = {}

local espParent = (typeof(gethui) == "function" and gethui())
    or (typeof(get_hidden_gui) == "function" and get_hidden_gui())
    or game:GetService("CoreGui")

local function makeESP(player, head)
    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_" .. player.Name
    bb.Size = UDim2.new(0, 200, 0, 42)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.ClipsDescendants = false
    bb.Adornee = head
    bb.Parent = espParent

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.new(1, 0, 1, 0)
    text.Font = Enum.Font.Gotham
    text.TextSize = 12
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextStrokeTransparency = 0.5
    text.TextYAlignment = Enum.TextYAlignment.Bottom
    text.RichText = true
    text.Text = player.DisplayName or player.Name
    text.Parent = bb

    espObjects[player] = { gui = bb, text = text }
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

--// ============================ M2 (Heavy) Cooldown HUD ============================
-- The game exposes M2Cooldown as a boolean attribute only, so we time the countdown
-- ourselves from the style's M2 cooldown duration (CombatConfig.GetStyleM2Cooldown)
-- when the attribute flips on. Display auto-detects the platform:
--   * Mobile: draggable on-screen text (mobile has no cooldown feedback at all)
--   * PC: the countdown is patched into the game's own "Heavy Attack" controls hint
--     (falls back to the text display if that hint isn't found)
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

    -- Draggable (touch + mouse) so it doesn't cover a button.
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
        if CombatConfig and typeof(CombatConfig.GetStyleM2Cooldown) == "function" and typeof(style) == "string" then
            local ok, v = pcall(CombatConfig.GetStyleM2Cooldown, string.lower(style))
            if ok and typeof(v) == "number" and v > 0 then return v end
        end
        return 12
    end

    -- Watch M2Cooldown flips to (re)start the local timer.
    local function bindChar(ch)
        if not ch then return end
        local function onCd()
            if ch:GetAttribute("M2Cooldown") == true then
                cdStart = os.clock()
                cdDur = styleCooldown()
            end
        end
        pcall(function() ch:GetAttributeChangedSignal("M2Cooldown"):Connect(onCd) end)
        onCd()
    end
    bindChar(LocalPlayer.Character)
    LocalPlayer.CharacterAdded:Connect(bindChar)

    -- PC path: patch the countdown into the game's "Heavy Attack" controls hint.
    local heavyLabel, heavyOrig = nil, nil
    local function findHeavyAttackLabel()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local controls = pg and pg:FindFirstChild("ControlsGui")
        local row2 = controls and controls:FindFirstChild("ControlsContainer")
            and controls.ControlsContainer:FindFirstChild("Row2")
        if not row2 then return nil end
        -- Row2 has 3 TextLabels: bullet, "R", "Heavy Attack"
        for _, c in ipairs(row2:GetChildren()) do
            if c:IsA("TextLabel") and c.Text and c.Text:lower():find("heavy") then
                return c
            end
        end
        return nil
    end
    local function restoreHeavyLabel()
        if heavyLabel and heavyLabel.Parent and heavyOrig then
            pcall(function() heavyLabel.Text = heavyOrig end)
        end
        heavyLabel, heavyOrig = nil, nil
    end

    task.spawn(function()
        while m2HudAlive do
            local ch = LocalPlayer.Character
            local tg = Toggles.HudM2Cooldown
            -- The game only builds the controls-hint rows (and you can only M2) while
            -- combat is EQUIPPED - show nothing at all when holstered, so the floating
            -- text never appears alongside/instead of the game's own hint.
            local equipped = ch and ch:GetAttribute("Equip") == true
            if not tg or not tg.Value or not equipped then
                if frame.Visible then frame.Visible = false end
                if heavyLabel then restoreHeavyLabel() end
                task.wait(equipped and 0.3 or 0.15)
            else
                local onCd = ch:GetAttribute("M2Cooldown") == true
                local remaining = onCd and math.max(cdDur - (os.clock() - cdStart), 0) or 0

                -- PC: prefer the game's own hint label; mobile (or hint missing): text display
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
        end
        restoreHeavyLabel() -- unload: put the game's hint text back
    end)
end

--// ============================ Auto Respawn ============================
-- Drive the game's OWN respawn method (SpawnServiceClient:_doRespawn) instead of
-- firing the SpawnRequest remote raw. _doRespawn fires the remote AND runs the death
-- overlay teardown (_completeRespawnTransition -> _clearEffects -> fade out the dark
-- _main/_light frames), so there's no lingering grey/black screen after spawning.
local autoRespawnConn = nil
local _spawnSvcCache = nil

local function findSpawnService()
    -- The instance persists (singleton), so a valid cache with _spawnRemote is reusable.
    if _spawnSvcCache and rawget(_spawnSvcCache, "_spawnRemote") ~= nil then
        return _spawnSvcCache
    end
    _spawnSvcCache = nil
    if typeof(getgc) ~= "function" then return nil end
    local grm = getrawmetatable or (debug and debug.getmetatable)
    pcall(function()
        -- The methods (_doRespawn etc.) live on the CLASS table; _spawnRemote lives on
        -- the INSTANCE. Find the class first, then the instance whose metatable is it.
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
                    -- Mobile fallback when metatables can't be read: signature match.
                    _spawnSvcCache = o; break
                end
            end
        end
    end)
    return _spawnSvcCache
end

startAutoRespawn = function()
    if autoRespawnConn then return end
    autoRespawnConn = RunService.Heartbeat:Connect(function()
        local dead = LocalPlayer:GetAttribute("Dead") == true
        local char = LocalPlayer.Character
        if not dead and char and char:GetAttribute("Dead") == true then dead = true end
        if not dead then return end

        local svc = findSpawnService()
        if svc then
            -- _doRespawn no-ops while a respawn is already in flight, so calling it
            -- each frame is safe; it handles the remote + clean overlay teardown.
            pcall(function() svc:_doRespawn() end)
        else
            -- Fallback (no getgc / service not found): raw remote. Respawns but the
            -- overlay teardown is up to the game; also hide the death UI if present.
            local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local sr = Remotes and Remotes:FindFirstChild("SpawnRequest")
            if sr then pcall(function() sr:FireServer() end) end
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            local dui = pg and pg:FindFirstChild("DeathUI")
            if dui and dui.Enabled then dui.Enabled = false end
        end
    end)
end
stopAutoRespawn = function()
    if autoRespawnConn then
        autoRespawnConn:Disconnect()
        autoRespawnConn = nil
    end
end

--// ============================ Consolidated Attribute Stripping ============================
-- One Heartbeat loop for NoStun/NoDodgeCD/InfStamina/NoRagdoll/NoBlur. MUST be declared
-- before the start/stop functions below that reference it - a later declaration makes
-- those functions compile against a nil global ("attempt to index nil with 'noRagdoll'").
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

local _attrStripConn = nil
local _attrStripActive = {
    noStun = false,
    noDodgeCD = false,
    infStamina = false,
    noRagdoll = false,
    noBlur = false,
}
local _stunAttrs = { "Stunned", "CantAnything", "CombatAttacking", "CombatRecovery" }
local _ragdollAttrs = { "Ragdoll", "Downed", "RespawnLocked" }

local function _updateAttrStripConn()
    local anyActive = false
    for _, v in pairs(_attrStripActive) do
        if v then
            anyActive = true; break
        end
    end
    if anyActive and not _attrStripConn then
        _attrStripConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end

            if _attrStripActive.noStun then
                for _, attr in ipairs(_stunAttrs) do
                    if char:GetAttribute(attr) == true then
                        char:SetAttribute(attr, nil)
                    end
                end
            end

            if _attrStripActive.noDodgeCD then
                if char:GetAttribute("IFRAMECD") == true then
                    char:SetAttribute("IFRAMECD", nil)
                end
                if char:GetAttribute("EvasiveCooldownRemaining") ~= nil then
                    char:SetAttribute("EvasiveCooldownRemaining", nil)
                end
            end

            if _attrStripActive.infStamina then
                local cur = char:GetAttribute("Stamina")
                if cur ~= 100 then
                    char:SetAttribute("Stamina", 100)
                end
            end

            if _attrStripActive.noRagdoll then
                for _, attr in ipairs(_ragdollAttrs) do
                    if char:GetAttribute(attr) == true then
                        char:SetAttribute(attr, nil)
                    end
                end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                end
            end

            if _attrStripActive.noBlur then
                removeBlurs()
            end
        end)
    elseif not anyActive and _attrStripConn then
        _attrStripConn:Disconnect()
        _attrStripConn = nil
    end
end

--// ============================ No Ragdoll ============================
startNoRagdoll = function()
    _attrStripActive.noRagdoll = true
    _updateAttrStripConn()
end
stopNoRagdoll = function()
    _attrStripActive.noRagdoll = false
    _updateAttrStripConn()
end

--// ============================ No Blur ============================
startNoBlur = function()
    _attrStripActive.noBlur = true
    _updateAttrStripConn()
end
stopNoBlur = function()
    _attrStripActive.noBlur = false
    _updateAttrStripConn()
end

--// ============================ Follow Player (teleport loop) ============================
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

--// ============================ No Parry Cooldown ============================
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

--// ============================ Auto Sprint ============================
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
    _isSprintingActive = false
    autoSprintConn = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        local isMoving = hum.MoveDirection.Magnitude > 0
        if isMoving and not _isSprintingActive then
            _isSprintingActive = true
            pcall(function()
                local VIM = game:GetService("VirtualInputManager")
                VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
            end)
            triggerMobileSprintBtn(true)
        elseif not isMoving and _isSprintingActive then
            _isSprintingActive = false
            pcall(function()
                local VIM = game:GetService("VirtualInputManager")
                VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
            end)
            triggerMobileSprintBtn(false)
        end
    end)
end

stopAutoSprint = function()
    if autoSprintConn then
        autoSprintConn:Disconnect()
        autoSprintConn = nil
    end
    if _isSprintingActive then
        _isSprintingActive = false
        pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
        triggerMobileSprintBtn(false)
    end
end

--// ============================ Infinite Stamina ============================
startInfStamina = function()
    _attrStripActive.infStamina = true
    _updateAttrStripConn()
end
stopInfStamina = function()
    _attrStripActive.infStamina = false
    _updateAttrStripConn()
end

--// ============================ No Stun ============================
startNoStun = function()
    _attrStripActive.noStun = true
    _updateAttrStripConn()
end
stopNoStun = function()
    _attrStripActive.noStun = false
    _updateAttrStripConn()
end

--// ============================ No Dodge Cooldown ============================
startNoDodgeCD = function()
    _attrStripActive.noDodgeCD = true
    _updateAttrStripConn()
end
stopNoDodgeCD = function()
    _attrStripActive.noDodgeCD = false
    _updateAttrStripConn()
end

--// ============================ Noclip ============================
local noclipConn = nil
startNoclip = function()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
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
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" or part.Name == "Torso" or part.Name == "UpperTorso" or part.Name == "LowerTorso" then
                    part.CanCollide = true
                end
            end
        end
    end
end

--// ============================ Unload ============================
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
    if _visUnload then _visUnload()
    if _disableLowGraphics then _disableLowGraphics() end end
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

--// ============================ Init ============================
if isMobile then
    local sg = Instance.new("ScreenGui")
    mobileToggleGui = sg
    sg.Name = "OweHubMobileToggle"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 99999
    pcall(function() sg.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 45, 0, 45)
    btn.Position = UDim2.new(0.5, -22, 0, 10)
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    btn.BorderColor3 = Color3.fromRGB(60, 60, 60)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = "OweHub"
    btn.Font = Enum.Font.Code
    btn.TextSize = 10
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    btn.Parent = sg

    btn.MouseButton1Click:Connect(function()
        Library:Toggle()
    end)

    local dragBtn, dStart, dPos
    btn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then
            dragBtn = true; dStart = inp.Position; dPos = btn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragBtn and inp.UserInputType == Enum.UserInputType.Touch then
            local delta = inp.Position - dStart
            btn.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + delta.X, dPos.Y.Scale, dPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then dragBtn = false end
    end)
end

-- Load the autoload config LAST: the UI fires every toggle's callback during Load,
-- and every engine function those callbacks reference is assigned by this point.
pcall(function() SaveManager:LoadAutoloadConfig() end)

-- A saved config could have re-enabled a ban-risky toggle; enforce Safe Mode after load.
task.defer(function()
    if Toggles.SafeMode and Toggles.SafeMode.Value and SAFE_BLOCKED then
        for key in pairs(SAFE_BLOCKED) do
            local t = Toggles[key]
            if t and t.Value then pcall(function() t:SetValue(false) end) end
        end
    end
end)

Library:Notify({ Title = "FoyiHub", Description =
"Loaded: RightShift toggles the UI (or tap the OweHub button on mobile)", Time = 4 })