-- CENTAURA :: Murderers vs Sheriffs 2 (v1 · HARD MODE)
-- By @zood3llotgk
--
-- Замечание по ремоутам: все 17 пойманных ремоутов — FireClient (сервер→клиент
-- с GUID-именами). Прямого FireServer на килл/урон нет. Скрипт использует
-- OnClientEvent хуки для чтения роли, стрика, коинов; а для урона/наводки —
-- клиентские методы (WalkSpeed, CFrame, Humanoid remount, аимбот).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local Lighting            = game:GetService("Lighting")
local Camera              = Workspace.CurrentCamera
local LP                  = Players.LocalPlayer
local Mouse               = LP:GetMouse()

-- ===== executor features =====
local function _G_get(name)
    local ok, v = pcall(function() return rawget(getfenv(0), name) end)
    if ok and v then return v end
    ok, v = pcall(function() return getfenv()[name] end)
    if ok and v then return v end
    return nil
end
local _getconnections = _G_get("getconnections")
local _firesignal     = _G_get("firesignal")

-- ===== state =====
local S = {
    -- Player
    speedHack    = false, walkSpeed = 32,
    jumpHack     = false, jumpPower = 80,
    infJump      = false,
    noclip       = false,
    fly          = false, flySpeed  = 60,
    antiAFK      = true,

    -- Combat
    silentAim    = false,
    aimbot       = false, aimKey = "E", fov = 90, teamCheck = true,
    killAura     = false, auraRange = 12,
    triggerBot   = false,

    -- Visuals
    espNames     = false,
    espBox       = false,
    espTracers   = false,
    teamChams    = false,

    -- Automation
    autoCase     = false,
    autoRespawn  = false,

    -- Info (readonly)
    role         = "Unknown",
    coins        = 0,
    streak       = 0,
    lastKilledBy = "-",
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

-- ===== Anti-AFK =====
LP.Idled:Connect(function()
    if not S.antiAFK then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game); task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end)

-- ===== Role detection =====
-- Murderer has Knife tool; Sheriff has Gun/Revolver tool; иначе Innocent.
local function computeRole()
    local c = char(); if not c then return "Unknown" end
    local hasKnife, hasGun = false, false
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") or t:IsA("Model") then
                local n = string.lower(t.Name or "")
                if n:find("knife") or n:find("blade") then hasKnife = true
                elseif n:find("gun") or n:find("revolver") or n:find("pistol") or n:find("rifle") then hasGun = true end
            end
        end
    end
    scan(c)
    scan(LP:FindFirstChild("Backpack"))
    if hasKnife and not hasGun then return "Murderer" end
    if hasGun and not hasKnife then return "Sheriff" end
    if hasKnife and hasGun then return "Both (?)" end
    return "Innocent"
end

task.spawn(function()
    while task.wait(0.5) do S.role = computeRole() end
end)

-- ===== OnClientEvent hooks (FireClient events by GUIDs) =====
-- 1. Подвешиваемся на все RemoteEvent в ReplicatedStorage чтобы парсить:
--    * streak/kill notifier   (args: number, "Streak", {Kills, Name, UserId})
--    * coins / currency       (args: number single-arg)
--    * inventory stats        (args: {dict of weapons -> counts})
local hookedRemotes = {}
local function hookRemote(r)
    if not r:IsA("RemoteEvent") then return end
    if hookedRemotes[r] then return end
    hookedRemotes[r] = true
    r.OnClientEvent:Connect(function(...)
        local a = {...}
        -- streak notif: (int, "Streak", {Kills, Name, UserId})
        if type(a[2]) == "string" and string.lower(a[2]) == "streak"
           and type(a[3]) == "table" then
            local info = a[3]
            if info.Name and info.Kills then
                if info.UserId == LP.UserId then
                    S.streak = info.Kills
                else
                    -- возможно нас убили
                    S.lastKilledBy = string.format("%s (%d streak)", info.Name, info.Kills or 0)
                end
            end
        end
        -- single number → coins / currency
        if #a == 1 and type(a[1]) == "number" and a[1] > 100 and a[1] < 1e12 then
            -- осторожно: это может быть что угодно, но обычно coins
            if a[1] ~= S.coins then S.coins = a[1] end
        end
    end)
end

local function scanReplicated()
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") then hookRemote(v) end
    end
end
scanReplicated()
ReplicatedStorage.DescendantAdded:Connect(function(v)
    if v:IsA("RemoteEvent") then hookRemote(v) end
end)

-- ===== Movement =====
-- Держим WS/JP через property change signals (переустановка при сбросе)
local function bindHum(hum)
    if not hum then return end
    hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if S.speedHack and hum.WalkSpeed ~= S.walkSpeed then hum.WalkSpeed = S.walkSpeed end
    end)
    hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
        if S.jumpHack and hum.JumpPower ~= S.jumpPower then hum.JumpPower = S.jumpPower end
    end)
    if S.speedHack then hum.WalkSpeed = S.walkSpeed end
    if S.jumpHack then hum.JumpPower = S.jumpPower; hum.UseJumpPower = true end
end
local function bindChar(c)
    local hum = c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid", 5)
    bindHum(hum)
end
if char() then bindChar(char()) end
LP.CharacterAdded:Connect(function(c) task.wait(0.2); bindChar(c) end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if not S.infJump then return end
    local _, hum = hrp()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- Noclip (cached char parts)
local charParts = {}
local function rebuildCharParts()
    charParts = {}
    local c = char(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(charParts, p) end
    end
end
LP.CharacterAdded:Connect(function() task.wait(0.3); rebuildCharParts() end)
if char() then rebuildCharParts() end
task.spawn(function()
    while task.wait(0.1) do
        if S.noclip then
            for _, p in ipairs(charParts) do
                if p and p.Parent and p.CanCollide then p.CanCollide = false end
            end
        end
    end
end)

-- Fly
local flyBV, flyBG
local flyConn
local function stopFly()
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if flyConn then flyConn:Disconnect(); flyConn = nil end
end
local function startFly()
    stopFly()
    local root, hum = hrp()
    if not root or not hum then return end
    flyBV = Instance.new("BodyVelocity", root)
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBG = Instance.new("BodyGyro", root)
    flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBG.P = 9000; flyBG.D = 500
    flyBG.CFrame = root.CFrame
    flyConn = RunService.Heartbeat:Connect(function()
        if not S.fly then return end
        local cam = Camera.CFrame
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0,1,0) end
        flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * S.flySpeed or Vector3.zero
        flyBG.CFrame = cam
    end)
end
local function setFly(on)
    if on then startFly() else stopFly() end
end

-- ===== Aimbot / Silent Aim =====
local function getNearestEnemy()
    local myRoot = hrp(); if not myRoot then return nil end
    local closest, closestScore
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP and pl.Character then
            local hrp2 = pl.Character:FindFirstChild("HumanoidRootPart")
            local hum2 = pl.Character:FindFirstChildOfClass("Humanoid")
            if hrp2 and hum2 and hum2.Health > 0 then
                -- team check: если у меня Sheriff — цель = Murderer; если Murderer — все кроме sheriff-союзников
                if S.teamCheck then
                    -- у MvS2 "командные флаги" через TeamColor нестабильно, поэтому
                    -- аимбот всегда активен на всех; пользователь сам выбирает
                end
                local v, onScreen = Camera:WorldToViewportPoint(hrp2.Position)
                if onScreen then
                    local mpos = UserInputService:GetMouseLocation()
                    local dist = ((Vector2.new(v.X, v.Y) - mpos)).Magnitude
                    if dist < S.fov and (not closestScore or dist < closestScore) then
                        closest = pl
                        closestScore = dist
                    end
                end
            end
        end
    end
    return closest
end

local aimKey = Enum.KeyCode[S.aimKey] or Enum.KeyCode.E
RunService.RenderStepped:Connect(function()
    if S.aimbot and UserInputService:IsKeyDown(aimKey) then
        local target = getNearestEnemy()
        if target and target.Character then
            local hrp2 = target.Character:FindFirstChild("HumanoidRootPart")
                      or target.Character:FindFirstChild("Head")
            if hrp2 then
                Camera.CFrame = CFrame.new(Camera.CFrame.Position, hrp2.Position)
            end
        end
    end
end)

-- Silent Aim: хук на Mouse.Hit / Mouse.Target когда инструмент ищет цель
local origMetatable
local function enableSilentAim()
    if origMetatable then return end
    local mt = getrawmetatable and getrawmetatable(game)
    if not mt then return end
    local oldIndex = mt.__index
    pcall(function()
        if setreadonly then setreadonly(mt, false) end
    end)
    origMetatable = oldIndex
    mt.__index = function(self, k)
        if S.silentAim and (self == LP or self == Mouse) then
            if k == "Hit" or k == "hit" then
                local target = getNearestEnemy()
                if target and target.Character then
                    local part = target.Character:FindFirstChild("Head")
                              or target.Character:FindFirstChild("HumanoidRootPart")
                    if part then return CFrame.new(part.Position) end
                end
            elseif k == "Target" or k == "target" then
                local target = getNearestEnemy()
                if target and target.Character then
                    return target.Character:FindFirstChild("Head")
                        or target.Character:FindFirstChild("HumanoidRootPart")
                end
            end
        end
        return oldIndex(self, k)
    end
    pcall(function()
        if setreadonly then setreadonly(mt, true) end
    end)
end
-- не активируем хук пока юзер не включит silentAim; включение — при первом переключении
local silentAimInitialized = false
local function setSilentAim(on)
    if on and not silentAimInitialized then
        silentAimInitialized = true
        enableSilentAim()
    end
end

-- ===== Kill Aura (knife swing at nearby players) =====
-- Активирует Tool (knife) если рядом есть цель — работает только когда игрок Murderer.
task.spawn(function()
    while task.wait(0.1) do
        if S.killAura then
            local c = char(); if c then
                local myRoot = c:FindFirstChild("HumanoidRootPart")
                local knife
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") and string.lower(t.Name):find("knife") then knife = t end
                end
                if myRoot and knife then
                    for _, pl in ipairs(Players:GetPlayers()) do
                        if pl ~= LP and pl.Character then
                            local hrp2 = pl.Character:FindFirstChild("HumanoidRootPart")
                            local hum2 = pl.Character:FindFirstChildOfClass("Humanoid")
                            if hrp2 and hum2 and hum2.Health > 0 then
                                if (hrp2.Position - myRoot.Position).Magnitude < S.auraRange then
                                    pcall(function() knife:Activate() end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ===== Trigger Bot (auto-fire when enemy under crosshair) =====
task.spawn(function()
    while task.wait(0.05) do
        if S.triggerBot then
            local mpos = UserInputService:GetMouseLocation()
            local target = getNearestEnemy()
            if target and target.Character then
                local hrp2 = target.Character:FindFirstChild("HumanoidRootPart")
                if hrp2 then
                    local v = Camera:WorldToViewportPoint(hrp2.Position)
                    local d = (Vector2.new(v.X, v.Y) - mpos).Magnitude
                    if d < 25 then
                        VirtualInputManager:SendMouseButtonEvent(mpos.X, mpos.Y, 0, true, game, 0); task.wait(0.03)
                        VirtualInputManager:SendMouseButtonEvent(mpos.X, mpos.Y, 0, false, game, 0)
                    end
                end
            end
        end
    end
end)

-- ===== ESP =====
local espStore = {}
local function clearESPFor(pl)
    local e = espStore[pl]; if not e then return end
    for _, obj in pairs(e) do pcall(function() obj:Destroy() end) end
    espStore[pl] = nil
end
local function ensureESPFor(pl)
    if pl == LP then return nil end
    if not pl.Character then return nil end
    if not espStore[pl] then espStore[pl] = {} end
    local e = espStore[pl]
    local head = pl.Character:FindFirstChild("Head")
    local hrp2 = pl.Character:FindFirstChild("HumanoidRootPart")
    if not head or not hrp2 then return e end

    if S.espNames or S.espBox then
        if not e.bb then
            local bb = Instance.new("BillboardGui", pl.Character)
            bb.Name = "_CENTAURA_ESP"
            bb.Adornee = head
            bb.Size = UDim2.new(0, 140, 0, 28)
            bb.StudsOffset = Vector3.new(0, 2.5, 0)
            bb.AlwaysOnTop = true
            local lbl = Instance.new("TextLabel", bb)
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 13
            lbl.TextStrokeTransparency = 0.3
            lbl.TextColor3 = Color3.fromRGB(255,255,255)
            e.bb = bb; e.lbl = lbl
        end
    end
    if e.bb and not (S.espNames or S.espBox) then
        e.bb:Destroy(); e.bb = nil; e.lbl = nil
    end

    if S.teamChams or S.espBox then
        if not e.hl then
            local hl = Instance.new("Highlight", pl.Character)
            hl.Name = "_CENTAURA_HL"
            hl.FillTransparency = 0.55
            hl.OutlineColor = Color3.fromRGB(255,255,255)
            e.hl = hl
        end
    end
    if e.hl and not (S.teamChams or S.espBox) then
        e.hl:Destroy(); e.hl = nil
    end

    if S.espTracers then
        if not e.line then
            local line = Drawing and Drawing.new and Drawing.new("Line")
            if line then
                line.Thickness = 1.5
                line.Transparency = 1
                e.line = line
            end
        end
    end
    if e.line and not S.espTracers then
        pcall(function() e.line:Remove() end)
        e.line = nil
    end

    return e
end

local function roleOfPlayer(pl)
    if not pl.Character then return "Innocent" end
    local hasKnife, hasGun = false, false
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") or t:IsA("Model") then
                local n = string.lower(t.Name or "")
                if n:find("knife") or n:find("blade") then hasKnife = true
                elseif n:find("gun") or n:find("revolver") or n:find("pistol") or n:find("rifle") then hasGun = true end
            end
        end
    end
    scan(pl.Character)
    scan(pl:FindFirstChild("Backpack"))
    if hasKnife then return "Murderer" end
    if hasGun then return "Sheriff" end
    return "Innocent"
end

local function roleColor(role)
    if role == "Murderer" then return Color3.fromRGB(255, 50, 60) end
    if role == "Sheriff"  then return Color3.fromRGB(60, 130, 255) end
    return Color3.fromRGB(220, 220, 220)
end

RunService.RenderStepped:Connect(function()
    local anyESP = S.espNames or S.espBox or S.espTracers or S.teamChams
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP then
            if not anyESP then
                clearESPFor(pl)
            else
                local e = ensureESPFor(pl)
                if e then
                    local role = roleOfPlayer(pl)
                    local col  = roleColor(role)
                    if e.lbl then
                        e.lbl.TextColor3 = col
                        e.lbl.Text = S.espNames and (pl.Name .. " · " .. role) or role
                    end
                    if e.hl then
                        e.hl.FillColor = col
                        e.hl.OutlineColor = col
                    end
                    if e.line then
                        local hrp2 = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
                        if hrp2 then
                            local v, on = Camera:WorldToViewportPoint(hrp2.Position)
                            if on then
                                local mp = UserInputService:GetMouseLocation()
                                e.line.From = Vector2.new(mp.X, mp.Y + 30)
                                e.line.To = Vector2.new(v.X, v.Y)
                                e.line.Color = col
                                e.line.Visible = true
                            else
                                e.line.Visible = false
                            end
                        else
                            e.line.Visible = false
                        end
                    end
                end
            end
        end
    end
end)
Players.PlayerRemoving:Connect(clearESPFor)

-- ===== Automation =====
-- Auto-click case button (pattern: "case" / "open" / "unlock")
local function clickButtonsMatching(patterns)
    local pg = LP:FindFirstChild("PlayerGui"); if not pg then return end
    for _, g in ipairs(pg:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton"))
           and not (CENTAURA_GUI and g:IsDescendantOf(CENTAURA_GUI)) then
            if g.Visible and g.Active and g.AbsoluteSize.X > 0 and g.AbsoluteSize.Y > 0 then
                local n = string.lower(g.Name or "")
                local t = (g:IsA("TextButton") and string.lower(g.Text or "")) or ""
                for _, p in ipairs(patterns) do
                    if n:find(p) or t:find(p) then
                        pcall(function()
                            if _firesignal then _firesignal(g.MouseButton1Click)
                            elseif _getconnections then
                                for _, c in ipairs(_getconnections(g.MouseButton1Click)) do
                                    if c.Fire then c:Fire() elseif c.Function then c.Function() end
                                end
                            end
                        end)
                        break
                    end
                end
            end
        end
    end
end
-- forward ref
CENTAURA_GUI = nil

task.spawn(function()
    while task.wait(0.6) do
        if S.autoCase then clickButtonsMatching({"openc","case","unlock","opencase"}) end
    end
end)

-- Auto Respawn (hook died)
task.spawn(function()
    while task.wait(1) do
        if S.autoRespawn then
            local _, hum = hrp()
            if hum and hum.Health <= 0 then
                pcall(function() LP:LoadCharacter() end)
            end
        end
    end
end)

-- ===== GUI (tabbed) =====
local pg = LP:WaitForChild("PlayerGui")
if pg:FindFirstChild("CENTAURA_MVS") then pg.CENTAURA_MVS:Destroy() end

local gui = Instance.new("ScreenGui", pg)
gui.Name = "CENTAURA_MVS"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
CENTAURA_GUI = gui

local root = Instance.new("Frame", gui)
root.Size             = UDim2.new(0, 460, 0, 360)
root.Position         = UDim2.new(0.5, -230, 0.5, -180)
root.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
root.BorderSizePixel  = 0
root.Active           = true
root.Draggable        = true
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", root)
stroke.Color = Color3.fromRGB(150, 80, 255); stroke.Thickness = 1.6

-- Header
local header = Instance.new("Frame", root)
header.Size             = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
header.BorderSizePixel  = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel", header)
title.Position = UDim2.new(0, 16, 0, 4)
title.Size = UDim2.new(1, -32, 0, 20)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(220, 200, 255)
title.Text = "CENTAURA · Murderers vs Sheriffs 2"

local sub = Instance.new("TextLabel", header)
sub.Position = UDim2.new(0, 16, 0, 22)
sub.Size = UDim2.new(1, -32, 0, 16)
sub.BackgroundTransparency = 1
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Font = Enum.Font.Gotham
sub.TextSize = 11
sub.TextColor3 = Color3.fromRGB(160, 140, 210)
sub.Text = "By @zood3llotgk"

-- Tab bar
local tabBar = Instance.new("Frame", root)
tabBar.Position          = UDim2.new(0, 8, 0, 48)
tabBar.Size              = UDim2.new(0, 120, 1, -56)
tabBar.BackgroundColor3  = Color3.fromRGB(20, 20, 28)
tabBar.BorderSizePixel   = 0
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 8)
local tabLay = Instance.new("UIListLayout", tabBar)
tabLay.Padding = UDim.new(0, 4)
tabLay.SortOrder = Enum.SortOrder.LayoutOrder
local tabPad = Instance.new("UIPadding", tabBar)
tabPad.PaddingTop = UDim.new(0, 6); tabPad.PaddingLeft = UDim.new(0, 6); tabPad.PaddingRight = UDim.new(0, 6)

-- Content pane
local content = Instance.new("Frame", root)
content.Position = UDim2.new(0, 136, 0, 48)
content.Size = UDim2.new(1, -144, 1, -56)
content.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
content.BorderSizePixel = 0
Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

local tabFrames = {}
local tabButtons = {}
local activeTab

local function selectTab(name)
    activeTab = name
    for n, f in pairs(tabFrames) do f.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        b.BackgroundColor3 = (n == name) and Color3.fromRGB(70, 30, 130) or Color3.fromRGB(30, 30, 40)
    end
end

local function addTab(name, order)
    local btn = Instance.new("TextButton", tabBar)
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.LayoutOrder = order
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(230, 230, 240)
    btn.Text = name
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    tabButtons[name] = btn

    local frame = Instance.new("ScrollingFrame", content)
    frame.Size = UDim2.new(1, -12, 1, -12)
    frame.Position = UDim2.new(0, 6, 0, 6)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.ScrollBarThickness = 4
    frame.ScrollBarImageColor3 = Color3.fromRGB(150, 80, 255)
    frame.Visible = false
    local lay = Instance.new("UIListLayout", frame); lay.Padding = UDim.new(0, 5)
    tabFrames[name] = frame

    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    return frame
end

local function toggle(parent, name, key, accent, onToggle)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(1, -4, 0, 28)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(240, 240, 245)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local onC = accent or Color3.fromRGB(70, 30, 130)
    local offC = Color3.fromRGB(28, 28, 36)
    local function r()
        b.Text = (S[key] and "[ ON  ]  " or "[ OFF ]  ") .. name
        b.BackgroundColor3 = S[key] and onC or offC
    end
    r()
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]; r()
        notify("CENTAURA", name .. ": " .. (S[key] and "ON" or "OFF"))
        if onToggle then pcall(onToggle, S[key]) end
    end)
end

local function slider(parent, label, key, mn, mx, step)
    local c = Instance.new("Frame", parent)
    c.Size = UDim2.new(1, -4, 0, 40)
    c.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    c.BorderSizePixel = 0
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(1, -10, 0, 14); l.Position = UDim2.new(0, 8, 0, 2)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(210, 210, 220)
    l.Text = label .. ": " .. tostring(S[key])
    local m = Instance.new("TextButton", c)
    m.Size = UDim2.new(0, 24, 0, 20); m.Position = UDim2.new(0, 8, 0, 18)
    m.Text = "-"; m.Font = Enum.Font.GothamBold; m.TextSize = 14
    m.BackgroundColor3 = Color3.fromRGB(60, 30, 110); m.TextColor3 = Color3.fromRGB(255,255,255); m.BorderSizePixel = 0
    Instance.new("UICorner", m).CornerRadius = UDim.new(0, 4)
    local p = Instance.new("TextButton", c)
    p.Size = UDim2.new(0, 24, 0, 20); p.Position = UDim2.new(1, -32, 0, 18)
    p.Text = "+"; p.Font = Enum.Font.GothamBold; p.TextSize = 14
    p.BackgroundColor3 = Color3.fromRGB(60, 30, 110); p.TextColor3 = Color3.fromRGB(255,255,255); p.BorderSizePixel = 0
    Instance.new("UICorner", p).CornerRadius = UDim.new(0, 4)
    local v = Instance.new("TextLabel", c)
    v.Size = UDim2.new(1, -72, 0, 20); v.Position = UDim2.new(0, 36, 0, 18)
    v.BackgroundTransparency = 1; v.Font = Enum.Font.GothamMedium; v.TextSize = 12
    v.TextColor3 = Color3.fromRGB(240, 240, 245); v.Text = tostring(S[key])
    local function ap(x) x = math.clamp(x, mn, mx); S[key] = x; v.Text = tostring(x); l.Text = label .. ": " .. tostring(x) end
    m.MouseButton1Click:Connect(function() ap(S[key] - step) end)
    p.MouseButton1Click:Connect(function() ap(S[key] + step) end)
end

local function infoRow(parent, getText)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1, -4, 0, 24)
    l.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    l.BorderSizePixel = 0
    l.Font = Enum.Font.GothamMedium; l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(220, 220, 230)
    l.Text = getText()
    Instance.new("UICorner", l).CornerRadius = UDim.new(0, 5)
    task.spawn(function()
        while l.Parent do
            l.Text = getText()
            task.wait(0.4)
        end
    end)
end

-- ===== Tabs =====
local tabPlayer     = addTab("Player", 1)
local tabCombat     = addTab("Combat", 2)
local tabVisuals    = addTab("Visuals", 3)
local tabAutomation = addTab("Automation", 4)
local tabInfo       = addTab("Info", 5)
local tabMisc       = addTab("Misc", 6)

-- Player
toggle(tabPlayer, "Speed Hack",    "speedHack", Color3.fromRGB(30, 140, 80), function(on)
    local _, hum = hrp(); if hum and on then hum.WalkSpeed = S.walkSpeed end
end)
slider(tabPlayer, "Walk Speed",    "walkSpeed", 16, 300, 4)
toggle(tabPlayer, "Jump Hack",     "jumpHack", Color3.fromRGB(30, 90, 180), function(on)
    local _, hum = hrp(); if hum and on then hum.JumpPower = S.jumpPower; hum.UseJumpPower = true end
end)
slider(tabPlayer, "Jump Power",    "jumpPower", 50, 500, 10)
toggle(tabPlayer, "Infinite Jump", "infJump")
toggle(tabPlayer, "Noclip",        "noclip", Color3.fromRGB(140, 50, 160))
toggle(tabPlayer, "Fly",           "fly", Color3.fromRGB(30, 140, 140), setFly)
slider(tabPlayer, "Fly Speed",     "flySpeed", 20, 300, 10)
toggle(tabPlayer, "Anti-AFK",      "antiAFK")

-- Combat
toggle(tabCombat, "Silent Aim",    "silentAim", Color3.fromRGB(180, 50, 50), setSilentAim)
toggle(tabCombat, "Aimbot (hold E)", "aimbot", Color3.fromRGB(200, 70, 50))
slider(tabCombat, "FOV",           "fov", 20, 500, 10)
toggle(tabCombat, "Kill Aura (knife)", "killAura", Color3.fromRGB(160, 40, 60))
slider(tabCombat, "Aura Range",    "auraRange", 4, 30, 1)
toggle(tabCombat, "Trigger Bot",   "triggerBot", Color3.fromRGB(140, 80, 30))

-- Visuals
toggle(tabVisuals, "ESP Names",    "espNames", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "ESP Box/Highlight", "espBox", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "ESP Tracers",  "espTracers", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "Team Chams",   "teamChams", Color3.fromRGB(150, 80, 255))

-- Automation
toggle(tabAutomation, "Auto Open Case", "autoCase", Color3.fromRGB(140, 100, 30))
toggle(tabAutomation, "Auto Respawn",   "autoRespawn")

-- Info
infoRow(tabInfo, function() return "Role: " .. (S.role or "?") end)
infoRow(tabInfo, function() return "Kill Streak: " .. tostring(S.streak or 0) end)
infoRow(tabInfo, function() return "Coins (?): " .. tostring(S.coins or 0) end)
infoRow(tabInfo, function() return "Last killed by: " .. tostring(S.lastKilledBy or "-") end)
infoRow(tabInfo, function() return "Players: " .. tostring(#Players:GetPlayers()) end)

-- Misc
local hint = Instance.new("TextLabel", tabMisc)
hint.Size = UDim2.new(1, -4, 0, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham; hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(160, 160, 170)
hint.Text = "RightShift — hide/show GUI"

local destroyBtn = Instance.new("TextButton", tabMisc)
destroyBtn.Size = UDim2.new(1, -4, 0, 28)
destroyBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
destroyBtn.BorderSizePixel = 0
destroyBtn.TextColor3 = Color3.fromRGB(255,255,255)
destroyBtn.Font = Enum.Font.GothamBold
destroyBtn.TextSize = 12
destroyBtn.Text = "Unload CENTAURA"
Instance.new("UICorner", destroyBtn).CornerRadius = UDim.new(0, 6)
destroyBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then root.Visible = not root.Visible end
end)

selectTab("Player")
notify("CENTAURA", "MvS2 v1 loaded · by @zood3llotgk", 4)
