-- CENTAURA :: Be a Streamer! (v4 · WORKING)
-- By @zood3llotgk
--
-- Mechanic:
--   StreamingEvent:FireServer("startStream")
--   StreamingEvent:FireServer("segmentStreamed") * N  -- cash + followers
--   StreamingEvent:FireServer("endStream")
--   GetMailBox:FireServer()                            -- claim mail
--   Rebirth:FireServer()                               -- rebirth

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")
local StarterGui         = game:GetService("StarterGui")
local Workspace          = game:GetService("Workspace")
local LP                 = Players.LocalPlayer

-- ===== remotes =====
local StreamingEvent = ReplicatedStorage:WaitForChild("StreamingEvent", 10)
local MailBox        = ReplicatedStorage:WaitForChild("GetMailBox",    10)
local Rebirth        = ReplicatedStorage:FindFirstChild("Rebirth")

-- ===== state =====
local S = {
    infMode      = false,  -- inf cash + followers (stream cycle)
    autoRebirth  = false,  -- Rebirth spam
    autoMail     = false,  -- mailbox spam (соберает уже накопленное)
    autoPrompt   = false,  -- все ProximityPrompt
    autoClick    = false,  -- все ClickDetector
    autoCollect  = false,  -- подтягивать дроп денег к игроку
    autoTpPrompt = false,  -- телепорт к промптам
    antiAFK      = true,

    segmentsPerCycle = 1000, -- больше = больше денег за цикл (и лаг)
    cycleDelay       = 0.5,  -- сек между циклами
}

-- ===== utils =====
local function notify(t, x, d)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = t or "CENTAURA", Text = x or "", Duration = d or 2
        })
    end)
end

local function hrp()
    local c = LP.Character
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

-- удалить спамные ноты от стрима (чтоб не залипал UI)
pcall(function()
    local pg = LP:FindFirstChild("PlayerGui")
    local notifs = pg and pg:FindFirstChild("Notifications")
    local summary = notifs and notifs:FindFirstChild("Summary")
    if summary then summary:Destroy() end
end)

-- ===== INF MODE (main stream cycle) =====
task.spawn(function()
    while true do
        if S.infMode and StreamingEvent then
            pcall(function()
                StreamingEvent:FireServer("startStream")
                local n = math.max(1, math.floor(S.segmentsPerCycle))
                for i = 1, n do
                    StreamingEvent:FireServer("segmentStreamed")
                end
                StreamingEvent:FireServer("endStream")
                if MailBox then MailBox:FireServer() end
            end)
            task.wait(S.cycleDelay)
        else
            task.wait(0.1)
        end
    end
end)

-- ===== Auto Rebirth =====
task.spawn(function()
    while true do
        if S.autoRebirth then
            local r = Rebirth or ReplicatedStorage:FindFirstChild("Rebirth")
            if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then
                pcall(function()
                    if r:IsA("RemoteEvent") then r:FireServer()
                    else r:InvokeServer() end
                end)
            end
            task.wait(0.5)
        else
            task.wait(0.2)
        end
    end
end)

-- ===== Auto MailBox =====
task.spawn(function()
    while true do
        if S.autoMail and MailBox then
            pcall(function() MailBox:FireServer() end)
        end
        task.wait(0.5)
    end
end)

-- ===== ProximityPrompt =====
task.spawn(function()
    while task.wait(0.15) do
        if S.autoPrompt then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Enabled then
                    pcall(function()
                        v.HoldDuration = 0
                        fireproximityprompt(v)
                    end)
                end
            end
        end
    end
end)

-- ===== ClickDetector =====
task.spawn(function()
    while task.wait(0.2) do
        if S.autoClick then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ClickDetector") then
                    pcall(function() fireclickdetector(v) end)
                end
            end
        end
    end
end)

-- ===== TP + Prompt =====
task.spawn(function()
    while task.wait(0.08) do
        if S.autoTpPrompt then
            local root, hum = hrp()
            if root and hum and hum.Health > 0 then
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if not S.autoTpPrompt then break end
                    if v:IsA("ProximityPrompt") and v.Enabled then
                        local p = v.Parent
                        local part = p and (p:IsA("BasePart") and p or p:FindFirstChildWhichIsA("BasePart"))
                        if part then
                            pcall(function()
                                root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                                v.HoldDuration = 0
                                task.wait(0.06)
                                fireproximityprompt(v)
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== Cash drop pull =====
local KW = {"cash","money","bill","coin","drop","donation","tip","dollar"}
local function isCash(n)
    n = string.lower(n or "")
    for _, k in ipairs(KW) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end
task.spawn(function()
    while task.wait(0.25) do
        if S.autoCollect then
            local root = hrp()
            if root then
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if v:IsA("BasePart") and isCash(v.Name) then
                        pcall(function() v.CFrame = root.CFrame end)
                    end
                end
            end
        end
    end
end)

-- ===== GUI =====
local pg = LP:WaitForChild("PlayerGui")
if pg:FindFirstChild("CENTAURA_BAS") then pg.CENTAURA_BAS:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name           = "CENTAURA_BAS"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent         = pg

local frame = Instance.new("Frame", gui)
frame.Size             = UDim2.new(0, 290, 0, 420)
frame.Position         = UDim2.new(0, 20, 0.5, -210)
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
head.Text                    = "CENTAURA · Be a Streamer!"
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

local list = Instance.new("Frame", frame)
list.Position                 = UDim2.new(0, 10, 0, 54)
list.Size                     = UDim2.new(1, -20, 1, -64)
list.BackgroundTransparency   = 1
local layout = Instance.new("UIListLayout", list)
layout.Padding   = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function toggle(name, key, accent)
    local b = Instance.new("TextButton", list)
    b.Size             = UDim2.new(1, 0, 0, 30)
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
    end)
end

local function slider(label, key, min, max, step)
    local c = Instance.new("Frame", list)
    c.Size = UDim2.new(1, 0, 0, 40)
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

toggle("Inf Cash + Followers", "infMode",    Color3.fromRGB(30, 140, 80))
toggle("Auto Rebirth",         "autoRebirth",Color3.fromRGB(180, 80, 40))
toggle("Auto MailBox",         "autoMail",   Color3.fromRGB(30, 90, 180))
toggle("Auto ProximityPrompt", "autoPrompt")
toggle("Auto TP + Prompt",     "autoTpPrompt")
toggle("Auto ClickDetector",   "autoClick")
toggle("Auto Collect $",       "autoCollect")
toggle("Anti-AFK",             "antiAFK")
slider("Segments / cycle", "segmentsPerCycle", 100, 5000, 250)

local hint = Instance.new("TextLabel", list)
hint.Size                   = UDim2.new(1, 0, 0, 22)
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

notify("CENTAURA", "Be a Streamer! v4 loaded · by @zood3llotgk", 4)
