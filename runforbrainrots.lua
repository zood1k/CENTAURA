-- CENTAURA :: Run For Brainrots! (v1 · HARD MODE)
-- By @zood3llotgk
--
-- Based on RemoteSpy captures:
--   Events.CollectedMoney  (server fires when a CollectTouch part is touched → cash)
--   Events.BrainrotPickedUp, BrainrotUpgraded, SpeedPurchased, UpdateRebirthUI
-- Main farm: fire touch interest on every CollectTouch part in Workspace.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")
local StarterGui         = game:GetService("StarterGui")
local Workspace          = game:GetService("Workspace")
local LP                 = Players.LocalPlayer

-- ===== events folder (best-effort) =====
local Events = ReplicatedStorage:FindFirstChild("Events")
if not Events then
    Events = ReplicatedStorage:WaitForChild("Events", 10)
end

local function findEvent(name)
    if Events then
        local e = Events:FindFirstChild(name)
        if e then return e end
    end
    return ReplicatedStorage:FindFirstChild(name)
end

-- Try common remote names that this genre of game uses for ACTIONS (client→server)
local CANDIDATE_COLLECT_NAMES   = {"CollectMoney","Collect","ClaimMoney","ClaimCash","CollectCash"}
local CANDIDATE_PICKUP_NAMES    = {"PickUpBrainrot","PickupBrainrot","BrainrotPickUp","PickUp","PickupItem"}
local CANDIDATE_UPGRADE_NAMES   = {"UpgradeBrainrot","Upgrade","UpgradeItem"}
local CANDIDATE_SPEED_NAMES     = {"PurchaseSpeed","BuySpeed","UpgradeSpeed","SpeedPurchase"}
local CANDIDATE_REBIRTH_NAMES   = {"Rebirth","DoRebirth","PurchaseRebirth"}

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
    autoCollect  = false,  -- firetouchinterest на все CollectTouch
    autoPickup   = false,  -- подбирать все Brainrot модели
    autoUpgrade  = false,  -- спам Upgrade remote
    autoSpeed    = false,  -- спам buy speed
    autoRebirth  = false,  -- спам Rebirth
    espBrainrots = false,  -- подсветка брейнротов
    noclip       = false,
    antiFall     = false,
    speedHack    = false,
    jumpHack     = false,
    antiAFK      = true,

    walkSpeed    = 60,
    jumpPower    = 80,
    collectRange = 2000,
}

-- ===== utils =====
local function notify(t, x, d)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = t or "CENTAURA", Text = x or "", Duration = d or 2
        })
    end)
end

local function char()
    return LP.Character
end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart"),
           c and c:FindFirstChildOfClass("Humanoid")
end

-- ===== anti-AFK =====
LP.Idled:Connect(function()
    if not S.antiAFK then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end)

-- ===== WalkSpeed / JumpPower / Noclip =====
local function applyMovement()
    local _, hum = hrp()
    if hum then
        if S.speedHack then hum.WalkSpeed = S.walkSpeed end
        if S.jumpHack  then
            hum.JumpPower     = S.jumpPower
            hum.UseJumpPower  = true
        end
    end
end

RunService.Heartbeat:Connect(function()
    local c = char()
    if not c then return end
    if S.noclip then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
    applyMovement()
end)

-- ===== Anti-Fall (keep last safe Y) =====
local lastSafeY = nil
task.spawn(function()
    while task.wait(0.1) do
        local root, hum = hrp()
        if root and hum and hum.Health > 0 then
            if hum.FloorMaterial ~= Enum.Material.Air then
                lastSafeY = root.Position.Y
            end
            if S.antiFall and lastSafeY and root.Position.Y < lastSafeY - 50 then
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.CFrame = CFrame.new(root.Position.X, lastSafeY + 5, root.Position.Z)
                end)
            end
        end
    end
end)

-- ===== Auto Collect (firetouchinterest on CollectTouch) =====
local function touchAll(root, partName, range)
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.Name == partName then
            if (root.Position - v.Position).Magnitude <= range then
                pcall(function()
                    firetouchinterest(root, v, 0)
                    firetouchinterest(root, v, 1)
                end)
            end
        end
    end
end

task.spawn(function()
    while task.wait(0.1) do
        if S.autoCollect then
            local root = hrp()
            if root then
                touchAll(root, "CollectTouch", S.collectRange)
                touchAll(root, "Touch",        S.collectRange)
                -- на всякий пожарный — если есть прямой remote
                tryFire(CANDIDATE_COLLECT_NAMES)
            end
        end
    end
end)

-- ===== Auto Pickup Brainrots =====
-- ищем в Workspace модели у которых есть ClickDetector или ProximityPrompt
task.spawn(function()
    while task.wait(0.15) do
        if S.autoPickup then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Enabled then
                    pcall(function()
                        v.HoldDuration = 0
                        fireproximityprompt(v)
                    end)
                elseif v:IsA("ClickDetector") then
                    pcall(function() fireclickdetector(v) end)
                end
            end
            tryFire(CANDIDATE_PICKUP_NAMES)
        end
    end
end)

-- ===== Auto Upgrade =====
task.spawn(function()
    while task.wait(0.5) do
        if S.autoUpgrade then tryFire(CANDIDATE_UPGRADE_NAMES) end
    end
end)

-- ===== Auto Buy Speed =====
task.spawn(function()
    while task.wait(0.4) do
        if S.autoSpeed then
            -- пробуем с возрастающим номером уровня
            for lvl = 1, 100 do
                tryFire(CANDIDATE_SPEED_NAMES, lvl)
            end
            tryFire(CANDIDATE_SPEED_NAMES)
        end
    end
end)

-- ===== Auto Rebirth =====
task.spawn(function()
    while task.wait(0.5) do
        if S.autoRebirth then tryFire(CANDIDATE_REBIRTH_NAMES) end
    end
end)

-- ===== ESP for Brainrots =====
local espHolders = {}
local function clearESP()
    for inst, hl in pairs(espHolders) do
        if hl and hl.Parent then hl:Destroy() end
        espHolders[inst] = nil
    end
end
task.spawn(function()
    while task.wait(0.5) do
        if S.espBrainrots then
            for _, m in ipairs(Workspace:GetDescendants()) do
                if m:IsA("Model") and string.lower(m.Name):find("brainrot") then
                    if not espHolders[m] then
                        local part = m:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local hl = Instance.new("Highlight")
                            hl.Adornee          = m
                            hl.FillColor        = Color3.fromRGB(150, 80, 255)
                            hl.OutlineColor     = Color3.fromRGB(255, 255, 255)
                            hl.FillTransparency = 0.55
                            hl.Parent           = m
                            espHolders[m] = hl
                        end
                    end
                end
            end
            -- clean dead
            for inst, hl in pairs(espHolders) do
                if not inst.Parent then
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

local gui = Instance.new("ScreenGui")
gui.Name           = "CENTAURA_RFB"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent         = pg

local frame = Instance.new("Frame", gui)
frame.Size             = UDim2.new(0, 300, 0, 480)
frame.Position         = UDim2.new(0, 20, 0.5, -240)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
frame.BorderSizePixel  = 0
frame.Active           = true
frame.Draggable        = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", frame)
stroke.Color     = Color3.fromRGB(150, 80, 255)
stroke.Thickness = 1.8

local head = Instance.new("TextLabel", frame)
head.Size                    = UDim2.new(1, 0, 0, 30)
head.Position                = UDim2.new(0, 0, 0, 4)
head.BackgroundTransparency  = 1
head.Text                    = "CENTAURA · Run For Brainrots!"
head.Font                    = Enum.Font.GothamBold
head.TextSize                = 15
head.TextColor3              = Color3.fromRGB(210, 180, 255)

local sub = Instance.new("TextLabel", frame)
sub.Position                 = UDim2.new(0, 0, 0, 32)
sub.Size                     = UDim2.new(1, 0, 0, 14)
sub.BackgroundTransparency   = 1
sub.Text                     = "By @zood3llotgk"
sub.Font                     = Enum.Font.Gotham
sub.TextSize                 = 11
sub.TextColor3               = Color3.fromRGB(150, 130, 200)

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
layout.Padding   = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function toggle(name, key, accent)
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
        if key == "espBrainrots" and not S[key] then clearESP() end
    end)
end

local function slider(label, key, min, max, step)
    local c = Instance.new("Frame", scroll)
    c.Size = UDim2.new(1, -4, 0, 40)
    c.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    c.BorderSizePixel  = 0
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 6)

    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(1, -10, 0, 14)
    l.Position = UDim2.new(0, 8, 0, 2)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(210, 210, 220)
    l.Text = label .. ": " .. tostring(S[key])

    local minus = Instance.new("TextButton", c)
    minus.Size = UDim2.new(0, 24, 0, 20)
    minus.Position = UDim2.new(0, 8, 0, 18)
    minus.Text = "-"; minus.Font = Enum.Font.GothamBold; minus.TextSize = 14
    minus.BackgroundColor3 = Color3.fromRGB(60, 30, 110)
    minus.TextColor3 = Color3.fromRGB(255,255,255)
    minus.BorderSizePixel = 0
    Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 4)

    local plus = Instance.new("TextButton", c)
    plus.Size = UDim2.new(0, 24, 0, 20)
    plus.Position = UDim2.new(1, -32, 0, 18)
    plus.Text = "+"; plus.Font = Enum.Font.GothamBold; plus.TextSize = 14
    plus.BackgroundColor3 = Color3.fromRGB(60, 30, 110)
    plus.TextColor3 = Color3.fromRGB(255,255,255)
    plus.BorderSizePixel = 0
    Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 4)

    local val = Instance.new("TextLabel", c)
    val.Size = UDim2.new(1, -72, 0, 20)
    val.Position = UDim2.new(0, 36, 0, 18)
    val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamMedium
    val.TextSize = 12
    val.TextColor3 = Color3.fromRGB(240, 240, 245)
    val.Text = tostring(S[key])

    local function apply(v)
        v = math.clamp(v, min, max)
        S[key] = v
        val.Text = tostring(v)
        l.Text = label .. ": " .. tostring(v)
    end
    minus.MouseButton1Click:Connect(function() apply(S[key] - step) end)
    plus.MouseButton1Click:Connect(function()  apply(S[key] + step) end)
end

toggle("Auto Collect Cash",    "autoCollect",  Color3.fromRGB(30, 140, 80))
toggle("Auto Pickup Brainrot", "autoPickup",   Color3.fromRGB(180, 80, 40))
toggle("Auto Upgrade",         "autoUpgrade",  Color3.fromRGB(30, 90, 180))
toggle("Auto Buy Speed",       "autoSpeed")
toggle("Auto Rebirth",         "autoRebirth")
toggle("ESP Brainrots",        "espBrainrots", Color3.fromRGB(150, 50, 200))
toggle("Noclip",               "noclip")
toggle("Anti-Fall",            "antiFall",     Color3.fromRGB(30, 140, 140))
toggle("Speed Hack",           "speedHack")
toggle("Jump Hack",            "jumpHack")
toggle("Anti-AFK",             "antiAFK")
slider("Walk Speed",   "walkSpeed",   16, 500, 8)
slider("Jump Power",   "jumpPower",   50, 500, 10)
slider("Collect Range","collectRange",50, 5000, 100)

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

-- ===== reapply on respawn =====
LP.CharacterAdded:Connect(function()
    task.wait(1)
    applyMovement()
end)

notify("CENTAURA", "Run For Brainrots! v1 loaded · by @zood3llotgk", 4)
