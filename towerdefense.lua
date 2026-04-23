-- CENTAURA :: Tower Defense Simulator (v1 · HARD MODE)
-- By @zood3llotgk
--
-- В TDS жёсткий серверный античит, поэтому прямой FireServer на Place/Upgrade/Sell
-- отлавливается. Скрипт работает через клиентские сигналы UI-кнопок (firesignal /
-- getconnections) — так клиент сам отправляет валидный запрос на сервер.
--
-- Features:
--   * Auto Ready / Auto Vote Skip / Auto Next Game / Auto Restart (через GUI)
--   * Sell All Towers / Upgrade All Towers (через GUI)
--   * Anti-Lag (глушит particles/smoke/fire/trails)
--   * ESP Mobs (подсветка Mobs + healthbar billboard)
--   * Tower Range ESP (показывает радиус атаки своих башен)
--   * HUD (Wave / Coins / Health)
--   * Anti-AFK
--   * Macro Record & Play (записывает клики UI-кнопок и повторяет)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local Lighting            = game:GetService("Lighting")
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

-- ===== state =====
local S = {
    autoReady    = false,
    autoSkip     = false,
    autoVoteNext = false,
    autoRestart  = false,
    antiLag      = false,
    espMobs      = false,
    espRange     = false,
    hud          = true,
    antiAFK      = true,
    sellAll      = false,
    upgradeAll   = false,
}

-- ===== utility =====
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
        VirtualInputManager:SendKeyEvent(true,  "Space", false, game); task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, "Space", false, game)
    end)
end)

-- ===== forward ref к нашему ScreenGui =====
local CENTAURA_GUI = nil

-- ===== click button helper =====
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

-- ищет видимую кнопку по patterns в Name/Text (кроме нашего GUI)
local function clickButtonsMatching(patterns, once)
    local pg = LP:FindFirstChild("PlayerGui"); if not pg then return false end
    local clicked = false
    for _, g in ipairs(pg:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton"))
           and not (CENTAURA_GUI and g:IsDescendantOf(CENTAURA_GUI)) then
            if g.Visible and g.Active and g.AbsoluteSize.X > 0 and g.AbsoluteSize.Y > 0 then
                local name = string.lower(g.Name or "")
                local text = (g:IsA("TextButton") and string.lower(g.Text or "")) or ""
                for _, p in ipairs(patterns) do
                    if name:find(p) or text:find(p) then
                        fireButton(g)
                        clicked = true
                        if once then return true end
                        break
                    end
                end
            end
        end
    end
    return clicked
end

-- ===== Auto Ready / Skip / Vote / Restart =====
task.spawn(function()
    while task.wait(0.4) do
        if S.autoReady   then clickButtonsMatching({"ready","readyup","readybtn","start"}) end
        if S.autoSkip    then clickButtonsMatching({"skip","voteskip","waveskip"}) end
        if S.autoVoteNext then clickButtonsMatching({"votenext","nextgame","continue","playagain"}) end
        if S.autoRestart then clickButtonsMatching({"restart","retry","tryagain"}) end
    end
end)

-- ===== Sell All / Upgrade All (одноразовый клик и reset toggle) =====
task.spawn(function()
    while task.wait(0.3) do
        if S.sellAll then
            clickButtonsMatching({"sellall","sell all","sellall_"})
            -- пробуем также по "sell" если есть явная "Sell All" под-кнопка
            S.sellAll = false
        end
        if S.upgradeAll then
            clickButtonsMatching({"upgradeall","upgrade all","upgradeall_"})
            S.upgradeAll = false
        end
    end
end)

-- ===== Anti-Lag =====
local antilagOriginals = {}
local function saveOriginal(v, prop)
    antilagOriginals[v] = antilagOriginals[v] or {}
    if antilagOriginals[v][prop] == nil then
        antilagOriginals[v][prop] = v[prop]
    end
end
local function applyAntiLag(v)
    if not S.antiLag then return end
    pcall(function()
        if v:IsA("ParticleEmitter") then
            saveOriginal(v, "Enabled"); v.Enabled = false
        elseif v:IsA("Trail") then
            saveOriginal(v, "Enabled"); v.Enabled = false
        elseif v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            saveOriginal(v, "Enabled"); v.Enabled = false
        elseif v:IsA("BasePart") and v.Material == Enum.Material.Neon then
            -- оставляем
        elseif v:IsA("PostEffect") then
            saveOriginal(v, "Enabled"); v.Enabled = false
        end
    end)
end
local function restoreAntiLag()
    for inst, props in pairs(antilagOriginals) do
        if inst and inst.Parent then
            for p, val in pairs(props) do
                pcall(function() inst[p] = val end)
            end
        end
    end
    antilagOriginals = {}
end
local antilagConn
local function setAntiLag(on)
    if on then
        for _, v in ipairs(Workspace:GetDescendants()) do applyAntiLag(v) end
        for _, v in ipairs(Lighting:GetDescendants()) do applyAntiLag(v) end
        if antilagConn then antilagConn:Disconnect() end
        antilagConn = Workspace.DescendantAdded:Connect(applyAntiLag)
    else
        if antilagConn then antilagConn:Disconnect(); antilagConn = nil end
        restoreAntiLag()
    end
end

-- ===== ESP Mobs =====
local function getMobsFolder()
    local cand = {"Mobs","Enemies","_ENEMIES","Zombies","Monsters"}
    for _, n in ipairs(cand) do
        local f = Workspace:FindFirstChild(n)
        if f then return f end
    end
    -- поиск по дескрипшнам
    for _, c in ipairs(Workspace:GetChildren()) do
        local low = string.lower(c.Name or "")
        if low:find("mob") or low:find("enemy") or low:find("zombie") then
            return c
        end
    end
    return nil
end

local mobESP = {}
local function addMobESP(m)
    if mobESP[m] then return end
    if not m:IsA("Model") then return end
    if not m:FindFirstChildWhichIsA("BasePart") then return end
    local hl = Instance.new("Highlight")
    hl.Adornee          = m
    hl.FillColor        = Color3.fromRGB(255, 40, 60)
    hl.OutlineColor     = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.6
    hl.Parent           = m

    local bb = Instance.new("BillboardGui")
    bb.Name = "CENTAURA_BB"
    bb.Size = UDim2.new(0, 120, 0, 24)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart")
    bb.Parent = m

    local label = Instance.new("TextLabel", bb)
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.4
    label.Text = m.Name

    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum then
        local function updateLabel()
            label.Text = string.format("%s [%.0f/%.0f]", m.Name, hum.Health, hum.MaxHealth)
        end
        updateLabel()
        hum.HealthChanged:Connect(updateLabel)
    end
    mobESP[m] = {hl = hl, bb = bb}
end
local function removeMobESP(m)
    local e = mobESP[m]
    if not e then return end
    pcall(function() if e.hl then e.hl:Destroy() end end)
    pcall(function() if e.bb then e.bb:Destroy() end end)
    mobESP[m] = nil
end
local function clearMobESP()
    for m,_ in pairs(mobESP) do removeMobESP(m) end
end
local mobFolderConn
local function setMobESP(on)
    if on then
        local f = getMobsFolder()
        if not f then
            notify("CENTAURA", "Mobs folder not found — waiting...", 3)
            -- ждём появление
            task.spawn(function()
                while S.espMobs do
                    f = getMobsFolder()
                    if f then break end
                    task.wait(0.5)
                end
                if S.espMobs and f then setMobESP(true) end
            end)
            return
        end
        for _, m in ipairs(f:GetChildren()) do addMobESP(m) end
        if mobFolderConn then mobFolderConn:Disconnect() end
        mobFolderConn = f.ChildAdded:Connect(addMobESP)
        f.ChildRemoved:Connect(removeMobESP)
    else
        if mobFolderConn then mobFolderConn:Disconnect(); mobFolderConn = nil end
        clearMobESP()
    end
end

-- ===== Tower Range ESP =====
local rangeESP = {}
local function getTowersFolder()
    for _, n in ipairs({"Towers","_TOWERS","PlacedTowers"}) do
        local f = Workspace:FindFirstChild(n)
        if f then return f end
    end
    return nil
end
local function addRangeESP(t)
    if rangeESP[t] then return end
    if not t:IsA("Model") then return end
    local root = t:FindFirstChild("HumanoidRootPart") or t:FindFirstChildWhichIsA("BasePart")
    if not root then return end
    -- ищем числовой stat "Range"
    local stats = t:FindFirstChild("Stats") or t
    local range = 18
    local rVal = stats and stats:FindFirstChild("Range")
    if rVal and rVal:IsA("NumberValue") then range = rVal.Value end
    local sphere = Instance.new("Part")
    sphere.Shape           = Enum.PartType.Ball
    sphere.Size            = Vector3.new(range*2, range*2, range*2)
    sphere.Anchored        = true
    sphere.CanCollide      = false
    sphere.CanQuery        = false
    sphere.CanTouch        = false
    sphere.Material        = Enum.Material.ForceField
    sphere.Color           = Color3.fromRGB(140, 80, 255)
    sphere.Transparency    = 0.75
    sphere.Parent          = t
    sphere.CFrame          = root.CFrame
    -- follow
    local conn = RunService.Heartbeat:Connect(function()
        if root and root.Parent then sphere.CFrame = root.CFrame end
    end)
    rangeESP[t] = {sphere = sphere, conn = conn}
    if rVal and rVal:IsA("NumberValue") then
        rVal:GetPropertyChangedSignal("Value"):Connect(function()
            sphere.Size = Vector3.new(rVal.Value*2, rVal.Value*2, rVal.Value*2)
        end)
    end
end
local function removeRangeESP(t)
    local e = rangeESP[t]
    if not e then return end
    if e.conn then e.conn:Disconnect() end
    pcall(function() if e.sphere then e.sphere:Destroy() end end)
    rangeESP[t] = nil
end
local function clearRangeESP()
    for t,_ in pairs(rangeESP) do removeRangeESP(t) end
end
local towersConn
local function setRangeESP(on)
    if on then
        local f = getTowersFolder()
        if not f then
            task.spawn(function()
                while S.espRange do
                    f = getTowersFolder()
                    if f then break end
                    task.wait(0.5)
                end
                if S.espRange and f then setRangeESP(true) end
            end)
            return
        end
        for _, t in ipairs(f:GetChildren()) do addRangeESP(t) end
        if towersConn then towersConn:Disconnect() end
        towersConn = f.ChildAdded:Connect(addRangeESP)
        f.ChildRemoved:Connect(removeRangeESP)
    else
        if towersConn then towersConn:Disconnect(); towersConn = nil end
        clearRangeESP()
    end
end

-- ===== Macro Record & Play =====
local macro = {}
local macroRecording = false
local macroPlaying = false

local function hookButtonForMacro(btn)
    if btn:GetAttribute("_CENTAURA_Hooked") then return end
    btn:SetAttribute("_CENTAURA_Hooked", true)
    btn.MouseButton1Click:Connect(function()
        if macroRecording and not (CENTAURA_GUI and btn:IsDescendantOf(CENTAURA_GUI)) then
            local path = btn:GetFullName()
            table.insert(macro, {time = tick(), path = path, name = btn.Name, text = btn:IsA("TextButton") and btn.Text or ""})
        end
    end)
end

local function hookAllButtons()
    local pg = LP:FindFirstChild("PlayerGui"); if not pg then return end
    for _, g in ipairs(pg:GetDescendants()) do
        if g:IsA("TextButton") or g:IsA("ImageButton") then hookButtonForMacro(g) end
    end
    pg.DescendantAdded:Connect(function(v)
        if v:IsA("TextButton") or v:IsA("ImageButton") then hookButtonForMacro(v) end
    end)
end
hookAllButtons()

local function resolvePath(path)
    local cur = game
    for part in string.gmatch(path, "[^%.]+") do
        cur = cur:FindFirstChild(part)
        if not cur then return nil end
    end
    return cur
end

local function playMacro()
    if macroPlaying then return end
    macroPlaying = true
    task.spawn(function()
        local t0 = macro[1] and macro[1].time or tick()
        local start = tick()
        for _, step in ipairs(macro) do
            if not macroPlaying then break end
            local wait = (step.time - t0) - (tick() - start)
            if wait > 0 then task.wait(wait) end
            local btn = resolvePath(step.path)
            if btn then fireButton(btn) end
        end
        macroPlaying = false
        notify("CENTAURA", "Macro playback finished", 3)
    end)
end

-- ===== HUD =====
local function safeChildValue(parent, name)
    local v = parent and parent:FindFirstChild(name)
    if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
        return v.Value
    end
    return nil
end
local function getStats()
    local wave, coins, hp
    -- Wave
    local statsFolder = Workspace:FindFirstChild("Stats")
                     or ReplicatedStorage:FindFirstChild("Stats")
                     or LP:FindFirstChild("Stats")
    if statsFolder then
        wave  = safeChildValue(statsFolder, "Wave") or safeChildValue(statsFolder, "CurrentWave")
        coins = safeChildValue(statsFolder, "Cash") or safeChildValue(statsFolder, "Coins") or safeChildValue(statsFolder, "Money")
        hp    = safeChildValue(statsFolder, "Health") or safeChildValue(statsFolder, "BaseHealth")
    end
    -- fallback: найти в PlayerGui текстовые поля "Wave:" "Health:" "Cash:"
    return wave, coins, hp
end

-- ===== GUI =====
local pg = LP:WaitForChild("PlayerGui")
if pg:FindFirstChild("CENTAURA_TDS") then pg.CENTAURA_TDS:Destroy() end

local gui = Instance.new("ScreenGui", pg)
gui.Name           = "CENTAURA_TDS"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
CENTAURA_GUI = gui

local frame = Instance.new("Frame", gui)
frame.Size             = UDim2.new(0, 310, 0, 540)
frame.Position         = UDim2.new(0, 20, 0.5, -270)
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
head.Text                   = "CENTAURA · Tower Defense Simulator"
head.Font                   = Enum.Font.GothamBold
head.TextSize               = 14
head.TextColor3             = Color3.fromRGB(210, 180, 255)

local sub = Instance.new("TextLabel", frame)
sub.Position                = UDim2.new(0, 0, 0, 32)
sub.Size                    = UDim2.new(1, 0, 0, 14)
sub.BackgroundTransparency  = 1
sub.Text                    = "By @zood3llotgk"
sub.Font                    = Enum.Font.Gotham
sub.TextSize                = 11
sub.TextColor3              = Color3.fromRGB(150, 130, 200)

-- HUD строка (wave / cash / hp)
local hudLabel = Instance.new("TextLabel", frame)
hudLabel.Position               = UDim2.new(0, 10, 0, 48)
hudLabel.Size                   = UDim2.new(1, -20, 0, 18)
hudLabel.BackgroundColor3       = Color3.fromRGB(28, 28, 36)
hudLabel.BorderSizePixel        = 0
hudLabel.TextColor3             = Color3.fromRGB(230, 230, 240)
hudLabel.Font                   = Enum.Font.GothamMedium
hudLabel.TextSize               = 12
hudLabel.Text                   = "Wave: ? | Cash: ? | HP: ?"
Instance.new("UICorner", hudLabel).CornerRadius = UDim.new(0, 5)

task.spawn(function()
    while task.wait(0.5) do
        if S.hud then
            hudLabel.Visible = true
            local w, c, h = getStats()
            hudLabel.Text = string.format("Wave: %s  |  Cash: %s  |  HP: %s",
                tostring(w or "?"), tostring(c or "?"), tostring(h or "?"))
        else
            hudLabel.Visible = false
        end
    end
end)

local scroll = Instance.new("ScrollingFrame", frame)
scroll.Position              = UDim2.new(0, 10, 0, 72)
scroll.Size                  = UDim2.new(1, -20, 1, -82)
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

local function button(name, cb, accent)
    local b = Instance.new("TextButton", scroll)
    b.Size             = UDim2.new(1, -4, 0, 30)
    b.BorderSizePixel  = 0
    b.Font             = Enum.Font.GothamMedium
    b.TextSize         = 13
    b.TextColor3       = Color3.fromRGB(240, 240, 245)
    b.BackgroundColor3 = accent or Color3.fromRGB(40, 40, 52)
    b.Text             = name
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function() pcall(cb) end)
end

toggle("Auto Ready",          "autoReady",    Color3.fromRGB(30, 140, 80))
toggle("Auto Vote Skip",      "autoSkip",     Color3.fromRGB(180, 80, 40))
toggle("Auto Vote Next",      "autoVoteNext", Color3.fromRGB(30, 90, 180))
toggle("Auto Restart",        "autoRestart")
toggle("Anti-Lag",            "antiLag",      Color3.fromRGB(140, 50, 160), setAntiLag)
toggle("ESP Mobs",            "espMobs",      Color3.fromRGB(160, 40, 60), setMobESP)
toggle("ESP Tower Range",     "espRange",     Color3.fromRGB(80, 60, 180), setRangeESP)
toggle("HUD (Wave/Cash/HP)",  "hud",          Color3.fromRGB(40, 120, 140))
toggle("Anti-AFK",            "antiAFK")

button("Sell All Towers", function()
    S.sellAll = true
    notify("CENTAURA", "Attempting Sell All", 2)
end, Color3.fromRGB(120, 30, 30))

button("Upgrade All Towers", function()
    S.upgradeAll = true
    notify("CENTAURA", "Attempting Upgrade All", 2)
end, Color3.fromRGB(30, 80, 150))

-- Macro controls
local macroLabel = Instance.new("TextLabel", scroll)
macroLabel.Size                   = UDim2.new(1, -4, 0, 22)
macroLabel.BackgroundTransparency = 1
macroLabel.Font                   = Enum.Font.GothamBold
macroLabel.TextSize               = 12
macroLabel.TextColor3             = Color3.fromRGB(180, 170, 220)
macroLabel.Text                   = "── Macro (0 steps) ──"
macroLabel.TextXAlignment         = Enum.TextXAlignment.Center

local function refreshMacroLabel()
    macroLabel.Text = string.format("── Macro (%d steps)%s ──", #macro,
        macroRecording and " · REC" or (macroPlaying and " · PLAY" or ""))
end

button("Macro: Start Recording", function()
    if macroPlaying then return end
    macro = {}
    macroRecording = true
    refreshMacroLabel()
    notify("CENTAURA", "Macro recording started — нажимай UI кнопки", 3)
end, Color3.fromRGB(130, 40, 30))

button("Macro: Stop Recording", function()
    macroRecording = false
    refreshMacroLabel()
    notify("CENTAURA", string.format("Macro recorded: %d steps", #macro), 3)
end, Color3.fromRGB(60, 60, 80))

button("Macro: Play", function()
    if macroRecording or macroPlaying then return end
    if #macro == 0 then notify("CENTAURA","Macro is empty",2); return end
    refreshMacroLabel()
    playMacro()
end, Color3.fromRGB(30, 130, 80))

button("Macro: Clear", function()
    macro = {}; macroRecording = false; macroPlaying = false
    refreshMacroLabel()
end)

task.spawn(function()
    while task.wait(0.5) do refreshMacroLabel() end
end)

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

notify("CENTAURA", "Tower Defense Simulator v1 · by @zood3llotgk", 4)
