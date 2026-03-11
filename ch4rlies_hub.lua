-- ch4rlies hub | Tower of Hell | v6.5
-- 100% ASCII, Lua 5.1 compatible, 3-phase vertical climb

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local VirtualUser      = game:GetService("VirtualUser")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- State
local _conns       = {}
local _checkpoints = {nil, nil, nil, nil, nil}
local _lastSafe    = nil
local _lastJump    = 0
local _frozen      = {}
local _killCache   = {}
local _espHL       = {}
local _killHL      = {}
local _safeHL      = {}
local _wallOrig    = {}

local cfg = {
    WalkSpeed    = 16,
    JumpPower    = 50,
    FlySpeed     = 55,
    LowGravMult  = 0.35,
    InfJump      = false,
    Fly          = false,
    Noclip       = false,
    GodMode      = false,
    AntiVoid     = false,
    AntiRagdoll  = false,
    LowGravity   = false,
    BunnyHop     = false,
    AutoClimb    = false,
    FreezeObst   = false,
    KillESP      = false,
    SafeESP      = false,
    Fullbright   = false,
    PlayerESP    = false,
    AntiAFK      = false,
    WallsTransp  = false,
    SlowFall     = false,
}

local DEFAULT_GRAVITY = 196.2

-- Helpers
local function Char()
    return LP.Character
end
local function HRP()
    local c = Char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function Hum()
    local c = Char()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function Kill(k)
    if _conns[k] then
        _conns[k]:Disconnect()
        _conns[k] = nil
    end
end
local function Notify(t, c, d)
    Rayfield:Notify({Title = t, Content = c, Duration = d or 3, Image = 4483362458})
end

-- Bypass 1: nullify kick
local function NullifyKick()
    pcall(function()
        local ps = LP:WaitForChild("PlayerScripts", 5)
        if not ps then return end
        local ls = ps:WaitForChild("LocalScript", 5)
        if not ls then return end
        local env = getsenv(ls)
        if env and type(env) == "table" then
            env.kick       = function() end
            env.Kick       = function() end
            env.kickPlayer = function() end
            env.KickPlayer = function() end
        end
    end)
    pcall(function()
        local mt  = getrawmetatable(game)
        local old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "Kick" and self == LP then
                return
            end
            return old(self, ...)
        end)
        setreadonly(mt, true)
    end)
end

-- Bypass 2: disable KillScript
local function DisableKillScript(char)
    char = char or Char()
    if not char then return end
    pcall(function()
        local ks = char:FindFirstChild("KillScript")
        if not ks then
            ks = char:WaitForChild("KillScript", 3)
        end
        if ks then ks.Disabled = true end
    end)
    pcall(function()
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("LocalScript") or v:IsA("Script") then
                local n = v.Name:lower()
                if n:find("kill") or n:find("death") or n:find("damage") then
                    v.Disabled = true
                end
            end
        end
    end)
end

-- Bypass 3: movement reset guard
local function StartMovementGuard()
    Kill("moveguard")
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

-- Apply speed/jump
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

-- Infinite jump
local function SetInfJump(v)
    cfg.InfJump = v
    Kill("infjump")
    if not v then return end
    _conns["infjump"] = UserInputService.JumpRequest:Connect(function()
        local h = Hum()
        if not h then return end
        local now = tick()
        if (now - _lastJump) < 0.35 then return end
        local state = h:GetState()
        if state == Enum.HumanoidStateType.Freefall
        or state == Enum.HumanoidStateType.Jumping then
            _lastJump = now
            local prev = workspace.Gravity
            workspace.Gravity = 0.1
            task.wait(0.02)
            h:ChangeState(Enum.HumanoidStateType.Jumping)
            task.wait(0.12)
            if not cfg.LowGravity then
                workspace.Gravity = prev
            end
        end
    end)
end

-- Fly
local function SetFly(v)
    cfg.Fly = v
    Kill("fly")
    if not v then return end
    _conns["fly"] = RunService.RenderStepped:Connect(function()
        local hrp = HRP()
        if not hrp then return end
        local dir = Vector3.new(0, 0, 0)
        local cf  = Camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            dir = dir + cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            dir = dir - cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            dir = dir - cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            dir = dir + cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            dir = dir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            dir = dir - Vector3.new(0, 1, 0)
        end
        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        if dir.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + dir.Unit * (cfg.FlySpeed * 0.016)
        end
    end)
end

-- Noclip
local function SetNoclip(v)
    cfg.Noclip = v
    Kill("noclip")
    if v then
        _conns["noclip"] = RunService.Stepped:Connect(function()
            local c = Char()
            if not c then return end
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = false
                end
            end
        end)
    else
        local c = Char()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = true
                end
            end
        end
    end
end

-- Kill part detection
local KILL_KW = {
    "kill", "lava", "death", "spike", "acid", "saw",
    "laser", "void", "fire", "toxic", "drown", "blade", "harm"
}
local function IsKillPart(p)
    local n = p.Name:lower()
    for _, kw in ipairs(KILL_KW) do
        if n:find(kw) then
            return true
        end
    end
    return false
end

-- God mode
local function SetGodMode(v)
    cfg.GodMode = v
    Kill("god_scan")
    Kill("god_hb")
    if v then
        DisableKillScript()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and IsKillPart(obj) then
                pcall(function()
                    obj.CanTouch = false
                    _killCache[obj] = true
                end)
            end
        end
        _conns["god_scan"] = workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("BasePart") and IsKillPart(obj) then
                pcall(function()
                    obj.CanTouch = false
                    _killCache[obj] = true
                end)
            end
        end)
        _conns["god_hb"] = RunService.Heartbeat:Connect(function()
            for p, _ in pairs(_killCache) do
                if p and p.Parent then
                    pcall(function() p.CanTouch = false end)
                else
                    _killCache[p] = nil
                end
            end
        end)
    else
        for p, _ in pairs(_killCache) do
            if p and p.Parent then
                pcall(function() p.CanTouch = true end)
            end
        end
        _killCache = {}
    end
end

-- Low gravity
local function SetLowGravity(v)
    cfg.LowGravity = v
    if v then
        workspace.Gravity = DEFAULT_GRAVITY * cfg.LowGravMult
    else
        if not cfg.InfJump then
            workspace.Gravity = DEFAULT_GRAVITY
        end
    end
end

-- Slow fall
local function SetSlowFall(v)
    cfg.SlowFall = v
    Kill("slowfall")
    if not v then return end
    _conns["slowfall"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if not hrp then return end
        local vel = hrp.AssemblyLinearVelocity
        if vel.Y < -20 then
            hrp.AssemblyLinearVelocity = Vector3.new(vel.X, -20, vel.Z)
        end
    end)
end

-- Bunny hop
local function SetBunnyHop(v)
    cfg.BunnyHop = v
    Kill("bhop")
    if not v then return end
    _conns["bhop"] = RunService.Heartbeat:Connect(function()
        local h = Hum()
        if not h then return end
        if h:GetState() == Enum.HumanoidStateType.Landed then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

-- Auto climb
local function SetAutoClimb(v)
    cfg.AutoClimb = v
    Kill("autoclimb")
    if v then
        local jumpTick = 0
        _conns["autoclimb"] = RunService.Heartbeat:Connect(function()
            local hrp = HRP()
            local h   = Hum()
            if not hrp or not h then return end
            local fwd = hrp.CFrame.LookVector
            h:Move(Vector3.new(fwd.X, 0, fwd.Z), false)
            local now   = tick()
            local state = h:GetState()
            if (now - jumpTick) > 0.55
            and state ~= Enum.HumanoidStateType.Jumping
            and state ~= Enum.HumanoidStateType.Freefall then
                jumpTick = now
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    else
        local h = Hum()
        if h then h:Move(Vector3.new(0, 0, 0), false) end
    end
end

-- Wall transparency
local function SetWallTransp(v)
    cfg.WallsTransp = v
    local ign = Char()
    if v then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
            and (not ign or not obj:IsDescendantOf(ign))
            and not IsKillPart(obj)
            and (obj.Size.X < 4 or obj.Size.Z < 4) then
                pcall(function()
                    _wallOrig[obj] = obj.Transparency
                    obj.Transparency = 0.75
                end)
            end
        end
    else
        for obj, t in pairs(_wallOrig) do
            if obj and obj.Parent then
                pcall(function() obj.Transparency = t end)
            end
        end
        _wallOrig = {}
    end
end

-- Kill ESP
local function ClearKillESP()
    for _, h in pairs(_killHL) do
        if h and h.Parent then h:Destroy() end
    end
    _killHL = {}
end
local function SetKillESP(v)
    cfg.KillESP = v
    ClearKillESP()
    Kill("killesp_scan")
    if not v then return end
    local function Tag(obj)
        if obj:IsA("BasePart") and IsKillPart(obj) then
            pcall(function()
                local h = Instance.new("SelectionBox")
                h.Adornee             = obj
                h.Color3              = Color3.fromRGB(255, 30, 30)
                h.LineThickness       = 0.04
                h.SurfaceTransparency = 0.7
                h.SurfaceColor3       = Color3.fromRGB(255, 30, 30)
                h.Parent              = workspace
                _killHL[obj]          = h
            end)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do Tag(obj) end
    _conns["killesp_scan"] = workspace.DescendantAdded:Connect(Tag)
end

-- Safe ESP
local function ClearSafeESP()
    for _, h in pairs(_safeHL) do
        if h and h.Parent then h:Destroy() end
    end
    _safeHL = {}
end
local function SetSafeESP(v)
    cfg.SafeESP = v
    ClearSafeESP()
    if not v then return end
    local ign = Char()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart")
        and (not ign or not obj:IsDescendantOf(ign))
        and not IsKillPart(obj)
        and obj.Size.X > 2
        and obj.Size.Z > 2 then
            pcall(function()
                local h = Instance.new("SelectionBox")
                h.Adornee             = obj
                h.Color3              = Color3.fromRGB(0, 200, 80)
                h.LineThickness       = 0.03
                h.SurfaceTransparency = 0.85
                h.SurfaceColor3       = Color3.fromRGB(0, 200, 80)
                h.Parent              = workspace
                _safeHL[obj]          = h
            end)
        end
    end
end

-- Freeze obstacles (CFrame lock method - works against TweenService/script movement)
local MOVE_KW = {
    "convey", "spin", "rotat", "move", "platform", "trap",
    "swing", "slide", "bounce", "gear", "obstacle",
    "saw", "blade", "hammer", "pendulum", "piston"
}
local function SetFreezeObst(v)
    cfg.FreezeObst = v
    Kill("freeze_hb")
    if v then
        local ign = Char()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
            and (not ign or not obj:IsDescendantOf(ign)) then
                local n   = obj.Name:lower()
                local hit = false
                for _, kw in ipairs(MOVE_KW) do
                    if n:find(kw) then
                        hit = true
                        break
                    end
                end
                if hit then
                    pcall(function()
                        _frozen[obj] = obj.CFrame
                    end)
                end
            end
        end
        _conns["freeze_hb"] = RunService.Heartbeat:Connect(function()
            for obj, cf in pairs(_frozen) do
                if obj and obj.Parent then
                    pcall(function()
                        obj.CFrame = cf
                        obj.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                        obj.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end)
                else
                    _frozen[obj] = nil
                end
            end
        end)
        Notify("ch4rlies hub", "Obstacles frozen!", 2)
    else
        _frozen = {}
        Notify("ch4rlies hub", "Obstacles unfrozen.", 2)
    end
end

-- Anti-void
local function SetAntiVoid(v)
    cfg.AntiVoid = v
    Kill("av_save")
    Kill("av_check")
    if not v then return end
    _conns["av_save"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y > -30 then
            _lastSafe = hrp.CFrame
        end
    end)
    _conns["av_check"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y < -80 and _lastSafe then
            hrp.CFrame = _lastSafe
        end
    end)
end

-- Anti-ragdoll
local function SetAntiRagdoll(v)
    cfg.AntiRagdoll = v
    Kill("ragdoll")
    if not v then return end
    _conns["ragdoll"] = RunService.Stepped:Connect(function()
        local h = Hum()
        if not h then return end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Ragdoll
        or s == Enum.HumanoidStateType.FallingDown then
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

-- Fullbright
local function SetFullbright(v)
    local L = workspace.Lighting
    if v then
        L.Brightness     = 2
        L.ClockTime      = 14
        L.FogEnd         = 100000
        L.GlobalShadows  = false
        L.Ambient        = Color3.fromRGB(255, 255, 255)
        L.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    else
        L.Brightness     = 1
        L.ClockTime      = 14
        L.FogEnd         = 100000
        L.GlobalShadows  = true
        L.Ambient        = Color3.fromRGB(127, 127, 127)
        L.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
    end
end

-- Player ESP
local function ClearESP()
    for _, h in pairs(_espHL) do
        if h and h.Parent then h:Destroy() end
    end
    _espHL = {}
end
local function SetPlayerESP(v)
    cfg.PlayerESP = v
    ClearESP()
    Kill("esp_a")
    Kill("esp_r")
    if not v then return end
    local function Add(p)
        if p == LP then return end
        task.spawn(function()
            local c = p.Character or p.CharacterAdded:Wait()
            if not c then return end
            local h = Instance.new("Highlight")
            h.FillColor         = Color3.fromRGB(0, 150, 255)
            h.OutlineColor      = Color3.fromRGB(255, 255, 255)
            h.FillTransparency  = 0.45
            h.Parent            = c
            _espHL[p.Name]      = h
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do Add(p) end
    _conns["esp_a"] = Players.PlayerAdded:Connect(Add)
    _conns["esp_r"] = Players.PlayerRemoving:Connect(function(p)
        if _espHL[p.Name] then
            _espHL[p.Name]:Destroy()
            _espHL[p.Name] = nil
        end
    end)
end

-- Anti-AFK
local function SetAntiAFK(v)
    cfg.AntiAFK = v
    Kill("afk")
    if not v then return end
    _conns["afk"] = LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
    end)
end

-- Find tower top
local TOP_KW = {"finish", "goal", "win", "top", "crown", "complete"}
local function FindTop()
    local best   = nil
    local bestY  = -math.huge
    local bestSz = Vector3.new(4, 4, 4)
    local ign    = Char()

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart")
        and (not ign or not obj:IsDescendantOf(ign)) then
            local n   = obj.Name:lower()
            local hit = false
            for _, kw in ipairs(TOP_KW) do
                if n:find(kw) then
                    hit = true
                    break
                end
            end
            if hit and obj.Position.Y > bestY then
                bestY  = obj.Position.Y
                best   = obj
                bestSz = obj.Size
            end
        end
    end

    if not best then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
            and (not ign or not obj:IsDescendantOf(ign)) then
                if obj.Position.Y > bestY then
                    bestY  = obj.Position.Y
                    best   = obj
                    bestSz = obj.Size
                end
            end
        end
    end

    return best, bestSz
end

-- Restore CanCollide briefly so finish Touched fires
-- ============================================================
-- RESTORE CANCOLLIDE so finish Touched fires for coins
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
-- CLIMB SYSTEM
-- Uses a 3-phase approach so the character never walks off:
--   Phase 1: Rise straight up above the whole tower
--   Phase 2: Move horizontally to above the target X,Z
--   Phase 3: Descend down onto the surface
--
-- Each step is 5 studs with task.wait(0.05) = 100 studs/sec.
-- This is within normal fast-walkspeed range, so no ban flag.
-- CFrame writes at this rate replicate as smooth movement.
-- ============================================================
local _climbActive = false

local function StepTo(from, to, stepSize, delay)
    -- Move from -> to in stepSize increments with delay between each.
    -- Runs in current coroutine (call inside task.spawn).
    local dir  = to - from
    local dist = dir.Magnitude
    if dist < 0.01 then return end
    local steps = math.ceil(dist / stepSize)
    for i = 1, steps do
        if not _climbActive then return end
        local hrp = HRP()
        if not hrp then return end
        local alpha = math.min(i / steps, 1)
        hrp.CFrame = CFrame.new(from:Lerp(to, alpha))
        task.wait(delay)
    end
end

local function ClimbTo(targetPos, onDone)
    if _climbActive then
        _climbActive = false
        Notify("ch4rlies hub", "Stopped.", 2)
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
        -- Rise 25 studs above the target to clear everything
        local risePos  = Vector3.new(startPos.X,  targetPos.Y + 25, startPos.Z)
        -- Float across to above the target X,Z
        local crossPos = Vector3.new(targetPos.X, targetPos.Y + 25, targetPos.Z)
        -- Land on the surface
        local landPos  = targetPos

        -- Phase 1: rise straight up
        StepTo(startPos, risePos, 5, 0.05)
        if not _climbActive then
            if not wasNoclip then SetNoclip(false) end
            return
        end

        -- Phase 2: move across horizontally
        local hrp2 = HRP()
        if hrp2 then
            StepTo(hrp2.Position, crossPos, 5, 0.05)
        end
        if not _climbActive then
            if not wasNoclip then SetNoclip(false) end
            return
        end

        -- Phase 3: descend onto the surface
        local hrp3 = HRP()
        if hrp3 then
            StepTo(hrp3.Position, landPos, 5, 0.05)
        end

        -- Lock to exact landing spot
        local hrp4 = HRP()
        if hrp4 then hrp4.CFrame = CFrame.new(landPos) end

        _climbActive = false
        if not wasNoclip then SetNoclip(false) end
        if onDone then onDone() end
    end)
end

-- Auto complete
local function AutoComplete()
    if _climbActive then
        _climbActive = false
        Notify("ch4rlies hub", "Auto Complete stopped.", 2)
        return
    end

    local top, sz = FindTop()
    if not top then
        Notify("ch4rlies hub", "Couldn't find tower top!", 3)
        return
    end

    local surfY = top.Position.Y + (sz.Y / 2) + 3.5
    local target = Vector3.new(top.Position.X, surfY, top.Position.Z)

    Notify("ch4rlies hub", "Auto completing... (press again to stop)", 4)

    ClimbTo(target, function()
        RestoreForCoins()
        Notify("ch4rlies hub", "Reached the top!", 4)
    end)
end

-- Teleport to top
local function TeleportTop()
    if _climbActive then
        _climbActive = false
        return false
    end

    local top, sz = FindTop()
    local hrp = HRP()
    if not hrp or not top then return false end

    local surfY = top.Position.Y + (sz.Y / 2) + 3.5
    local target = Vector3.new(top.Position.X, surfY, top.Position.Z)

    Notify("ch4rlies hub", "Climbing to top...", 3)

    ClimbTo(target, function()
        RestoreForCoins()
        Notify("ch4rlies hub", "Reached the top!", 3)
    end)

    return true
end

-- Skip section (rise up 15, go forward 30)
local function SkipSection()
    if _climbActive then return end
    local hrp = HRP()
    if not hrp then return end

    local wasNoclip = cfg.Noclip
    SetNoclip(true)
    _climbActive = true

    local startPos = hrp.Position
    local fwd      = hrp.CFrame.LookVector
    local flat     = Vector3.new(fwd.X, 0, fwd.Z)
    local risePos  = startPos + Vector3.new(0, 15, 0)
    local fwdPos   = risePos + (flat.Magnitude > 0 and flat.Unit * 30 or Vector3.new(0, 0, -30))

    task.spawn(function()
        StepTo(startPos, risePos, 5, 0.05)
        local hrp2 = HRP()
        if hrp2 then StepTo(hrp2.Position, fwdPos, 5, 0.05) end
        _climbActive = false
        if not wasNoclip then SetNoclip(false) end
        Notify("ch4rlies hub", "Section skipped!", 2)
    end)
end

-- Server hop
local function ServerHop()
    Notify("ch4rlies hub", "Finding new server...", 3)
    local id = game.PlaceId
    local ok, sv = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. id .. "/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url)).data
    end)
    if not ok or not sv or #sv == 0 then
        TeleportService:Teleport(id, LP)
        return
    end
    local cur = game.JobId
    for _, s in ipairs(sv) do
        if s.id ~= cur and s.playing < s.maxPlayers then
            TeleportService:TeleportToPlaceInstance(id, s.id, LP)
            return
        end
    end
    TeleportService:Teleport(id, LP)
end

-- Respawn handler
LP.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    NullifyKick()
    DisableKillScript(char)
    StartMovementGuard()
    local h = Hum()
    if h then
        h.WalkSpeed = cfg.WalkSpeed
        h.JumpPower = cfg.JumpPower
    end
    if cfg.InfJump     then SetInfJump(true)    end
    if cfg.Fly         then SetFly(true)         end
    if cfg.Noclip      then SetNoclip(true)      end
    if cfg.GodMode     then SetGodMode(true)     end
    if cfg.AntiVoid    then SetAntiVoid(true)    end
    if cfg.AntiRagdoll then SetAntiRagdoll(true) end
    if cfg.LowGravity  then SetLowGravity(true)  end
    if cfg.SlowFall    then SetSlowFall(true)    end
    if cfg.BunnyHop    then SetBunnyHop(true)    end
    if cfg.PlayerESP   then SetPlayerESP(true)   end
end)

-- Initial bypass
task.spawn(function()
    task.wait(1)
    NullifyKick()
    DisableKillScript()
    StartMovementGuard()
end)

-- Build window
local Window = Rayfield:CreateWindow({
    Name             = "ch4rlies hub - Tower of Hell",
    LoadingTitle     = "ch4rlies hub",
    LoadingSubtitle  = "Tower of Hell | v6.5",
    Theme            = "Default",
    DisableRayfieldPrompts  = false,
    DisableBuildWarnings    = true,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "ch4rlies_toh_v6",
    },
    KeySystem = false,
})

-- Tab: Player
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
    Name = "Bunny Hop (auto-chain jumps on land)",
    CurrentValue = false, Flag = "BunnyHop",
    Callback = function(v) SetBunnyHop(v) end,
})

TabP:CreateSection("Gravity and Physics")
TabP:CreateToggle({
    Name = "Low Gravity (like in-game mutator)",
    CurrentValue = false, Flag = "LowGravity",
    Callback = function(v) SetLowGravity(v) end,
})
TabP:CreateSlider({
    Name = "Gravity Multiplier", Range = {10, 100}, Increment = 5,
    Suffix = "%", CurrentValue = 35, Flag = "GravMult",
    Callback = function(v)
        cfg.LowGravMult = v / 100
        if cfg.LowGravity then SetLowGravity(true) end
    end,
})
TabP:CreateToggle({
    Name = "Slow Fall (caps fall speed)",
    CurrentValue = false, Flag = "SlowFall",
    Callback = function(v) SetSlowFall(v) end,
})
TabP:CreateToggle({
    Name = "Noclip (pass through obstacles)",
    CurrentValue = false, Flag = "Noclip",
    Callback = function(v) SetNoclip(v) end,
})

TabP:CreateSection("Survival")
TabP:CreateToggle({
    Name = "God Mode (disables kill parts)",
    CurrentValue = false, Flag = "GodMode",
    Callback = function(v) SetGodMode(v) end,
})
TabP:CreateToggle({
    Name = "Anti-Void (catch falls)",
    CurrentValue = false, Flag = "AntiVoid",
    Callback = function(v) SetAntiVoid(v) end,
})
TabP:CreateToggle({
    Name = "Anti-Ragdoll",
    CurrentValue = false, Flag = "AntiRagdoll",
    Callback = function(v) SetAntiRagdoll(v) end,
})

TabP:CreateSection("Fly")
TabP:CreateToggle({
    Name = "Fly (WASD + Space / Shift)",
    CurrentValue = false, Flag = "Fly",
    Callback = function(v) SetFly(v) end,
})
TabP:CreateSlider({
    Name = "Fly Speed", Range = {10, 200}, Increment = 5,
    Suffix = " studs/s", CurrentValue = 55, Flag = "FlySpeed",
    Callback = function(v) cfg.FlySpeed = v end,
})

-- Tab: Tower
local TabT = Window:CreateTab("Tower", 4483362458)

TabT:CreateSection("Quick Finish")
TabT:CreateButton({
    Name = "Teleport to Top",
    Callback = function()
        local ok = TeleportTop()
        if ok then
            Notify("ch4rlies hub", "Teleported to top!", 3)
        else
            Notify("ch4rlies hub", "Couldn't find top.", 3)
        end
    end,
})
TabT:CreateButton({
    Name = "Auto Complete Tower (press again to stop)",
    Callback = function() AutoComplete() end,
})
TabT:CreateButton({
    Name = "Skip Current Section",
    Callback = function() SkipSection() end,
})
TabT:CreateToggle({
    Name = "Auto Climb (auto move and jump forward)",
    CurrentValue = false, Flag = "AutoClimb",
    Callback = function(v) SetAutoClimb(v) end,
})

TabT:CreateSection("Obstacles")
TabT:CreateToggle({
    Name = "Freeze Moving Obstacles",
    CurrentValue = false, Flag = "FreezeObst",
    Callback = function(v) SetFreezeObst(v) end,
})
TabT:CreateToggle({
    Name = "Wall Transparency (see through walls)",
    CurrentValue = false, Flag = "WallTransp",
    Callback = function(v) SetWallTransp(v) end,
})

TabT:CreateSection("Checkpoints (5 slots)")
for i = 1, 5 do
    local idx = i
    TabT:CreateButton({
        Name = "Save Slot " .. idx,
        Callback = function()
            local hrp = HRP()
            if hrp then
                _checkpoints[idx] = hrp.CFrame
                Notify("ch4rlies hub", "Saved slot " .. idx .. "!", 2)
            end
        end,
    })
    TabT:CreateButton({
        Name = "Load Slot " .. idx,
        Callback = function()
            local hrp = HRP()
            if hrp and _checkpoints[idx] then
                hrp.CFrame = _checkpoints[idx]
                Notify("ch4rlies hub", "Loaded slot " .. idx .. "!", 2)
            else
                Notify("ch4rlies hub", "Slot " .. idx .. " is empty!", 2)
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

-- Tab: Visuals
local TabV = Window:CreateTab("Visuals", 4483362458)

TabV:CreateSection("Danger")
TabV:CreateToggle({
    Name = "Kill Brick ESP (red)",
    CurrentValue = false, Flag = "KillESP",
    Callback = function(v) SetKillESP(v) end,
})
TabV:CreateToggle({
    Name = "Safe Platform ESP (green)",
    CurrentValue = false, Flag = "SafeESP",
    Callback = function(v) SetSafeESP(v) end,
})

TabV:CreateSection("Environment")
TabV:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false, Flag = "Fullbright",
    Callback = function(v) SetFullbright(v) end,
})

TabV:CreateSection("Players")
TabV:CreateToggle({
    Name = "Player ESP",
    CurrentValue = false, Flag = "PlayerESP",
    Callback = function(v) SetPlayerESP(v) end,
})

-- Tab: Misc
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
        Notify("ch4rlies hub", "Bypasses re-applied!", 3)
    end,
})

TabM:CreateSection("Session")
TabM:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false, Flag = "AntiAFK",
    Callback = function(v) SetAntiAFK(v) end,
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
                .. game.PlaceId .. ',"' .. game.JobId
                .. '",game.Players.LocalPlayer)'
            )
            Notify("ch4rlies hub", "Copied!", 2)
        end)
    end,
})

TabM:CreateSection("Info")
TabM:CreateLabel("ch4rlies hub | v6.5 | Tower of Hell")
TabM:CreateLabel("3-Phase Climb - Rise, Cross, Land")
TabM:CreateLabel("Fly - Noclip - InfJump - God Mode - Kill ESP")

Rayfield:LoadConfiguration()
task.wait(0.8)
Notify("ch4rlies hub v6.5", "Fixed auto-complete. Rise, cross, land!", 5)
