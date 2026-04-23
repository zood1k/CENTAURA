-- CENTAURA :: Be a Streamer! (v3 · HARD MODE)
-- By @zood3llotgk
--
-- Inf Cash:       GetMailBox:FireServer()          (спам)
-- Inf Followers:  StreamingEvent:FireServer("Responded") (спам)
-- + Auto ProxPrompt / Auto ClickDetector / Auto Collect $ / Anti-AFK

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")
local StarterGui         = game:GetService("StarterGui")
local Workspace          = game:GetService("Workspace")
local LP                 = Players.LocalPlayer

-- ===== remotes =====
local RespondEvent = ReplicatedStorage:WaitForChild("StreamingEvent", 10)
local MailEvent    = ReplicatedStorage:WaitForChild("GetMailBox",    10)

-- ===== state =====
local S = {
    infCash      = false,  -- GetMailBox:FireServer()       спам 0.00 wait
    infFollowers = false,  -- StreamingEvent:FireServer("Responded") спам
    autoPrompt   = false,  -- все ProximityPrompt
    autoClick    = false,  -- все ClickDetector
    autoCollect  = false,  -- подтягивать деньги к игроку
    autoTpPrompt = false,  -- телепорт к промптам и жать
    antiAFK      = true,
    cashSpamRate = 0,      -- 0 = каждый тик (RunService.Heartbeat)
    respSpamRate = 0,
}

-- ===== notify =====
local function notify(t, x, d)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = t or "CENTAURA", Text = x or "", Duration = d or 2
        })
    end)
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

-- ===== utils =====
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart"),
           c and c:FindFirstChildOfClass("Humanoid")
end

-- ===== INF CASH =====
task.spawn(function()
    while true do
        if S.infCash and MailEvent then
            pcall(function() MailEvent:FireServer() end)
        end
        if S.cashSpamRate <= 0 then
            RunService.Heartbeat:Wait()
        else
            task.wait(S.cashSpamRate)
        end
    end
end)

-- второй поток для удвоенного темпа
task.spawn(function()
    while true do
        if S.infCash and MailEvent then
            pcall(function() MailEvent:FireServer() end)
        end
        RunService.Heartbeat:Wait()
    end
end)

-- ===== INF FOLLOWERS =====
task.spawn(function()
    while true do
        if S.infFollowers and RespondEvent then
            pcall(function() RespondEvent:FireServer("Responded") end)
        end
        if S.respSpamRate <= 0 then
            RunService.Heartbeat:Wait()
        else
            task.wait(S.respSpamRate)
        end
    end
end)

task.spawn(function()
    while true do
        if S.infFollowers and RespondEvent then
            pcall(function() RespondEvent:FireServer("Responded") end)
        end
        RunService.Heartbeat:Wait()
    end
end)

-- ===== ProximityPrompt по всему миру =====
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

-- ===== TP to prompts =====
task.spawn(function()
    while task.wait(0.05) do
        if S.autoTpPrompt then
            local root, hum = hrp()
            if root and hum and hum.Health > 0 then
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if S.autoTpPrompt and v:IsA("ProximityPrompt") and v.Enabled then
                        local p = v.Parent
                        local part = p and (p:IsA("BasePart") and p or p:FindFirstChildWhichIsA("BasePart"))
                        if part then
                            pcall(function()
                                root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                                v.HoldDuration = 0
                                task.wait(0.08)
                                fireproximityprompt(v)
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== Collect cash models =====
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
frame.Size             = UDim2.new(0, 280, 0, 360)
frame.Position         = UDim2.new(0, 20, 0.5, -180)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
frame.BorderSizePixel  = 0
frame.Active           = true
frame.Draggable        = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local stroke       = Instance.new("UIStroke", frame)
stroke.Color       = Color3.fromRGB(150, 80, 255)
stroke.Thickness   = 1.8
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local head = Instance.new("TextLabel", frame)
head.Size                  = UDim2.new(1, 0, 0, 34)
head.BackgroundTransparency= 1
head.Text                  = "CENTAURA · Be a Streamer!"
head.Font                  = Enum.Font.GothamBold
head.TextSize              = 15
head.TextColor3            = Color3.fromRGB(210, 180, 255)

local sub = Instance.new("TextLabel", frame)
sub.Position               = UDim2.new(0, 0, 0, 34)
sub.Size                   = UDim2.new(1, 0, 0, 16)
sub.BackgroundTransparency = 1
sub.Text                   = "By @zood3llotgk"
sub.Font                   = Enum.Font.Gotham
sub.TextSize               = 11
sub.TextColor3             = Color3.fromRGB(150, 130, 200)

local list = Instance.new("Frame", frame)
list.Position              = UDim2.new(0, 10, 0, 58)
list.Size                  = UDim2.new(1, -20, 1, -68)
list.BackgroundTransparency= 1
local layout = Instance.new("UIListLayout", list)
layout.Padding   = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function toggle(name, key, accent)
    local b = Instance.new("TextButton", list)
    b.Size             = UDim2.new(1, 0, 0, 32)
    b.BorderSizePixel  = 0
    b.Font             = Enum.Font.GothamMedium
    b.TextSize         = 13
    b.TextColor3       = Color3.fromRGB(240, 240, 245)
    b.AutoButtonColor  = true
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local onColor  = accent or Color3.fromRGB(70, 30, 130)
    local offColor = Color3.fromRGB(28, 28, 36)
    local function render()
        b.Text            = (S[key] and "[ ON  ]  " or "[ OFF ]  ") .. name
        b.BackgroundColor3 = S[key] and onColor or offColor
    end
    render()
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]
        render()
        notify("CENTAURA", name .. ": " .. (S[key] and "ON" or "OFF"))
    end)
end

toggle("Inf Cash",             "infCash",      Color3.fromRGB(30, 140, 80))
toggle("Inf Followers",        "infFollowers", Color3.fromRGB(30, 90, 180))
toggle("Auto ProximityPrompt", "autoPrompt")
toggle("Auto TP + Prompt",     "autoTpPrompt")
toggle("Auto ClickDetector",   "autoClick")
toggle("Auto Collect $",       "autoCollect")
toggle("Anti-AFK",             "antiAFK")

local hint = Instance.new("TextLabel", list)
hint.Size                    = UDim2.new(1, 0, 0, 28)
hint.BackgroundTransparency  = 1
hint.Font                    = Enum.Font.Gotham
hint.TextSize                = 11
hint.TextColor3              = Color3.fromRGB(150, 150, 160)
hint.TextWrapped             = true
hint.Text                    = "RightShift — hide/show"

UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        frame.Visible = not frame.Visible
    end
end)

notify("CENTAURA", "Be a Streamer! loaded · by @zood3llotgk", 4)
