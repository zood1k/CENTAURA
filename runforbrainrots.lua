-- CENTAURA :: Run For Brainrots! (v3 · HARD MODE)
-- By @zood3llotgk
--
-- v3 fixes:
--   * CollectTouch scan teper ТОЛЬКО v tvoyem plote (ne Workspace) — fix sbora
--   * Nashli tvoy plot cherez Plots/Bases/Tycoons + Owner value/attribute
--   * Ubrali Heartbeat polling po descendants (bylo prichinoy laga)
--   * WalkSpeed/JumpPower derzhatsya cherez GetPropertyChangedSignal
--   * Coin-fix na character cherez DescendantAdded (a ne kazhdyy frame)
--   * Noclip — per-tick s kesh parts
--   * Auto Pickup propuskayet tolko tvoy plot (ne vse plots)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local LP                  = Players.LocalPlayer

-- ===== executor feature detection =====
local function _G_get(name)
    local ok, v = pcall(function() return rawget(getfenv(0), name) end)
    if ok and v then return v end
    ok, v = pcall(function() return getfenv()[name] end)
    if ok and v then return v end
    return nil
end
local _getconnections = _G_get("getconnections")
local _firesignal     = _G_get("firesignal")
local _firetouch      = _G_get("firetouchinterest")
local _fireprompt     = _G_get("fireproximityprompt")
local _fireclick      = _G_get("fireclickdetector")

local Events = ReplicatedStorage:FindFirstChild("Events")
              or ReplicatedStorage:WaitForChild("Events", 10)

local function findEvent(n)
    if Events then
        local e = Events:FindFirstChild(n); if e then return e end
    end
    return ReplicatedStorage:FindFirstChild(n)
end

local UPG_NAMES   = {"UpgradeBrainrot","Upgrade","UpgradeItem","BrainrotUpgrade"}
local SPEED_NAMES = {"PurchaseSpeed","BuySpeed","UpgradeSpeed","SpeedPurchase","SpeedUpgrade"}
local REB_NAMES   = {"Rebirth","DoRebirth","PurchaseRebirth","RequestRebirth"}

local function tryFire(names, ...)
    local args = {...}
    for _, n in ipairs(names) do
        local r = findEvent(n)
        if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then
            pcall(function()
                if r:IsA("RemoteEvent") then r:FireServer(unpack(args))
                else r:InvokeServer(unpack(args)) end
            end)
        end
    end
end

-- ===== state =====
local S = {
    autoCollect  = false,
    autoPickup   = false,
    autoUpgrade  = false,
    autoSpeed    = false,
    autoRebirth  = false,
    espBrainrots = false,
    noclip       = false,
    speedHack    = false,
    jumpHack     = false,
    antiAFK      = true,
    muteSpam     = true,

    walkSpeed    = 60,
    jumpPower    = 80,
}

local function notify(t, x, d)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = t or "CENTAURA", Text = x or "", Duration = d or 2
        })
    end)
end

local function char() return LP.Character end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart"),
           c and c:FindFirstChildOfClass("Humanoid")
end

-- ===== find player's plot =====
local PLOT_FOLDER_PAT = {"plots","bases","tycoons","playerplots","playerbases","map","maps"}
local function isOwnedByMe(inst)
    if not inst then return false end
    local ownerVal = inst:FindFirstChild("Owner")
    if ownerVal and ownerVal:IsA("ValueBase") then
        if ownerVal.Value == LP then return true end
        if typeof(ownerVal.Value) == "string" and
           (ownerVal.Value == LP.Name or ownerVal.Value == tostring(LP.UserId)) then
            return true
        end
    end
    local a1 = inst:GetAttribute("Owner")
    if a1 ~= nil and (a1 == LP.UserId or a1 == tostring(LP.UserId) or a1 == LP.Name) then
        return true
    end
    local a2 = inst:GetAttribute("OwnerUserId") or inst:GetAttribute("UserId")
    if a2 == LP.UserId then return true end
    if inst.Name == LP.Name or inst.Name == tostring(LP.UserId) then return true end
    return false
end

local myPlot = nil
local function findMyPlot()
    -- прямой дочерний по имени
    for _, c in ipairs(Workspace:GetChildren()) do
        if c.Name == LP.Name or c.Name == tostring(LP.UserId) then
            return c
        end
    end
    -- в контейнере "Plots"/"Bases"/...
    for _, c in ipairs(Workspace:GetChildren()) do
        local low = string.lower(c.Name or "")
        local isContainer = false
        for _, pat in ipairs(PLOT_FOLDER_PAT) do
            if low == pat or low:find(pat) then isContainer = true; break end
        end
        if isContainer then
            local direct = c:FindFirstChild(LP.Name) or c:FindFirstChild(tostring(LP.UserId))
            if direct then return direct end
            for _, ch in ipairs(c:GetChildren()) do
                if isOwnedByMe(ch) then return ch end
            end
        end
    end
    return nil
end

task.spawn(function()
    while true do
        if not myPlot or not myPlot.Parent then
            myPlot = findMyPlot()
        end
        task.wait(3)
    end
end)

-- ===== anti-AFK =====
LP.Idled:Connect(function()
    if not S.antiAFK then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game); task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end)

-- ===== movement =====
local function applySpeed(hum)
    if S.speedHack and hum then
        if hum.WalkSpeed ~= S.walkSpeed then hum.WalkSpeed = S.walkSpeed end
    end
end
local function applyJump(hum)
    if S.jumpHack and hum then
        hum.UseJumpPower = true
        if hum.JumpPower ~= S.jumpPower then hum.JumpPower = S.jumpPower end
    end
end

local function bindHumanoid(hum)
    if not hum then return end
    applySpeed(hum); applyJump(hum)
    pcall(function()
        hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function() applySpeed(hum) end)
        hum:GetPropertyChangedSignal("JumpPower"):Connect(function() applyJump(hum) end)
    end)
end

-- ===== coin-fix on character (only on new descendants) =====
local COIN_KW = {"coin","cash","bill","dollar","collect","drop","money","green"}
local function isCoinName(n)
    n = string.lower(n or "")
    for _, k in ipairs(COIN_KW) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end
local function softenPart(v)
    if not v or not v:IsA("BasePart") then return end
    local c = char()
    if c and v == c.PrimaryPart then return end
    pcall(function()
        v.CanCollide = false
        v.CanQuery   = false
        v.CanTouch   = false
        v.Massless   = true
    end)
end
local function fixCharDescendant(v)
    if v:IsA("BasePart") and isCoinName(v.Name) then softenPart(v) end
end

-- ===== noclip: cache character parts =====
local charParts = {}
local function rebuildCharParts()
    table.clear(charParts)
    local c = char(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(charParts, p) end
    end
end

local function onCharacterAdded(c)
    task.wait(0.1)
    local hum = c:FindFirstChildOfClass("Humanoid")
    bindHumanoid(hum)
    rebuildCharParts()
    c.DescendantAdded:Connect(function(v)
        if v:IsA("BasePart") then
            table.insert(charParts, v)
            fixCharDescendant(v)
        end
    end)
    c.DescendantRemoving:Connect(function(v)
        for i, p in ipairs(charParts) do
            if p == v then table.remove(charParts, i); break end
        end
    end)
    -- initial coin-fix pass
    for _, v in ipairs(c:GetDescendants()) do fixCharDescendant(v) end
end
if LP.Character then task.spawn(onCharacterAdded, LP.Character) end
LP.CharacterAdded:Connect(onCharacterAdded)

-- noclip tick (не каждый фрейм — 0.1с достаточно)
task.spawn(function()
    while task.wait(0.1) do
        if S.noclip then
            for _, p in ipairs(charParts) do
                if p.Parent and p.CanCollide then p.CanCollide = false end
            end
        end
    end
end)

-- ===== Auto Collect (СТРОГО CollectTouch в пределах моего плота) =====
local function collectInPlot(root, plot)
    for _, v in ipairs(plot:GetDescendants()) do
        if v:IsA("BasePart") and v.Name == "CollectTouch" then
            pcall(function()
                _firetouch(root, v, 0)
                _firetouch(root, v, 1)
            end)
        end
    end
end
task.spawn(function()
    while task.wait(0.25) do
        if S.autoCollect then
            local root = hrp()
            if root then
                if myPlot and myPlot.Parent then
                    collectInPlot(root, myPlot)
                else
                    -- плот не найден — пробуем весь Workspace, только CollectTouch
                    for _, v in ipairs(Workspace:GetDescendants()) do
                        if v:IsA("BasePart") and v.Name == "CollectTouch" then
                            pcall(function()
                                _firetouch(root, v, 0); _firetouch(root, v, 1)
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== Auto Pickup (пропускаем ТОЛЬКО мой плот) =====
task.spawn(function()
    while task.wait(0.25) do
        if S.autoPickup then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if myPlot and v:IsDescendantOf(myPlot) then
                    -- skip own plot
                elseif v:IsA("ProximityPrompt") and v.Enabled then
                    pcall(function() v.HoldDuration = 0; _fireprompt(v) end)
                elseif v:IsA("ClickDetector") then
                    pcall(function() _fireclick(v) end)
                end
            end
        end
    end
end)

-- ===== ShowNotification mute =====
local _notifConns = nil
local function setShowNotifMuted(on)
    local ev = findEvent("ShowNotification")
    if not ev or not _getconnections then return end
    if on then
        if _notifConns then return end
        _notifConns = {}
        pcall(function()
            for _, c in ipairs(_getconnections(ev.OnClientEvent)) do
                table.insert(_notifConns, c)
                pcall(function() c:Disable() end)
            end
        end)
    else
        if not _notifConns then return end
        for _, c in ipairs(_notifConns) do
            pcall(function() c:Enable() end)
        end
        _notifConns = nil
    end
end

-- forward ref (должен быть до clickButtonsMatching)
local CENTAURA_GUI = nil

-- ===== GUI click helpers =====
local function fireButton(btn)
    pcall(function()
        if _firesignal then _firesignal(btn.MouseButton1Click); return end
        if _getconnections then
            for _, c in ipairs(_getconnections(btn.MouseButton1Click)) do
                pcall(function()
                    if c.Fire then c:Fire() elseif c.Function then c.Function() end
                end)
            end
        end
    end)
end

local function clickButtonsMatching(patterns)
    local pg = LP:FindFirstChild("PlayerGui"); if not pg then return end
    for _, g in ipairs(pg:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton"))
           and not (CENTAURA_GUI and g:IsDescendantOf(CENTAURA_GUI)) then
            if g.Visible and g.Active and g.AbsoluteSize.X > 0 then
                local name = string.lower(g.Name or "")
                local text = (g:IsA("TextButton") and string.lower(g.Text or "")) or ""
                for _, p in ipairs(patterns) do
                    if name:find(p) or text:find(p) then
                        fireButton(g); break
                    end
                end
            end
        end
    end
end

-- ===== Auto Upgrade =====
task.spawn(function()
    while task.wait(0.35) do
        if S.autoUpgrade then
            clickButtonsMatching({"upgrade","upgd","improve"})
            tryFire(UPG_NAMES)
        end
    end
end)

-- ===== Auto Buy Speed =====
task.spawn(function()
    while task.wait(0.35) do
        if S.autoSpeed then
            if S.muteSpam then setShowNotifMuted(true) end
            clickButtonsMatching({"buyspeed","purchasespeed","speedpurchase"})
            for lvl = 1, 100 do tryFire(SPEED_NAMES, lvl) end
            tryFire(SPEED_NAMES)
        else
            if _notifConns and not S.autoRebirth then setShowNotifMuted(false) end
        end
    end
end)

-- ===== Auto Rebirth =====
task.spawn(function()
    while task.wait(0.5) do
        if S.autoRebirth then
            if S.muteSpam then setShowNotifMuted(true) end
            clickButtonsMatching({"rebirth","rebirthbtn","rebirthbutton"})
            tryFire(REB_NAMES)
        else
            if _notifConns and not S.autoSpeed then setShowNotifMuted(false) end
        end
    end
end)

-- ===== ESP running brainrots =====
local espHolders = {}
local function clearESP()
    for inst, hl in pairs(espHolders) do
        if hl and hl.Parent then hl:Destroy() end
        espHolders[inst] = nil
    end
end
local function isLikelyRunningBrainrot(m)
    if not m:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    if not m:FindFirstChildOfClass("Humanoid") then return false end
    if myPlot and m:IsDescendantOf(myPlot) then return false end
    if not m:FindFirstChildWhichIsA("BasePart") then return false end
    return true
end
task.spawn(function()
    while task.wait(0.6) do
        if S.espBrainrots then
            for _, m in ipairs(Workspace:GetDescendants()) do
                if isLikelyRunningBrainrot(m) and not espHolders[m] then
                    local hl = Instance.new("Highlight")
                    hl.Adornee          = m
                    hl.FillColor        = Color3.fromRGB(150, 80, 255)
                    hl.OutlineColor     = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.55
                    hl.Parent           = m
                    espHolders[m]       = hl
                end
            end
            for inst, hl in pairs(espHolders) do
                if not inst.Parent or not isLikelyRunningBrainrot(inst) then
                    if hl and hl.Parent then hl:Destroy() end
                    espHolders[inst] = nil
                end
            end
        else
            if next(espHolders) then clearESP() end
        end
    end
end)

-- ===== GUI =====
local pg = LP:WaitForChild("PlayerGui")
if pg:FindFirstChild("CENTAURA_RFB") then pg.CENTAURA_RFB:Destroy() end

local gui = Instance.new("ScreenGui", pg)
gui.Name           = "CENTAURA_RFB"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
CENTAURA_GUI = gui

local frame = Instance.new("Frame", gui)
frame.Size             = UDim2.new(0, 300, 0, 480)
frame.Position         = UDim2.new(0, 20, 0.5, -240)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
frame.BorderSizePixel  = 0
frame.Active           = true
frame.Draggable        = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(150, 80, 255); stroke.Thickness = 1.8

local head = Instance.new("TextLabel", frame)
head.Size                   = UDim2.new(1, 0, 0, 30)
head.Position               = UDim2.new(0, 0, 0, 4)
head.BackgroundTransparency = 1
head.Text                   = "CENTAURA · Run For Brainrots!"
head.Font                   = Enum.Font.GothamBold
head.TextSize               = 15
head.TextColor3             = Color3.fromRGB(210, 180, 255)

local sub = Instance.new("TextLabel", frame)
sub.Position                = UDim2.new(0, 0, 0, 32)
sub.Size                    = UDim2.new(1, 0, 0, 14)
sub.BackgroundTransparency  = 1
sub.Text                    = "By @zood3llotgk"
sub.Font                    = Enum.Font.Gotham
sub.TextSize                = 11
sub.TextColor3              = Color3.fromRGB(150, 130, 200)

local scroll = Instance.new("ScrollingFrame", frame)
scroll.Position              = UDim2.new(0, 10, 0, 54)
scroll.Size                  = UDim2.new(1, -20, 1, -64)
scroll.BackgroundTransparency= 1
scroll.BorderSizePixel       = 0
scroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
scroll.ScrollBarThickness    = 4
scroll.ScrollBarImageColor3  = Color3.fromRGB(150, 80, 255)

local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 5)

local function toggle(name, key, accent, onToggle)
    local b = Instance.new("TextButton", scroll)
    b.Size             = UDim2.new(1, -4, 0, 30)
    b.BorderSizePixel  = 0
    b.Font             = Enum.Font.GothamMedium
    b.TextSize         = 13
    b.TextColor3       = Color3.fromRGB(240, 240, 245)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local onC  = accent or Color3.fromRGB(70, 30, 130)
    local offC = Color3.fromRGB(28, 28, 36)
    local function r()
        b.Text             = (S[key] and "[ ON  ]  " or "[ OFF ]  ") .. name
        b.BackgroundColor3 = S[key] and onC or offC
    end
    r()
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]; r()
        notify("CENTAURA", name .. ": " .. (S[key] and "ON" or "OFF"))
        if onToggle then pcall(onToggle, S[key]) end
    end)
end

local function slider(label, key, min, max, step)
    local c = Instance.new("Frame", scroll)
    c.Size = UDim2.new(1, -4, 0, 40)
    c.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    c.BorderSizePixel  = 0
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(1, -10, 0, 14); l.Position = UDim2.new(0, 8, 0, 2)
    l.BackgroundTransparency = 1; l.Font = Enum.Font.Gotham; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(210, 210, 220)
    l.Text = label .. ": " .. tostring(S[key])
    local minus = Instance.new("TextButton", c)
    minus.Size = UDim2.new(0, 24, 0, 20); minus.Position = UDim2.new(0, 8, 0, 18)
    minus.Text = "-"; minus.Font = Enum.Font.GothamBold; minus.TextSize = 14
    minus.BackgroundColor3 = Color3.fromRGB(60, 30, 110)
    minus.TextColor3 = Color3.fromRGB(255,255,255); minus.BorderSizePixel = 0
    Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 4)
    local plus = Instance.new("TextButton", c)
    plus.Size = UDim2.new(0, 24, 0, 20); plus.Position = UDim2.new(1, -32, 0, 18)
    plus.Text = "+"; plus.Font = Enum.Font.GothamBold; plus.TextSize = 14
    plus.BackgroundColor3 = Color3.fromRGB(60, 30, 110)
    plus.TextColor3 = Color3.fromRGB(255,255,255); plus.BorderSizePixel = 0
    Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 4)
    local val = Instance.new("TextLabel", c)
    val.Size = UDim2.new(1, -72, 0, 20); val.Position = UDim2.new(0, 36, 0, 18)
    val.BackgroundTransparency = 1; val.Font = Enum.Font.GothamMedium
    val.TextSize = 12; val.TextColor3 = Color3.fromRGB(240, 240, 245)
    val.Text = tostring(S[key])
    local function apply(v)
        v = math.clamp(v, min, max); S[key] = v
        val.Text = tostring(v); l.Text = label .. ": " .. tostring(v)
        local _, hum = hrp()
        if hum then
            if key == "walkSpeed" and S.speedHack then hum.WalkSpeed = v end
            if key == "jumpPower" and S.jumpHack  then hum.JumpPower = v end
        end
    end
    minus.MouseButton1Click:Connect(function() apply(S[key] - step) end)
    plus.MouseButton1Click:Connect(function()  apply(S[key] + step) end)
end

toggle("Auto Collect Cash",    "autoCollect",  Color3.fromRGB(30, 140, 80))
toggle("Auto Pickup Brainrot", "autoPickup",   Color3.fromRGB(180, 80, 40))
toggle("Auto Upgrade (GUI)",   "autoUpgrade",  Color3.fromRGB(30, 90, 180))
toggle("Auto Buy Speed",       "autoSpeed")
toggle("Auto Rebirth",         "autoRebirth")
toggle("Mute Error Popups",    "muteSpam",     Color3.fromRGB(140, 40, 80), function(on)
    if not on then setShowNotifMuted(false) end
end)
toggle("ESP Brainrots",        "espBrainrots", Color3.fromRGB(150, 50, 200), function(on)
    if not on then clearESP() end
end)
toggle("Noclip",               "noclip")
toggle("Speed Hack",           "speedHack", nil, function(on)
    local _, hum = hrp(); if hum then
        if on then hum.WalkSpeed = S.walkSpeed else hum.WalkSpeed = 16 end
    end
end)
toggle("Jump Hack",            "jumpHack", nil, function(on)
    local _, hum = hrp(); if hum then
        if on then hum.UseJumpPower = true; hum.JumpPower = S.jumpPower
        else hum.JumpPower = 50 end
    end
end)
toggle("Anti-AFK",             "antiAFK")
slider("Walk Speed",    "walkSpeed",    16, 500, 8)
slider("Jump Power",    "jumpPower",    50, 500, 10)

local hint = Instance.new("TextLabel", scroll)
hint.Size                   = UDim2.new(1, -4, 0, 22)
hint.BackgroundTransparency = 1
hint.Font                   = Enum.Font.Gotham
hint.TextSize               = 11
hint.TextColor3             = Color3.fromRGB(150, 150, 160)
hint.Text                   = "RightShift — hide/show"

UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        frame.Visible = not frame.Visible
    end
end)

notify("CENTAURA", "Run For Brainrots! v3 loaded · by @zood3llotgk", 4)
