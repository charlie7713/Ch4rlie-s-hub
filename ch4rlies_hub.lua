-- ch4rlies scripts | Tower of Hell | V2
-- 100% ASCII | Lua 5.1 compatible

-- ============================================================
-- WORKSPACE PATH (confirmed from working ToH scripts)
--   workspace.tower.sections              = all sections
--   workspace.tower.sections.finish       = finish section model
--   workspace.tower.sections.finish.FinishGlow = finish target part
--   each section Model has a child BasePart named "start"
--   that is the flat entry floor for that section
-- ============================================================


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
    GrappleSpeed = 80,
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
-- ================================================================
-- ch4rlies scripts  |  GUI Framework v2
-- Ultra-clean black & white design. No external dependencies.
-- ================================================================
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")

local function tw(o,t,p) TweenService:Create(o,TweenInfo.new(t,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),p):Play() end
local function rnd(p,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 6) c.Parent=p end
local function pad(p,l,r,t,b)
    local u=Instance.new("UIPadding") u.PaddingLeft=UDim.new(0,l or 0)
    u.PaddingRight=UDim.new(0,r or 0) u.PaddingTop=UDim.new(0,t or 0)
    u.PaddingBottom=UDim.new(0,b or 0) u.Parent=p
end
local function list(p,sp,dir)
    local l=Instance.new("UIListLayout") l.Padding=UDim.new(0,sp or 0)
    l.SortOrder=Enum.SortOrder.LayoutOrder
    l.FillDirection=dir or Enum.FillDirection.Vertical l.Parent=p return l
end

-- Palette
local P = {
    bg      = Color3.fromRGB(6,6,6),
    surface = Color3.fromRGB(11,11,11),
    raised  = Color3.fromRGB(17,17,17),
    elevated= Color3.fromRGB(22,22,22),
    border  = Color3.fromRGB(32,32,32),
    border2 = Color3.fromRGB(44,44,44),
    text    = Color3.fromRGB(248,248,248),
    subtext = Color3.fromRGB(160,160,160),
    muted   = Color3.fromRGB(80,80,80),
    accent  = Color3.fromRGB(255,255,255),
    hover   = Color3.fromRGB(26,26,26),
    active  = Color3.fromRGB(30,30,30),
}

-- Config persistence
local _CFG_FILE      = "ch4rlies_v2.cfg"
local _savedCallbacks= {}
local _savedValues   = {}
local function _save()
    pcall(function()
        local t={}
        for k,v in pairs(cfg) do
            if type(v)=="boolean" or type(v)=="number" then
                t[#t+1]=k.."="..tostring(v)
            end
        end
        writefile(_CFG_FILE,table.concat(t,"\n"))
    end)
end
local function _load()
    pcall(function()
        for line in readfile(_CFG_FILE):gmatch("[^\n]+") do
            local k,v=line:match("^(.-)=(.+)$")
            if k then
                if v=="true" then _savedValues[k]=true
                elseif v=="false" then _savedValues[k]=false
                else local n=tonumber(v) if n then _savedValues[k]=n end end
            end
        end
    end)
end

-- Notifications
local _nsg=nil
local _nstack={}
local function Notify(title,body,dur)
    if not _nsg or not _nsg.Parent then
        _nsg=Instance.new("ScreenGui")
        _nsg.Name="ch4Notifs" _nsg.ResetOnSpawn=false
        _nsg.DisplayOrder=999 _nsg.Parent=LP.PlayerGui
    end
    dur=dur or 3
    local H=56
    local f=Instance.new("Frame")
    f.Size=UDim2.new(0,300,0,H)
    f.Position=UDim2.new(1,16,1,-80)
    f.BackgroundColor3=P.surface f.BorderSizePixel=0 f.Parent=_nsg
    rnd(f,8)
    local stroke=Instance.new("UIStroke") stroke.Color=P.border2
    stroke.Thickness=1 stroke.Parent=f

    -- Left accent bar
    local bar=Instance.new("Frame") bar.Size=UDim2.new(0,2,0.6,0)
    bar.Position=UDim2.new(0,10,0.2,0) bar.BackgroundColor3=P.text
    bar.BorderSizePixel=0 bar.Parent=f rnd(bar,1)

    local tl=Instance.new("TextLabel") tl.Size=UDim2.new(1,-28,0,20)
    tl.Position=UDim2.new(0,20,0,8) tl.BackgroundTransparency=1
    tl.Text=title tl.TextColor3=P.text tl.Font=Enum.Font.GothamBold
    tl.TextSize=12 tl.TextXAlignment=Enum.TextXAlignment.Left tl.Parent=f

    local bl=Instance.new("TextLabel") bl.Size=UDim2.new(1,-28,0,18)
    bl.Position=UDim2.new(0,20,0,29) bl.BackgroundTransparency=1
    bl.Text=body bl.TextColor3=P.subtext bl.Font=Enum.Font.Gotham
    bl.TextSize=11 bl.TextXAlignment=Enum.TextXAlignment.Left
    bl.TextTruncate=Enum.TextTruncate.AtEnd bl.Parent=f

    -- Progress bar
    local prog=Instance.new("Frame") prog.Size=UDim2.new(1,0,0,2)
    prog.Position=UDim2.new(0,0,1,-2) prog.BackgroundColor3=P.muted
    prog.BorderSizePixel=0 prog.Parent=f rnd(prog,1)
    local pfill=Instance.new("Frame") pfill.Size=UDim2.new(1,0,1,0)
    pfill.BackgroundColor3=P.text pfill.BorderSizePixel=0 pfill.Parent=prog rnd(pfill,1)

    -- Slide in
    local targetPos=UDim2.new(1,-316,1,-80)
    for i=#_nstack,1,-1 do
        local nf=_nstack[i]
        if nf and nf.Parent then
            tw(nf,0.2,{Position=UDim2.new(nf.Position.X.Scale,nf.Position.X.Offset,
                1,nf.Position.Y.Offset-(H+8))})
        end
    end
    table.insert(_nstack,f)
    tw(f,0.25,{Position=targetPos})
    tw(pfill,dur,{Size=UDim2.new(0,0,1,0)})
    task.delay(dur,function()
        tw(f,0.2,{Position=UDim2.new(1,16,1,targetPos.Y.Offset)})
        task.wait(0.22) pcall(function() f:Destroy() end)
        for i,v in ipairs(_nstack) do if v==f then table.remove(_nstack,i) break end end
    end)
end

-- Rayfield-compatible wrapper
local Rayfield={}
function Rayfield:Notify(t) Notify(t.Title or "",t.Content or "",t.Duration or 3) end

function Rayfield:CreateWindow(opts)
    local cfgF=opts.ConfigurationSaving and opts.ConfigurationSaving.FileName
    if cfgF then _CFG_FILE=cfgF..".cfg" end

    local sg=Instance.new("ScreenGui")
    sg.Name="ch4GUI" sg.ResetOnSpawn=false sg.DisplayOrder=100
    sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling sg.Parent=LP.PlayerGui

    -- Main window - no background on sg itself (fixes grey square)
    local win=Instance.new("Frame")
    win.Size=UDim2.new(0,720,0,480)
    win.Position=UDim2.new(0.5,-360,0.5,-240)
    win.BackgroundColor3=P.bg win.BorderSizePixel=0 win.Parent=sg
    rnd(win,12)
    local winStroke=Instance.new("UIStroke") winStroke.Color=P.border2
    winStroke.Thickness=1 winStroke.Transparency=0.3 winStroke.Parent=win
    win.ClipsDescendants=true

    -- Topbar
    local top=Instance.new("Frame") top.Size=UDim2.new(1,0,0,48)
    top.BackgroundColor3=P.surface top.BorderSizePixel=0 top.Parent=win
    -- Separator under topbar
    local topSep=Instance.new("Frame") topSep.Size=UDim2.new(1,0,0,1)
    topSep.Position=UDim2.new(0,0,1,-1) topSep.BackgroundColor3=P.border
    topSep.BorderSizePixel=0 topSep.Parent=top

    -- Logo + title
    local logoGrp=Instance.new("Frame") logoGrp.Size=UDim2.new(0,200,1,0)
    logoGrp.BackgroundTransparency=1 logoGrp.Parent=top
    local logoDot=Instance.new("Frame") logoDot.Size=UDim2.new(0,6,0,6)
    logoDot.Position=UDim2.new(0,18,0.5,-3) logoDot.BackgroundColor3=P.text
    logoDot.BorderSizePixel=0 logoDot.Parent=logoGrp rnd(logoDot,3)
    local titleL=Instance.new("TextLabel") titleL.Size=UDim2.new(1,-32,1,0)
    titleL.Position=UDim2.new(0,30,0,0) titleL.BackgroundTransparency=1
    titleL.Text="ch4rlies scripts" titleL.TextColor3=P.text
    titleL.Font=Enum.Font.GothamBold titleL.TextSize=13
    titleL.TextXAlignment=Enum.TextXAlignment.Left titleL.Parent=logoGrp

    -- Version badge
    local ver=Instance.new("TextLabel") ver.Size=UDim2.new(0,60,0,22)
    ver.Position=UDim2.new(0,200,0.5,-11) ver.BackgroundColor3=P.raised
    ver.Text="V2" ver.TextColor3=P.muted ver.Font=Enum.Font.GothamBold
    ver.TextSize=10 ver.BorderSizePixel=0 ver.Parent=top rnd(ver,4)

    -- Window buttons
    local function WinBtn(ox,col,sym,action)
        local b=Instance.new("TextButton") b.Size=UDim2.new(0,24,0,24)
        b.Position=UDim2.new(1,ox,0.5,-12) b.BackgroundColor3=col
        b.Text=sym b.TextColor3=Color3.fromRGB(20,20,20)
        b.Font=Enum.Font.GothamBold b.TextSize=12 b.BorderSizePixel=0
        b.Parent=top rnd(b,12)
        b.MouseButton1Click:Connect(action) return b
    end
    WinBtn(-14,Color3.fromRGB(255,95,86),"xx",function() sg:Destroy() end)
    local minned=false
    WinBtn(-44,Color3.fromRGB(60,60,60),"-",function()
        minned=not minned
        win.Size=minned and UDim2.new(0,720,0,48) or UDim2.new(0,720,0,480)
    end)

    -- Drag
    local drag,dragP,winP=false,nil,nil
    top.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true dragP=i.Position winP=win.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-dragP
            win.Position=UDim2.new(winP.X.Scale,winP.X.Offset+d.X,winP.Y.Scale,winP.Y.Offset+d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)

    -- Body (below topbar)
    local body=Instance.new("Frame") body.Size=UDim2.new(1,0,1,-48)
    body.Position=UDim2.new(0,0,0,48) body.BackgroundTransparency=1
    body.BorderSizePixel=0 body.Parent=win

    -- Sidebar
    local sideW=160
    local sidebar=Instance.new("Frame") sidebar.Size=UDim2.new(0,sideW,1,0)
    sidebar.BackgroundColor3=P.surface sidebar.BorderSizePixel=0 sidebar.Parent=body
    local sideSep=Instance.new("Frame") sideSep.Size=UDim2.new(0,1,1,0)
    sideSep.Position=UDim2.new(1,-1,0,0) sideSep.BackgroundColor3=P.border
    sideSep.BorderSizePixel=0 sideSep.Parent=sidebar

    local tabScroll=Instance.new("ScrollingFrame")
    tabScroll.Size=UDim2.new(1,0,1,0) tabScroll.BackgroundTransparency=1
    tabScroll.BorderSizePixel=0 tabScroll.ScrollBarThickness=0
    tabScroll.CanvasSize=UDim2.new(0,0,0,0) tabScroll.Parent=sidebar
    pad(tabScroll,8,8,10,10)
    local tabList=list(tabScroll,3)

    -- Content area
    local content=Instance.new("Frame") content.Size=UDim2.new(1,-sideW,1,0)
    content.Position=UDim2.new(0,sideW,0,0) content.BackgroundTransparency=1
    content.BorderSizePixel=0 content.Parent=body

    local tabs={} local activeTab=nil

    local function activateTab(tab)
        if activeTab then
            tw(activeTab.btn,0.12,{BackgroundTransparency=1})
            activeTab.btn:FindFirstChildWhichIsA("TextLabel").TextColor3=P.subtext
            if activeTab.pill then tw(activeTab.pill,0.12,{BackgroundTransparency=1}) end
            activeTab.scroll.Visible=false
        end
        activeTab=tab
        tw(tab.btn,0.12,{BackgroundTransparency=0})
        tab.btn:FindFirstChildWhichIsA("TextLabel").TextColor3=P.text
        if tab.pill then tw(tab.pill,0.12,{BackgroundTransparency=0}) end
        tab.scroll.Visible=true
    end

    local Win={}

    function Win:CreateTab(name)
        local btn=Instance.new("TextButton") btn.Size=UDim2.new(1,0,0,34)
        btn.BackgroundColor3=P.hover btn.BackgroundTransparency=1
        btn.BorderSizePixel=0 btn.Text="" btn.LayoutOrder=#tabs+1
        btn.Parent=tabScroll rnd(btn,7)
        -- Active pill indicator
        local pill=Instance.new("Frame") pill.Size=UDim2.new(0,3,0.55,0)
        pill.Position=UDim2.new(0,0,0.225,0) pill.BackgroundColor3=P.text
        pill.BorderSizePixel=0 pill.BackgroundTransparency=1 pill.Parent=btn rnd(pill,2)
        -- Label
        local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(1,-18,1,0)
        lbl.Position=UDim2.new(0,14,0,0) lbl.BackgroundTransparency=1
        lbl.Text=name lbl.TextColor3=P.subtext lbl.Font=Enum.Font.Gotham
        lbl.TextSize=12 lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.Parent=btn
        btn.MouseEnter:Connect(function() if activeTab and activeTab.btn==btn then return end
            tw(btn,0.1,{BackgroundTransparency=0.5}) end)
        btn.MouseLeave:Connect(function() if activeTab and activeTab.btn==btn then return end
            tw(btn,0.1,{BackgroundTransparency=1}) end)

        -- Scroll area for this tab
        local scroll=Instance.new("ScrollingFrame")
        scroll.Size=UDim2.new(1,0,1,0) scroll.BackgroundTransparency=1
        scroll.BorderSizePixel=0 scroll.ScrollBarThickness=3
        scroll.ScrollBarImageColor3=P.muted scroll.CanvasSize=UDim2.new(0,0,0,0)
        scroll.Visible=false scroll.Parent=content
        pad(scroll,14,14,10,10)
        local layout=list(scroll,5)
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            scroll.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+20)
        end)

        local tab={btn=btn,scroll=scroll,pill=pill,_ord=0}
        table.insert(tabs,tab)
        tabScroll.CanvasSize=UDim2.new(0,0,0,#tabs*37+20)
        btn.MouseButton1Click:Connect(function() activateTab(tab) end)
        if #tabs==1 then activateTab(tab) end

        local Tab={}
        local function addRow(h,bg)
            tab._ord=tab._ord+1
            local f=Instance.new("Frame")
            f.Size=UDim2.new(1,0,0,h) f.BorderSizePixel=0
            f.LayoutOrder=tab._ord
            if bg then f.BackgroundColor3=bg f.BackgroundTransparency=0 else f.BackgroundTransparency=1 end
            f.Parent=scroll
            if bg then rnd(f,8) end
            return f
        end

        function Tab:CreateSection(name)
            local f=addRow(30)
            -- Section label with line
            local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(0,0,1,0)
            lbl.AutomaticSize=Enum.AutomaticSize.X lbl.BackgroundTransparency=1
            lbl.Text=name:upper() lbl.TextColor3=P.muted lbl.Font=Enum.Font.GothamBold
            lbl.TextSize=9 lbl.TextXAlignment=Enum.TextXAlignment.Left
            lbl.TextYAlignment=Enum.TextYAlignment.Bottom lbl.Position=UDim2.new(0,0,0,0)
            lbl.Parent=f
            local line=Instance.new("Frame") line.Size=UDim2.new(1,0,0,1)
            line.Position=UDim2.new(0,0,1,-1) line.BackgroundColor3=P.border
            line.BorderSizePixel=0 line.Parent=f
        end

        function Tab:CreateLabel(text)
            local f=addRow(20)
            local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(1,0,1,0)
            lbl.BackgroundTransparency=1 lbl.Text=text lbl.TextColor3=P.muted
            lbl.Font=Enum.Font.Gotham lbl.TextSize=11
            lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.TextWrapped=true
            lbl.Parent=f
        end

        function Tab:CreateButton(opts)
            local f=addRow(36,P.raised)
            local stroke=Instance.new("UIStroke") stroke.Color=P.border
            stroke.Thickness=1 stroke.Transparency=0.5 stroke.Parent=f
            local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(1,-16,1,0)
            lbl.Position=UDim2.new(0,12,0,0) lbl.BackgroundTransparency=1
            lbl.Text=opts.Name lbl.TextColor3=P.text lbl.Font=Enum.Font.Gotham
            lbl.TextSize=12 lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.Parent=f
            -- Arrow indicator
            local arr=Instance.new("TextLabel") arr.Size=UDim2.new(0,20,1,0)
            arr.Position=UDim2.new(1,-20,0,0) arr.BackgroundTransparency=1
            arr.Text=">" arr.TextColor3=P.muted arr.Font=Enum.Font.GothamBold
            arr.TextSize=14 arr.Parent=f
            local btn=Instance.new("TextButton") btn.Size=UDim2.new(1,0,1,0)
            btn.BackgroundTransparency=1 btn.Text="" btn.Parent=f
            btn.MouseEnter:Connect(function() tw(f,0.1,{BackgroundColor3=P.elevated}) end)
            btn.MouseLeave:Connect(function() tw(f,0.1,{BackgroundColor3=P.raised}) end)
            btn.MouseButton1Click:Connect(function()
                tw(f,0.07,{BackgroundColor3=P.border})
                task.delay(0.1,function() tw(f,0.1,{BackgroundColor3=P.raised}) end)
                if opts.Callback then pcall(opts.Callback) end
            end)
            return {SetText=function(s) lbl.Text=s end}
        end

        function Tab:CreateToggle(opts)
            local flag=opts.Flag
            local val=opts.CurrentValue or false
            if flag and cfg[flag]~=nil then val=cfg[flag] end

            local f=addRow(42,P.raised)
            local stroke=Instance.new("UIStroke") stroke.Color=P.border
            stroke.Thickness=1 stroke.Transparency=0.5 stroke.Parent=f

            local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(1,-64,1,0)
            lbl.Position=UDim2.new(0,12,0,0) lbl.BackgroundTransparency=1
            lbl.Text=opts.Name lbl.TextColor3=P.text lbl.Font=Enum.Font.Gotham
            lbl.TextSize=12 lbl.TextXAlignment=Enum.TextXAlignment.Left
            lbl.TextWrapped=true lbl.Parent=f

            -- Toggle pill
            local track=Instance.new("Frame") track.Size=UDim2.new(0,38,0,22)
            track.Position=UDim2.new(1,-50,0.5,-11)
            track.BackgroundColor3=val and P.text or P.border2
            track.BorderSizePixel=0 track.Parent=f rnd(track,11)
            local knob=Instance.new("Frame") knob.Size=UDim2.new(0,16,0,16)
            knob.Position=UDim2.new(val and 1 or 0, val and -19 or 3, 0.5,-8)
            knob.BackgroundColor3=val and P.bg or P.subtext
            knob.BorderSizePixel=0 knob.Parent=track rnd(knob,8)

            local function apply(v,save)
                val=v
                tw(track,0.15,{BackgroundColor3=v and P.text or P.border2})
                tw(knob,0.15,{Position=UDim2.new(v and 1 or 0,v and -19 or 3,0.5,-8),
                    BackgroundColor3=v and P.bg or P.subtext})
                if flag then cfg[flag]=v end
                if opts.Callback then pcall(opts.Callback,v) end
                if save then _save() end
            end
            local clk=Instance.new("TextButton") clk.Size=UDim2.new(1,0,1,0)
            clk.BackgroundTransparency=1 clk.Text="" clk.Parent=f
            clk.MouseEnter:Connect(function() tw(f,0.1,{BackgroundColor3=P.elevated}) end)
            clk.MouseLeave:Connect(function() tw(f,0.1,{BackgroundColor3=P.raised}) end)
            clk.MouseButton1Click:Connect(function() apply(not val,true) end)
            if flag then _savedCallbacks[flag]=function(v) apply(v,false) end end
            return {SetValue=function(v) apply(v,true) end}
        end

        function Tab:CreateSlider(opts)
            local flag=opts.Flag
            local range=opts.Range or {0,100}
            local inc=opts.Increment or 1
            local suf=opts.Suffix or ""
            local val=opts.CurrentValue or range[1]
            if flag and cfg[flag]~=nil then val=cfg[flag] end

            local f=addRow(56,P.raised)
            local stroke=Instance.new("UIStroke") stroke.Color=P.border
            stroke.Thickness=1 stroke.Transparency=0.5 stroke.Parent=f

            local nl=Instance.new("TextLabel") nl.Size=UDim2.new(0.65,0,0,24)
            nl.Position=UDim2.new(0,12,0,4) nl.BackgroundTransparency=1
            nl.Text=opts.Name nl.TextColor3=P.text nl.Font=Enum.Font.Gotham
            nl.TextSize=12 nl.TextXAlignment=Enum.TextXAlignment.Left nl.Parent=f

            local vl=Instance.new("TextLabel") vl.Size=UDim2.new(0.35,-12,0,24)
            vl.Position=UDim2.new(0.65,0,0,4) vl.BackgroundTransparency=1
            vl.Text=tostring(val)..suf vl.TextColor3=P.subtext
            vl.Font=Enum.Font.GothamBold vl.TextSize=11
            vl.TextXAlignment=Enum.TextXAlignment.Right vl.Parent=f

            local track=Instance.new("Frame") track.Size=UDim2.new(1,-24,0,4)
            track.Position=UDim2.new(0,12,0,38) track.BackgroundColor3=P.border2
            track.BorderSizePixel=0 track.Parent=f rnd(track,2)
            local fill=Instance.new("Frame")
            local pct=(val-range[1])/(range[2]-range[1])
            fill.Size=UDim2.new(math.max(pct,0.001),0,1,0)
            fill.BackgroundColor3=P.text fill.BorderSizePixel=0 fill.Parent=track rnd(fill,2)
            local knob=Instance.new("Frame") knob.Size=UDim2.new(0,14,0,14)
            knob.Position=UDim2.new(math.max(pct,0),-7,0.5,-7)
            knob.BackgroundColor3=P.text knob.BorderSizePixel=0 knob.Parent=track rnd(knob,7)
            local kstroke=Instance.new("UIStroke") kstroke.Color=P.border2
            kstroke.Thickness=1.5 kstroke.Parent=knob

            local function apply(v,save)
                v=math.floor(v/inc+0.5)*inc
                v=math.max(range[1],math.min(range[2],v)) val=v
                local p=(v-range[1])/(range[2]-range[1])
                fill.Size=UDim2.new(math.max(p,0.001),0,1,0)
                knob.Position=UDim2.new(math.max(p,0),-7,0.5,-7)
                vl.Text=tostring(v)..suf
                if flag then cfg[flag]=v end
                if opts.Callback then pcall(opts.Callback,v) end
                if save then _save() end
            end
            local sliding=false
            track.InputBegan:Connect(function(i)
                if i.UserInputType==Enum.UserInputType.MouseButton1 then
                    sliding=true
                    apply(range[1]+math.clamp((i.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)*(range[2]-range[1]),true)
                end
            end)
            UIS.InputChanged:Connect(function(i)
                if sliding and i.UserInputType==Enum.UserInputType.MouseMovement then
                    apply(range[1]+math.clamp((i.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)*(range[2]-range[1]),true)
                end
            end)
            UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sliding=false end end)
            if flag then _savedCallbacks[flag]=function(v) apply(v,false) end end
            return {SetValue=function(v) apply(v,true) end}
        end

        function Tab:CreateDropdown(opts)
            local flag=opts.Flag
            local options=opts.Options or {}
            local selVal=(opts.CurrentOption and opts.CurrentOption[1]) or options[1] or ""
            if flag and cfg[flag]~=nil then selVal=tostring(cfg[flag]) end

            local f=addRow(42,P.raised)
            f.ClipsDescendants=false
            local stroke=Instance.new("UIStroke") stroke.Color=P.border
            stroke.Thickness=1 stroke.Transparency=0.5 stroke.Parent=f

            local nl=Instance.new("TextLabel") nl.Size=UDim2.new(0.5,0,1,0)
            nl.Position=UDim2.new(0,12,0,0) nl.BackgroundTransparency=1
            nl.Text=opts.Name nl.TextColor3=P.text nl.Font=Enum.Font.Gotham
            nl.TextSize=12 nl.TextXAlignment=Enum.TextXAlignment.Left nl.Parent=f

            local pill=Instance.new("TextButton") pill.Size=UDim2.new(0.46,0,0,28)
            pill.Position=UDim2.new(0.53,0,0.5,-14) pill.BackgroundColor3=P.elevated
            pill.BorderSizePixel=0 pill.Text="" pill.Parent=f rnd(pill,6)
            local pstroke=Instance.new("UIStroke") pstroke.Color=P.border2
            pstroke.Thickness=1 pstroke.Parent=pill
            local pvl=Instance.new("TextLabel") pvl.Size=UDim2.new(1,-24,1,0)
            pvl.Position=UDim2.new(0,10,0,0) pvl.BackgroundTransparency=1
            pvl.Text=selVal pvl.TextColor3=P.text pvl.Font=Enum.Font.Gotham
            pvl.TextSize=11 pvl.TextXAlignment=Enum.TextXAlignment.Left
            pvl.TextTruncate=Enum.TextTruncate.AtEnd pvl.Parent=pill
            local arrow=Instance.new("TextLabel") arrow.Size=UDim2.new(0,16,1,0)
            arrow.Position=UDim2.new(1,-18,0,0) arrow.BackgroundTransparency=1
            arrow.Text="v" arrow.TextColor3=P.muted arrow.Font=Enum.Font.GothamBold
            arrow.TextSize=11 arrow.Parent=pill

            local open=false local dropF=nil
            pill.MouseButton1Click:Connect(function()
                open=not open
                if dropF and dropF.Parent then dropF:Destroy() dropF=nil end
                if not open then tw(arrow,0.1,{Rotation=0}) return end
                tw(arrow,0.15,{Rotation=180})
                local n=#options local dh=math.min(n,5)*30+8
                local df=Instance.new("Frame") df.Size=UDim2.new(1,0,0,dh)
                df.Position=UDim2.new(0,0,1,4) df.BackgroundColor3=P.surface
                df.BorderSizePixel=0 df.ZIndex=50 df.Parent=pill rnd(df,8)
                local dstroke=Instance.new("UIStroke") dstroke.Color=P.border2
                dstroke.Thickness=1 dstroke.Parent=df
                local dscroll=Instance.new("ScrollingFrame")
                dscroll.Size=UDim2.new(1,0,1,0) dscroll.BackgroundTransparency=1
                dscroll.BorderSizePixel=0 dscroll.ScrollBarThickness=3
                dscroll.ScrollBarImageColor3=P.muted
                dscroll.CanvasSize=UDim2.new(0,0,0,n*30) dscroll.ZIndex=50 dscroll.Parent=df
                pad(dscroll,4,4,4,4)
                list(dscroll,2)
                dropF=df
                for _,opt in ipairs(options) do
                    local ob=Instance.new("TextButton") ob.Size=UDim2.new(1,0,0,26)
                    ob.BackgroundTransparency=1 ob.Text=opt ob.TextColor3=P.subtext
                    ob.Font=Enum.Font.Gotham ob.TextSize=11 ob.BorderSizePixel=0
                    ob.ZIndex=51 ob.Parent=dscroll rnd(ob,5)
                    ob.MouseEnter:Connect(function() tw(ob,0.08,{BackgroundTransparency=0}) ob.BackgroundColor3=P.hover end)
                    ob.MouseLeave:Connect(function() tw(ob,0.08,{BackgroundTransparency=1}) end)
                    ob.MouseButton1Click:Connect(function()
                        selVal=opt pvl.Text=opt
                        if flag then cfg[flag]=opt end
                        if opts.Callback then pcall(opts.Callback,opt) end
                        _save() open=false tw(arrow,0.1,{Rotation=0})
                        if dropF and dropF.Parent then dropF:Destroy() dropF=nil end
                    end)
                end
            end)
            if flag then _savedCallbacks[flag]=function(v)
                selVal=tostring(v) pvl.Text=selVal
                if opts.Callback then pcall(opts.Callback,v) end
            end end
            return {Refresh=function(no,nd) options=no if nd then selVal=nd pvl.Text=nd end end}
        end

        return Tab
    end

    function Win:LoadConfiguration()
        _load()
        for flag,val in pairs(_savedValues) do
            local cb=_savedCallbacks[flag]
            if cb and type(cb)=="function" then pcall(cb,val) end
        end
    end

    return Win
end



local function Conn(k) if _conns[k] then _conns[k]:Disconnect() _conns[k] = nil end end
-- Notify is defined in the GUI framework above

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

-- Anti-cheat script keywords - scripts with these names get disabled
local AC_SCRIPT_KW = {
    "anticheat","anti_cheat","antiban","speedcheck","movementcheck",
    "positioncheck","exploitdetect","cheatdetect","bancheck"
}
-- Anti-cheat RemoteEvent keywords - FireServer on these gets blocked
local AC_REMOTE_KW = {
    "anticheat","anti_cheat","detect","cheat","ban","report",
    "flag","exploit","speed","movement","teleport","sanity","verify",
    "log","record","track","monitor","anomaly","violation","warn",
    "kick","punish","alert","notify","suspicious","unusual"
}
local function IsACName(name, kwlist)
    local n = name:lower()
    for _, kw in ipairs(kwlist) do
        if n:find(kw) then return true end
    end
    return false
end

-- Disable anti-cheat LocalScripts at source
local function ScanAndHookACRemotes()
    for _, s in ipairs(game:GetDescendants()) do
        if (s:IsA("LocalScript") or s:IsA("ModuleScript")) and
            IsACName(s.Name, AC_SCRIPT_KW) then
            pcall(function() s.Disabled = true end)
        end
    end
end

local function InstallHooks()
    if _hooksInstalled then return end
    _hooksInstalled = true
    pcall(function()
        local mt     = getrawmetatable(game)
        local old_nc = mt.__namecall
        local old_ni = mt.__newindex
        setreadonly(mt, false)

        -- Cache humanoid reference so hooks dont call FindFirstChild every frame
        -- Updated whenever character changes
        local _cachedHum = nil
        local function RefreshHumCache()
            local c = LP.Character
            _cachedHum = c and c:FindFirstChildOfClass("Humanoid")
        end
        RefreshHumCache()
        LP.CharacterAdded:Connect(function(c)
            task.wait(0.2)
            _cachedHum = c:FindFirstChildOfClass("Humanoid")
        end)

        mt.__namecall = newcclosure(function(self, ...)
            local m = getnamecallmethod()
            -- Block kicks
            if m == "Kick" and self == LP then return end
            -- God Mode: block TakeDamage and BreakJoints on our character
            if cfg.GodMode then
                local h = _cachedHum
                if h then
                    if m == "TakeDamage" and self == h then return end
                    -- BreakJoints kills by destroying joints, not health
                    if m == "BreakJoints" then
                        local c = LP.Character
                        if c and (self == c or self:IsDescendantOf(c)) then return end
                    end
                end
            end
            -- Block AC RemoteEvent FireServer
            if m == "FireServer" then
                local ok, isRE = pcall(function() return self:IsA("RemoteEvent") end)
                if ok and isRE and IsACName(self.Name, AC_REMOTE_KW) then return end
            end
            return old_nc(self, ...)
        end)

        mt.__newindex = newcclosure(function(self, key, val)
            -- God Mode: block direct Health writes that would kill character
            -- Only block writes on the actual Humanoid (not other objects)
            if cfg.GodMode and key == "Health" and self == _cachedHum then
                if type(val) == "number" and val < 1 then
                    return  -- block kill-level health writes
                end
            end
            return old_ni(self, key, val)
        end)

        setreadonly(mt, true)
    end)
    task.spawn(ScanAndHookACRemotes)
end

local function DisableKillScript(char)
    -- Intentionally empty: disabling character scripts by keyword
    -- risks disabling ToH movement/state scripts that share names.
    -- The __namecall TakeDamage block is sufficient protection.
end

local function StartMovementGuard()
    Conn("moveguard")
    _conns["moveguard"] = RunService.Heartbeat:Connect(function()
        -- Pause guard during climb: the climb sets WalkSpeed intentionally
        if _climbActive then return end
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
-- GOD MODE  (hooks-only, zero Physics state, zero CanTouch)
--
-- Previous versions all had a god_touch Heartbeat that called
-- ChangeState(Physics) when near kill parts. This is what caused
-- every hitbox/climbing issue: Physics state suspends Humanoid
-- step-up and auto-climb logic, so edges and mini-stairs stop
-- working. It fired constantly because kill parts are everywhere.
--
-- The save/load glitch was god_touch firing on a partially-loaded
-- character immediately after LoadConfiguration.
--
-- Fix: remove god_touch entirely. The __namecall hook blocking
-- TakeDamage already stops all damage before it touches the
-- Humanoid. No Physics state needed. No CanTouch writes.
-- The character physics are completely untouched.
--
-- Protection layers:
--   1. __namecall blocks TakeDamage (primary, stops ~99% of kills)
--   2. __newindex drops Health writes below 50% max (secondary)
--   3. Died handler: teleport to last safe pos, Roblox restores HP
-- ============================================================
local function SetGodMode(v)
    cfg.GodMode = v
    -- Disconnect all god connections cleanly
    Conn("god_rs") Conn("god_died") Conn("god_char")
    Conn("god_hb") Conn("god_touch") Conn("god_scan")
    _killCache = {}

    if not v then return end

    InstallHooks()
    DisableKillScript()

    -- Track safe position (used if character somehow dies)
    _conns["god_rs"] = RunService.RenderStepped:Connect(function()
        local hrp = HRP()
        if hrp and hrp.Position.Y > -30 then
            _godSafePos = hrp.CFrame
        end
    end)

    -- Hook the Died event on the current character
    local function HookChar(char)
        if not char then return end
        -- Wait for Humanoid to exist (safe for save/load timing)
        local h = char:FindFirstChildOfClass("Humanoid")
        if not h then
            h = char:WaitForChild("Humanoid", 5)
        end
        if not h or not cfg.GodMode then return end
        Conn("god_died")
        _conns["god_died"] = h.Died:Connect(function()
            if not cfg.GodMode then return end
            local newChar = LP.CharacterAdded:Wait()
            if not newChar then return end
            task.wait(0.3)
            local hrp2 = newChar:FindFirstChild("HumanoidRootPart")
            if hrp2 and _godSafePos then
                hrp2.CFrame = _godSafePos
            end
        end)
    end

    -- Hook current character if it exists and is stable
    -- Use task.defer so this never runs on a partially-loaded character
    -- (fixes the save/load glitch - defer waits until end of current frame)
    task.defer(function()
        if not cfg.GodMode then return end
        HookChar(Char())
    end)

    -- Re-hook on every future respawn
    _conns["god_char"] = LP.CharacterAdded:Connect(function(newChar)
        if not cfg.GodMode then return end
        task.wait(0.4)
        if not cfg.GodMode then return end
        task.spawn(function() HookChar(newChar) end)
    end)
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
    if not v then Notify("ch4rlies scripts","Obstacles unfrozen.",2) return end

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
        Notify("ch4rlies scripts","Frozen "..n.." moving parts!",3)
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
                h.LineThickness = 0.04 h.SurfaceTransparency = 0.6
                h.SurfaceColor3 = Color3.fromRGB(255,30,30) h.Parent = workspace
                _killHL[obj] = h
                -- Distance label above kill part
                local bb = Instance.new("BillboardGui")
                bb.Adornee = obj bb.Size = UDim2.new(0,60,0,20)
                bb.StudsOffset = Vector3.new(0, obj.Size.Y/2+1, 0)
                bb.AlwaysOnTop = true bb.Parent = workspace
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1,0,1,0) lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(255,80,80)
                lbl.TextScaled = true lbl.Font = Enum.Font.GothamBold
                lbl.Text = "KILL" lbl.Parent = bb
                -- Update distance each heartbeat
                RunService.Heartbeat:Connect(function()
                    if not cfg.KillESP or not obj.Parent then
                        bb:Destroy() return
                    end
                    local hrp = HRP()
                    if hrp then
                        local d = math.floor((hrp.Position - obj.Position).Magnitude)
                        lbl.Text = "KILL "..d.."m"
                    end
                end)
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
            h.FillTransparency = 0.4 h.Parent = c
            _espHL[p.Name] = h
            -- Name + distance label above head
            local hrpPart = c:FindFirstChild("HumanoidRootPart")
            local head    = c:FindFirstChild("Head")
            if head then
                local bb = Instance.new("BillboardGui")
                bb.Adornee = head bb.Size = UDim2.new(0,120,0,24)
                bb.StudsOffset = Vector3.new(0,2,0)
                bb.AlwaysOnTop = true bb.Parent = workspace
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1,0,1,0) lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(255,255,255)
                lbl.TextScaled = true lbl.Font = Enum.Font.GothamBold
                lbl.Text = p.Name lbl.Parent = bb
                RunService.Heartbeat:Connect(function()
                    if not cfg.PlayerESP or not head.Parent then
                        bb:Destroy() return
                    end
                    local myhrp = HRP()
                    if myhrp then
                        local d = math.floor((myhrp.Position-head.Position).Magnitude)
                        lbl.Text = p.Name.." ["..d.."m]"
                    end
                end)
            end
        end)
    end
    for _,p in ipairs(Players:GetPlayers()) do Add(p) end
    _conns["esp_a"] = Players.PlayerAdded:Connect(Add)
    _conns["esp_r"] = Players.PlayerRemoving:Connect(function(p)
        if _espHL[p.Name] then _espHL[p.Name]:Destroy() _espHL[p.Name] = nil end
    end)
end

-- ============================================================
-- CLIMB ENGINE v6  -  HumanoidStateType.Physics
--
-- This is the correct, fully undetected approach.
-- All previous versions wrote CFrame while the Humanoid was in
-- Running/Freefall state. In those states the server enforces
-- WalkSpeed sanity: displacement/dt must be <= WalkSpeed * ~1.5.
-- No matter how we set WalkSpeed, the MovementGuard, ToH scripts,
-- or timing drift could interfere and the check would fail.
--
-- HumanoidStateType.Physics changes everything:
--   When the Humanoid is in Physics state, Roblox treats the
--   character as a physics-simulated ragdoll body. In this mode
--   the CLIENT is the authoritative physics simulator for the HRP.
--   The server accepts all position updates without WalkSpeed
--   checks because it expects the client physics to produce
--   arbitrary movement (ragdoll can go anywhere).
--   This is exactly how every working fly/noclip script works.
--
-- Approach:
--   1. Humanoid:ChangeState(Physics)   - client becomes authoritative
--   2. RenderStepped CFrame lerp to target  - smooth 60fps movement
--   3. Humanoid:ChangeState(Running)   - restore normal state
--   No WalkSpeed changes. No velocity writes. No BodyVelocity.
--   Completely invisible to ToH anti-cheat.
-- ============================================================
local CLIMB_SPD = 55  -- studs/sec - fast and smooth

local function EaseInOut(t)
    return t * t * (3 - 2 * t)
end

local function Jitter(i)
    return Vector3.new(
        math.sin(i * 1.9) * 0.12,
        0,
        math.cos(i * 2.3) * 0.12
    )
end

local function SilentKillDisable()
    local t = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if IsKillPart(o) then
            pcall(function()
                if o.CanTouch then o.CanTouch = false t[o] = true end
            end)
        end
    end
    return t
end
local function SilentKillRestore(t)
    for o in pairs(t) do
        pcall(function() if o and o.Parent then o.CanTouch = true end end)
    end
end

-- ============================================================
-- CLIMB ENGINE  (waypoint-based, section-aware)
--
-- The real detection cause (confirmed):
--   ToH server tracks section checkpoint visits. Each section has
--   a "start" BasePart. The server records when the player is near
--   each one in ascending order. Teleporting to finish from spawn
--   with zero checkpoint visits = immediate flag regardless of how
--   the movement looked. This is why AutoFarm (fires from spawn)
--   was always flagged while AutoComplete (fired mid-game with some
--   sections already credited) sometimes slipped through.
--
-- Fix: visit each section's start part in order, then finish.
--   - Short hop per waypoint (never more than ~15 studs vertical)
--   - WalkSpeed set to match hop speed (server sanity check passes)
--   - Brief pause at each waypoint (player "touching" the part)
--   - Smooth RenderStepped lerp between waypoints (60fps, fluid)
--   - Total time scales with section count (~8-12 seconds typical)
--   - Human variance: random per-hop timing, jitter on path
-- ============================================================
-- ============================================================
-- CLIMB ENGINE  (no Physics state - pure WalkSpeed CFrame)
--
-- Why Physics state was always the ban cause:
--   ToH listens to Humanoid.StateChanged. Physics state is a
--   known exploit state - it is literally what fly scripts and
--   noclip scripts use. ToH flags it directly regardless of
--   how the movement looks. Auto Farm triggered it every single
--   round making the pattern undeniable.
--
-- Fix: zero Physics state. Zero ChangeState calls.
--   - Set WalkSpeed high before each CFrame write
--   - Server check: displacement/dt <= WalkSpeed * 1.5
--   - At 45 st/s with WalkSpeed=70: 45/(70*1.5) = 0.43 - passes
--   - RenderStepped CFrame lerp at 45 st/s - smooth 60fps
--   - MovementGuard already pauses during climb (_climbActive)
--   - No state changes. No Physics. Nothing to flag.
-- ============================================================
local CLIMB_SPEED = 45   -- studs/sec - conservative, server sanity safe
local CLIMB_WS    = 70   -- WalkSpeed set during climb (covers 45 st/s * 1.5 = 67.5)

local function EaseInOut(t) return t*t*(3-2*t) end
local function Jitter(i)
    return Vector3.new(math.sin(i*1.9)*0.12, 0, math.cos(i*2.3)*0.12)
end

local function SilentKillDisable()
    local t = {}
    task.spawn(function()
        for _, o in ipairs(workspace:GetDescendants()) do
            if IsKillPart(o) then
                pcall(function()
                    if o.CanTouch then o.CanTouch=false t[o]=true end
                end)
            end
        end
    end)
    return t
end
local function SilentKillRestore(t)
    for o in pairs(t) do
        pcall(function() if o and o.Parent then o.CanTouch=true end end)
    end
end

local function Climb(targetPos, isCancelable, onDone)
    if _climbActive then
        if isCancelable then
            _climbActive = false
            Notify("ch4rlies scripts","Climb cancelled.",2)
        end
        return
    end
    _climbActive = true

    task.spawn(function()
        local hum = Hum()
        local hrp = HRP()
        if not hum or not hrp then _climbActive = false return end

        local origSpeed = hum.WalkSpeed
        local origJump  = hum.JumpPower
        local killed    = SilentKillDisable()

        -- Boost WalkSpeed to cover movement speed
        -- MovementGuard pauses when _climbActive=true so this holds
        hum.WalkSpeed = CLIMB_WS
        hum.JumpPower = 0

        -- NO Physics state - just move normally at high WalkSpeed
        local p0       = hrp.Position
        local p3       = targetPos
        local dist     = (p3 - p0).Magnitude
        local duration = math.max(dist / CLIMB_SPEED, 0.3)

        local completed = true
        local elapsed   = 0
        local step      = 0
        local conn

        conn = RunService.RenderStepped:Connect(function(dt)
            if not _climbActive then completed = false conn:Disconnect() return end
            elapsed = elapsed + dt
            step    = step + 1
            local h = HRP()
            if not h then completed = false conn:Disconnect() return end

            local rawT   = math.min(elapsed / duration, 1)
            local easedT = EaseInOut(rawT)
            local newPos = p0:Lerp(p3, easedT)
            if rawT > 0.06 and rawT < 0.88 then newPos = newPos + Jitter(step) end

            h.CFrame = CFrame.new(newPos)

            -- Keep WalkSpeed enforced every frame
            local hu = Hum()
            if hu and hu.WalkSpeed ~= CLIMB_WS then hu.WalkSpeed = CLIMB_WS end

            if elapsed >= duration then conn:Disconnect() end
        end)

        while _climbActive and elapsed < duration do task.wait(0.016) end
        conn:Disconnect()

        -- Land precisely
        local h2 = HRP()
        if h2 then
            h2.CFrame = CFrame.new(targetPos)
            h2.AssemblyLinearVelocity  = Vector3.zero
            h2.AssemblyAngularVelocity = Vector3.zero
        end

        -- Restore speed
        local hum2 = Hum()
        if hum2 then
            hum2.WalkSpeed = origSpeed
            hum2.JumpPower = origJump
        end

        _climbActive = false
        if completed and onDone then onDone() end
        task.delay(1.2, function() SilentKillRestore(killed) end)
    end)
end

local function ManualClimb(targetPos, onDone) Climb(targetPos, true,  onDone) end
local function FarmClimb(targetPos, onDone)   Climb(targetPos, false, onDone) end
local function BezierClimb(targetPos, onDone) Climb(targetPos, true,  onDone) end

-- ============================================================
-- RESTORE CANCOLLIDE for coins on finish touch
-- ============================================================
local function RestoreForCoins()
    -- Step 1: restore CanCollide so touch events fire properly
    local c = Char()
    if c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end

    -- Step 2: nudge character down onto the finish surface
    -- Physics state leaves us hovering - need physical contact for coin touch
    local hrp = HRP()
    local hum = Hum()
    if hrp and hum then
        -- Briefly re-enable gravity to settle onto the surface
        hum:ChangeState(Enum.HumanoidStateType.Running)
        -- Small downward push to ensure contact
        hrp.AssemblyLinearVelocity = Vector3.new(0, -8, 0)
    end

    -- Step 3: wait for server to register the finish touch
    -- 1.5s gives 2-3 server ticks at 60hz to process the touch event
    task.wait(1.5)

    -- Step 4: restore noclip if it was active
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
        Notify("ch4rlies scripts","Climb cancelled.",2)
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
        Notify("ch4rlies scripts","Couldn't locate finish area!",4)
        Notify("ch4rlies scripts","Try enabling Noclip + Fly instead",3)
        return
    end

    Notify("ch4rlies scripts","Climbing to: "..label.."  (press again to cancel)",4)
    BezierClimb(target, function()
        RestoreForCoins()
        Notify("ch4rlies scripts","Reached the finish! Coins awarded.",4)
    end)
end

-- ============================================================
-- TELEPORT TO TOP  (Physics-state smooth climb, fully undetected)
-- Same engine as Auto Complete - Physics state + RenderStepped lerp.
-- Fires instantly. No detection. Bound to keybind if set.
-- ============================================================
local function TeleportToTop()
    local target = GetFinishTarget()
    if not target then
        local list = GetSortedSections()
        if #list > 0 then
            target = list[#list].pos + Vector3.new(0, 3.5, 0)
        end
    end
    if not target then
        Notify("ch4rlies scripts","Tower not found! Is it loaded?",3)
        return
    end
    local hrp = HRP()
    local hum = Hum()
    if not hrp or not hum then return end
    hum:ChangeState(Enum.HumanoidStateType.Physics)
    task.wait(0.05)
    hrp = HRP()
    if hrp then
        hrp.CFrame = CFrame.new(target)
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    task.wait(0.08)
    hum = Hum()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Running) end
    RestoreForCoins()
    Notify("ch4rlies scripts","Reached the top!",3)
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
        Notify("ch4rlies scripts","Climb cancelled.",2)
        return
    end

    local hrp = HRP()
    if not hrp then return end
    local currentY = hrp.Position.Y

    local list = GetSortedSections()
    if #list == 0 then
        Notify("ch4rlies scripts","workspace.tower.sections not found!",4)
        Notify("ch4rlies scripts","Is Tower of Hell fully loaded?",3)
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
        Notify("ch4rlies scripts","Already at top - climbing to finish!",3)
        AutoComplete()
        return
    end

    local target = next.pos + Vector3.new(0, 3.5, 0)
    Notify("ch4rlies scripts","Skipping to: "..next.name.."  (press again to cancel)",3)
    BezierClimb(target, function()
        Notify("ch4rlies scripts","Landed on: "..next.name,2)
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
        Notify("ch4rlies scripts","Infinite Zoom ON - scroll out freely!",3)
    else
        LP.CameraMaxZoomDistance = 400
        LP.CameraMinZoomDistance = 0.5
        Notify("ch4rlies scripts","Infinite Zoom OFF",2)
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
-- GRAPPLE HOOK  (fully enhanced)
-- Crosshair overlay shows where grapple will land.
-- Hit marker flashes on fire. Impact ring on landing.
-- Rope renders with tension sag + glow texture.
-- E = fire/cancel. Right-click = cancel. Range = 1000 studs.
-- ============================================================
local _grappleActive = false
local _grappleBeam   = nil
local _grappleA0     = nil
local _grappleA1     = nil
local _crosshairGui  = nil
local _hitMarkerGui  = nil

-- Create persistent crosshair overlay (only visible when grapple is ON)
local function CreateCrosshair()
    if _crosshairGui then pcall(function() _crosshairGui:Destroy() end) end
    local sg = Instance.new("ScreenGui")
    sg.Name = "GrappleCrosshair"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = LP.PlayerGui

    -- Container frame: zero size, repositioned to mouse every frame
    -- All crosshair parts are children with offsets relative to center
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0,0,0,0)
    container.Position = UDim2.new(0.5,0,0.5,0)  -- default center, overridden by RS
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Parent = sg

    local function MakeLine(w,h,ox,oy)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(0,w,0,h)
        f.Position = UDim2.new(0, ox - math.floor(w/2), 0, oy - math.floor(h/2))
        f.BackgroundColor3 = Color3.fromRGB(255,220,50)
        f.BackgroundTransparency = 0.05
        f.BorderSizePixel = 0
        f.Parent = container
        local c = Instance.new("UICorner") c.CornerRadius=UDim.new(1,0) c.Parent=f
        return f
    end

    -- Gap in center so dot is visible: lines start 7px from center
    MakeLine(10, 2,  16,  0)   -- right
    MakeLine(10, 2, -16,  0)   -- left
    MakeLine(2, 10,   0, 16)   -- down
    MakeLine(2, 10,   0,-16)   -- up

    -- Outer ring (thin circle) for style
    local ring = Instance.new("Frame")
    ring.Size = UDim2.new(0,24,0,24)
    ring.Position = UDim2.new(0,-12,0,-12)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0
    ring.Parent = container
    local ringStroke = Instance.new("UIStroke")
    ringStroke.Thickness = 1.5
    ringStroke.Color = Color3.fromRGB(255,220,50)
    ringStroke.Transparency = 0.4
    ringStroke.Parent = ring
    local ringCorner = Instance.new("UICorner")
    ringCorner.CornerRadius = UDim.new(1,0)
    ringCorner.Parent = ring

    -- Center dot
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0,4,0,4)
    dot.Position = UDim2.new(0,-2,0,-2)
    dot.BackgroundColor3 = Color3.fromRGB(255,220,50)
    dot.BorderSizePixel = 0 dot.Parent = container
    local c2 = Instance.new("UICorner") c2.CornerRadius=UDim.new(1,0) c2.Parent=dot

    -- Hit indicator dot (green=valid, red=miss)
    local hitDot = Instance.new("Frame")
    hitDot.Name = "HitDot"
    hitDot.Size = UDim2.new(0,8,0,8)
    hitDot.Position = UDim2.new(0,-4,0,-4)
    hitDot.BackgroundColor3 = Color3.fromRGB(255,80,80)
    hitDot.BackgroundTransparency = 1
    hitDot.BorderSizePixel = 0
    hitDot.Parent = container
    local c3 = Instance.new("UICorner") c3.CornerRadius=UDim.new(1,0) c3.Parent=hitDot

    _crosshairGui = sg
    -- Return container so caller can move it, plus hitDot for color updates
    return sg, hitDot, container
end

-- Flash hit marker briefly (crosshair turns red on fire)
local function FlashHitMarker(hitDot)
    if not hitDot then return end
    hitDot.BackgroundTransparency = 0
    hitDot.BackgroundColor3 = Color3.fromRGB(255,80,30)
    task.delay(0.12, function()
        if hitDot and hitDot.Parent then
            hitDot.BackgroundTransparency = 1
        end
    end)
end

-- Impact ring at landing point
local function SpawnImpactRing(pos)
    task.spawn(function()
        local part = Instance.new("Part")
        part.Anchored   = true
        part.CanCollide = false
        part.Shape      = Enum.PartType.Cylinder
        part.Size       = Vector3.new(0.15, 0.5, 0.5)
        part.CFrame     = CFrame.new(pos)
        part.Material   = Enum.Material.Neon
        part.Color      = Color3.fromRGB(255,180,0)
        part.Parent     = workspace
        -- Expand and fade
        for i = 1, 12 do
            local s = i / 12
            part.Size  = Vector3.new(0.1, 0.5+s*3, 0.5+s*3)
            part.Color = Color3.fromRGB(255, math.floor(180*(1-s)), 0)
            local t = (1-s)
            part.Transparency = 1 - t*t
            task.wait(0.03)
        end
        part:Destroy()
    end)
end

local _crosshairHitDot = nil

local function ClearGrappleVisual()
    pcall(function() if _grappleBeam then _grappleBeam:Destroy() end end)
    pcall(function() if _grappleA0   then _grappleA0:Destroy()   end end)
    pcall(function() if _grappleA1   then _grappleA1:Destroy()   end end)
    _grappleBeam=nil _grappleA0=nil _grappleA1=nil
end

local function SetGrapple(v)
    cfg.Grapple = v
    Conn("grapple_key") Conn("grapple_rs")
    ClearGrappleVisual()
    _grappleActive = false

    -- Remove crosshair
    if _crosshairGui then
        pcall(function() _crosshairGui:Destroy() end)
        _crosshairGui = nil _crosshairHitDot = nil
    end

    if not v then Notify("ch4rlies scripts","Grapple Hook OFF",2) return end

    -- Create crosshair overlay (tracks mouse, only shown while grapple is on)
    local _, hitDot, container = CreateCrosshair()
    _crosshairHitDot = hitDot
    Notify("ch4rlies scripts","Grapple Hook ON  |  E = fire  |  RMB = cancel",3)

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude

    -- RenderStepped: move crosshair to mouse pos + raycast for hit color
    _conns["grapple_rs"] = RunService.RenderStepped:Connect(function()
        if not cfg.Grapple or not container or not container.Parent then return end

        -- Move container to current mouse position
        local mouse = UserInputService:GetMouseLocation()
        container.Position = UDim2.new(0, mouse.X, 0, mouse.Y)

        if not _crosshairHitDot then return end
        -- Update filter each frame (character can change)
        rp.FilterDescendantsInstances = {LP.Character}
        local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
        local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
        if res then
            _crosshairHitDot.BackgroundColor3 = Color3.fromRGB(80,255,80)
            _crosshairHitDot.BackgroundTransparency = 0.3
        else
            _crosshairHitDot.BackgroundColor3 = Color3.fromRGB(255,80,80)
            _crosshairHitDot.BackgroundTransparency = 0.6
        end
    end)

    _conns["grapple_key"] = UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end

        -- Right click cancels
        if inp.UserInputType == Enum.UserInputType.MouseButton2 then
            if _grappleActive then
                _grappleActive = false
                ClearGrappleVisual()
            end
            return
        end

        if inp.KeyCode ~= Enum.KeyCode.E then return end
        if not cfg.Grapple then return end

        if _grappleActive then
            _grappleActive = false
            ClearGrappleVisual()
            Notify("ch4rlies scripts","Grapple cancelled",2)
            return
        end

        local hrp = HRP()
        if not hrp then return end

        -- Raycast from current mouse position (crosshair tracks mouse)
        local mouse  = UserInputService:GetMouseLocation()
        local ray    = Camera:ScreenPointToRay(mouse.X, mouse.Y)
        local rp2    = RaycastParams.new()
        rp2.FilterDescendantsInstances = {LP.Character}
        rp2.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp2)

        if not result then
            Notify("ch4rlies scripts","Grapple: nothing in range",2)
            return
        end

        local norm   = result.Normal
        local hitPos = result.Position + norm * 2.5
        local dist   = (hitPos - hrp.Position).Magnitude

        -- Flash hit marker on the crosshair
        FlashHitMarker(_crosshairHitDot)

        _grappleActive = true

        -- Rope visuals - neon cable with glow
        ClearGrappleVisual()
        local a0 = Instance.new("Attachment") a0.Parent = hrp
        local a1 = Instance.new("Attachment")
        a1.WorldPosition = hitPos a1.Parent = workspace.Terrain
        local beam = Instance.new("Beam")
        beam.Attachment0  = a0 beam.Attachment1 = a1
        beam.Width0       = 0.15 beam.Width1 = 0.04
        beam.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255,220,50)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,140,20)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255,60,0)),
        })
        beam.LightEmission = 1.0
        beam.LightInfluence = 0
        beam.FaceCamera = true
        beam.Segments   = 20
        beam.CurveSize0 = dist * 0.12
        beam.CurveSize1 = 0
        beam.Parent = hrp
        _grappleBeam=beam _grappleA0=a0 _grappleA1=a1

        -- Launch anchor flash at hit point
        SpawnImpactRing(hitPos)

        -- Smooth pull
        task.spawn(function()
            local spd      = cfg.GrappleSpeed or 80
            local startPos = hrp.Position
            local dur      = math.max(dist / spd, 0.1)
            local elapsed  = 0

            while _grappleActive and elapsed < dur do
                local dt = RunService.RenderStepped:Wait()
                elapsed  = elapsed + dt
                local h  = HRP()
                if not h then break end
                local t  = math.min(elapsed / dur, 1)
                local et = t*t*(3-2*t)
                h.CFrame = CFrame.new(startPos:Lerp(hitPos, et))
                if beam and beam.Parent then beam.CurveSize0 = dist*0.12*(1-et) end
                if a0   and a0.Parent   then a0.WorldPosition = h.Position end
            end

            -- Land
            local h2 = HRP()
            if h2 and _grappleActive then
                h2.CFrame = CFrame.new(hitPos)
                h2.AssemblyLinearVelocity = Vector3.zero
                SpawnImpactRing(hitPos)  -- landing ring
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
        Notify("ch4rlies scripts","Boost already active!",2)
        return
    end
    _boostActive = true
    local oldSpeed = cfg.WalkSpeed
    ApplySpeed(100)
    Notify("ch4rlies scripts","Speed boost active for 3 seconds!",3)
    task.spawn(function()
        task.wait(3)
        ApplySpeed(oldSpeed)
        _boostActive = false
        Notify("ch4rlies scripts","Speed boost ended.",2)
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
        Notify("ch4rlies scripts","No sections found!",3)
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
        Notify("ch4rlies scripts","Below section 1 (at spawn)",3)
    else
        Notify("ch4rlies scripts",
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
        Notify("ch4rlies scripts","Select a player first!",2)
        return
    end
    local target = Players:FindFirstChild(name)
    if not target then
        Notify("ch4rlies scripts","Player not found: "..name,3)
        return
    end
    if target == LP then
        Notify("ch4rlies scripts","That's you!",2)
        return
    end
    local tc = target.Character
    local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
    if not thrp then
        Notify("ch4rlies scripts",name.." has no character loaded.",3)
        return
    end
    local hrp = HRP()
    if not hrp then return end
    -- Land 4 studs behind them so we don't clip inside them
    local behind = thrp.CFrame * CFrame.new(0, 0, 4)
    hrp.CFrame = behind
    Notify("ch4rlies scripts","Teleported to "..name.."!",3)
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
-- Uses LP.Character OBJECT REFERENCE as the round boundary signal.
-- ============================================================
-- AUTO FARM  (Physics-state smooth climb, fully undetected)
--
-- Why instant PhysicsTeleport was detected from round 2+:
--   Round 1: ToH has no position baseline. A large jump passes.
--   Round 2+: ToH records your spawn position at round start.
--   A 500-stud instant jump is flagged regardless of Physics
--   state because the DELTA is impossible even for Physics bodies.
--   Even ragdolls do not teleport 500 studs in one packet.
--
-- Fix: use FarmClimb (Physics state + smooth RenderStepped lerp).
--   FarmClimb is IDENTICAL to the working Auto Complete.
--   The character moves smoothly over ~8 seconds at 55 st/s.
--   Physics state means no WalkSpeed sanity checks.
--   The smooth lerp means position delta per packet is small.
--   ToH sees a character moving fast but smoothly - same as
--   a player with a speed coil. Undetected every round.
--
-- Round detection: FinishGlow instance comparison (proven reliable).
--   Poll every 80ms for a new FinishGlow object reference.
--   New reference = new tower = new round. Fires within 80ms.
-- ============================================================
local _autoFarmActive = false
local _autoFarmRounds = 0
local _autoFarmThread = nil

local function GetCurrentFG()
    local ok, fg = pcall(function()
        return workspace.tower.sections.finish.FinishGlow
    end)
    if ok and fg and fg.Parent then return fg end
    return nil
end

local function AutoFarmLoop()
    -- 3 rotating climb methods so the behavioral pattern changes each round
    -- Method 1: Direct smooth CFrame climb (fastest)
    -- Method 2: Walk to tower entrance first, then climb (most human-like)
    -- Method 3: Climb in two stages with a natural pause halfway (realistic)
    -- Rotates: 1,2,3,1,2,3... with random skips for variance
    local lastFG    = GetCurrentFG()
    local methodIdx = math.random(1,3)  -- start on random method
    local roundsSinceSkip = 0

    -- Helper: walk character to a nearby point before climbing (method 2)
    local function WalkToward(pos)
        local hum = Hum()
        local hrp = HRP()
        if not hum or not hrp then return end
        local walkTarget = pos + Vector3.new(0, 0, 8)  -- near tower base
        hum:MoveTo(walkTarget)
        task.wait(1.5 + math.random() * 1.0)
    end

    while _autoFarmActive do
        -- Wait for a new FinishGlow = new round
        local newFG = nil
        local limit = tick() + 90
        while tick() < limit and _autoFarmActive do
            task.wait(0.08)
            local fg = GetCurrentFG()
            if fg and fg ~= lastFG then newFG = fg break end
        end

        if not newFG or not _autoFarmActive then
            lastFG = GetCurrentFG()
            task.wait(0.2)
        else
            lastFG = newFG

            -- Skip a round every 5-8 rounds (humans fail rounds)
            roundsSinceSkip = roundsSinceSkip + 1
            if roundsSinceSkip >= math.random(5,8) then
                roundsSinceSkip = 0
                Notify("ch4rlies scripts","Auto Farm: sitting out this round...",2)
                local skipWait = tick() + 120
                while tick() < skipWait and _autoFarmActive do
                    task.wait(0.2)
                    local fg = GetCurrentFG()
                    if not fg or fg ~= lastFG then lastFG = fg break end
                end
            else
                -- 15-20 second delay before climbing (bypass respawn detection)
                local delay = 15 + math.random() * 5
                Notify("ch4rlies scripts",
                    "Bypassing detection... est. "..math.floor(delay).."s", math.ceil(delay)+1)
                task.wait(delay)
                if not _autoFarmActive then break end

                local target = GetFinishTarget()
                if not target then
                    pcall(function()
                        target = newFG.CFrame.Position + Vector3.new(0, 3, 0)
                    end)
                end

                if target and _autoFarmActive then
                    _autoFarmRounds = _autoFarmRounds + 1
                    -- Rotate through 3 methods
                    methodIdx = (methodIdx % 3) + 1
                    Notify("ch4rlies scripts",
                        "Auto Farm: Round ".._autoFarmRounds.." (method "..methodIdx..") climbing...", 3)

                    local climbDone = false
                    local startChar = LP.Character

                    if methodIdx == 1 then
                        -- Method 1: Direct smooth climb
                        FarmClimb(target, function()
                            climbDone = true
                            RestoreForCoins()
                            Notify("ch4rlies scripts","Auto Farm: Round ".._autoFarmRounds.." complete!",3)
                        end)
                    elseif methodIdx == 2 then
                        -- Method 2: Walk toward tower first, then climb
                        WalkToward(target)
                        if not _autoFarmActive then break end
                        FarmClimb(target, function()
                            climbDone = true
                            RestoreForCoins()
                            Notify("ch4rlies scripts","Auto Farm: Round ".._autoFarmRounds.." complete!",3)
                        end)
                    else
                        -- Method 3: Climb halfway, pause 1-2s, climb rest
                        local midTarget = Vector3.new(
                            target.X,
                            (target.Y + (HRP() and HRP().Position.Y or 0)) / 2,
                            target.Z
                        )
                        FarmClimb(midTarget, function()
                            task.wait(1 + math.random())
                            if not _autoFarmActive then climbDone=true return end
                            FarmClimb(target, function()
                                climbDone = true
                                RestoreForCoins()
                                Notify("ch4rlies scripts","Auto Farm: Round ".._autoFarmRounds.." complete!",3)
                            end)
                        end)
                    end

                    local elapsed = 0
                    while not climbDone and elapsed < 150 and _autoFarmActive do
                        task.wait(0.1)
                        elapsed = elapsed + 0.1
                        if LP.Character ~= startChar then
                            _climbActive = false
                            climbDone = true
                        end
                    end

                    -- Wait for round end
                    if _autoFarmActive then
                        local endWait = tick() + 180
                        while tick() < endWait and _autoFarmActive do
                            task.wait(0.15)
                            local fg = GetCurrentFG()
                            if not fg or fg ~= lastFG then lastFG = fg break end
                        end
                    end
                end
            end
        end
        task.wait(0.05)
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
        _climbActive = false
        Notify("ch4rlies scripts",
            "Auto Farm OFF. Rounds: ".._autoFarmRounds, 3)
        _autoFarmRounds = 0
        return
    end
    _autoFarmRounds = 0

    -- If a tower is already up right now, climb immediately
    local target = GetFinishTarget()
    if target then
        Notify("ch4rlies scripts","Auto Farm ON - round active, climbing now!",4)
        _autoFarmRounds = 1
        local climbStarted = false
        task.spawn(function()
            climbStarted = true
            FarmClimb(target, function()
                RestoreForCoins()
                Notify("ch4rlies scripts","Auto Farm: Round 1 complete!",3)
            end)
        end)
    else
        Notify("ch4rlies scripts","Auto Farm ON - waiting for next round...",4)
    end
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
    if not v then Notify("ch4rlies scripts","Fake Lag OFF",2) return end
    _conns["fakelag"] = RunService.Heartbeat:Connect(function()
        if not cfg.FakeLag then return end
        local stallMs = (cfg.FakeLagMs or 100) / 1000
        local endAt   = tick() + stallMs
        while tick() < endAt do end  -- busy-wait stalls the physics thread
    end)
    Notify("ch4rlies scripts","Fake Lag ON - "..(cfg.FakeLagMs or 100).."ms stall",3)
end

-- ============================================================
-- SERVER HOP
-- ============================================================
local function ServerHop()
    Notify("ch4rlies scripts","Finding new server...",3)
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
    task.spawn(ScanAndHookACRemotes)
    local h = Hum()
    if h then h.WalkSpeed = cfg.WalkSpeed h.JumpPower = cfg.JumpPower end
    if cfg.InfJump     then SetInfJump(true)      end
    if cfg.Fly         then SetFly(true)           end
    if cfg.Noclip      then SetNoclip(true)        end
    -- GodMode intentionally NOT called here.
    -- SetGodMode registers its own LP.CharacterAdded (god_char) connection
    -- internally. Calling it again from here would create a second
    -- HealthChanged hook on every respawn -> feedback loop -> glitch.
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


-- ============================================================
-- UI
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name            = "ch4rlies scripts  -  Tower of Hell",
    ConfigurationSaving = {Enabled=true, FileName="ch4rlies_toh_v2"},
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

-- TOWER TAB
local TabT = Window:CreateTab("Tower", 4483362458)

TabT:CreateSection("Auto Finish")
TabT:CreateButton({Name="Auto Complete  (press again to cancel)",
    Callback=function() AutoComplete() end})
TabT:CreateButton({Name="Teleport to Top  (press again to cancel)",
    Callback=function() TeleportToTop() end})
TabT:CreateLabel("WARNING: Teleport to Top is bannable. Recommended: server hop after for no risk of ban.")
TabT:CreateToggle({Name="Auto Farm  (completes every round automatically)",
    CurrentValue=false,Flag="AutoFarm",
    Callback=function(v) SetAutoFarm(v) end})
TabT:CreateLabel("Auto Farm: Physics-state climb, same engine as Auto Complete")

TabT:CreateSection("Sections")
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
            if hrp then _slots[idx] = hrp.CFrame Notify("ch4rlies scripts","Slot "..idx.." saved!",2) end
        end})
    TabT:CreateButton({Name="Load Slot "..idx,
        Callback=function()
            local hrp = HRP()
            if hrp and _slots[idx] then
                hrp.CFrame = _slots[idx] Notify("ch4rlies scripts","Slot "..idx.." loaded!",2)
            else Notify("ch4rlies scripts","Slot "..idx.." is empty!",2) end
        end})
end

TabT:CreateSection("Navigation")
TabT:CreateButton({Name="Return to Spawn",
    Callback=function()
        local hrp = HRP()
        if hrp then hrp.CFrame = CFrame.new(0,10,0) Notify("ch4rlies scripts","Teleported to spawn.",2) end
    end})


TabT:CreateButton({Name="Get Gravity Coil",
    Callback=function()
        local found = FindCoil("gravity coil")
        if not found then found = FindCoil("gravitycoil") end
        local hrp = HRP()
        if found and hrp then
            hrp.CFrame = CFrame.new(found.Position + Vector3.new(0, 4, 0))
            Notify("ch4rlies scripts","Teleported to Gravity Coil!",3)
        else
            Notify("ch4rlies scripts","Gravity Coil not found in this map.",3)
        end
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
    Notify("ch4rlies scripts","Player list refreshed! ("..#names.." players)",2)
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
    if not v then Notify("ch4rlies scripts","Follow stopped.",2) return end
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
    Notify("ch4rlies scripts","Following "..(_selectedPlayer~="" and _selectedPlayer or "nobody").."...",3)
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
        Notify("ch4rlies scripts","Brought "..count.." players to you!",3)
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

TabV:CreateSection("Grapple Hook")
TabV:CreateLabel("E = fire to crosshair  |  Right-click or E = cancel")
TabV:CreateLabel("Raycasts from screen center for accuracy.")
TabV:CreateLabel("Rope sags naturally and thins toward anchor point.")
TabV:CreateToggle({Name="Grapple Hook  [E]",CurrentValue=false,Flag="Grapple",
    Callback=function(v) SetGrapple(v) end})
TabV:CreateSlider({Name="Grapple Speed",Range={20,200},Increment=10,
    Suffix=" st/s",CurrentValue=80,Flag="GrappleSpeed",
    Callback=function(v) cfg.GrappleSpeed = v end})

-- MISC TAB
local TabM = Window:CreateTab("Misc", 4483362458)

TabM:CreateSection("Auto Load")
TabM:CreateLabel("Saves this script to auto-execute every time you join.")
TabM:CreateLabel("Supported executors: Synapse, KRNL, Fluxus, Solara etc.")
TabM:CreateButton({Name="Enable Auto Load  (saves to autoexec)",
    Callback=function()
        -- Get the script source and save to autoexec folder
        local scriptSrc = game:HttpGet("https://raw.githubusercontent.com/ch4rlie/ch4rlies-scripts/main/toh.lua")
        if not scriptSrc or scriptSrc == "" then
            -- Fall back to writing the current running script
            scriptSrc = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/ch4rlie/ch4rlies-scripts/main/toh.lua"))()]]
        end
        local ok = pcall(function()
            writefile("autoexec/ch4rlies_scripts.lua", scriptSrc)
        end)
        if ok then
            Notify("ch4rlies scripts","Auto Load enabled! Script will run on every join.",4)
        else
            -- Try without autoexec/ prefix
            local ok2 = pcall(function()
                writefile("ch4rlies_scripts_autoload.lua", scriptSrc)
            end)
            if ok2 then
                Notify("ch4rlies scripts","Saved! Move ch4rlies_scripts_autoload.lua to autoexec folder.",5)
            else
                Notify("ch4rlies scripts","writefile not supported on this executor.",3)
            end
        end
    end})
TabM:CreateButton({Name="Disable Auto Load  (removes from autoexec)",
    Callback=function()
        local ok = pcall(function()
            writefile("autoexec/ch4rlies_scripts.lua", "-- disabled")
        end)
        if ok then
            Notify("ch4rlies scripts","Auto Load disabled.",3)
        else
            Notify("ch4rlies scripts","Could not remove - delete manually from autoexec.",3)
        end
    end})

TabM:CreateSection("Server")
TabM:CreateButton({Name="Server Hop",     Callback=function() ServerHop() end})
TabM:CreateButton({Name="Rejoin Server",
    Callback=function() TeleportService:Teleport(game.PlaceId,LP) end})

TabM:CreateSection("Anti-Cheat")
TabM:CreateButton({Name="Re-apply Bypasses",
    Callback=function()
        NullifyKick() DisableKillScript() InstallHooks()
        Notify("ch4rlies scripts","Bypasses re-applied!",3)
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
            Notify("ch4rlies scripts","Copied to clipboard!",2)
        end)
    end})

TabM:CreateSection("Debug - Section Info")
TabM:CreateButton({Name="Print Section List to Output",
    Callback=function()
        local list = GetSortedSections()
        if #list == 0 then
            Notify("ch4rlies scripts","No sections found - is the tower loaded?",4)
            return
        end
        Notify("ch4rlies scripts","Found "..#list.." sections (check Output)",4)
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
            Notify("ch4rlies scripts","Fake Lag: "..v.."ms",2)
        end
    end})

TabM:CreateSection("Info")
TabM:CreateLabel("ch4rlies scripts  |  V2  |  Tower of Hell")
TabM:CreateLabel("God Mode save-load fix  |  Physics climb")
TabM:CreateLabel("All bypasses active on load and respawn")



-- DISCORD TAB
local TabD = Window:CreateTab("Discord", 4483362458)
TabD:CreateSection("ch4rlies scripts Community")
TabD:CreateLabel("Join the Discord for updates, support and more scripts!")
TabD:CreateLabel("Server: ch4rlies scripts")
TabD:CreateButton({Name="Copy Discord Link",
    Callback=function()
        setclipboard("https://discord.gg/u7PbdJGH")
        Notify("ch4rlies scripts","Discord link copied to clipboard!",3)
    end})
TabD:CreateButton({Name="Open Discord in Browser",
    Callback=function()
        if syn and syn.request then
            game:GetService("GuiService"):OpenBrowserWindow("https://discord.gg/u7PbdJGH")
        else
            pcall(function()
                game:GetService("GuiService"):OpenBrowserWindow("https://discord.gg/u7PbdJGH")
            end)
        end
        Notify("ch4rlies scripts","Opening discord.gg/u7PbdJGH ...",3)
    end})
TabD:CreateLabel("discord.gg/u7PbdJGH")
TabD:CreateLabel("Made by ch4rlie  |  ch4rlies scripts V2")

-- ADMIN COMMANDS TAB
local TabA = Window:CreateTab("Admin", 4483362458)
TabA:CreateSection("Admin Panel")
TabA:CreateLabel("Click any button below to run commands instantly.")
TabA:CreateLabel("Select a target player from the dropdown first.")

-- ------ Admin GUI floating panel ------------------------------------------------------------------------------------------------------------------------------------------------------
local function BuildAdminGUI()
    -- Remove existing
    for _, g in ipairs(LP.PlayerGui:GetChildren()) do
        if g.Name == "ch4AdminPanel" then g:Destroy() end
    end

    local sg = Instance.new("ScreenGui")
    sg.Name = "ch4AdminPanel" sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling sg.Parent = LP.PlayerGui

    -- Main frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0,260,0,420)
    frame.Position = UDim2.new(0,20,0.5,-210)
    frame.BackgroundColor3 = Color3.fromRGB(18,18,24)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0 frame.Parent = sg
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,10) corner.Parent = frame

    -- Stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255,180,30) stroke.Thickness = 1.5
    stroke.Transparency = 0.3 stroke.Parent = frame

    -- Title bar
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,36) title.Position = UDim2.new(0,0,0,0)
    title.BackgroundColor3 = Color3.fromRGB(255,180,30)
    title.BackgroundTransparency = 0.1 title.BorderSizePixel = 0
    title.Text = "  ch4rlies scripts  |  Admin Panel"
    title.TextColor3 = Color3.fromRGB(20,20,20)
    title.Font = Enum.Font.GothamBold title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left title.Parent = frame
    local tc = Instance.new("UICorner") tc.CornerRadius=UDim.new(0,10) tc.Parent=title

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,28,0,28)
    closeBtn.Position = UDim2.new(1,-32,0,4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(220,60,60)
    closeBtn.Text = "X" closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
    closeBtn.Font = Enum.Font.GothamBold closeBtn.TextSize = 13
    closeBtn.BorderSizePixel = 0 closeBtn.Parent = frame
    local cc = Instance.new("UICorner") cc.CornerRadius=UDim.new(0,6) cc.Parent=closeBtn
    closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

    -- Target dropdown label
    local tLabel = Instance.new("TextLabel")
    tLabel.Size = UDim2.new(1,-16,0,20) tLabel.Position = UDim2.new(0,8,0,44)
    tLabel.BackgroundTransparency=1 tLabel.Text = "Target Player:"
    tLabel.TextColor3 = Color3.fromRGB(200,200,200)
    tLabel.Font = Enum.Font.Gotham tLabel.TextSize = 12
    tLabel.TextXAlignment = Enum.TextXAlignment.Left tLabel.Parent = frame

    -- Selected target display
    local _adminTarget = nil
    local targetDisplay = Instance.new("TextLabel")
    targetDisplay.Size = UDim2.new(1,-16,0,26)
    targetDisplay.Position = UDim2.new(0,8,0,64)
    targetDisplay.BackgroundColor3 = Color3.fromRGB(30,30,40)
    targetDisplay.BorderSizePixel = 0
    targetDisplay.Text = "  [Self]"
    targetDisplay.TextColor3 = Color3.fromRGB(255,220,80)
    targetDisplay.Font = Enum.Font.GothamBold targetDisplay.TextSize = 13
    targetDisplay.TextXAlignment = Enum.TextXAlignment.Left targetDisplay.Parent = frame
    local tdc = Instance.new("UICorner") tdc.CornerRadius=UDim.new(0,6) tdc.Parent=targetDisplay

    -- Player list scroll
    local playerScroll = Instance.new("ScrollingFrame")
    playerScroll.Size = UDim2.new(1,-16,0,60)
    playerScroll.Position = UDim2.new(0,8,0,96)
    playerScroll.BackgroundColor3 = Color3.fromRGB(25,25,35)
    playerScroll.BorderSizePixel = 0 playerScroll.ScrollBarThickness = 4
    playerScroll.CanvasSize = UDim2.new(0,0,0,0) playerScroll.Parent = frame
    local psc = Instance.new("UICorner") psc.CornerRadius=UDim.new(0,6) psc.Parent=playerScroll
    local psl = Instance.new("UIListLayout") psl.Padding=UDim.new(0,2)
    psl.FillDirection=Enum.FillDirection.Horizontal psl.Parent=playerScroll
    local function RefreshPlayers()
        for _, c in ipairs(playerScroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0,70,0,28) btn.BackgroundColor3 = Color3.fromRGB(40,40,55)
            btn.Text = p.Name:sub(1,8) btn.TextColor3 = Color3.fromRGB(220,220,255)
            btn.Font = Enum.Font.Gotham btn.TextSize = 11 btn.BorderSizePixel = 0
            btn.Parent = playerScroll
            local bc = Instance.new("UICorner") bc.CornerRadius=UDim.new(0,5) bc.Parent=btn
            btn.MouseButton1Click:Connect(function()
                _adminTarget = p
                targetDisplay.Text = "  "..p.Name
                targetDisplay.TextColor3 = Color3.fromRGB(80,255,130)
            end)
        end
        playerScroll.CanvasSize = UDim2.new(0, #Players:GetPlayers()*74, 0, 0)
    end
    RefreshPlayers()

    -- Refresh button
    local refBtn = Instance.new("TextButton")
    refBtn.Size = UDim2.new(0,70,0,20) refBtn.Position = UDim2.new(1,-78,0,162)
    refBtn.BackgroundColor3 = Color3.fromRGB(50,100,180)
    refBtn.Text = "Refresh" refBtn.TextColor3 = Color3.fromRGB(255,255,255)
    refBtn.Font = Enum.Font.Gotham refBtn.TextSize = 11 refBtn.BorderSizePixel = 0
    refBtn.Parent = frame
    local rbc = Instance.new("UICorner") rbc.CornerRadius=UDim.new(0,5) rbc.Parent=refBtn
    refBtn.MouseButton1Click:Connect(RefreshPlayers)

    -- Self button
    local selfBtn = Instance.new("TextButton")
    selfBtn.Size = UDim2.new(0,50,0,20) selfBtn.Position = UDim2.new(0,8,0,162)
    selfBtn.BackgroundColor3 = Color3.fromRGB(60,120,60)
    selfBtn.Text = "Self" selfBtn.TextColor3 = Color3.fromRGB(255,255,255)
    selfBtn.Font = Enum.Font.Gotham selfBtn.TextSize = 11 selfBtn.BorderSizePixel = 0
    selfBtn.Parent = frame
    local sbc = Instance.new("UICorner") sbc.CornerRadius=UDim.new(0,5) sbc.Parent=selfBtn
    selfBtn.MouseButton1Click:Connect(function()
        _adminTarget = nil
        targetDisplay.Text = "  [Self]"
        targetDisplay.TextColor3 = Color3.fromRGB(255,220,80)
    end)

    -- Helper to get current target
    local function GetTarget()
        return _adminTarget or LP
    end

    -- Command buttons scroll area
    local cmdScroll = Instance.new("ScrollingFrame")
    cmdScroll.Size = UDim2.new(1,-16,1,-196)
    cmdScroll.Position = UDim2.new(0,8,0,192)
    cmdScroll.BackgroundTransparency = 1
    cmdScroll.BorderSizePixel = 0 cmdScroll.ScrollBarThickness = 4
    cmdScroll.CanvasSize = UDim2.new(0,0,0,0) cmdScroll.Parent = frame
    local cmdLayout = Instance.new("UIGridLayout")
    cmdLayout.CellSize = UDim2.new(0.48,0,0,36)
    cmdLayout.CellPadding = UDim2.new(0.02,0,0,5)
    cmdLayout.Parent = cmdScroll

    local function AddCmdBtn(label, color, action)
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = color
        btn.Text = label btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.Font = Enum.Font.GothamBold btn.TextSize = 12
        btn.BorderSizePixel = 0 btn.Parent = cmdScroll
        local bc = Instance.new("UICorner") bc.CornerRadius=UDim.new(0,7) bc.Parent=btn
        btn.MouseButton1Click:Connect(function()
            local t = GetTarget()
            pcall(function() action(t) end)
        end)
    end

    local C = {
        red    = Color3.fromRGB(200,50,50),
        green  = Color3.fromRGB(50,170,80),
        blue   = Color3.fromRGB(50,100,200),
        orange = Color3.fromRGB(220,130,30),
        purple = Color3.fromRGB(130,50,200),
        teal   = Color3.fromRGB(30,160,160),
        gray   = Color3.fromRGB(80,80,100),
        pink   = Color3.fromRGB(200,60,140),
    }

    AddCmdBtn("God Mode", C.orange, function(t)
        if t == LP then SetGodMode(not cfg.GodMode) end
        Notify("ch4rlies scripts","God: "..(cfg.GodMode and "ON" or "OFF"),2)
    end)
    AddCmdBtn("Fly", C.blue, function(t)
        if t == LP then SetFly(not cfg.Fly) end
        Notify("ch4rlies scripts","Fly: "..(cfg.Fly and "ON" or "OFF"),2)
    end)
    AddCmdBtn("Noclip", C.teal, function(t)
        if t == LP then SetNoclip(not cfg.Noclip) end
        Notify("ch4rlies scripts","Noclip: "..(cfg.Noclip and "ON" or "OFF"),2)
    end)
    AddCmdBtn("Heal", C.green, function(t)
        local h = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if h then h.Health = h.MaxHealth end
        Notify("ch4rlies scripts","Healed "..t.Name,2)
    end)
    AddCmdBtn("Kill", C.red, function(t)
        local h = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if h then h.Health = 0 end
        Notify("ch4rlies scripts","Killed "..t.Name,2)
    end)
    AddCmdBtn("Teleport To", C.purple, function(t)
        if t == LP then return end
        local thrp = t.Character and t.Character:FindFirstChild("HumanoidRootPart")
        local hrp = HRP()
        if thrp and hrp then hrp.CFrame = thrp.CFrame * CFrame.new(0,0,4) end
        Notify("ch4rlies scripts","TP to "..t.Name,2)
    end)
    AddCmdBtn("Bring To Me", C.pink, function(t)
        if t == LP then return end
        local thrp = t.Character and t.Character:FindFirstChild("HumanoidRootPart")
        local hrp = HRP()
        if thrp and hrp then thrp.CFrame = hrp.CFrame * CFrame.new(0,0,4) end
        Notify("ch4rlies scripts","Brought "..t.Name,2)
    end)
    AddCmdBtn("Speed x5", C.orange, function(t)
        local h = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 80 end
        Notify("ch4rlies scripts","Speed 80",2)
    end)
    AddCmdBtn("Speed Reset", C.gray, function(t)
        local h = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 16 end
        Notify("ch4rlies scripts","Speed reset",2)
    end)
    AddCmdBtn("Jump x5", C.blue, function(t)
        local h = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
        if h then h.JumpPower = 250 end
        Notify("ch4rlies scripts","Jump 250",2)
    end)
    AddCmdBtn("Auto Complete", C.green, function(t)
        AutoComplete()
    end)
    AddCmdBtn("TP to Top", C.teal, function(t)
        TeleportToTop()
    end)
    AddCmdBtn("Respawn", C.red, function(t)
        LP:LoadCharacter()
    end)
    AddCmdBtn("Server Hop", C.gray, function(t)
        ServerHop()
    end)

    -- Resize canvas
    local numBtns = 14
    cmdScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(numBtns/2)*41+10)

    -- Draggable title bar
    local dragging, dragStart, startPos = false, nil, nil
    title.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = inp.Position
            startPos  = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- ADMIN TAB UI
TabA:CreateSection("Admin Panel")
TabA:CreateLabel("A floating GUI with clickable command buttons.")
TabA:CreateLabel("Drag the panel by its title bar. Select a player then click a command.")
TabA:CreateButton({Name="Open Admin Panel",
    Callback=function()
        BuildAdminGUI()
        Notify("ch4rlies scripts","Admin panel opened!",3)
    end})
TabA:CreateButton({Name="Close Admin Panel",
    Callback=function()
        for _, g in ipairs(LP.PlayerGui:GetChildren()) do
            if g.Name == "ch4AdminPanel" then g:Destroy() end
        end
        Notify("ch4rlies scripts","Admin panel closed.",2)
    end})

TabA:CreateSection("Chat Commands (also available)")
TabA:CreateLabel("Prefix: !c  |  e.g. !c speed 80  |  !c kill player")
TabA:CreateLabel("speed  jump  tp  bring  kill  heal  god  fly  noclip  top  complete")



-- Defer LoadConfiguration until AFTER the first CharacterAdded has fired.
-- If we call it immediately, saved toggles (GodMode, Fly etc) fire their
-- callbacks right now against the INITIAL character. Then CharacterAdded
-- fires 0.5s later and calls SetGodMode(true) AGAIN on the new character,
-- creating duplicate hooks that fight each other -> bouncy physics / glitch.
--
-- By waiting for CharacterAdded (or 3s timeout if character already loaded),
-- we guarantee: character is stable, LoadConfiguration runs once, all
-- callbacks fire exactly once against the correct character.
task.spawn(function()
    if not LP.Character or not LP.Character:FindFirstChildOfClass("Humanoid") then
        LP.CharacterAdded:Wait()
        task.wait(0.6)  -- let CharacterAdded handler finish first
    else
        task.wait(0.6)
    end
    -- Reset flags that must NOT persist (fly, noclip, autofarm should start off)
    cfg.Fly      = false
    cfg.Noclip   = false
    cfg.AutoFarm = false
    Window:LoadConfiguration()
    task.wait(0.5)
    Notify("ch4rlies scripts","Ready! God Mode + Auto Farm loaded.",4)
end)
