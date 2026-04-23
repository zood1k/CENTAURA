-- CENTAURA :: Be a Streamer! auto-farm
-- Based on RemoteSpy captures: StreamingEvent / NewStreamer / Purchase /
-- SetComputer / PassiveIncomeStream
-- NOTE: все перехваченные ремоуты были :FireClient (server->client),
-- поэтому основной фарм — через ProximityPrompt и ClickDetector.
-- FireServer вызовы оставлены как best-effort попытка.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")
local StarterGui         = game:GetService("StarterGui")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- ===== state =====
local state = {
    autoPrompt   = false,   -- жать все ProximityPrompt рядом
    autoClick    = false,   -- триггерить ClickDetector'ы рядом
    autoCollect  = false,   -- тянуться к моделям дохода
    autoStream   = false,   -- попытка FireServer на StreamingEvent
    antiAFK      = true,
    radius       = 50,
}

-- ===== notify =====
local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = title or "CENTAURA",
            Text     = text  or "",
            Duration = dur   or 3,
        })
    end)
end

-- ===== anti-AFK =====
LP.Idled:Connect(function()
    if not state.antiAFK then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end)

-- ===== utils =====
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function near(part, r)
    local root = hrp()
    if not root or not part then return false end
    return (root.Position - part.Position).Magnitude <= (r or state.radius)
end

-- ===== ProximityPrompt farm =====
task.spawn(function()
    while task.wait(0.35) do
        if state.autoPrompt then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Enabled then
                    local anchor = v.Parent
                    if anchor and anchor:IsA("BasePart") and near(anchor, state.radius) then
                        pcall(function()
                            v.HoldDuration = 0
                            fireproximityprompt(v)
                        end)
                    elseif anchor then
                        local any = anchor:FindFirstChildWhichIsA("BasePart")
                        if any and near(any, state.radius) then
                            pcall(function()
                                v.HoldDuration = 0
                                fireproximityprompt(v)
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== ClickDetector farm =====
task.spawn(function()
    while task.wait(0.4) do
        if state.autoClick then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ClickDetector") then
                    local anchor = v.Parent
                    if anchor and (anchor:IsA("BasePart") or anchor:IsA("Model")) then
                        local pivot = anchor:IsA("Model")
                            and (anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart"))
                            or anchor
                        if pivot and near(pivot, state.radius) then
                            pcall(function() fireclickdetector(v) end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== income collect =====
-- хвататься за любые валидные дроп-модели в Workspace (money/cash/bill и т.п.)
local CASH_KEYWORDS = {"cash","money","bill","coin","drop","donation","tip"}
local function looksLikeCash(name)
    name = string.lower(name or "")
    for _, k in ipairs(CASH_KEYWORDS) do
        if string.find(name, k, 1, true) then return true end
    end
    return false
end

task.spawn(function()
    while task.wait(0.5) do
        if state.autoCollect then
            local root = hrp()
            if root then
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if v:IsA("BasePart") and looksLikeCash(v.Name) then
                        if (root.Position - v.Position).Magnitude <= 200 then
                            pcall(function()
                                v.CFrame = root.CFrame
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== best-effort FireServer (на случай если ремоуты двунаправленные) =====
local function safeFireServer(remoteName, ...)
    local r = ReplicatedStorage:FindFirstChild(remoteName)
    if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then
        pcall(function()
            if r:IsA("RemoteEvent") then
                r:FireServer(...)
            else
                r:InvokeServer(...)
            end
        end)
    end
end

task.spawn(function()
    while task.wait(2) do
        if state.autoStream then
            safeFireServer("StreamingEvent", "segmentPreview", {
                ["followers"]  = 1,
                ["subscribers"]= 0,
                ["donations"]  = 7,
                ["newViewers"] = 2,
            })
            safeFireServer("Purchase")
            safeFireServer("PassiveIncomeStream")
        end
    end
end)

-- ===== GUI =====
local function buildGui()
    local old = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("CENTAURA_BAS")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name              = "CENTAURA_BAS"
    gui.ResetOnSpawn      = false
    gui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset    = true
    gui.Parent            = LP:WaitForChild("PlayerGui")

    local root = Instance.new("Frame", gui)
    root.Size                 = UDim2.new(0, 260, 0, 280)
    root.Position             = UDim2.new(0, 20, 0.5, -140)
    root.BackgroundColor3     = Color3.fromRGB(18, 18, 22)
    root.BorderSizePixel      = 0
    root.Active               = true
    root.Draggable            = true

    local corner = Instance.new("UICorner", root)
    corner.CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", root)
    stroke.Color     = Color3.fromRGB(130, 70, 220)
    stroke.Thickness = 1.5

    local title = Instance.new("TextLabel", root)
    title.Size                 = UDim2.new(1, 0, 0, 34)
    title.BackgroundTransparency = 1
    title.Text                 = "CENTAURA · Be a Streamer!"
    title.Font                 = Enum.Font.GothamBold
    title.TextSize             = 14
    title.TextColor3           = Color3.fromRGB(200, 170, 255)

    local list = Instance.new("Frame", root)
    list.Position              = UDim2.new(0, 10, 0, 40)
    list.Size                  = UDim2.new(1, -20, 1, -50)
    list.BackgroundTransparency= 1

    local layout = Instance.new("UIListLayout", list)
    layout.Padding              = UDim.new(0, 6)
    layout.SortOrder            = Enum.SortOrder.LayoutOrder

    local function toggle(name, key)
        local btn = Instance.new("TextButton", list)
        btn.Size             = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        btn.BorderSizePixel  = 0
        btn.Font             = Enum.Font.Gotham
        btn.TextSize         = 13
        btn.TextColor3       = Color3.fromRGB(235, 235, 240)
        btn.AutoButtonColor  = true
        local c = Instance.new("UICorner", btn); c.CornerRadius = UDim.new(0, 6)

        local function render()
            btn.Text = (state[key] and "[ON]  " or "[OFF] ") .. name
            btn.BackgroundColor3 = state[key]
                and Color3.fromRGB(60, 30, 110)
                or  Color3.fromRGB(28, 28, 36)
        end
        render()
        btn.MouseButton1Click:Connect(function()
            state[key] = not state[key]
            render()
            notify("CENTAURA", name .. ": " .. (state[key] and "ON" or "OFF"), 2)
        end)
    end

    toggle("Auto ProximityPrompt", "autoPrompt")
    toggle("Auto ClickDetector",   "autoClick")
    toggle("Auto Collect $",       "autoCollect")
    toggle("Auto Stream (exp.)",   "autoStream")
    toggle("Anti-AFK",             "antiAFK")

    local hint = Instance.new("TextLabel", list)
    hint.Size                 = UDim2.new(1, 0, 0, 28)
    hint.BackgroundTransparency = 1
    hint.Font                 = Enum.Font.Gotham
    hint.TextSize             = 11
    hint.TextColor3           = Color3.fromRGB(150, 150, 160)
    hint.TextWrapped          = true
    hint.Text                 = "RightShift — скрыть/показать"

    UserInputService.InputBegan:Connect(function(i, gpe)
        if gpe then return end
        if i.KeyCode == Enum.KeyCode.RightShift then
            root.Visible = not root.Visible
        end
    end)
end

pcall(buildGui)
notify("CENTAURA", "Be a Streamer! loaded", 4)
