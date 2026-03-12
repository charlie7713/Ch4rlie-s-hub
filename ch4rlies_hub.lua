-- ch4rlies hub | Tower of Hell | v8.0
-- 100% ASCII | Lua 5.1 | Full rewrite

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local VirtualUser      = game:GetService("VirtualUser")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================
-- STATE
-- ============================================================
local _conns       = {}
local _slots       = {nil,nil,nil,nil,nil}
local _lastSafe    = nil
local _lastJump    = 0
local _killCache   = {}
local _espHL       = {}
local _killHL      = {}
local _safeHL      = {}
local _wallOrig    = {}
local _frozenParts = {}   -- parts detected as actually moving, locked by us
local _climbActive = false
local _godSafePos  = nil
local _hooksInstalled = false
local _rainbowOn   = false
local _origColors  = {}
local _muteOrig    = {}
local _muted       = false

-- Tower of Hell world constants (measured from game source)
-- The tower is centred at roughly X=0, Z=0 and is ~110 studs wide.
-- Anything outside this radius is outside the tower / in the void zone.
local TOH_CENTER_X  =  0
local TOH_CENTER_Z  =  0
local TOH_RADIUS    = 80   -- parts within this horizontal radius are "in the tower"
local TOH_BASE_Y    =  0   -- floor of the tower
local SECTION_H     = 100  -- each section is ~100 studs tall

local cfg = {
    WalkSpeed   = 16,
    JumpPower   = 50,
    FlySpeed    = 55,
    GravMult    = 0.35,
    InfJump     = false,
    Fly         = false,
    Noclip      = false,
    GodMode     = false,
    AntiVoid    = false,
    AntiRagdoll = false,
    LowGravity  = false,
    SlowFall    = false,
    BunnyHop    = false,
    AutoClimb   = false,
    FreezeObst  = false,
    KillESP     = false,
    SafeESP     = false,
    Fullbright  = false,
    PlayerESP   = false,
    AntiAFK     = false,
    WallTransp  = false,
    Rainbow     = false,
    Mute        = false,
    AutoRespawn = false,
}

local DEFAULT_GRAVITY = 196.2

-- ============================================================
-- HELPERS
-- ============================================================
local function Char()  return LP.Character end
local function HRP()   local c = Char() return c and c:FindFirstChild("HumanoidRootPart") end
local function Hum()   local c = Char() return c and c:FindFirstChildOfClass("Humanoid") end
local function Conn(k) if _conns[k] then _conns[k]:Disconnect() _conns[k] = nil end end
local function Notify(t, c, d)
    Rayfield:Notify({Title = t, Content = c, Duration = d or 3, Image = 4483362458})
end

-- Is a position inside the tower's horizontal footprint?
local function InTower(pos)
    local dx = pos.X - TOH_CENTER_X
    local dz = pos.Z - TOH_CENTER_Z
    return (dx*dx + dz*dz) <= (TOH_RADIUS * TOH_RADIUS)
end

-- ============================================================
-- KILL PART DETECTION
-- ============================================================
local KILL_KW = {
    "kill","lava","death","spike","acid","saw",
    "laser","void","fire","toxic","drown","blade","harm"
}
local function IsKillPart(p)
    local n = p.Name:lower()
    for _, kw in ipairs(KILL_KW) do
        if n:find(kw) then return true end
    end
    return false
end

-- ============================================================
-- BYPASSES
-- ============================================================
local function NullifyKick()
    pcall(function()
        local ps = LP:WaitForChild("PlayerScripts", 5)
        if not ps then return end
        local ls = ps:WaitForChild("LocalScript", 5)
        if not ls then return end
        local env = getsenv(ls)
        if env and type(env) == "table" then
            env.kick = function() end  env.Kick = function() end
            env.kickPlayer = function() end  env.KickPlayer = function() end
        end
    end)
end

local function InstallHooks()
    if _hooksInstalled then return end
    _hooksInstalled = true
    pcall(function()
        local mt       = getrawmetatable(game)
        local old_nc   = mt.__namecall
        local old_ni   = mt.__newindex
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if m == "Kick" and self == LP then return end
            if cfg.GodMode and m == "TakeDamage" then
                local h = Hum()
                if h and self == h then return end
            end
            return old_nc(self, ...)
        end)
        mt.__newindex = newcclosure(function(self, key, val)
            if cfg.GodMode and key == "Health" then
                local h = Hum()
                if h and self == h and type(val) == "number" and val < h.MaxHealth * 0.5 then
                    return
                end
            end
            return old_ni(self, key, val)
        end)
        setreadonly(mt, true)
    end)
end

local function DisableKillScript(char)
    char = char or Char()
    if not char then return end
    pcall(function()
        local ks = char:FindFirstChild("KillScript") or char:WaitForChild("KillScript", 3)
        if ks then ks.Disabled = true end
    end)
    pcall(function()
        for _, v in ipairs(char:GetDescendants()) do
            if (v:IsA("LocalScript") or v:IsA("Script")) then
                local n = v.Name:lower()
                if n:find("kill") or n:find("death") or n:find("damage") then
                    v.Disabled = true
                end
            end
        end
    end)
end

local function StartMovementGuard()
    Conn("moveguard")
    _conns["moveguard"] = RunService.Heartbeat:Connect(function()
        local h = Hum()
        if not h then return end
        if h.WalkSpeed ~= cfg.WalkSpeed then
            pcall(function() sethiddenproperty(h, "WalkSpeed", cfg.WalkSpeed) end)
            h.WalkSpeed = cfg.WalkSpeed
        end
        if h.JumpPower ~= cfg.JumpPower then
            pcall(function() sethiddenproperty(h, "JumpPower", cfg.JumpPower) end)
            h.JumpPower = cfg.JumpPower
        end
    end)
end

-- ============================================================
-- MOVEMENT
-- ============================================================
local function ApplySpeed(v)
    cfg.WalkSpeed = v
    local h = Hum()
    if not h then return end
    pcall(function() sethiddenproperty(h, "WalkSpeed", v) end)
    h.WalkSpeed = v
end

local function ApplyJump(v)
    cfg.JumpPower = v
    local h = Hum()
    if not h then return end
    pcall(function() sethiddenproperty(h, "JumpPower", v) end)
    h.JumpPower = v
end

local function SetInfJump(v)
    cfg.InfJump = v
    Conn("infjump")
    if not v then return end
    _conns["infjump"] = UserInputService.JumpRequest:Connect(function()
        local h = Hum()
        if not h then return end
        local now = tick()
        if (now - _lastJump) < 0.35 then return end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping then
            _lastJump = now
            local prev = workspace.Gravity
            workspace.Gravity = 0.1
            task.wait(0.02)
            h:ChangeState(Enum.HumanoidStateType.Jumping)
            task.wait(0.12)
            if not cfg.LowGravity then workspace.Gravity = prev end
        end
    end)
end

local function SetFly(v)
    cfg.Fly = v
    Conn("fly")
    if not v then return end
    _conns["fly"] = RunService.RenderStepped:Connect(function()
        local hrp = HRP()
        if not hrp then return end
        local dir = Vector3.new(0, 0, 0)
        local cf  = Camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W)         then dir = dir + cf.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)         then dir = dir - cf.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)         then dir = dir - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)         then dir = dir + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir = dir + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0,1,0) end
        hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
        if dir.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + dir.Unit * (cfg.FlySpeed * 0.016)
        end
    end)
end

local function SetNoclip(v)
    cfg.Noclip = v
    Conn("noclip")
    if v then
        _conns["noclip"] = RunService.Stepped:Connect(function()
            local c = Char()
            if not c then return end
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    else
        local c = Char()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end
end

-- ============================================================
-- GOD MODE (4 layers)
-- ============================================================
local function SetGodMode(v)
    cfg.GodMode = v
    Conn("god_scan") Conn("god_hb") Conn("god_rs") Conn("god_hc") Conn("god_died")

    if v then
        InstallHooks()
        DisableKillScript()

        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and IsKillPart(obj) then
                pcall(function() obj.CanTouch = false _killCache[obj] = true end)
            end
        end
        _conns["god_scan"] = workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("BasePart") and IsKillPart(obj) then
                pcall(function() obj.CanTouch = false _killCache[obj] = true end)
            end
        end)
        _conns["god_hb"] = RunService.Heartbeat:Connect(function()
            for p, _ in pairs(_killCache) do
                if p and p.Parent then pcall(function() p.CanTouch = false end)
                else _killCache[p] = nil end
            end
        end)
        _conns["god_rs"] = RunService.RenderStepped:Connect(function()
            local hrp = HRP() local h = Hum()
            if not hrp or not h then return end
            if hrp.Position.Y > -30 then _godSafePos = hrp.CFrame end
            if h.Health < h.MaxHealth then
                pcall(function() sethiddenproperty(h, "Health", h.MaxHealth) end)
                pcall(function() h.Health = h.MaxHealth end)
            end
        end)
        local function HookHealth(char)
            local h = char and char:FindFirstChildOfClass("Humanoid")
            if not h then return end
            Conn("god_hc")
            _conns["god_hc"] = h.HealthChanged:Connect(function(hp)
                if not cfg.GodMode or hp >= h.MaxHealth then return end
                pcall(function() sethiddenproperty(h, "Health", h.MaxHealth) end)
                pcall(function() h.Health = h.MaxHealth end)
            end)
            Conn("god_died")
            _conns["god_died"] = h.Died:Connect(function()
                if not cfg.GodMode then return end
                task.wait(0.05)
                local h2 = Hum() local hrp2 = HRP()
                if h2 and hrp2 then
                    pcall(function() sethiddenproperty(h2, "Health", h2.MaxHealth) end)
                    pcall(function() h2.Health = h2.MaxHealth end)
                    if _godSafePos then hrp2.CFrame = _godSafePos end
                end
            end)
        end
        HookHealth(Char())
    else
        for p, _ in pairs(_killCache) do
            if p and p.Parent then pcall(function() p.CanTouch = true end) end
        end
        _killCache = {}
    end
end

-- ============================================================
-- GRAVITY / SLOW FALL / BHOP / AUTO CLIMB
-- ============================================================
local function SetLowGravity(v)
    cfg.LowGravity = v
    workspace.Gravity = v and (DEFAULT_GRAVITY * cfg.GravMult) or DEFAULT_GRAVITY
end

local function SetSlowFall(v)
    cfg.SlowFall = v
    Conn("slowfall")
    if not v then return end
    _conns["slowfall"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if not hrp then return end
        local vel = hrp.AssemblyLinearVelocity
        if vel.Y < -20 then hrp.AssemblyLinearVelocity = Vector3.new(vel.X, -20, vel.Z) end
    end)
end

local function SetBunnyHop(v)
    cfg.BunnyHop = v
    Conn("bhop")
    if not v then return end
    _conns["bhop"] = RunService.Heartbeat:Connect(function()
        local h = Hum()
        if not h then return end
        if h:GetState() == Enum.HumanoidStateType.Landed then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

local function SetAutoClimb(v)
    cfg.AutoClimb = v
    Conn("autoclimb")
    if v then
        local jt = 0
        _conns["autoclimb"] = RunService.Heartbeat:Connect(function()
            local hrp = HRP() local h = Hum()
            if not hrp or not h then return end
            local fwd = hrp.CFrame.LookVector
            h:Move(Vector3.new(fwd.X, 0, fwd.Z), false)
            local now = tick()
            local s   = h:GetState()
            if (now - jt) > 0.55
            and s ~= Enum.HumanoidStateType.Jumping
            and s ~= Enum.HumanoidStateType.Freefall then
                jt = now
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    else
        local h = Hum()
        if h then h:Move(Vector3.new(0,0,0), false) end
    end
end

-- ============================================================
-- ANTI-VOID / ANTI-RAGDOLL / ANTI-AFK
-- ============================================================
local function SetAntiVoid(v)
    cfg.AntiVoid = v
    Conn("av_save") Conn("av_check")
    if not v then return end
    _conns["av_save"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y > -30 then _lastSafe = hrp.CFrame end
    end)
    _conns["av_check"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y < -80 and _lastSafe then hrp.CFrame = _lastSafe end
    end)
end

local function SetAntiRagdoll(v)
    cfg.AntiRagdoll = v
    Conn("ragdoll")
    if not v then return end
    _conns["ragdoll"] = RunService.Stepped:Connect(function()
        local h = Hum()
        if not h then return end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown then
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function SetAntiAFK(v)
    cfg.AntiAFK = v
    Conn("afk")
    if not v then return end
    _conns["afk"] = LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
    end)
end

-- ============================================================
-- AUTO RESPAWN (when you fall below -60 Y, respawn yourself)
-- ============================================================
local function SetAutoRespawn(v)
    cfg.AutoRespawn = v
    Conn("autorsp")
    if not v then return end
    _conns["autorsp"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y < -60 then
            task.wait(0.2)
            LP:LoadCharacter()
        end
    end)
end

-- ============================================================
-- RAINBOW CHARACTER
-- ============================================================
local _rainbowTick = 0
local function SetRainbow(v)
    cfg.Rainbow = v
    _rainbowOn  = v
    Conn("rainbow")
    if v then
        local c = Char()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                    _origColors[p] = p.Color
                end
            end
        end
        _conns["rainbow"] = RunService.Heartbeat:Connect(function()
            _rainbowTick = (_rainbowTick + 0.8) % 360
            local col = Color3.fromHSV(_rainbowTick / 360, 1, 1)
            local ch  = Char()
            if not ch then return end
            for _, p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                    pcall(function() p.Color = col end)
                end
            end
        end)
    else
        local c = Char()
        if c then
            for p, col in pairs(_origColors) do
                if p and p.Parent then pcall(function() p.Color = col end) end
            end
        end
        _origColors = {}
    end
end

-- ============================================================
-- MUTE GAME
-- ============================================================
local function SetMute(v)
    cfg.Mute = v
    _muted   = v
    if v then
        for _, s in ipairs(workspace:GetDescendants()) do
            if s:IsA("Sound") then
                _muteOrig[s] = s.Volume
                pcall(function() s.Volume = 0 end)
            end
        end
        for _, s in ipairs(SoundService:GetDescendants()) do
            if s:IsA("Sound") then
                _muteOrig[s] = s.Volume
                pcall(function() s.Volume = 0 end)
            end
        end
    else
        for s, vol in pairs(_muteOrig) do
            if s and s.Parent then pcall(function() s.Volume = vol end) end
        end
        _muteOrig = {}
    end
end

-- ============================================================
-- WALL TRANSPARENCY
-- ============================================================
local function SetWallTransp(v)
    cfg.WallTransp = v
    local ign = Char()
    if v then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
            and (not ign or not obj:IsDescendantOf(ign))
            and not IsKillPart(obj)
            and (obj.Size.X < 4 or obj.Size.Z < 4) then
                pcall(function()
                    _wallOrig[obj] = obj.Transparency
                    obj.Transparency = 0.78
                end)
            end
        end
    else
        for obj, t in pairs(_wallOrig) do
            if obj and obj.Parent then pcall(function() obj.Transparency = t end) end
        end
        _wallOrig = {}
    end
end

-- ============================================================
-- FREEZE MOVING PARTS (detect by actual motion, not by name)
-- ============================================================
-- Scans workspace for parts that are visibly moving by comparing
-- their CFrame between frames. Any part that moves > 0.15 studs
-- per heartbeat is flagged as a moving obstacle and locked.
-- ============================================================
local _prevFrameCF  = {}   -- CFrame snapshot from previous frame
local _freezeActive = false

local function SetFreezeObst(v)
    cfg.FreezeObst = v
    Conn("freeze_scan")
    Conn("freeze_lock")
    _frozenParts = {}
    _prevFrameCF = {}

    if not v then
        Notify("ch4rlies hub", "Obstacles unfrozen.", 2)
        return
    end

    local ign = Char()

    -- Phase 1: snapshot all part CFrames this frame
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart")
        and (not ign or not obj:IsDescendantOf(ign))
        and not obj.Anchored then
            _prevFrameCF[obj] = obj.CFrame
        end
    end

    -- Phase 2: next frame, compare - anything that moved is a moving part
    _conns["freeze_scan"] = RunService.Heartbeat:Connect(function()
        if not cfg.FreezeObst then return end
        local ign2 = Char()
        for obj, prevCF in pairs(_prevFrameCF) do
            if obj and obj.Parent and (not ign2 or not obj:IsDescendantOf(ign2)) then
                local moved = (obj.Position - prevCF.Position).Magnitude
                if moved > 0.12 and not _frozenParts[obj] then
                    _frozenParts[obj] = obj.CFrame  -- lock it at current position
                end
                _prevFrameCF[obj] = obj.CFrame
            else
                _prevFrameCF[obj] = nil
            end
        end
    end)

    -- Phase 3: every heartbeat, re-apply locked CFrames
    _conns["freeze_lock"] = RunService.Heartbeat:Connect(function()
        if not cfg.FreezeObst then return end
        for obj, cf in pairs(_frozenParts) do
            if obj and obj.Parent then
                pcall(function()
                    obj.CFrame = cf
                    obj.AssemblyLinearVelocity  = Vector3.new(0,0,0)
                    obj.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end)
            else
                _frozenParts[obj] = nil
            end
        end
    end)

    -- Give the scanner one second to detect movers, then notify count
    task.spawn(function()
        task.wait(1.5)
        local n = 0
        for _ in pairs(_frozenParts) do n = n + 1 end
        Notify("ch4rlies hub", "Frozen " .. n .. " moving parts!", 3)
    end)
end

-- ============================================================
-- ESP
-- ============================================================
local function ClearKillESP()
    for _, h in pairs(_killHL) do if h and h.Parent then h:Destroy() end end
    _killHL = {}
end
local function SetKillESP(v)
    cfg.KillESP = v
    ClearKillESP()
    Conn("killesp")
    if not v then return end
    local function Tag(obj)
        if obj:IsA("BasePart") and IsKillPart(obj) then
            pcall(function()
                local h = Instance.new("SelectionBox")
                h.Adornee = obj h.Color3 = Color3.fromRGB(255,30,30)
                h.LineThickness = 0.04 h.SurfaceTransparency = 0.7
                h.SurfaceColor3 = Color3.fromRGB(255,30,30) h.Parent = workspace
                _killHL[obj] = h
            end)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do Tag(obj) end
    _conns["killesp"] = workspace.DescendantAdded:Connect(Tag)
end

local function ClearSafeESP()
    for _, h in pairs(_safeHL) do if h and h.Parent then h:Destroy() end end
    _safeHL = {}
end
local function SetSafeESP(v)
    cfg.SafeESP = v
    ClearSafeESP()
    if not v then return end
    local ign = Char()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (not ign or not obj:IsDescendantOf(ign))
        and not IsKillPart(obj) and obj.Size.X > 2 and obj.Size.Z > 2 then
            pcall(function()
                local h = Instance.new("SelectionBox")
                h.Adornee = obj h.Color3 = Color3.fromRGB(0,200,80)
                h.LineThickness = 0.03 h.SurfaceTransparency = 0.85
                h.SurfaceColor3 = Color3.fromRGB(0,200,80) h.Parent = workspace
                _safeHL[obj] = h
            end)
        end
    end
end

local function SetFullbright(v)
    local L = workspace.Lighting
    if v then
        L.Brightness = 2 L.ClockTime = 14 L.FogEnd = 100000
        L.GlobalShadows = false
        L.Ambient = Color3.fromRGB(255,255,255)
        L.OutdoorAmbient = Color3.fromRGB(255,255,255)
    else
        L.Brightness = 1 L.ClockTime = 14 L.FogEnd = 100000
        L.GlobalShadows = true
        L.Ambient = Color3.fromRGB(127,127,127)
        L.OutdoorAmbient = Color3.fromRGB(127,127,127)
    end
end

local function ClearESP()
    for _, h in pairs(_espHL) do if h and h.Parent then h:Destroy() end end
    _espHL = {}
end
local function SetPlayerESP(v)
    cfg.PlayerESP = v
    ClearESP()
    Conn("esp_a") Conn("esp_r")
    if not v then return end
    local function Add(p)
        if p == LP then return end
        task.spawn(function()
            local c = p.Character or p.CharacterAdded:Wait()
            if not c then return end
            local h = Instance.new("Highlight")
            h.FillColor = Color3.fromRGB(0,150,255)
            h.OutlineColor = Color3.fromRGB(255,255,255)
            h.FillTransparency = 0.45 h.Parent = c
            _espHL[p.Name] = h
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do Add(p) end
    _conns["esp_a"] = Players.PlayerAdded:Connect(Add)
    _conns["esp_r"] = Players.PlayerRemoving:Connect(function(p)
        if _espHL[p.Name] then _espHL[p.Name]:Destroy() _espHL[p.Name] = nil end
    end)
end

-- ============================================================
-- MAP HELPERS
-- InTowerPart: returns true for BaseParts that are inside the
-- tower's horizontal footprint, are walkable (flat-ish, big
-- enough), and are not kill parts.
-- ============================================================
local function IsFloorPart(obj)
    if not obj:IsA("BasePart") then return false end
    if IsKillPart(obj) then return false end
    local ign = Char()
    if ign and obj:IsDescendantOf(ign) then return false end
    -- Must be within tower bounds
    if not InTower(obj.Position) then return false end
    -- Must be a reasonably large horizontal surface (section floors)
    -- Size: X>=6, Z>=6, and not super tall (not a wall)
    if obj.Size.X < 6 or obj.Size.Z < 6 then return false end
    -- Above the base
    if obj.Position.Y < TOH_BASE_Y then return false end
    return true
end

-- ============================================================
-- FIND TOP
-- Finds the highest walkable floor part inside the tower.
-- ============================================================
local function FindTop()
    local best   = nil
    local bestY  = -math.huge

    -- First pass: look for parts literally named "Finish"
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if (n == "finish" or n == "goal" or n == "win") and InTower(obj.Position) then
                local sy = obj.Position.Y + obj.Size.Y / 2
                if sy > bestY then bestY = sy best = obj end
            end
        end
    end

    -- Second pass: highest floor part inside tower bounds
    if not best then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if IsFloorPart(obj) then
                local sy = obj.Position.Y + obj.Size.Y / 2
                if sy > bestY then bestY = sy best = obj end
            end
        end
    end

    return best
end

-- ============================================================
-- FIND NEXT SECTION FLOOR
-- Returns the floor of the nearest section above the player.
-- "Section floor" = a large (>=8x8) flat part, inside tower
-- bounds, at least 8 studs above current position.
-- To avoid picking tiny decorations, minimum size is strict.
-- ============================================================
local function FindNextSection()
    local hrp = HRP()
    if not hrp then return nil end
    local currentY = hrp.Position.Y
    local best     = nil
    local bestY    = math.huge

    for _, obj in ipairs(workspace:GetDescendants()) do
        if IsFloorPart(obj) and obj.Size.X >= 8 and obj.Size.Z >= 8 then
            local surfTop = obj.Position.Y + obj.Size.Y / 2
            -- Must be meaningfully above us (at least one body height above)
            -- and the closest one so we skip exactly one section
            if surfTop > currentY + 8 and surfTop < bestY then
                bestY = surfTop
                best  = obj
            end
        end
    end

    return best
end

-- ============================================================
-- RESTORE CANCOLLIDE so finish Touched fires -> coins
-- ============================================================
local function RestoreForCoins()
    local c = Char()
    if c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
    task.wait(0.8)
    if cfg.Noclip then
        local c2 = Char()
        if c2 then
            for _, p in ipairs(c2:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end

-- ============================================================
-- 3-PHASE CLIMB (Rise -> Cross -> Land)
-- Speed: 5 studs per 0.1s = 50 studs/sec
-- Press button again to cancel mid-climb.
-- ============================================================
local STEP  = 5
local DELAY = 0.1

local function StepPath(fromPos, toPos)
    local diff  = toPos - fromPos
    local dist  = diff.Magnitude
    if dist < 0.5 then return end
    local steps = math.ceil(dist / STEP)
    for i = 1, steps do
        if not _climbActive then return end
        local hrp = HRP()
        if not hrp then return end
        hrp.CFrame = CFrame.new(fromPos:Lerp(toPos, i / steps))
        task.wait(DELAY)
    end
end

local function ClimbTo(targetPos, onDone)
    if _climbActive then
        _climbActive = false
        Notify("ch4rlies hub", "Cancelled.", 2)
        return
    end
    _climbActive = true

    local wasNoclip = cfg.Noclip
    SetNoclip(true)

    task.spawn(function()
        local hrp = HRP()
        if not hrp then
            _climbActive = false
            if not wasNoclip then SetNoclip(false) end
            return
        end

        local startPos = hrp.Position
        local aboveStart  = Vector3.new(startPos.X,  targetPos.Y + 30, startPos.Z)
        local aboveTarget = Vector3.new(targetPos.X, targetPos.Y + 30, targetPos.Z)

        StepPath(startPos, aboveStart)
        if not _climbActive then
            if not wasNoclip then SetNoclip(false) end
            return
        end

        local p2 = HRP()
        if p2 then StepPath(p2.Position, aboveTarget) end
        if not _climbActive then
            if not wasNoclip then SetNoclip(false) end
            return
        end

        local p3 = HRP()
        if p3 then StepPath(p3.Position, targetPos) end

        local p4 = HRP()
        if p4 then p4.CFrame = CFrame.new(targetPos) end

        _climbActive = false
        if not wasNoclip then SetNoclip(false) end
        if onDone then onDone() end
    end)
end

-- ============================================================
-- AUTO COMPLETE
-- ============================================================
local function AutoComplete()
    local top = FindTop()
    if not top then
        Notify("ch4rlies hub", "Couldn't find tower top!", 3)
        return
    end
    local surfY  = top.Position.Y + top.Size.Y / 2 + 3.5
    local target = Vector3.new(top.Position.X, surfY, top.Position.Z)
    Notify("ch4rlies hub", "Climbing to top... press again to cancel", 4)
    ClimbTo(target, function()
        RestoreForCoins()
        Notify("ch4rlies hub", "Reached the top!", 4)
    end)
end

-- ============================================================
-- SKIP ONE SECTION
-- ============================================================
local function SkipSection()
    local next = FindNextSection()
    if not next then
        Notify("ch4rlies hub", "No next section found!", 3)
        return
    end
    local surfY  = next.Position.Y + next.Size.Y / 2 + 3.5
    local target = Vector3.new(next.Position.X, surfY, next.Position.Z)
    Notify("ch4rlies hub", "Skipping to next section...", 3)
    ClimbTo(target, function()
        Notify("ch4rlies hub", "Landed on next section!", 2)
    end)
end

-- ============================================================
-- SERVER HOP
-- ============================================================
local function ServerHop()
    Notify("ch4rlies hub", "Finding new server...", 3)
    local id = game.PlaceId
    local ok, sv = pcall(function()
        local url = "https://games.roblox.com/v1/games/"..id.."/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url)).data
    end)
    if not ok or not sv or #sv == 0 then TeleportService:Teleport(id, LP) return end
    local cur = game.JobId
    for _, s in ipairs(sv) do
        if s.id ~= cur and s.playing < s.maxPlayers then
            TeleportService:TeleportToPlaceInstance(id, s.id, LP)
            return
        end
    end
    TeleportService:Teleport(id, LP)
end

-- ============================================================
-- RESPAWN
-- ============================================================
LP.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    NullifyKick()
    DisableKillScript(char)
    StartMovementGuard()
    local h = Hum()
    if h then h.WalkSpeed = cfg.WalkSpeed h.JumpPower = cfg.JumpPower end
    if cfg.InfJump     then SetInfJump(true)     end
    if cfg.Fly         then SetFly(true)          end
    if cfg.Noclip      then SetNoclip(true)       end
    if cfg.GodMode     then SetGodMode(true)      end
    if cfg.AntiVoid    then SetAntiVoid(true)     end
    if cfg.AntiRagdoll then SetAntiRagdoll(true)  end
    if cfg.LowGravity  then SetLowGravity(true)   end
    if cfg.SlowFall    then SetSlowFall(true)     end
    if cfg.BunnyHop    then SetBunnyHop(true)     end
    if cfg.PlayerESP   then SetPlayerESP(true)    end
    if cfg.Rainbow     then SetRainbow(true)      end
    if cfg.AutoRespawn then SetAutoRespawn(true)  end
end)

task.spawn(function()
    task.wait(1)
    NullifyKick()
    DisableKillScript()
    InstallHooks()
    StartMovementGuard()
end)

-- ============================================================
-- BUILD UI
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name            = "ch4rlies hub  -  Tower of Hell",
    LoadingTitle    = "ch4rlies hub",
    LoadingSubtitle = "Tower of Hell  |  v8.0",
    Theme           = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = true,
    ConfigurationSaving = {Enabled = true, FileName = "ch4rlies_toh_v8"},
    KeySystem = false,
})

-- ============================================================
-- TAB: PLAYER
-- ============================================================
local TabP = Window:CreateTab("Player", 4483362458)

TabP:CreateSection("Movement")
TabP:CreateSlider({
    Name = "Walk Speed", Range = {16, 150}, Increment = 1,
    Suffix = " studs/s", CurrentValue = 16, Flag = "WalkSpeed",
    Callback = function(v) ApplySpeed(v) end,
})
TabP:CreateSlider({
    Name = "Jump Power", Range = {50, 300}, Increment = 1,
    Suffix = " power", CurrentValue = 50, Flag = "JumpPower",
    Callback = function(v) ApplyJump(v) end,
})
TabP:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false, Flag = "InfJump",
    Callback = function(v) SetInfJump(v) end,
})
TabP:CreateToggle({
    Name = "Bunny Hop",
    CurrentValue = false, Flag = "BunnyHop",
    Callback = function(v) SetBunnyHop(v) end,
})

TabP:CreateSection("Gravity")
TabP:CreateToggle({
    Name = "Low Gravity",
    CurrentValue = false, Flag = "LowGravity",
    Callback = function(v) SetLowGravity(v) end,
})
TabP:CreateSlider({
    Name = "Gravity Multiplier", Range = {10, 100}, Increment = 5,
    Suffix = "%", CurrentValue = 35, Flag = "GravMult",
    Callback = function(v)
        cfg.GravMult = v / 100
        if cfg.LowGravity then SetLowGravity(true) end
    end,
})
TabP:CreateToggle({
    Name = "Slow Fall",
    CurrentValue = false, Flag = "SlowFall",
    Callback = function(v) SetSlowFall(v) end,
})
TabP:CreateToggle({
    Name = "Noclip",
    CurrentValue = false, Flag = "Noclip",
    Callback = function(v) SetNoclip(v) end,
})

TabP:CreateSection("Survival")
TabP:CreateToggle({
    Name = "God Mode",
    CurrentValue = false, Flag = "GodMode",
    Callback = function(v) SetGodMode(v) end,
})
TabP:CreateToggle({
    Name = "Anti-Void",
    CurrentValue = false, Flag = "AntiVoid",
    Callback = function(v) SetAntiVoid(v) end,
})
TabP:CreateToggle({
    Name = "Anti-Ragdoll",
    CurrentValue = false, Flag = "AntiRagdoll",
    Callback = function(v) SetAntiRagdoll(v) end,
})
TabP:CreateToggle({
    Name = "Auto Respawn on Fall",
    CurrentValue = false, Flag = "AutoRespawn",
    Callback = function(v) SetAutoRespawn(v) end,
})

TabP:CreateSection("Fly")
TabP:CreateToggle({
    Name = "Fly  (WASD + Space / Shift)",
    CurrentValue = false, Flag = "Fly",
    Callback = function(v) SetFly(v) end,
})
TabP:CreateSlider({
    Name = "Fly Speed", Range = {10, 200}, Increment = 5,
    Suffix = " studs/s", CurrentValue = 55, Flag = "FlySpeed",
    Callback = function(v) cfg.FlySpeed = v end,
})

-- ============================================================
-- TAB: TOWER
-- ============================================================
local TabT = Window:CreateTab("Tower", 4483362458)

TabT:CreateSection("Auto Finish")
TabT:CreateButton({
    Name = "Auto Complete  (press again to cancel)",
    Callback = function() AutoComplete() end,
})

TabT:CreateSection("Sections")
TabT:CreateButton({
    Name = "Skip One Section  (press again to cancel)",
    Callback = function() SkipSection() end,
})
TabT:CreateToggle({
    Name = "Auto Climb",
    CurrentValue = false, Flag = "AutoClimb",
    Callback = function(v) SetAutoClimb(v) end,
})

TabT:CreateSection("Obstacles")
TabT:CreateToggle({
    Name = "Freeze Moving Obstacles  (waits 1.5s to detect)",
    CurrentValue = false, Flag = "FreezeObst",
    Callback = function(v) SetFreezeObst(v) end,
})
TabT:CreateToggle({
    Name = "Wall Transparency",
    CurrentValue = false, Flag = "WallTransp",
    Callback = function(v) SetWallTransp(v) end,
})

TabT:CreateSection("5-Slot Checkpoints")
for i = 1, 5 do
    local idx = i
    TabT:CreateButton({
        Name = "Save Slot " .. idx,
        Callback = function()
            local hrp = HRP()
            if hrp then
                _slots[idx] = hrp.CFrame
                Notify("ch4rlies hub", "Slot "..idx.." saved!", 2)
            end
        end,
    })
    TabT:CreateButton({
        Name = "Load Slot " .. idx,
        Callback = function()
            local hrp = HRP()
            if hrp and _slots[idx] then
                hrp.CFrame = _slots[idx]
                Notify("ch4rlies hub", "Slot "..idx.." loaded!", 2)
            else
                Notify("ch4rlies hub", "Slot "..idx.." is empty!", 2)
            end
        end,
    })
end

TabT:CreateSection("Navigation")
TabT:CreateButton({
    Name = "Return to Spawn",
    Callback = function()
        local hrp = HRP()
        if hrp then
            hrp.CFrame = CFrame.new(0, 10, 0)
            Notify("ch4rlies hub", "Teleported to spawn.", 2)
        end
    end,
})

-- ============================================================
-- TAB: VISUALS
-- ============================================================
local TabV = Window:CreateTab("Visuals", 4483362458)

TabV:CreateSection("ESP")
TabV:CreateToggle({
    Name = "Kill Brick ESP  (red)",
    CurrentValue = false, Flag = "KillESP",
    Callback = function(v) SetKillESP(v) end,
})
TabV:CreateToggle({
    Name = "Safe Platform ESP  (green)",
    CurrentValue = false, Flag = "SafeESP",
    Callback = function(v) SetSafeESP(v) end,
})
TabV:CreateToggle({
    Name = "Player ESP",
    CurrentValue = false, Flag = "PlayerESP",
    Callback = function(v) SetPlayerESP(v) end,
})

TabV:CreateSection("World")
TabV:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false, Flag = "Fullbright",
    Callback = function(v) SetFullbright(v) end,
})

TabV:CreateSection("Character")
TabV:CreateToggle({
    Name = "Rainbow Character",
    CurrentValue = false, Flag = "Rainbow",
    Callback = function(v) SetRainbow(v) end,
})
TabV:CreateSlider({
    Name = "Rainbow Speed", Range = {1, 20}, Increment = 1,
    Suffix = "x", CurrentValue = 8, Flag = "RainbowSpeed",
    Callback = function(v) _rainbowTick = v * 0.1 end,
})

-- ============================================================
-- TAB: MISC
-- ============================================================
local TabM = Window:CreateTab("Misc", 4483362458)

TabM:CreateSection("Server")
TabM:CreateButton({
    Name = "Server Hop",
    Callback = function() ServerHop() end,
})
TabM:CreateButton({
    Name = "Rejoin Server",
    Callback = function() TeleportService:Teleport(game.PlaceId, LP) end,
})

TabM:CreateSection("Anti-Cheat")
TabM:CreateButton({
    Name = "Re-apply Bypasses",
    Callback = function()
        NullifyKick()
        DisableKillScript()
        InstallHooks()
        Notify("ch4rlies hub", "Bypasses re-applied!", 3)
    end,
})

TabM:CreateSection("Session")
TabM:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false, Flag = "AntiAFK",
    Callback = function(v) SetAntiAFK(v) end,
})
TabM:CreateToggle({
    Name = "Mute Game Sounds",
    CurrentValue = false, Flag = "Mute",
    Callback = function(v) SetMute(v) end,
})
TabM:CreateButton({
    Name = "Respawn Character",
    Callback = function() LP:LoadCharacter() end,
})
TabM:CreateButton({
    Name = "Copy Server Join Script",
    Callback = function()
        pcall(function()
            setclipboard(
                'game:GetService("TeleportService"):TeleportToPlaceInstance('
                ..game.PlaceId..',"'..game.JobId
                ..'",game.Players.LocalPlayer)'
            )
            Notify("ch4rlies hub", "Copied!", 2)
        end)
    end,
})

TabM:CreateSection("Info")
TabM:CreateLabel("ch4rlies hub  |  v8.0  |  Tower of Hell")
TabM:CreateLabel("Motion-detect Freeze  |  Section Skip  |  Rainbow")
TabM:CreateLabel("All bypasses active on load and respawn")

Rayfield:LoadConfiguration()
task.wait(0.8)
Notify("ch4rlies hub v8.0", "Fully rebuilt. Freeze and skip fixed!", 5)
