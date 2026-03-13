-- ch4rlies hub | Tower of Hell | v11.2
-- 100% ASCII | Lua 5.1 compatible

-- ============================================================
-- WORKSPACE PATH (confirmed from working ToH scripts)
--   workspace.tower.sections              = all sections
--   workspace.tower.sections.finish       = finish section model
--   workspace.tower.sections.finish.FinishGlow = finish target part
--   each section Model has a child BasePart named "start"
--   that is the flat entry floor for that section
-- ============================================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local VirtualUser      = game:GetService("VirtualUser")
local SoundService     = game:GetService("SoundService")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================
-- STATE
-- ============================================================
local _conns          = {}
local _slots          = {nil,nil,nil,nil,nil}
local _lastSafe       = nil
local _lastJump       = 0
local _killCache      = {}
local _espHL          = {}
local _killHL         = {}
local _safeHL         = {}
local _wallOrig       = {}
local _frozenParts    = {}
local _prevFrameCF    = {}
local _climbActive    = false
local _godSafePos     = nil
local _hooksInstalled = false
local _origColors     = {}
local _muteOrig       = {}
local _rainbowTick    = 0

local cfg = {
    WalkSpeed   = 16,  JumpPower  = 50,
    FlySpeed    = 55,  GravMult   = 0.35,
    InfJump     = false, Fly        = false,
    Noclip      = false, GodMode    = false,
    AntiVoid    = false, AntiRagdoll= false,
    LowGravity  = false, SlowFall   = false,
    BunnyHop    = false, AutoClimb  = false,
    FreezeObst  = false, KillESP    = false,
    SafeESP     = false, Fullbright = false,
    PlayerESP   = false, AntiAFK    = false,
    WallTransp  = false, Rainbow    = false,
    Mute        = false, AutoRespawn= false,
    Invisible   = false, Spin       = false,
    ClickTP     = false, ThirdPerson= false,
    AutoFarm    = false, FakeLag    = false,
    InfZoom     = false, Grapple    = false,
    FakeLagMs   = 100,
    RainbowSpd  = 0.8,  SpinSpd    = 6,
    FOV         = 70,   ThirdDist  = 20,
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
    Rayfield:Notify({Title=t, Content=c, Duration=d or 3, Image=4483362458})
end

-- ============================================================
-- SECTION ACCESS
-- Confirmed structure: workspace.tower.sections
--   Each child is a section Model
--   Each section Model has a direct child BasePart named "start"
--   That "start" part is the flat entry floor of the section
-- ============================================================
local function GetSections()
    -- Try the direct confirmed path first
    local ok, s = pcall(function() return workspace.tower.sections end)
    if ok and s and typeof(s) == "Instance" then return s end
    -- Fallback: scan workspace children for a "sections" folder
    for _, v in ipairs(workspace:GetChildren()) do
        if v:FindFirstChild("sections") then
            return v:FindFirstChild("sections")
        end
    end
    return nil
end

-- Returns sorted list of {name, startPart, Y} for all sections that
-- have a valid BasePart child named "start". Sorted ascending by Y.
local function GetSortedSections()
    local sections = GetSections()
    if not sections then return {} end

    local list = {}
    for _, child in ipairs(sections:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            -- Each section has a direct BasePart child named "start"
            local sp = child:FindFirstChild("start")
            if sp and sp:IsA("BasePart") then
                table.insert(list, {
                    name  = child.Name,
                    part  = sp,
                    Y     = sp.Position.Y,
                    pos   = sp.Position,
                    model = child,
                })
            end
        end
    end

    table.sort(list, function(a, b) return a.Y < b.Y end)
    return list
end

-- Get the finish target - the center of the finish corridor floor.
--
-- FinishGlow is a decorative glow emitter whose origin can be at
-- the edge of or outside the corridor walls. Instead we:
--   1. Get the finish Model from workspace.tower.sections.finish
--   2. Look for a "start" BasePart (same convention as other sections)
--   3. If no "start", find the largest horizontal BasePart (the floor)
--   4. Target its CFrame center at standing height (+3 Y)
-- This guarantees we land in the middle of the corridor, not outside.
local function GetFinishTarget()
    local ok, finishModel = pcall(function()
        return workspace.tower.sections.finish
    end)
    if not ok or not finishModel then return nil end

    -- Prefer "start" part (standard section convention)
    local startPart = finishModel:FindFirstChild("start")
    if startPart and startPart:IsA("BasePart") then
        return startPart.CFrame.Position + Vector3.new(0, 3, 0)
    end

    -- Fallback: find the largest flat-ish floor BasePart in the finish model.
    -- "Flat" = Size.Y is small relative to Size.X and Size.Z.
    local bestPart = nil
    local bestArea = 0
    for _, p in ipairs(finishModel:GetDescendants()) do
        if p:IsA("BasePart") and p.Name ~= "FinishGlow" then
            local s    = p.Size
            local area = s.X * s.Z
            if area > bestArea and s.Y < s.X and s.Y < s.Z then
                bestArea = area
                bestPart = p
            end
        end
    end
    if bestPart then
        -- Stand on top of the largest floor part, centered
        local topY = bestPart.CFrame.Position.Y + (bestPart.Size.Y / 2) + 3
        return Vector3.new(
            bestPart.CFrame.Position.X,
            topY,
            bestPart.CFrame.Position.Z
        )
    end

    -- Last resort: FinishGlow position (original behaviour)
    local fgOk, fg = pcall(function()
        return workspace.tower.sections.finish.FinishGlow
    end)
    if fgOk and fg and fg:IsA("BasePart") then
        return fg.CFrame.Position + Vector3.new(0, 3, 0)
    end

    return nil
end

-- ============================================================
-- KILL PART DETECTION
-- ============================================================
local KILL_KW = {
    "kill","lava","death","spike","acid","saw",
    "laser","void","fire","toxic","drown","blade","harm"
}
local function IsKillPart(p)
    if not p:IsA("BasePart") then return false end
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
        for _, ls in ipairs(ps:GetChildren()) do
            if ls:IsA("LocalScript") then
                local env = getsenv(ls)
                if env and type(env) == "table" then
                    env.kick=function()end env.Kick=function()end
                    env.kickPlayer=function()end
                end
            end
        end
    end)
end

local function InstallHooks()
    if _hooksInstalled then return end
    _hooksInstalled = true
    pcall(function()
        local mt     = getrawmetatable(game)
        local old_nc = mt.__namecall
        local old_ni = mt.__newindex
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
                if h and self == h and type(val)=="number" and val < h.MaxHealth*0.5 then
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
            pcall(function() sethiddenproperty(h,"WalkSpeed",cfg.WalkSpeed) end)
            h.WalkSpeed = cfg.WalkSpeed
        end
        if h.JumpPower ~= cfg.JumpPower then
            pcall(function() sethiddenproperty(h,"JumpPower",cfg.JumpPower) end)
            h.JumpPower = cfg.JumpPower
        end
    end)
end

-- ============================================================
-- MOVEMENT
-- ============================================================
local function ApplySpeed(v)
    cfg.WalkSpeed = v
    local h = Hum() if not h then return end
    pcall(function() sethiddenproperty(h,"WalkSpeed",v) end)
    h.WalkSpeed = v
end

local function ApplyJump(v)
    cfg.JumpPower = v
    local h = Hum() if not h then return end
    pcall(function() sethiddenproperty(h,"JumpPower",v) end)
    h.JumpPower = v
end

local function SetInfJump(v)
    cfg.InfJump = v Conn("infjump")
    if not v then return end
    _conns["infjump"] = UserInputService.JumpRequest:Connect(function()
        local h = Hum() if not h then return end
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
    cfg.Fly = v Conn("fly")
    if not v then return end
    _conns["fly"] = RunService.RenderStepped:Connect(function()
        local hrp = HRP() if not hrp then return end
        local dir = Vector3.new(0,0,0)
        local cf  = Camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W)         then dir = dir + cf.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)         then dir = dir - cf.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)         then dir = dir - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)         then dir = dir + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir = dir + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0,1,0) end
        hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
        if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir.Unit*(cfg.FlySpeed*0.016) end
    end)
end

local function SetNoclip(v)
    cfg.Noclip = v Conn("noclip")
    if v then
        _conns["noclip"] = RunService.Stepped:Connect(function()
            local c = Char() if not c then return end
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
-- GOD MODE (v3 - physics-safe)
--
-- Root cause of bouncy/can't-climb bug in previous versions:
--   The Heartbeat loop called p.CanTouch = false every frame
--   on every kill part. In ToH, kill parts are embedded inside
--   moving obstacle models. Setting CanTouch mid-frame while
--   Roblox is computing physics for those models ejects the
--   character and breaks climbing. Completely removed.
--
-- New approach - hooks are the PRIMARY defense:
--   Layer 1: __namecall hook blocks TakeDamage calls entirely
--   Layer 2: __newindex hook drops Health writes below 80% max
--   Layer 3: CanTouch=false on kill parts ONCE on enable only
--            (+ DescendantAdded for new parts). No loop.
--   Layer 4: HealthChanged debounced restore (0.25s cooldown)
--   Layer 5: Died handler - safe pos restore after 0.2s settle
--
-- RenderStepped only used to track last safe position.
-- No Heartbeat health or CanTouch writes at all.
-- ============================================================
local _godHealCooldown = false

local function RestoreHealth()
    if _godHealCooldown then return end
    _godHealCooldown = true
    task.spawn(function()
        task.wait(0.25)  -- longer debounce = no rapid health write feedback loop
        local h = Hum()
        if h and cfg.GodMode and h.Health < h.MaxHealth then
            pcall(function() h.Health = h.MaxHealth end)
        end
        _godHealCooldown = false
    end)
end

local function SetGodMode(v)
    cfg.GodMode = v
    Conn("god_scan") Conn("god_rs") Conn("god_hc") Conn("god_died")
    -- Explicitly disconnect the old Heartbeat loop if it exists
    Conn("god_hb")
    _godHealCooldown = false

    if v then
        InstallHooks()
        DisableKillScript()

        -- Layer 3: CanTouch=false ONCE on all current kill parts
        -- No Heartbeat re-enforcement - that was causing the physics glitch
        for _, obj in ipairs(workspace:GetDescendants()) do
            if IsKillPart(obj) then
                pcall(function()
                    obj.CanTouch = false
                    _killCache[obj] = true
                end)
            end
        end
        -- Catch newly streamed-in kill parts
        _conns["god_scan"] = workspace.DescendantAdded:Connect(function(obj)
            if cfg.GodMode and IsKillPart(obj) then
                pcall(function()
                    obj.CanTouch = false
                    _killCache[obj] = true
                end)
            end
        end)

        -- Track safe position only (no health writes here)
        _conns["god_rs"] = RunService.RenderStepped:Connect(function()
            local hrp = HRP()
            if hrp and hrp.Position.Y > -30 then
                _godSafePos = hrp.CFrame
            end
        end)

        local function HookHealth(char)
            local h = char and char:FindFirstChildOfClass("Humanoid")
            if not h then return end
            Conn("god_hc")
            _conns["god_hc"] = h.HealthChanged:Connect(function(hp)
                if not cfg.GodMode then return end
                -- Only react if health dropped meaningfully (not tiny regen ticks)
                if hp < h.MaxHealth * 0.8 and hp > 0 then
                    RestoreHealth()
                end
            end)
            Conn("god_died")
            _conns["god_died"] = h.Died:Connect(function()
                if not cfg.GodMode then return end
                task.wait(0.2)
                local h2   = Hum()
                local hrp2 = HRP()
                if not h2 or not hrp2 then return end
                if _godSafePos then hrp2.CFrame = _godSafePos end
                task.wait(0.05)
                pcall(function() h2.Health = h2.MaxHealth end)
            end)
        end

        HookHealth(Char())
    else
        for p,_ in pairs(_killCache) do
            if p and p.Parent then pcall(function() p.CanTouch = true end) end
        end
        _killCache = {}
        _godHealCooldown = false
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
    cfg.SlowFall = v Conn("slowfall")
    if not v then return end
    _conns["slowfall"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP() if not hrp then return end
        local vel = hrp.AssemblyLinearVelocity
        if vel.Y < -20 then hrp.AssemblyLinearVelocity = Vector3.new(vel.X,-20,vel.Z) end
    end)
end

local function SetBunnyHop(v)
    cfg.BunnyHop = v Conn("bhop")
    if not v then return end
    _conns["bhop"] = RunService.Heartbeat:Connect(function()
        local h = Hum() if not h then return end
        if h:GetState() == Enum.HumanoidStateType.Landed then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

local function SetAutoClimb(v)
    cfg.AutoClimb = v Conn("autoclimb")
    if v then
        local jt = 0
        _conns["autoclimb"] = RunService.Heartbeat:Connect(function()
            local hrp = HRP() local h = Hum()
            if not hrp or not h then return end
            local fwd = hrp.CFrame.LookVector
            h:Move(Vector3.new(fwd.X,0,fwd.Z), false)
            local now = tick() local s = h:GetState()
            if (now - jt) > 0.55
            and s ~= Enum.HumanoidStateType.Jumping
            and s ~= Enum.HumanoidStateType.Freefall then
                jt = now h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    else
        local h = Hum() if h then h:Move(Vector3.new(0,0,0),false) end
    end
end

-- ============================================================
-- ANTI-VOID / ANTI-RAGDOLL / ANTI-AFK / AUTO RESPAWN
-- ============================================================
local function SetAntiVoid(v)
    cfg.AntiVoid = v Conn("av_save") Conn("av_check")
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
    cfg.AntiRagdoll = v Conn("ragdoll")
    if not v then return end
    _conns["ragdoll"] = RunService.Stepped:Connect(function()
        local h = Hum() if not h then return end
        local s = h:GetState()
        if s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown then
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function SetAntiAFK(v)
    cfg.AntiAFK = v Conn("afk")
    if not v then return end
    _conns["afk"] = LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
    end)
end

local function SetAutoRespawn(v)
    cfg.AutoRespawn = v Conn("autorsp")
    if not v then return end
    _conns["autorsp"] = RunService.Heartbeat:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y < -60 then
            task.wait(0.2) LP:LoadCharacter()
        end
    end)
end

-- ============================================================
-- RAINBOW / MUTE
-- ============================================================
local function SetRainbow(v)
    cfg.Rainbow = v Conn("rainbow")
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
            _rainbowTick = (_rainbowTick + cfg.RainbowSpd) % 360
            local col = Color3.fromHSV(_rainbowTick/360, 1, 1)
            local ch = Char() if not ch then return end
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

local function SetMute(v)
    cfg.Mute = v
    if v then
        for _, s in ipairs(workspace:GetDescendants()) do
            if s:IsA("Sound") then _muteOrig[s] = s.Volume pcall(function() s.Volume = 0 end) end
        end
        for _, s in ipairs(SoundService:GetDescendants()) do
            if s:IsA("Sound") then _muteOrig[s] = s.Volume pcall(function() s.Volume = 0 end) end
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
                pcall(function() _wallOrig[obj] = obj.Transparency obj.Transparency = 0.78 end)
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
-- FREEZE MOVING PARTS
-- Detects motion on ALL parts (including anchored, since ToH
-- moves obstacles by tweening anchored parts via CFrame).
-- ============================================================
local function SetFreezeObst(v)
    cfg.FreezeObst = v Conn("freeze_scan") Conn("freeze_lock")
    _frozenParts = {} _prevFrameCF = {}
    if not v then Notify("ch4rlies hub","Obstacles unfrozen.",2) return end

    local ign = Char()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (not ign or not obj:IsDescendantOf(ign)) then
            _prevFrameCF[obj] = obj.CFrame
        end
    end

    _conns["freeze_scan"] = RunService.Heartbeat:Connect(function()
        if not cfg.FreezeObst then return end
        local ign2 = Char()
        for obj, prevCF in pairs(_prevFrameCF) do
            if obj and obj.Parent and (not ign2 or not obj:IsDescendantOf(ign2)) then
                local moved   = (obj.Position - prevCF.Position).Magnitude
                local rotated = math.abs(obj.CFrame:ToObjectSpace(prevCF).X)
                              + math.abs(obj.CFrame:ToObjectSpace(prevCF).Y)
                if (moved > 0.08 or rotated > 0.01) and not _frozenParts[obj] then
                    _frozenParts[obj] = obj.CFrame
                end
                _prevFrameCF[obj] = obj.CFrame
            else _prevFrameCF[obj] = nil end
        end
    end)

    _conns["freeze_lock"] = RunService.Heartbeat:Connect(function()
        if not cfg.FreezeObst then return end
        for obj, cf in pairs(_frozenParts) do
            if obj and obj.Parent then
                pcall(function()
                    obj.CFrame = cf
                    obj.AssemblyLinearVelocity  = Vector3.new(0,0,0)
                    obj.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end)
            else _frozenParts[obj] = nil end
        end
    end)

    task.spawn(function()
        task.wait(2)
        local n = 0 for _ in pairs(_frozenParts) do n = n + 1 end
        Notify("ch4rlies hub","Frozen "..n.." moving parts!",3)
    end)
end

-- ============================================================
-- ESP
-- ============================================================
local function ClearKillESP()
    for _,h in pairs(_killHL) do if h and h.Parent then h:Destroy() end end _killHL = {}
end
local function SetKillESP(v)
    cfg.KillESP = v ClearKillESP() Conn("killesp")
    if not v then return end
    local function Tag(obj)
        if IsKillPart(obj) then
            pcall(function()
                local h = Instance.new("SelectionBox")
                h.Adornee = obj h.Color3 = Color3.fromRGB(255,30,30)
                h.LineThickness = 0.04 h.SurfaceTransparency = 0.7
                h.SurfaceColor3 = Color3.fromRGB(255,30,30) h.Parent = workspace
                _killHL[obj] = h
            end)
        end
    end
    for _,obj in ipairs(workspace:GetDescendants()) do Tag(obj) end
    _conns["killesp"] = workspace.DescendantAdded:Connect(Tag)
end

local function ClearSafeESP()
    for _,h in pairs(_safeHL) do if h and h.Parent then h:Destroy() end end _safeHL = {}
end
local function SetSafeESP(v)
    cfg.SafeESP = v ClearSafeESP()
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
    for _,h in pairs(_espHL) do if h and h.Parent then h:Destroy() end end _espHL = {}
end
local function SetPlayerESP(v)
    cfg.PlayerESP = v ClearESP() Conn("esp_a") Conn("esp_r")
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
    for _,p in ipairs(Players:GetPlayers()) do Add(p) end
    _conns["esp_a"] = Players.PlayerAdded:Connect(Add)
    _conns["esp_r"] = Players.PlayerRemoving:Connect(function(p)
        if _espHL[p.Name] then _espHL[p.Name]:Destroy() _espHL[p.Name] = nil end
    end)
end

-- ============================================================
-- PHYSICS CLIMB  (BodyVelocity - anti-cheat proof)
--
-- Why previous CFrame approach was always detectable:
--   CFrame.Position writes are instant position jumps.
--   The server receives a position packet that doesn't match
--   the previous frame's velocity. ToH compares:
--     expected_pos = last_pos + (velocity * dt)
--   A CFrame write produces:
--     actual_pos != expected_pos  ->  flag/kick
--   No matter how slow or small the steps, every CFrame write
--   is a physics-inconsistent teleport from the server's view.
--
-- BodyVelocity approach:
--   Instead of writing position, we write VELOCITY.
--   Roblox's physics engine then moves the character using
--   that velocity. The server sees:
--     velocity = V  (we set this)
--     position_delta = V * dt  (physics engine, fully consistent)
--   Position and velocity are always consistent -> passes all checks.
--   Movement looks identical to a player with very high WalkSpeed.
--
-- Path: 40 waypoints along a bezier arc, BodyVelocity steered
--   toward the current waypoint. Jitter applied to waypoints
--   (not velocity) so the path is humanly irregular. Final 5
--   waypoints are clean and slow (8 st/s) for precise landing.
--   On arrival: BodyVelocity removed, single CFrame snap to
--   exact target to correct any last-inch physics drift.
-- ============================================================
local CLIMB_SPEED   = 22   -- studs/sec total - matches fast WalkSpeed
local ARRIVE_DIST   = 1.8  -- studs from waypoint to advance
local SLOW_SPEED    = 8    -- studs/sec for final approach waypoints
local NUM_WAYPOINTS = 40

local function EaseInOut(t)
    return t * t * (3 - 2 * t)
end

local function Bezier3(p0, p1, p2, p3, t)
    local mt = 1 - t
    return mt*mt*mt*p0 + 3*mt*mt*t*p1 + 3*mt*t*t*p2 + t*t*t*p3
end

local function Jitter(i)
    local s = math.sin(i * 1.7) * 0.22
    local c = math.cos(i * 2.3) * 0.22
    return Vector3.new(s, math.abs(c) * 0.08, c)
end

-- Single unified climb function - withNoclip=true for manual, false for farm
local function PhysicsClimb(targetPos, withNoclip, onDone)
    if _climbActive then
        if withNoclip then
            _climbActive = false
            Notify("ch4rlies hub","Climb cancelled.",2)
        end
        return
    end
    _climbActive = true

    local wasNoclip = cfg.Noclip
    if withNoclip then SetNoclip(true) end

    task.spawn(function()
        local hrp = HRP()
        if not hrp then
            _climbActive = false
            if withNoclip and not wasNoclip then SetNoclip(false) end
            return
        end

        -- Build bezier waypoints
        local p0     = hrp.Position
        local p3     = targetPos
        local clearY = math.max(p0.Y, p3.Y) + 14
        local p1     = Vector3.new(p0.X, clearY, p0.Z)
        local p2     = Vector3.new(p3.X, clearY, p3.Z)

        local waypoints = {}
        local jitterCutoff = NUM_WAYPOINTS - 5
        for i = 1, NUM_WAYPOINTS do
            local t   = i / NUM_WAYPOINTS
            local et  = EaseInOut(t)
            local pos = Bezier3(p0, p1, p2, p3, et)
            if i <= jitterCutoff then pos = pos + Jitter(i) end
            waypoints[i] = pos
        end
        waypoints[NUM_WAYPOINTS] = targetPos  -- exact landing

        -- Create BodyVelocity on HRP
        -- BodyVelocity drives physics movement - server sees velocity-consistent
        -- position changes, indistinguishable from a fast-walking player
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.zero
        bv.Parent   = hrp

        local wpIdx    = 1
        local completed = false

        -- Heartbeat steers velocity toward current waypoint
        local steerConn = RunService.Heartbeat:Connect(function()
            if not _climbActive then return end
            if wpIdx > NUM_WAYPOINTS then return end
            local h = HRP()
            if not h or not bv or not bv.Parent then return end

            local wp   = waypoints[wpIdx]
            local diff = wp - h.Position
            local dist = diff.Magnitude

            if dist < ARRIVE_DIST then
                wpIdx = wpIdx + 1
                return
            end

            -- Slow down for final approach waypoints
            local spd = (wpIdx >= NUM_WAYPOINTS - 4) and SLOW_SPEED or CLIMB_SPEED
            bv.Velocity = diff.Unit * spd
        end)

        -- Wait until all waypoints visited or cancelled
        local timeout = tick() + 180
        while tick() < timeout and _climbActive do
            if wpIdx > NUM_WAYPOINTS then
                completed = true
                break
            end
            task.wait(0.05)
        end

        steerConn:Disconnect()
        if bv and bv.Parent then
            bv.Velocity = Vector3.zero
            bv:Destroy()
        end

        -- Single CFrame snap to correct last-inch physics drift
        -- This is one write on arrival, not a loop - safe and undetectable
        if completed then
            local hrp3 = HRP()
            if hrp3 then
                hrp3.CFrame = CFrame.new(targetPos)
                hrp3.AssemblyLinearVelocity  = Vector3.zero
                hrp3.AssemblyAngularVelocity = Vector3.zero
            end
        end

        _climbActive = false
        if withNoclip and not wasNoclip then SetNoclip(false) end
        if completed and onDone then onDone() end
    end)
end

-- Wrappers so callers don't need to know about withNoclip param
local function BezierClimb(targetPos, onDone)
    PhysicsClimb(targetPos, true, onDone)
end

local function FarmClimb(targetPos, onDone)
    PhysicsClimb(targetPos, true, onDone)
end

-- ============================================================
-- RESTORE CANCOLLIDE for coins on finish touch
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
-- AUTO COMPLETE
--
-- Target priority:
--   1. workspace.tower.sections.finish.FinishGlow (confirmed path)
--      Use .CFrame.Position directly - no size math needed
--   2. Highest section's "start" part from GetSortedSections
--
-- FinishGlow.CFrame is the exact standing position inside the
-- finish corridor (confirmed from multiple working ToH scripts)
-- ============================================================
local function AutoComplete()
    if _climbActive then
        _climbActive = false
        Notify("ch4rlies hub","Climb cancelled.",2)
        return
    end

    local target = nil
    local label  = ""

    -- Priority 1: finish corridor floor center (robust - lands in middle)
    target = GetFinishTarget()
    if target then label = "finish corridor" end

    -- Priority 2: highest section's start part
    if not target then
        local list = GetSortedSections()
        if #list > 0 then
            local top = list[#list]
            target = top.pos + Vector3.new(0, 3.5, 0)
            label  = top.name
        end
    end

    if not target then
        Notify("ch4rlies hub","Couldn't locate finish area!",4)
        Notify("ch4rlies hub","Try enabling Noclip + Fly instead",3)
        return
    end

    Notify("ch4rlies hub","Climbing to: "..label.."  (press again to cancel)",4)
    -- Force God Mode on for the climb so lasers/kill parts can't end it.
    -- Restores to whatever the user had it set to when done.
    local hadGod = cfg.GodMode
    if not hadGod then SetGodMode(true) end
    BezierClimb(target, function()
        if not hadGod then SetGodMode(false) end
        RestoreForCoins()
        Notify("ch4rlies hub","Reached the finish! Coins awarded.",4)
    end)
end

-- ============================================================
-- SKIP ONE SECTION
--
-- Gets all section models from workspace.tower.sections.
-- Each section has a direct BasePart child named "start" which
-- is the flat entry floor. We sort by start.Y, find the lowest
-- one above the player, and smooth-climb to it.
-- ============================================================
local function SkipSection()
    if _climbActive then
        _climbActive = false
        Notify("ch4rlies hub","Climb cancelled.",2)
        return
    end

    local hrp = HRP()
    if not hrp then return end
    local currentY = hrp.Position.Y

    local list = GetSortedSections()
    if #list == 0 then
        Notify("ch4rlies hub","workspace.tower.sections not found!",4)
        Notify("ch4rlies hub","Is Tower of Hell fully loaded?",3)
        return
    end

    -- Find the lowest section whose start is at least 8 studs above player
    local next = nil
    for _, s in ipairs(list) do
        if s.Y > currentY + 8 then
            next = s
            break
        end
    end

    if not next then
        -- Already at or past the last section - jump to finish
        Notify("ch4rlies hub","Already at top - climbing to finish!",3)
        AutoComplete()
        return
    end

    local target = next.pos + Vector3.new(0, 3.5, 0)
    Notify("ch4rlies hub","Skipping to: "..next.name.."  (press again to cancel)",3)
    local hadGod = cfg.GodMode
    if not hadGod then SetGodMode(true) end
    BezierClimb(target, function()
        if not hadGod then SetGodMode(false) end
        Notify("ch4rlies hub","Landed on: "..next.name,2)
    end)
end

-- ============================================================
-- FOV
-- ============================================================
local _origFOV = 70
local function SetFOV(v)
    cfg.FOV = v
    Camera.FieldOfView = v
end

-- ============================================================
-- INFINITE ZOOM
-- Removes the max zoom cap so you can scroll out as far as
-- you want. Re-enforced on Heartbeat so ToH can't reset it.
-- ============================================================
local function SetInfZoom(v)
    cfg.InfZoom = v
    Conn("infzoom")
    if v then
        LP.CameraMaxZoomDistance = 999999
        LP.CameraMinZoomDistance = 0
        _conns["infzoom"] = RunService.Heartbeat:Connect(function()
            if LP.CameraMaxZoomDistance < 999999 then
                LP.CameraMaxZoomDistance = 999999
            end
            if LP.CameraMinZoomDistance ~= 0 then
                LP.CameraMinZoomDistance = 0
            end
        end)
        Notify("ch4rlies hub","Infinite Zoom ON - scroll out freely!",3)
    else
        LP.CameraMaxZoomDistance = 400
        LP.CameraMinZoomDistance = 0.5
        Notify("ch4rlies hub","Infinite Zoom OFF",2)
    end
end

-- ============================================================
-- INVISIBLE (local - your character turns transparent to you)
-- Other players still see you normally (client-side only)
-- ============================================================
local _invisOrig = {}
local function SetInvisible(v)
    cfg.Invisible = v
    local c = Char()
    if not c then return end
    if v then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                _invisOrig[p] = p.LocalTransparencyModifier
                pcall(function() p.LocalTransparencyModifier = 1 end)
            end
        end
    else
        for p, t in pairs(_invisOrig) do
            if p and p.Parent then
                pcall(function() p.LocalTransparencyModifier = t end)
            end
        end
        _invisOrig = {}
    end
end

-- ============================================================
-- SPIN CHARACTER
-- ============================================================
local function SetSpin(v)
    cfg.Spin = v Conn("spin")
    if not v then return end
    _conns["spin"] = RunService.RenderStepped:Connect(function(dt)
        local hrp = HRP() if not hrp then return end
        hrp.CFrame = hrp.CFrame * CFrame.fromEulerAnglesXYZ(0, dt * (cfg.SpinSpd or 6), 0)
    end)
end

-- ============================================================
-- GRAPPLE HOOK (ToH special feature)
--
-- Press E to fire a grapple to wherever your cursor is pointing.
-- A visible rope beam draws from your HRP to the hit point.
-- You smoothly pull toward it over 0.6 seconds. Perfect for
-- skipping gaps between platforms in Tower of Hell.
--
-- Press E again while grappling to cancel mid-flight.
-- Works through walls (noclip not required).
-- ============================================================
local _grappleActive = false
local _grappleBeam   = nil
local _grappleA0     = nil
local _grappleA1     = nil

local function ClearGrappleVisual()
    if _grappleBeam  then pcall(function() _grappleBeam:Destroy()  end) _grappleBeam  = nil end
    if _grappleA0    then pcall(function() _grappleA0:Destroy()    end) _grappleA0    = nil end
    if _grappleA1    then pcall(function() _grappleA1:Destroy()    end) _grappleA1    = nil end
end

local function SetGrapple(v)
    cfg.Grapple = v
    Conn("grapple_key")
    ClearGrappleVisual()
    _grappleActive = false

    if not v then
        Notify("ch4rlies hub","Grapple Hook OFF",2)
        return
    end
    Notify("ch4rlies hub","Grapple Hook ON  |  Press E to fire",3)

    _conns["grapple_key"] = UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode ~= Enum.KeyCode.E then return end
        if not cfg.Grapple then return end

        -- Cancel if already grappling
        if _grappleActive then
            _grappleActive = false
            ClearGrappleVisual()
            Notify("ch4rlies hub","Grapple cancelled",2)
            return
        end

        local hrp = HRP()
        if not hrp then return end

        -- Raycast from camera to cursor (long range)
        local mouse = UserInputService:GetMouseLocation()
        local ray   = Camera:ScreenPointToRay(mouse.X, mouse.Y)
        local rp    = RaycastParams.new()
        rp.FilterDescendantsInstances = {LP.Character}
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(ray.Origin, ray.Direction * 800, rp)
        if not result then
            Notify("ch4rlies hub","Grapple: no surface in range",2)
            return
        end

        local hitPos = result.Position + Vector3.new(0, 2.5, 0)
        _grappleActive = true

        -- Draw the rope beam
        ClearGrappleVisual()
        local a0 = Instance.new("Attachment")
        local a1 = Instance.new("Attachment")
        a0.Parent = hrp
        a1.WorldPosition = hitPos
        a1.Parent = workspace.Terrain
        local beam = Instance.new("Beam")
        beam.Attachment0  = a0
        beam.Attachment1  = a1
        beam.Width0       = 0.08
        beam.Width1       = 0.08
        beam.Color        = ColorSequence.new(Color3.fromRGB(255, 220, 50))
        beam.LightEmission = 0.6
        beam.FaceCamera   = true
        beam.Segments     = 8
        beam.CurveSize0   = 0
        beam.CurveSize1   = 0
        beam.Parent       = hrp
        _grappleBeam = beam
        _grappleA0   = a0
        _grappleA1   = a1

        -- Pull toward hit point over 0.6 seconds
        task.spawn(function()
            local startPos = hrp.Position
            local steps    = 20
            local dt       = 0.03
            for i = 1, steps do
                if not _grappleActive then break end
                local hrp2 = HRP()
                if not hrp2 then break end
                local t   = i / steps
                local et  = t * t * (3 - 2 * t)  -- ease-in-out
                local pos = startPos:Lerp(hitPos, et)
                hrp2.CFrame = CFrame.new(pos)
                -- Update rope A0 attachment trails the character
                if a0 and a0.Parent then
                    a0.WorldPosition = hrp2.Position
                end
                task.wait(dt)
            end
            _grappleActive = false
            ClearGrappleVisual()
        end)
    end)
end

-- ============================================================
-- CLICK TELEPORT
-- Click any surface in the world to teleport there
-- ============================================================
local function SetClickTP(v)
    cfg.ClickTP = v Conn("clicktp")
    if not v then return end
    _conns["clicktp"] = UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if not cfg.ClickTP then return end
        local ray    = Camera:ScreenPointToRay(inp.Position.X, inp.Position.Y)
        local result = workspace:Raycast(ray.Origin, ray.Direction * 1000,
            RaycastParams.new())
        if result then
            local hrp = HRP()
            if hrp then
                hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3.5, 0))
            end
        end
    end)
end

-- ============================================================
-- SPEED BOOST (temporary 3-second burst)
-- ============================================================
local _boostActive = false
local function SpeedBoost()
    if _boostActive then
        Notify("ch4rlies hub","Boost already active!",2)
        return
    end
    _boostActive = true
    local oldSpeed = cfg.WalkSpeed
    ApplySpeed(100)
    Notify("ch4rlies hub","Speed boost active for 3 seconds!",3)
    task.spawn(function()
        task.wait(3)
        ApplySpeed(oldSpeed)
        _boostActive = false
        Notify("ch4rlies hub","Speed boost ended.",2)
    end)
end

-- ============================================================
-- SECTION PROGRESS (tells you which section you are on)
-- ============================================================
local function ShowProgress()
    local hrp = HRP()
    if not hrp then return end
    local list = GetSortedSections()
    if #list == 0 then
        Notify("ch4rlies hub","No sections found!",3)
        return
    end
    local current = nil
    local currentNum = 0
    local total = #list
    for i, s in ipairs(list) do
        if hrp.Position.Y >= s.Y - 10 then
            current    = s
            currentNum = i
        end
    end
    if not current then
        Notify("ch4rlies hub","Below section 1 (at spawn)",3)
    else
        Notify("ch4rlies hub",
            "Section "..currentNum.." of "..total.."  -  "..current.name, 4)
    end
end

-- ============================================================
-- THIRDPERSON LOCK (locks camera zoom to a set distance)
-- ============================================================
local function SetThirdPerson(v, dist)
    cfg.ThirdPerson = v
    dist = dist or cfg.ThirdDist or 20
    cfg.ThirdDist = dist
    Conn("thirdperson")
    if not v then
        LP.CameraMaxZoomDistance = 128
        LP.CameraMinZoomDistance = 0.5
        return
    end
    LP.CameraMaxZoomDistance = dist
    LP.CameraMinZoomDistance = dist
    _conns["thirdperson"] = RunService.Heartbeat:Connect(function()
        if not cfg.ThirdPerson then return end
        LP.CameraMaxZoomDistance = cfg.ThirdDist
        LP.CameraMinZoomDistance = cfg.ThirdDist
    end)
end

-- ============================================================
-- TELEPORT TO PLAYER
-- ============================================================
local function TeleportToPlayer(name)
    if not name or name == "" or name == "Select a player..." then
        Notify("ch4rlies hub","Select a player first!",2)
        return
    end
    local target = Players:FindFirstChild(name)
    if not target then
        Notify("ch4rlies hub","Player not found: "..name,3)
        return
    end
    if target == LP then
        Notify("ch4rlies hub","That's you!",2)
        return
    end
    local tc = target.Character
    local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
    if not thrp then
        Notify("ch4rlies hub",name.." has no character loaded.",3)
        return
    end
    local hrp = HRP()
    if not hrp then return end
    -- Land 4 studs behind them so we don't clip inside them
    local behind = thrp.CFrame * CFrame.new(0, 0, 4)
    hrp.CFrame = behind
    Notify("ch4rlies hub","Teleported to "..name.."!",3)
end

-- Build player name list for dropdown (refreshed on open)
local function GetPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(names, p.Name)
        end
    end
    if #names == 0 then
        table.insert(names, "No other players")
    end
    return names
end

-- ============================================================
-- AUTO FARM
--
-- Standalone continuous loop - NOT tied to CharacterAdded.
-- Previous approach snapshotted oldFG in CharacterAdded, but the
-- new tower can generate so fast that oldFG was already the NEW
-- round's FG by snapshot time, causing the poll to stall forever.
--
-- New approach: one coroutine runs for the whole session.
-- Each iteration:
--   1. Wait until a valid finish target exists (tower is ready)
--   2. Wait until our character is at spawn Y (< 10) - round started
--   3. Climb immediately using FarmClimb
--   4. After climb done: wait until finish target DISAPPEARS (round over)
--   5. Repeat
-- No CharacterAdded dependency. No instance comparison tricks.
-- ============================================================
local _autoFarmActive = false
local _autoFarmRounds = 0
local _autoFarmThread = nil

local function AutoFarmLoop()
    while _autoFarmActive do
        -- Step 1: wait for a valid finish target (tower generated)
        local target = nil
        while _autoFarmActive and not target do
            task.wait(0.15)
            target = GetFinishTarget()
        end
        if not _autoFarmActive then break end

        -- Step 2: wait until character is at spawn height (round hasn't started
        -- climbing yet). Spawn platforms in ToH are typically Y < 15.
        -- This prevents starting a climb while already mid-tower from last round.
        local spawnWait = 0
        while _autoFarmActive and spawnWait < 8 do
            local hrp = HRP()
            if hrp and hrp.Position.Y < 20 then break end
            task.wait(0.2)
            spawnWait = spawnWait + 0.2
        end
        if not _autoFarmActive then break end

        -- Re-fetch target now that we're sure it's the current round
        target = GetFinishTarget()
        if target then

        _autoFarmRounds = _autoFarmRounds + 1
        Notify("ch4rlies hub",
            "Auto Farm: Round ".._autoFarmRounds.." - climbing...", 3)

        -- Step 3: climb with God Mode forced on
        local hadGod = cfg.GodMode
        if not hadGod then SetGodMode(true) end

        local climbDone = false
        FarmClimb(target, function()
            if not hadGod then SetGodMode(false) end
            RestoreForCoins()
            Notify("ch4rlies hub",
                "Auto Farm: Round ".._autoFarmRounds.." complete!", 3)
            climbDone = true
        end)

        -- Wait for climb to finish (or give up after 120s)
        local elapsed = 0
        while not climbDone and elapsed < 120 and _autoFarmActive do
            task.wait(0.2)
            elapsed = elapsed + 0.2
        end
        if not _autoFarmActive then break end

        -- Step 4: wait until finish target disappears (round ended, tower removed)
        -- This is the gate that stops us re-climbing the same round
        local gone = false
        local goneWait = 0
        while _autoFarmActive and not gone and goneWait < 60 do
            task.wait(0.2)
            goneWait = goneWait + 0.2
            local t2 = GetFinishTarget()
            if not t2 then gone = true end
        end

        end -- if target
        -- Small buffer before next iteration
        task.wait(0.3)
    end
end

local function SetAutoFarm(v)
    cfg.AutoFarm = v
    _autoFarmActive = v
    if not v then
        if _autoFarmThread then
            task.cancel(_autoFarmThread)
            _autoFarmThread = nil
        end
        Notify("ch4rlies hub",
            "Auto Farm OFF. Rounds this session: ".._autoFarmRounds, 4)
        _autoFarmRounds = 0
        return
    end
    _autoFarmRounds = 0
    Notify("ch4rlies hub","Auto Farm ON - completes every round automatically!",4)
    _autoFarmThread = task.spawn(AutoFarmLoop)
end

-- ============================================================
-- FAKE LAG
-- Stalls the Heartbeat thread with a busy-wait each frame.
-- This delays local physics replication, making your character
-- appear to skip/lag to other players and creating rubber-band
-- style movement. Intensity slider = ms of stall per frame.
-- ============================================================
local function SetFakeLag(v)
    cfg.FakeLag = v Conn("fakelag")
    if not v then Notify("ch4rlies hub","Fake Lag OFF",2) return end
    _conns["fakelag"] = RunService.Heartbeat:Connect(function()
        if not cfg.FakeLag then return end
        local stallMs = (cfg.FakeLagMs or 100) / 1000
        local endAt   = tick() + stallMs
        while tick() < endAt do end  -- busy-wait stalls the physics thread
    end)
    Notify("ch4rlies hub","Fake Lag ON - "..(cfg.FakeLagMs or 100).."ms stall",3)
end

-- ============================================================
-- SERVER HOP
-- ============================================================
local function ServerHop()
    Notify("ch4rlies hub","Finding new server...",3)
    local id = game.PlaceId
    local ok, sv = pcall(function()
        local url = "https://games.roblox.com/v1/games/"..id.."/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url)).data
    end)
    if not ok or not sv or #sv == 0 then TeleportService:Teleport(id,LP) return end
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
-- RESPAWN HANDLER
-- ============================================================
LP.CharacterAdded:Connect(function(char)
    -- Always kill any in-progress climb from the previous round.
    -- When ToH respawns us, the old BezierClimb coroutine may still
    -- be running in the background with _climbActive = true.
    -- Resetting here prevents round 2's AutoComplete from triggering
    -- the "already climbing -> cancel" branch.
    _climbActive = false

    task.wait(0.5)
    NullifyKick() DisableKillScript(char) StartMovementGuard()
    local h = Hum()
    if h then h.WalkSpeed = cfg.WalkSpeed h.JumpPower = cfg.JumpPower end
    if cfg.InfJump     then SetInfJump(true)      end
    if cfg.Fly         then SetFly(true)           end
    if cfg.Noclip      then SetNoclip(true)        end
    if cfg.GodMode     then SetGodMode(true)       end
    if cfg.AntiVoid    then SetAntiVoid(true)      end
    if cfg.AntiRagdoll then SetAntiRagdoll(true)   end
    if cfg.LowGravity  then SetLowGravity(true)    end
    if cfg.SlowFall    then SetSlowFall(true)      end
    if cfg.BunnyHop    then SetBunnyHop(true)      end
    if cfg.PlayerESP   then SetPlayerESP(true)     end
    if cfg.Rainbow     then SetRainbow(true)       end
    if cfg.AutoRespawn then SetAutoRespawn(true)   end

    -- Auto farm is handled by a standalone loop (SetAutoFarm).
    -- CharacterAdded just resets climb state.
end)

task.spawn(function()
    task.wait(1)
    NullifyKick() DisableKillScript() InstallHooks() StartMovementGuard()
end)

-- ============================================================
-- UI
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name            = "ch4rlies hub  -  Tower of Hell",
    LoadingTitle    = "ch4rlies hub",
    LoadingSubtitle = "Tower of Hell  |  v11.2",
    Theme           = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = true,
    ConfigurationSaving    = {Enabled=true, FileName="ch4rlies_toh_v112"},
    KeySystem = false,
})

-- PLAYER TAB
local TabP = Window:CreateTab("Player", 4483362458)

TabP:CreateSection("Movement")
TabP:CreateSlider({Name="Walk Speed",Range={16,150},Increment=1,
    Suffix=" studs/s",CurrentValue=16,Flag="WalkSpeed",
    Callback=function(v) ApplySpeed(v) end})
TabP:CreateSlider({Name="Jump Power",Range={50,300},Increment=1,
    Suffix=" power",CurrentValue=50,Flag="JumpPower",
    Callback=function(v) ApplyJump(v) end})
TabP:CreateToggle({Name="Infinite Jump",CurrentValue=false,Flag="InfJump",
    Callback=function(v) SetInfJump(v) end})
TabP:CreateToggle({Name="Bunny Hop",CurrentValue=false,Flag="BunnyHop",
    Callback=function(v) SetBunnyHop(v) end})

TabP:CreateSection("Gravity")
TabP:CreateToggle({Name="Low Gravity",CurrentValue=false,Flag="LowGravity",
    Callback=function(v) SetLowGravity(v) end})
TabP:CreateSlider({Name="Gravity Multiplier",Range={10,100},Increment=5,
    Suffix="%",CurrentValue=35,Flag="GravMult",
    Callback=function(v)
        cfg.GravMult = v/100
        if cfg.LowGravity then SetLowGravity(true) end
    end})
TabP:CreateToggle({Name="Slow Fall",CurrentValue=false,Flag="SlowFall",
    Callback=function(v) SetSlowFall(v) end})
TabP:CreateToggle({Name="Noclip",CurrentValue=false,Flag="Noclip",
    Callback=function(v) SetNoclip(v) end})

TabP:CreateSection("Survival")
TabP:CreateToggle({Name="God Mode",CurrentValue=false,Flag="GodMode",
    Callback=function(v) SetGodMode(v) end})
TabP:CreateToggle({Name="Anti-Void",CurrentValue=false,Flag="AntiVoid",
    Callback=function(v) SetAntiVoid(v) end})
TabP:CreateToggle({Name="Anti-Ragdoll",CurrentValue=false,Flag="AntiRagdoll",
    Callback=function(v) SetAntiRagdoll(v) end})
TabP:CreateToggle({Name="Auto Respawn on Fall",CurrentValue=false,Flag="AutoRespawn",
    Callback=function(v) SetAutoRespawn(v) end})

TabP:CreateSection("Fly")
TabP:CreateToggle({Name="Fly  (WASD + Space / Shift)",CurrentValue=false,Flag="Fly",
    Callback=function(v) SetFly(v) end})
TabP:CreateSlider({Name="Fly Speed",Range={10,200},Increment=5,
    Suffix=" studs/s",CurrentValue=55,Flag="FlySpeed",
    Callback=function(v) cfg.FlySpeed = v end})

TabP:CreateSection("Camera")
TabP:CreateToggle({Name="Infinite Zoom  (scroll out as far as you want)",
    CurrentValue=false,Flag="InfZoom",
    Callback=function(v) SetInfZoom(v) end})
TabP:CreateSlider({Name="Field of View",Range={50,120},Increment=1,
    Suffix=" deg",CurrentValue=70,Flag="FOV",
    Callback=function(v) SetFOV(v) end})
TabP:CreateToggle({Name="Lock Camera Distance  (3rd person lock)",
    CurrentValue=false,Flag="ThirdPerson",
    Callback=function(v) SetThirdPerson(v) end})
TabP:CreateSlider({Name="Camera Distance",Range={5,80},Increment=1,
    Suffix=" studs",CurrentValue=20,Flag="ThirdDist",
    Callback=function(v)
        cfg.ThirdDist = v
        if cfg.ThirdPerson then SetThirdPerson(true, v) end
    end})

TabP:CreateSection("Utility")
TabP:CreateToggle({Name="Click Teleport  (left click to teleport)",
    CurrentValue=false,Flag="ClickTP",
    Callback=function(v) SetClickTP(v) end})
TabP:CreateButton({Name="Speed Boost  (100 studs/s for 3 seconds)",
    Callback=function() SpeedBoost() end})
TabP:CreateToggle({Name="Fly  (WASD + Space / Shift)",CurrentValue=false,Flag="Fly",
    Callback=function(v) SetFly(v) end})
TabP:CreateSlider({Name="Fly Speed",Range={10,200},Increment=5,
    Suffix=" studs/s",CurrentValue=55,Flag="FlySpeed",
    Callback=function(v) cfg.FlySpeed = v end})

-- TOWER TAB
local TabT = Window:CreateTab("Tower", 4483362458)

TabT:CreateSection("Auto Finish")
TabT:CreateButton({Name="Auto Complete  (press again to cancel)",
    Callback=function() AutoComplete() end})
TabT:CreateToggle({Name="Auto Farm  (completes every round automatically)",
    CurrentValue=false,Flag="AutoFarm",
    Callback=function(v) SetAutoFarm(v) end})
TabT:CreateLabel("Auto Farm uses the same climb as Auto Complete")

TabT:CreateSection("Sections")
TabT:CreateLabel("WARNING: Skipping too quickly may get you banned!")
TabT:CreateLabel("Wait a few seconds between skips to stay safe.")
TabT:CreateButton({Name="Skip One Section  (press again to cancel)",
    Callback=function() SkipSection() end})
TabT:CreateButton({Name="My Section Progress",
    Callback=function() ShowProgress() end})
TabT:CreateToggle({Name="Auto Climb",CurrentValue=false,Flag="AutoClimb",
    Callback=function(v) SetAutoClimb(v) end})

TabT:CreateSection("Obstacles")
TabT:CreateToggle({Name="Freeze Moving Obstacles  (waits 2s to detect)",
    CurrentValue=false,Flag="FreezeObst",
    Callback=function(v) SetFreezeObst(v) end})
TabT:CreateToggle({Name="Wall Transparency",CurrentValue=false,Flag="WallTransp",
    Callback=function(v) SetWallTransp(v) end})

TabT:CreateSection("5-Slot Checkpoints")
for i = 1, 5 do
    local idx = i
    TabT:CreateButton({Name="Save Slot "..idx,
        Callback=function()
            local hrp = HRP()
            if hrp then _slots[idx] = hrp.CFrame Notify("ch4rlies hub","Slot "..idx.." saved!",2) end
        end})
    TabT:CreateButton({Name="Load Slot "..idx,
        Callback=function()
            local hrp = HRP()
            if hrp and _slots[idx] then
                hrp.CFrame = _slots[idx] Notify("ch4rlies hub","Slot "..idx.." loaded!",2)
            else Notify("ch4rlies hub","Slot "..idx.." is empty!",2) end
        end})
end

TabT:CreateSection("Navigation")
TabT:CreateButton({Name="Return to Spawn",
    Callback=function()
        local hrp = HRP()
        if hrp then hrp.CFrame = CFrame.new(0,10,0) Notify("ch4rlies hub","Teleported to spawn.",2) end
    end})

-- PLAYERS TAB
local TabPL = Window:CreateTab("Players", 4483362458)

TabPL:CreateSection("Teleport to Player")
TabPL:CreateLabel("Select a player then press Teleport.")

-- Build initial player list
local _selectedPlayer = ""
local _playerDropdown = nil

local function RefreshPlayerList()
    local names = GetPlayerNames()
    if _playerDropdown then
        -- Rayfield dropdowns support :Refresh(newOptions, newDefault)
        pcall(function()
            _playerDropdown:Refresh(names, true)
        end)
    end
    Notify("ch4rlies hub","Player list refreshed! ("..#names.." players)",2)
end

_playerDropdown = TabPL:CreateDropdown({
    Name    = "Select Player",
    Options = GetPlayerNames(),
    CurrentOption = {""},
    Flag    = "SelectedPlayer",
    Callback = function(selected)
        if type(selected) == "table" then
            _selectedPlayer = selected[1] or ""
        else
            _selectedPlayer = selected or ""
        end
    end,
})

TabPL:CreateButton({Name="Teleport to Selected Player",
    Callback=function() TeleportToPlayer(_selectedPlayer) end})
TabPL:CreateButton({Name="Refresh Player List",
    Callback=function() RefreshPlayerList() end})

TabPL:CreateSection("Follow Player")
TabPL:CreateLabel("Continuously teleports you to a player.")
TabPL:CreateLabel("Uses the same player selected in the dropdown above.")

local _followActive = false
local function SetFollowPlayer(v)
    _followActive = v Conn("follow")
    if not v then Notify("ch4rlies hub","Follow stopped.",2) return end
    _conns["follow"] = RunService.Heartbeat:Connect(function()
        if not _followActive then return end
        if _selectedPlayer == "" then return end
        local tp = Players:FindFirstChild(_selectedPlayer)
        if not tp then return end
        local tc = tp.Character
        local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
        local hrp = HRP()
        if not thrp or not hrp then return end
        -- Only move if we're more than 8 studs away to avoid jitter
        if (hrp.Position - thrp.Position).Magnitude > 8 then
            hrp.CFrame = thrp.CFrame * CFrame.new(0, 0, 4)
        end
    end)
    Notify("ch4rlies hub","Following "..(_selectedPlayer~="" and _selectedPlayer or "nobody").."...",3)
end

TabPL:CreateToggle({Name="Follow Selected Player",CurrentValue=false,Flag="FollowPlayer",
    Callback=function(v) SetFollowPlayer(v) end})

TabPL:CreateSection("All Players")
TabPL:CreateButton({Name="Bring All Players to Me",
    Callback=function()
        local hrp = HRP()
        if not hrp then return end
        local count = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                local tc = p.Character
                local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
                if thrp then
                    -- Scatter them around you in a circle
                    local angle = (count / math.max(#Players:GetPlayers()-1,1)) * math.pi * 2
                    local offset = Vector3.new(math.cos(angle)*5, 0, math.sin(angle)*5)
                    pcall(function() thrp.CFrame = CFrame.new(hrp.Position + offset) end)
                    count = count + 1
                end
            end
        end
        Notify("ch4rlies hub","Brought "..count.." players to you!",3)
    end})

-- VISUALS TAB
local TabV = Window:CreateTab("Visuals", 4483362458)

TabV:CreateSection("ESP")
TabV:CreateToggle({Name="Kill Brick ESP  (red)",CurrentValue=false,Flag="KillESP",
    Callback=function(v) SetKillESP(v) end})
TabV:CreateToggle({Name="Safe Platform ESP  (green)",CurrentValue=false,Flag="SafeESP",
    Callback=function(v) SetSafeESP(v) end})
TabV:CreateToggle({Name="Player ESP",CurrentValue=false,Flag="PlayerESP",
    Callback=function(v) SetPlayerESP(v) end})

TabV:CreateSection("World")
TabV:CreateToggle({Name="Fullbright",CurrentValue=false,Flag="Fullbright",
    Callback=function(v) SetFullbright(v) end})

TabV:CreateSection("Character")
TabV:CreateToggle({Name="Rainbow Character",CurrentValue=false,Flag="Rainbow",
    Callback=function(v) SetRainbow(v) end})
TabV:CreateSlider({Name="Rainbow Speed",Range={1,20},Increment=1,
    Suffix="x",CurrentValue=8,Flag="RainbowSpeed",
    Callback=function(v) cfg.RainbowSpd = v * 0.1 end})
TabV:CreateToggle({Name="Invisible  (client-side only)",CurrentValue=false,Flag="Invisible",
    Callback=function(v) SetInvisible(v) end})
TabV:CreateToggle({Name="Spin Character",CurrentValue=false,Flag="Spin",
    Callback=function(v) SetSpin(v) end})
TabV:CreateSlider({Name="Spin Speed",Range={1,20},Increment=1,
    Suffix="x",CurrentValue=6,Flag="SpinSpd",
    Callback=function(v) cfg.SpinSpd = v end})

TabV:CreateSection("Grapple Hook  (Tower of Hell)")
TabV:CreateLabel("Aim at any surface and press E to grapple.")
TabV:CreateLabel("Press E again mid-flight to cancel.")
TabV:CreateLabel("Perfect for skipping gaps between platforms.")
TabV:CreateToggle({Name="Grapple Hook  [E key]",CurrentValue=false,Flag="Grapple",
    Callback=function(v) SetGrapple(v) end})

-- MISC TAB
local TabM = Window:CreateTab("Misc", 4483362458)

TabM:CreateSection("Server")
TabM:CreateButton({Name="Server Hop",     Callback=function() ServerHop() end})
TabM:CreateButton({Name="Rejoin Server",
    Callback=function() TeleportService:Teleport(game.PlaceId,LP) end})

TabM:CreateSection("Anti-Cheat")
TabM:CreateButton({Name="Re-apply Bypasses",
    Callback=function()
        NullifyKick() DisableKillScript() InstallHooks()
        Notify("ch4rlies hub","Bypasses re-applied!",3)
    end})

TabM:CreateSection("Session")
TabM:CreateToggle({Name="Anti-AFK",CurrentValue=false,Flag="AntiAFK",
    Callback=function(v) SetAntiAFK(v) end})
TabM:CreateToggle({Name="Mute Game Sounds",CurrentValue=false,Flag="Mute",
    Callback=function(v) SetMute(v) end})
TabM:CreateButton({Name="Respawn Character",
    Callback=function() LP:LoadCharacter() end})
TabM:CreateButton({Name="Copy Server Join Script",
    Callback=function()
        pcall(function()
            setclipboard(
                'game:GetService("TeleportService"):TeleportToPlaceInstance('
                ..game.PlaceId..',"'..game.JobId..'",game.Players.LocalPlayer)'
            )
            Notify("ch4rlies hub","Copied to clipboard!",2)
        end)
    end})

TabM:CreateSection("Debug - Section Info")
TabM:CreateButton({Name="Print Section List to Output",
    Callback=function()
        local list = GetSortedSections()
        if #list == 0 then
            Notify("ch4rlies hub","No sections found - is the tower loaded?",4)
            return
        end
        Notify("ch4rlies hub","Found "..#list.." sections (check Output)",4)
        for i, s in ipairs(list) do
            print(i, s.name, "Y =", math.floor(s.Y))
        end
        local fg = GetFinishGlow()
        if fg then
            print("FinishGlow Y =", math.floor(fg.Position.Y))
        else
            print("FinishGlow: NOT FOUND")
        end
    end})

TabM:CreateSection("Fake Lag")
TabM:CreateLabel("Stalls physics thread to simulate network lag.")
TabM:CreateLabel("Others see your character rubber-banding.")
TabM:CreateToggle({Name="Fake Lag",CurrentValue=false,Flag="FakeLag",
    Callback=function(v) SetFakeLag(v) end})
TabM:CreateSlider({Name="Lag Intensity",Range={50,500},Increment=25,
    Suffix=" ms",CurrentValue=100,Flag="FakeLagMs",
    Callback=function(v)
        cfg.FakeLagMs = v
        if cfg.FakeLag then
            Notify("ch4rlies hub","Fake Lag: "..v.."ms",2)
        end
    end})

TabM:CreateSection("Info")
TabM:CreateLabel("ch4rlies hub  |  v11.2  |  Tower of Hell")
TabM:CreateLabel("Auto Farm loop rewrite  |  Corridor landing fix")
TabM:CreateLabel("All bypasses active on load and respawn")

Rayfield:LoadConfiguration()
task.wait(0.8)
Notify("ch4rlies hub v11.2","Landing + Auto Farm fully fixed!  v11.2",5)
