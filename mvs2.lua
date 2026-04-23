-- CENTAURA :: Murderers vs Sheriffs 2 (v2 · HARD MODE)
-- By @zood3llotgk
--
-- v2 changelog:
--  * Player tab: теперь ищет настоящий character model в Workspace (MvS2 парентит
--    персонажа в кастомный контейнер, LP.Character не всегда равен активному чару)
--  * Movement: всё работает на getActiveCharacter() + force-переустановка WS/JP
--    каждые 0.3s
--  * Aimbot: плавный lerp, целится в Head
--  * Trigger Bot: raycast Camera→Target, не стреляет сквозь стены
--  * ESP: переведён с RenderStepped на Heartbeat 0.1s, кэш всего
--  * Tracer cleanup: использует :Remove() вместо :Destroy()

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local Camera              = Workspace.CurrentCamera
local LP                  = Players.LocalPlayer
local Mouse               = LP:GetMouse()

-- ===== executor features =====
local _getconnections = (rawget(_G, "getconnections")) or getconnections
local _firesignal     = (rawget(_G, "firesignal")) or firesignal
local _getrawmt       = (rawget(_G, "getrawmetatable")) or getrawmetatable
local _setreadonly    = (rawget(_G, "setreadonly")) or setreadonly

-- ===== lifecycle =====
local RUNNING = true
local CONNECTIONS = {}
local function track(conn) table.insert(CONNECTIONS, conn); return conn end
-- все task.spawn лупы чекают RUNNING. aimbot/fly коннекшны тоже.

-- ===== state =====
local S = {
    speedHack    = false, walkSpeed = 40,
    jumpHack     = false, jumpPower = 80,
    infJump      = false,
    noclip       = false,
    fly          = false, flySpeed  = 60,
    antiAFK      = true,

    silentAim    = false,
    aimbot       = false, aimKey = "E", fov = 120, aimSmooth = 1, aimTarget = "HumanoidRootPart",
    killAura     = false, auraRange = 12,
    triggerBot   = false, tbWallCheck = true, tbRadius = 18,

    espNames     = false,
    espBox       = false,
    espTracers   = false,
    teamChams    = false,

    autoCase     = false,
    autoRespawn  = false,

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

-- ========================================================
-- Character resolution (MvS2 не всегда кладёт character в LP.Character)
-- ========================================================
local function findCharacterByName(name)
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") and m.Name == name and m:FindFirstChildOfClass("Humanoid") then
            return m
        end
    end
    -- поиск в под-папках (MvS2 может складывать в Workspace.Characters / Players / Map)
    for _, folder in ipairs({"Characters","Players","Alive","Map","Game","Entities"}) do
        local f = Workspace:FindFirstChild(folder)
        if f then
            local m = f:FindFirstChild(name)
            if m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
                return m
            end
        end
    end
    return nil
end

local function getActiveCharacter()
    -- 1) стандартный путь
    local c = LP.Character
    if c and c:FindFirstChildOfClass("Humanoid") and c:FindFirstChild("HumanoidRootPart") then
        return c
    end
    -- 2) fallback — поиск модели с именем игрока
    return findCharacterByName(LP.Name)
end

local function getHRP()
    local c = getActiveCharacter(); if not c then return nil, nil end
    return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function charOfPlayer(pl)
    if pl.Character and pl.Character:FindFirstChildOfClass("Humanoid") then
        return pl.Character
    end
    return findCharacterByName(pl.Name)
end

-- ========================================================
-- Anti-AFK
-- ========================================================
track(LP.Idled:Connect(function()
    if not RUNNING then return end
    if not S.antiAFK then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game); task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end))

-- ========================================================
-- Movement (speed / jump / noclip / fly / inf jump)
-- ========================================================

-- Ленивая переустановка каждые 0.3s: найти активного чара, выставить WS/JP
task.spawn(function()
    while RUNNING and task.wait(0.3) do
        local _, hum = getHRP()
        if hum then
            if S.speedHack and hum.WalkSpeed ~= S.walkSpeed then
                pcall(function() hum.WalkSpeed = S.walkSpeed end)
            end
            if S.jumpHack then
                if hum.JumpPower ~= S.jumpPower then
                    pcall(function() hum.JumpPower = S.jumpPower; hum.UseJumpPower = true end)
                end
            end
        end
    end
end)

-- Infinite Jump
track(UserInputService.JumpRequest:Connect(function()
    if not RUNNING or not S.infJump then return end
    local _, hum = getHRP()
    if hum then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end))

-- Noclip: выключаем CanCollide на всех частях активного чара
task.spawn(function()
    while RUNNING and task.wait(0.1) do
        if S.noclip then
            local c = getActiveCharacter()
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then
                        pcall(function() p.CanCollide = false end)
                    end
                end
            end
        end
    end
end)

-- Fly
local flyBV, flyBG, flyConn
local function stopFly()
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
    if flyConn then flyConn:Disconnect(); flyConn = nil end
end
local function startFly()
    stopFly()
    local root = getHRP(); if not root then return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent   = root
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5)
    flyBG.P = 9000; flyBG.D = 500
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root
    flyConn = RunService.Heartbeat:Connect(function()
        if not S.fly then stopFly(); return end
        local newRoot = getHRP()
        if not newRoot or newRoot ~= root then stopFly(); if S.fly then startFly() end; return end
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
local function setFly(on) if on then startFly() else stopFly() end end

-- ========================================================
-- Role detection
-- ========================================================
local function scanTools(container, out)
    if not container then return end
    for _, t in ipairs(container:GetChildren()) do
        if t:IsA("Tool") then
            local n = string.lower(t.Name or "")
            if n:find("knife") or n:find("blade") then out.knife = true
            elseif n:find("gun") or n:find("revolver") or n:find("pistol") or n:find("rifle") or n:find("shotgun") then out.gun = true end
        end
    end
end
local function computeRoleFor(pl)
    local out = {knife = false, gun = false}
    scanTools(charOfPlayer(pl), out)
    scanTools(pl:FindFirstChild("Backpack"), out)
    if out.knife and not out.gun then return "Murderer" end
    if out.gun and not out.knife then return "Sheriff" end
    if out.knife and out.gun then return "Both" end
    return "Innocent"
end
task.spawn(function()
    while RUNNING and task.wait(0.5) do S.role = computeRoleFor(LP) end
end)

-- ========================================================
-- OnClientEvent hooks (stream stats through GUID-named remotes)
-- ========================================================
local hookedRemotes = {}
local function hookRemote(r)
    if not r or not r:IsA("RemoteEvent") or hookedRemotes[r] then return end
    hookedRemotes[r] = true
    r.OnClientEvent:Connect(function(...)
        local a = {...}
        if type(a[2]) == "string" and string.lower(a[2]) == "streak" and type(a[3]) == "table" then
            local info = a[3]
            if info.Name and info.Kills then
                if info.UserId == LP.UserId then
                    S.streak = info.Kills
                else
                    S.lastKilledBy = string.format("%s (%d streak)", info.Name, info.Kills or 0)
                end
            end
        end
        if #a == 1 and type(a[1]) == "number" and a[1] > 100 and a[1] < 1e12 then
            if a[1] ~= S.coins then S.coins = a[1] end
        end
    end)
end
for _, v in ipairs(ReplicatedStorage:GetDescendants()) do hookRemote(v) end
track(ReplicatedStorage.DescendantAdded:Connect(hookRemote))

-- ========================================================
-- Aimbot + Silent Aim
-- ========================================================
local function isAlive(c)
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

-- Raycast check: есть ли прямая видимость Camera→target
local function hasLineOfSight(targetPart)
    if not targetPart then return false end
    local origin = Camera.CFrame.Position
    local dir = targetPart.Position - origin
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local me = getActiveCharacter()
    rp.FilterDescendantsInstances = me and {me} or {}
    rp.IgnoreWater = true
    local r = Workspace:Raycast(origin, dir, rp)
    if not r then return true end
    -- попали в часть: если она принадлежит character цели — LOS есть
    local hit = r.Instance
    if hit and targetPart.Parent and hit:IsDescendantOf(targetPart.Parent) then return true end
    return false
end

local function getNearestEnemy(requireLOS)
    local closest, score
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP then
            local c = charOfPlayer(pl)
            if c and isAlive(c) then
                local head = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
                if head then
                    local v, on = Camera:WorldToViewportPoint(head.Position)
                    if on and v.Z > 0 then
                        local mp = UserInputService:GetMouseLocation()
                        local d  = (Vector2.new(v.X, v.Y) - mp).Magnitude
                        if d < S.fov then
                            if (not requireLOS) or hasLineOfSight(head) then
                                if (not score) or d < score then
                                    closest = pl; score = d
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local aimKeyCode = Enum.KeyCode[S.aimKey] or Enum.KeyCode.E
-- Aimbot: целится в HumanoidRootPart (дефолт — стабильнее чем Head), строит CFrame через
-- lookAt с Vector3.yAxis (никакого roll-а — камера не "кривится"). Default smooth = 1 (snap).
track(RunService.RenderStepped:Connect(function()
    if not RUNNING then return end
    if not (S.aimbot and UserInputService:IsKeyDown(aimKeyCode)) then return end
    local target = getNearestEnemy(false)
    if not target then return end
    local c = charOfPlayer(target); if not c then return end
    local part = c:FindFirstChild(S.aimTarget) or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
    if not part then return end
    local origin = Camera.CFrame.Position
    local desired = CFrame.lookAt(origin, part.Position, Vector3.yAxis)
    local smooth = math.clamp(S.aimSmooth, 0.05, 1)
    if smooth >= 0.999 then
        Camera.CFrame = desired
    else
        Camera.CFrame = Camera.CFrame:Lerp(desired, smooth)
    end
end))

-- Silent Aim: подменяем Mouse.Hit / Mouse.Target
local silentAimInstalled = false
local function installSilentAim()
    if silentAimInstalled then return end
    if not _getrawmt then
        notify("CENTAURA", "Silent Aim: executor без getrawmetatable", 4); return
    end
    local mt = _getrawmt(game)
    if not mt then return end
    pcall(function() if _setreadonly then _setreadonly(mt, false) end end)
    local oldIndex = mt.__index
    mt.__index = function(self, k)
        if S.silentAim and (self == LP or self == Mouse) then
            if k == "Hit" or k == "hit" then
                local target = getNearestEnemy(false)
                if target then
                    local c = charOfPlayer(target)
                    local p = c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
                    if p then return CFrame.new(p.Position) end
                end
            elseif k == "Target" or k == "target" then
                local target = getNearestEnemy(false)
                if target then
                    local c = charOfPlayer(target)
                    return c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
                end
            end
        end
        return oldIndex(self, k)
    end
    pcall(function() if _setreadonly then _setreadonly(mt, true) end end)
    silentAimInstalled = true
end
local function setSilentAim(on) if on then installSilentAim() end end

-- ========================================================
-- Kill Aura
-- ========================================================
task.spawn(function()
    while RUNNING and task.wait(0.12) do
        if S.killAura then
            local c = getActiveCharacter()
            if c then
                local root = c:FindFirstChild("HumanoidRootPart")
                local knife
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") and string.lower(t.Name):find("knife") then knife = t; break end
                end
                if root and knife then
                    for _, pl in ipairs(Players:GetPlayers()) do
                        if pl ~= LP then
                            local ec = charOfPlayer(pl)
                            if ec and isAlive(ec) then
                                local er = ec:FindFirstChild("HumanoidRootPart")
                                if er and (er.Position - root.Position).Magnitude < S.auraRange then
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

-- ========================================================
-- Trigger Bot (raycast wall check)
-- ========================================================
task.spawn(function()
    while RUNNING and task.wait(0.04) do
        if S.triggerBot then
            local target = getNearestEnemy(S.tbWallCheck)
            if target then
                local c = charOfPlayer(target)
                local head = c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
                if head then
                    local v = Camera:WorldToViewportPoint(head.Position)
                    local mp = UserInputService:GetMouseLocation()
                    local d = (Vector2.new(v.X, v.Y) - mp).Magnitude
                    if d < S.tbRadius then
                        -- проверка что курсор реально на враге (Mouse.Target)
                        local t = Mouse.Target
                        local onEnemy = false
                        if t and c and t:IsDescendantOf(c) then onEnemy = true end
                        -- либо курсор достаточно близко (d < tbRadius) + LOS
                        if onEnemy or (not S.tbWallCheck) or hasLineOfSight(head) then
                            local mx, my = mp.X, mp.Y
                            pcall(function()
                                VirtualInputManager:SendMouseButtonEvent(mx, my, 0, true, game, 0)
                                task.wait(0.03)
                                VirtualInputManager:SendMouseButtonEvent(mx, my, 0, false, game, 0)
                            end)
                            task.wait(0.15) -- кулдаун чтобы не спамить
                        end
                    end
                end
            end
        end
    end
end)

-- ========================================================
-- ESP (Heartbeat 0.1s, cached objects)
-- ========================================================
local espStore = {} -- [player] = {bb, lbl, hl, line}
local function roleColor(role)
    if role == "Murderer" then return Color3.fromRGB(255, 55, 60) end
    if role == "Sheriff"  then return Color3.fromRGB(60, 130, 255) end
    if role == "Both"     then return Color3.fromRGB(255, 180, 40) end
    return Color3.fromRGB(220, 220, 220)
end

local function cleanupDrawing(obj)
    if not obj then return end
    pcall(function() obj:Remove() end)
end

local function clearESPFor(pl)
    local e = espStore[pl]; if not e then return end
    if e.bb then pcall(function() e.bb:Destroy() end) end
    if e.hl then pcall(function() e.hl:Destroy() end) end
    cleanupDrawing(e.line)
    espStore[pl] = nil
end

local function ensureLabel(pl, c)
    local e = espStore[pl]
    local head = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
    if not head then return end
    if not e.bb then
        local bb = Instance.new("BillboardGui")
        bb.Name = "_CENTAURA_ESP"
        bb.Size = UDim2.new(0, 160, 0, 24)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.AlwaysOnTop = true
        bb.Parent = c
        bb.Adornee = head
        local lbl = Instance.new("TextLabel", bb)
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 13
        lbl.TextStrokeTransparency = 0.3
        e.bb = bb; e.lbl = lbl
    else
        if e.bb.Adornee ~= head then e.bb.Adornee = head end
    end
end
local function ensureHL(pl, c)
    local e = espStore[pl]
    if not e.hl then
        local hl = Instance.new("Highlight")
        hl.Name = "_CENTAURA_HL"
        hl.FillTransparency = 0.55
        hl.OutlineColor = Color3.fromRGB(255,255,255)
        hl.Parent = c
        hl.Adornee = c
        e.hl = hl
    end
end
local function ensureTracer(pl)
    local e = espStore[pl]
    if not e.line and Drawing and Drawing.new then
        local ok, line = pcall(function() return Drawing.new("Line") end)
        if ok and line then
            line.Thickness = 1.5
            line.Transparency = 1
            e.line = line
        end
    end
end

task.spawn(function()
    while RUNNING and task.wait(0.1) do
        local anyESP = S.espNames or S.espBox or S.espTracers or S.teamChams
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LP then
                if not anyESP then
                    clearESPFor(pl)
                else
                    espStore[pl] = espStore[pl] or {}
                    local c = charOfPlayer(pl)
                    if not c or not isAlive(c) then
                        clearESPFor(pl)
                    else
                        local role = computeRoleFor(pl)
                        local col  = roleColor(role)
                        -- label
                        if S.espNames then
                            ensureLabel(pl, c)
                            local e = espStore[pl]
                            if e.lbl then
                                e.lbl.TextColor3 = col
                                e.lbl.Text = string.format("%s · %s", pl.Name, role)
                            end
                        elseif espStore[pl].bb then
                            pcall(function() espStore[pl].bb:Destroy() end)
                            espStore[pl].bb = nil; espStore[pl].lbl = nil
                        end
                        -- highlight
                        if S.teamChams or S.espBox then
                            ensureHL(pl, c)
                            local e = espStore[pl]
                            if e.hl then
                                e.hl.FillColor = col
                                e.hl.OutlineColor = col
                            end
                        elseif espStore[pl].hl then
                            pcall(function() espStore[pl].hl:Destroy() end)
                            espStore[pl].hl = nil
                        end
                        -- tracer
                        if S.espTracers then
                            ensureTracer(pl)
                            local e = espStore[pl]
                            if e.line then
                                local head = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
                                if head then
                                    local v, on = Camera:WorldToViewportPoint(head.Position)
                                    if on and v.Z > 0 then
                                        local vs = Camera.ViewportSize
                                        e.line.From = Vector2.new(vs.X/2, vs.Y)
                                        e.line.To   = Vector2.new(v.X, v.Y)
                                        e.line.Color = col
                                        e.line.Visible = true
                                    else
                                        e.line.Visible = false
                                    end
                                else
                                    e.line.Visible = false
                                end
                            end
                        elseif espStore[pl].line then
                            cleanupDrawing(espStore[pl].line)
                            espStore[pl].line = nil
                        end
                    end
                end
            end
        end
    end
end)
track(Players.PlayerRemoving:Connect(clearESPFor))

-- ========================================================
-- Automation
-- ========================================================
local CENTAURA_GUI -- forward
local function clickGUIMatching(patterns)
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

task.spawn(function()
    while RUNNING and task.wait(0.8) do
        if S.autoCase then clickGUIMatching({"opencase","unlock","^case$","open case"}) end
    end
end)
task.spawn(function()
    while RUNNING and task.wait(1) do
        if S.autoRespawn then
            local _, hum = getHRP()
            if hum and hum.Health <= 0 then pcall(function() LP:LoadCharacter() end) end
        end
    end
end)

-- ========================================================
-- GUI (tabbed)
-- ========================================================
local pg = LP:WaitForChild("PlayerGui")
if pg:FindFirstChild("CENTAURA_MVS") then pg.CENTAURA_MVS:Destroy() end

local gui = Instance.new("ScreenGui", pg)
gui.Name = "CENTAURA_MVS"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
CENTAURA_GUI = gui

local root = Instance.new("Frame", gui)
root.Size             = UDim2.new(0, 480, 0, 380)
root.Position         = UDim2.new(0.5, -240, 0.5, -190)
root.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
root.BorderSizePixel  = 0
root.Active           = true
root.Draggable        = true
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", root)
stroke.Color = Color3.fromRGB(150, 80, 255); stroke.Thickness = 1.6

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
title.Text = "CENTAURA · Murderers vs Sheriffs 2  v2"

local sub = Instance.new("TextLabel", header)
sub.Position = UDim2.new(0, 16, 0, 22)
sub.Size = UDim2.new(1, -32, 0, 16)
sub.BackgroundTransparency = 1
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Font = Enum.Font.Gotham
sub.TextSize = 11
sub.TextColor3 = Color3.fromRGB(160, 140, 210)
sub.Text = "By @zood3llotgk"

local tabBar = Instance.new("Frame", root)
tabBar.Position          = UDim2.new(0, 8, 0, 48)
tabBar.Size              = UDim2.new(0, 120, 1, -56)
tabBar.BackgroundColor3  = Color3.fromRGB(20, 20, 28)
tabBar.BorderSizePixel   = 0
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 8)
local tabLay = Instance.new("UIListLayout", tabBar)
tabLay.Padding = UDim.new(0, 4); tabLay.SortOrder = Enum.SortOrder.LayoutOrder
local tabPad = Instance.new("UIPadding", tabBar)
tabPad.PaddingTop = UDim.new(0, 6); tabPad.PaddingLeft = UDim.new(0, 6); tabPad.PaddingRight = UDim.new(0, 6)

local content = Instance.new("Frame", root)
content.Position = UDim2.new(0, 136, 0, 48)
content.Size = UDim2.new(1, -144, 1, -56)
content.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
content.BorderSizePixel = 0
Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

local tabFrames, tabButtons = {}, {}
local function selectTab(name)
    for n, f in pairs(tabFrames) do f.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        b.BackgroundColor3 = (n == name) and Color3.fromRGB(70, 30, 130) or Color3.fromRGB(30, 30, 40)
    end
end
local function addTab(name, order)
    local btn = Instance.new("TextButton", tabBar)
    btn.Size = UDim2.new(1, 0, 0, 28); btn.LayoutOrder = order
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40); btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamMedium; btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(230, 230, 240); btn.Text = name
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    tabButtons[name] = btn

    local frame = Instance.new("ScrollingFrame", content)
    frame.Size = UDim2.new(1, -12, 1, -12); frame.Position = UDim2.new(0, 6, 0, 6)
    frame.BackgroundTransparency = 1; frame.BorderSizePixel = 0
    frame.CanvasSize = UDim2.new(0, 0, 0, 0); frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
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
    b.Size = UDim2.new(1, -4, 0, 28); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(240, 240, 245)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local onC = accent or Color3.fromRGB(70, 30, 130); local offC = Color3.fromRGB(28, 28, 36)
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
    c.BackgroundColor3 = Color3.fromRGB(28, 28, 36); c.BorderSizePixel = 0
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
    local function ap(x)
        if step < 1 then x = math.floor(x * 100 + 0.5) / 100 end
        x = math.clamp(x, mn, mx); S[key] = x; v.Text = tostring(x); l.Text = label .. ": " .. tostring(x)
    end
    m.MouseButton1Click:Connect(function() ap(S[key] - step) end)
    p.MouseButton1Click:Connect(function() ap(S[key] + step) end)
end
local function infoRow(parent, getText)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1, -4, 0, 24)
    l.BackgroundColor3 = Color3.fromRGB(28, 28, 36); l.BorderSizePixel = 0
    l.Font = Enum.Font.GothamMedium; l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(220, 220, 230)
    l.Text = getText()
    Instance.new("UICorner", l).CornerRadius = UDim.new(0, 5)
    task.spawn(function()
        while l.Parent do l.Text = getText(); task.wait(0.4) end
    end)
end

local tabPlayer  = addTab("Player", 1)
local tabCombat  = addTab("Combat", 2)
local tabVisuals = addTab("Visuals", 3)
local tabAuto    = addTab("Automation", 4)
local tabInfo    = addTab("Info", 5)
local tabMisc    = addTab("Misc", 6)

-- Player
toggle(tabPlayer, "Speed Hack",    "speedHack", Color3.fromRGB(30, 140, 80), function(on)
    local _, hum = getHRP(); if hum and on then pcall(function() hum.WalkSpeed = S.walkSpeed end) end
end)
slider(tabPlayer, "Walk Speed",    "walkSpeed", 16, 300, 4)
toggle(tabPlayer, "Jump Hack",     "jumpHack", Color3.fromRGB(30, 90, 180), function(on)
    local _, hum = getHRP(); if hum and on then pcall(function() hum.JumpPower = S.jumpPower; hum.UseJumpPower = true end) end
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
slider(tabCombat, "Aimbot FOV",    "fov", 20, 800, 20)
slider(tabCombat, "Aim Smooth",    "aimSmooth", 0.05, 1, 0.05)
-- aimTarget toggle: Head vs HRP
do
    local b = Instance.new("TextButton", tabCombat)
    b.Size = UDim2.new(1, -4, 0, 28); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(240, 240, 245)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function r() b.Text = "Aim Target: " .. S.aimTarget; b.BackgroundColor3 = Color3.fromRGB(50, 50, 70) end
    r()
    b.MouseButton1Click:Connect(function()
        S.aimTarget = (S.aimTarget == "Head") and "HumanoidRootPart" or "Head"; r()
        notify("CENTAURA", "Aim Target: " .. S.aimTarget)
    end)
end
toggle(tabCombat, "Trigger Bot",   "triggerBot", Color3.fromRGB(140, 80, 30))
toggle(tabCombat, "TB Wall Check", "tbWallCheck", Color3.fromRGB(60, 90, 180))
slider(tabCombat, "TB Radius",     "tbRadius", 6, 60, 2)
toggle(tabCombat, "Kill Aura (knife)", "killAura", Color3.fromRGB(160, 40, 60))
slider(tabCombat, "Aura Range",    "auraRange", 4, 30, 1)

-- Visuals
toggle(tabVisuals, "ESP Names",    "espNames", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "ESP Box/Highlight", "espBox", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "ESP Tracers",  "espTracers", Color3.fromRGB(80, 130, 200))
toggle(tabVisuals, "Team Chams",   "teamChams", Color3.fromRGB(150, 80, 255))

-- Automation
toggle(tabAuto, "Auto Open Case", "autoCase", Color3.fromRGB(140, 100, 30))
toggle(tabAuto, "Auto Respawn",   "autoRespawn")

-- Info
infoRow(tabInfo, function() return "Role: " .. (S.role or "?") end)
infoRow(tabInfo, function() return "Kill Streak: " .. tostring(S.streak or 0) end)
infoRow(tabInfo, function() return "Coins (?): " .. tostring(S.coins or 0) end)
infoRow(tabInfo, function() return "Last killed by: " .. tostring(S.lastKilledBy or "-") end)
infoRow(tabInfo, function() return "Players: " .. tostring(#Players:GetPlayers()) end)
infoRow(tabInfo, function()
    local c = getActiveCharacter()
    return "Active char: " .. (c and c:GetFullName() or "nil")
end)

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
destroyBtn.Font = Enum.Font.GothamBold; destroyBtn.TextSize = 12
destroyBtn.Text = "Unload CENTAURA"
Instance.new("UICorner", destroyBtn).CornerRadius = UDim.new(0, 6)
-- Full unload: disconnect все connections, выключаем RUNNING, сносим ESP/fly,
-- сбрасываем S флаги, восстанавливаем metatable (silent aim).
local origMTIndex
local function doUnload()
    RUNNING = false
    -- сброс флагов
    S.speedHack = false; S.jumpHack = false; S.infJump = false
    S.noclip = false; S.fly = false; S.antiAFK = false
    S.silentAim = false; S.aimbot = false; S.killAura = false; S.triggerBot = false
    S.espNames = false; S.espBox = false; S.espTracers = false; S.teamChams = false
    S.autoCase = false; S.autoRespawn = false
    -- останавливаем fly
    pcall(stopFly)
    -- сносим ESP
    for pl, _ in pairs(espStore) do clearESPFor(pl) end
    -- восстановление WS/JP/гравитации
    local _, hum = getHRP()
    if hum then
        pcall(function() hum.WalkSpeed = 16; hum.JumpPower = 50 end)
    end
    -- отключаем все tracked connections
    for _, c in ipairs(CONNECTIONS) do pcall(function() c:Disconnect() end) end
    CONNECTIONS = {}
    -- silent aim: восстанавливаем __index если инсталлили (хук теперь no-op б/c S.silentAim=false)
    -- но чтобы было чисто — не трогаем metatable (опасно если другой скрипт уже перехукнул)
    if gui and gui.Parent then gui:Destroy() end
end
destroyBtn.MouseButton1Click:Connect(doUnload)

track(UserInputService.InputBegan:Connect(function(i, gpe)
    if not RUNNING or gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then root.Visible = not root.Visible end
end))

selectTab("Player")
notify("CENTAURA", "MvS2 v2 loaded · by @zood3llotgk", 4)
