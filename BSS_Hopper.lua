--[[
═══════════════════════════════════════════════════════════════════════
  🐍 BSS SPROUT HOPPER v3.1
═══════════════════════════════════════════════════════════════════════
  ЛКМ по змейке  → настройки
  ПКМ по змейке  → включить / выключить
  Escape         → закрыть окно
  Настройки сохраняются в файл и переживают перезаход
═══════════════════════════════════════════════════════════════════════
]]

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ══════════════════════════════════════════════════════════════════════
--  ТРАССИРОВКА ЗАПУСКА — показывает, на чём именно падает скрипт
-- ══════════════════════════════════════════════════════════════════════
local STEP = 0
local function trace(msg)
    STEP += 1
    print(string.format("[ШАГ %02d] %s", STEP, msg))
end

trace("Скрипт стартовал")

-- Баннер ошибок прямо на экране. Если скрипт упадёт при сборке GUI,
-- без этого баннера ты увидишь старый интерфейс с мёртвыми кнопками
-- и не поймёшь почему. С этим — сразу видно, что и где сломалось.
_G.BSS_FATAL = nil

local function showFatal(msg)
    _G.BSS_FATAL = msg
    pcall(function()
        print("[ФАТАЛЬНО] " .. tostring(msg))
        local plr = game:GetService("Players").LocalPlayer
        local pg = plr:WaitForChild("PlayerGui")

        local old = pg:FindFirstChild("BssFatalGui")
        if old then old:Destroy() end

        local g = Instance.new("ScreenGui")
        g.Name = "BssFatalGui"
        g.DisplayOrder = 9999999
        g.IgnoreGuiInset = true
        g.Parent = pg

        local f = Instance.new("Frame")
        f.Size = UDim2.new(0, 560, 0, 150)
        f.Position = UDim2.new(0.5, -280, 0, 90)
        f.BackgroundColor3 = Color3.fromRGB(46, 18, 18)
        f.BorderSizePixel = 0
        f.Active = true
        f.Parent = g

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 12)
        c.Parent = f

        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -24, 0, 24)
        t.Position = UDim2.new(0, 12, 0, 10)
        t.BackgroundTransparency = 1
        t.Text = "ОШИБКА ЗАПУСКА СКРИПТА"
        t.TextColor3 = Color3.fromRGB(255, 120, 120)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 14
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Parent = f

        local d = Instance.new("TextLabel")
        d.Size = UDim2.new(1, -24, 1, -46)
        d.Position = UDim2.new(0, 12, 0, 38)
        d.BackgroundTransparency = 1
        d.Text = tostring(msg)
        d.TextColor3 = Color3.fromRGB(230, 200, 200)
        d.Font = Enum.Font.Gotham
        d.TextSize = 11
        d.TextWrapped = true
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.TextYAlignment = Enum.TextYAlignment.Top
        d.Parent = f
    end)
end

-- ══════════════════════════════════════════════════════════════════════
--  КОНФИГУРАЦИЯ ПО УМОЛЧАНИЮ
--  Значения перезаписываются сохранёнными (см. ЗАГРУЗКА НАСТРОЕК)
-- ══════════════════════════════════════════════════════════════════════
local CONFIG = {
    MODE         = "searcher",
    API_URL      = "https://hopper-bss-production.up.railway.app",
    API_KEY      = "fc2aa6619c2ddf188294559d9cac760fefb6c25e9ba32e2a0ac46ff5abc8d850",
    SELF_TAG     = "searcher1",
    VICIOUS_CHANNEL_ID = "", -- Discord channel ID for Vicious Bee reports (handled by backend)
    PUFFSHROOM_CHANNEL_ID = "1558633541577740318", -- Discord channel для редких Puffshroom
    CHECK_PUFFSHROOMS = true,
    PUFF_MIN_RARITY = "rare", -- минимальная редкость Puffshroom для уведомлений/цели
    FIXED_LEVEL  = "basic",
    MIN_RARITY   = "basic",   -- лутающий берёт только не ниже этого
    PLACE_ID     = 1537690962,

    HOP_DELAY      = 1.5,
    POLL_INTERVAL  = 3,
    BROKEN_WAIT    = 20,
    INITIAL_CHECK  = 1,
    REPORT_DELAY   = 2.5,
    CONNECT_TIMEOUT = 20,
    MAX_ATTEMPTS   = 3,
    FAILED_TTL     = 180,

    DEBUG_SPROUT = true,
    -- Искать Vicious Bee в дополнение к спрутам
    CHECK_VICIOUS = true,
    CHECK_SPROUTS = true,
    USE_ATLAS    = true,
    ATLAS_URL = "https://raw.githubusercontent.com/Chris12089/atlasbss/main/script.lua",

    -- Автозапуск сохранённого режима после перезахода
    AUTO_START = true,
}

local SAVE_FILE  = "bss_hopper_config.json"
local uiState    = { snakePos = nil, winPos = nil }
local lastMode   = "searcher"

local function packPosition(pos)
    if not pos then return nil end
    return {
        xScale = pos.X.Scale, xOffset = pos.X.Offset,
        yScale = pos.Y.Scale, yOffset = pos.Y.Offset,
    }
end

local function unpackPosition(pos)
    if type(pos) ~= "table" then return nil end
    local xs, xo = tonumber(pos.xScale), tonumber(pos.xOffset)
    local ys, yo = tonumber(pos.yScale), tonumber(pos.yOffset)
    if not xs or not xo or not ys or not yo then return nil end
    return UDim2.new(xs, xo, ys, yo)
end

-- ══════════════════════════════════════════════════════════════════════
--  ЗАЩИТА ОТ ДУБЛЕЙ
--  Executor перезапускает скрипт при каждом переходе на новый сервер.
--  Прежняя копия уничтожает GUI новой, но её потоки продолжают жить и
--  ходить по серверам. Без защиты через несколько перезаходов появляются
--  зомби-копии, которые конфликтуют между собой.
--
--  Способ: у каждой копии свой токен. Новый запуск делает токен
--  неактуальным — все старые циклы выходят на следующей итерации,
--  даже если их нельзя отменить.
-- ══════════════════════════════════════════════════════════════════════
local OLD = rawget(_G, "BSS_Hopper")
if OLD and type(OLD.Destroy) == "function" then
    pcall(OLD.Destroy)
end

local MY_TOKEN = {}
_G.BSS_HOPPER_TOKEN = MY_TOKEN

local function alive()
    return rawget(_G, "BSS_HOPPER_TOKEN") == MY_TOKEN
end

local myConns = {}

local function trackConn(conn)
    if conn then table.insert(myConns, conn) end
    return conn
end

local function stopEverything()
    if type(Hopper) == "table" and Hopper.Mode then
        pcall(function() Hopper.Mode:Stop() end)
    end
    for _, c in ipairs(myConns) do
        pcall(function() c:Disconnect() end)
    end
    myConns = {}
    pcall(function() if gui then gui:Destroy() end end)
end

local function log(tag, msg)
    -- Подробная консольная диагностика: выводится в консоль executor/Roblox.
    local line = string.format("[BSS Hopper][%s][%.1f] %s", tostring(tag), os.clock(), tostring(msg))
    print(line)
end

-- ══════════════════════════════════════════════════════════════════════
--  СОХРАНЕНИЕ / ЗАГРУЗКА НАСТРОЕК
-- ══════════════════════════════════════════════════════════════════════
local HAS_FS = (type(writefile) == "function") and (type(readfile) == "function")
local PERSIST_ENV = _G
pcall(function()
    if type(getgenv) == "function" then PERSIST_ENV = getgenv() end
end)

local SAVED_KEYS = {
    "MODE", "API_URL", "API_KEY", "SELF_TAG", "VICIOUS_CHANNEL_ID", "FIXED_LEVEL", "MIN_RARITY",
    "PLACE_ID", "HOP_DELAY", "POLL_INTERVAL", "BROKEN_WAIT", "INITIAL_CHECK",
    "REPORT_DELAY", "CONNECT_TIMEOUT", "MAX_ATTEMPTS", "FAILED_TTL",
    "DEBUG_SPROUT", "USE_ATLAS", "ATLAS_URL", "AUTO_START", "CHECK_VICIOUS", "CHECK_SPROUTS", "CHECK_PUFFSHROOMS", "PUFFSHROOM_CHANNEL_ID", "PUFF_MIN_RARITY",
}

local function applySavedData(data, source)
    if type(data) ~= "table" then return false end
    for _, key in ipairs(SAVED_KEYS) do
        if data[key] ~= nil then CONFIG[key] = data[key] end
    end
    -- Keep the last selected working mode separate from the temporary runtime state.
    -- LAST_ACTIVE_MODE хранит последний выбранный режим; MODE — совместимость
    -- со старыми конфигами. Приоритет у последнего явного выбора.
    local savedMode = data.LAST_ACTIVE_MODE
    if savedMode ~= "searcher" and savedMode ~= "looter" and savedMode ~= "solo" then
        savedMode = data.MODE
    end
    if savedMode == "searcher" or savedMode == "looter" or savedMode == "solo" then
        lastMode = savedMode
        CONFIG.MODE = savedMode
    end
    uiState.snakePos = unpackPosition(data.snakePos) or uiState.snakePos
    uiState.winPos = unpackPosition(data.winPos) or uiState.winPos
    if data.winOpen ~= nil then uiState.winOpen = (data.winOpen ~= false) end
    log("CFG", "Настройки загружены: " .. tostring(source))
    return true
end

local function loadSaved()
    local envData
    pcall(function() envData = PERSIST_ENV.BSS_HOPPER_SAVED_CONFIG end)
    if applySavedData(envData, "память executor") then
        -- File config, when present, is authoritative and overrides environment cache.
    end

    if not HAS_FS then
        log("CFG", "readfile/writefile недоступны: настройки живут только в памяти текущего executor")
        return envData
    end

    local ok, content = pcall(readfile, SAVE_FILE)
    if not ok or not content or content == "" then return envData end

    local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(data) ~= "table" then
        log("CFG", "Файл настроек повреждён; использую настройки из памяти, если они есть")
        return envData
    end
    applySavedData(data, "файл " .. SAVE_FILE)
    return data
end

-- Загружаем до построения GUI: иначе переключатели и выбранная редкость
-- создавались бы со значениями по умолчанию и визуально сбрасывались.
loadSaved()

local saveFailed = false

local function saveNow()
    local data = {}
    for _, key in ipairs(SAVED_KEYS) do data[key] = CONFIG[key] end
    -- MODE / LAST_ACTIVE_MODE must never be overwritten with "off" just
    -- because a server hop or GUI stop temporarily stopped the worker.
    data.MODE = (lastMode == "searcher" or lastMode == "looter" or lastMode == "solo") and lastMode
        or ((CONFIG.MODE == "searcher" or CONFIG.MODE == "looter" or CONFIG.MODE == "solo") and CONFIG.MODE or "searcher")
    data.LAST_ACTIVE_MODE = data.MODE
    data.snakePos = packPosition(uiState.snakePos)
    data.winPos = packPosition(uiState.winPos)
    data.winOpen = uiState.winOpen ~= false

    -- Always cache in executor environment first; this works even without file APIs.
    local cacheOk, cacheErr = pcall(function() PERSIST_ENV.BSS_HOPPER_SAVED_CONFIG = data end)
    if not cacheOk then log("CFG", "Не удалось сохранить в память executor: " .. tostring(cacheErr)) end

    if not HAS_FS then
        if not saveFailed then
            saveFailed = true
            log("CFG", "Нет файловых API: сохранено только в памяти executor, не гарантируется после полного перезапуска")
        end
        return cacheOk
    end

    local encoded, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not encoded then
        log("CFG", "Не удалось сериализовать настройки: " .. tostring(json))
        return false
    end
    local ok, result = pcall(writefile, SAVE_FILE, json)
    if not ok or result == false then
        log("CFG", "Ошибка записи: " .. tostring(result))
        return cacheOk
    end

    local okRead, content = pcall(readfile, SAVE_FILE)
    if okRead and content and content ~= "" then
        local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
        if decodeOk and type(decoded) == "table" then
            saveFailed = false
            log("CFG", "Настройки записаны и проверены: " .. SAVE_FILE)
            return true
        end
    end
    log("CFG", "Запись вызвана, но проверочное чтение/JSONDecode не прошло")
    return cacheOk
end
-- Синхронное сохранение перед телепортом: клиент сейчас умрёт
local function flushSettings()
    saveNow()
end

-- ══════════════════════════════════════════════════════════════════════
--  ПОИСК СПРУТА И СЕРВЕРОВ
-- ══════════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════════
--  ПОИСК СПРУТА
--
--  В BSS спрут появляется как объект с именем "Sprout" внутри
--  Workspace.Particles.Folder2 (иногда другие папки — проверяем все).
--  Ловим и уже существующие, и те, что появятся ПОСЛЕ захода.
-- ══════════════════════════════════════════════════════════════════════

local sproutFolders = {}
local freshSprout = nil
local isSprout -- forward declaration: addFolder callbacks use this local

local function addFolder(path)
    local node = Workspace
    for piece in path:gmatch("[^%.]+") do
        node = node:FindFirstChild(piece)
        if not node then return false end
    end
    if node:IsA("Folder") or node:IsA("Model") then
        for _, existing in ipairs(sproutFolders) do
            if existing == node then return false end
        end
        table.insert(sproutFolders, node)
        -- DescendantAdded catches sprouts nested inside folders/models too.
        pcall(function()
            trackConn(node.DescendantAdded:Connect(function(child)
                if alive() and isSprout(child) then
                    freshSprout = child
                    log("Спрут", "Новый вложенный объект: " .. tostring(child:GetFullName()))
                end
            end))
        end)
        return true
    end
    return false
end

isSprout = function(obj)
    if not obj then return false end
    local ok, name = pcall(function() return obj.Name end)
    if not ok or type(name) ~= "string" then return false end
    local low = string.lower(name)
    return low == "sprout" or string.find(low, "sprout", 1, true) ~= nil
end

-- Флаг freshSprout объявлен выше, чтобы callbacks захватывали именно local-переменную.

local function watchFolders()
    local paths = {
        "Particles.Folder2",
        "Particles",
        "Sprouts",
        "Happenings",
        "Happenings.Sprouts",
        "Fields",
    }
    for _, p in ipairs(paths) do addFolder(p) end

    for _, folder in ipairs(sproutFolders) do
        pcall(function()
            trackConn(folder.ChildAdded:Connect(function(child)
                if not alive() then return end
                if isSprout(child) then
                    freshSprout = child
                    log("Спрут", "Появился новый: " .. tostring(child.Name))
                end
            end))
        end)
    end
end

watchFolders()
-- Папки могут появиться позже — перепроверяем
task.spawn(function()
    for _ = 1, 30 do
        if not alive() then return end
        task.wait(2)
        if #sproutFolders < 3 then
            local before = #sproutFolders
            watchFolders()
            if #sproutFolders > before then
                log("Спрут", "Подключена новая папка, всего: " .. #sproutFolders)
            end
        end
    end
end)

local function findSprout()
    -- Только что появившийся имеет приоритет
    if freshSprout then
        if freshSprout.Parent then
            return freshSprout
        end
        freshSprout = nil
    end

    for _, folder in ipairs(sproutFolders) do
        -- Search recursively so already-present/nested sprouts are not missed.
        local ok, descendants = pcall(function() return folder:GetDescendants() end)
        if ok then
            for _, child in ipairs(descendants) do
                if isSprout(child) then return child end
            end
        end
        -- A folder/model can itself be the sprout root.
        if isSprout(folder) then return folder end
    end
    return nil
end

-- Позиция объекта в мире (работает и для Part, и для Model)
local function worldPos(obj)
    local ok, p = pcall(function()
        if obj:IsA("BasePart") then return obj.Position end
        return obj:GetPivot().Position
    end)
    if ok and p then return p end
    return nil
end

-- Поля лежат в Workspace.FlowerZones с английскими именами
-- ("Stump Field", "Sunflower Field", "Ant Field" и т.д.)
-- Компактный отчёт об определении — одну строку скопировать в чат
local function detectionReport(sprout, rarity, source)
    local c
    pcall(function()
        if sprout:IsA("BasePart") then c = sprout.Color end
    end)
    if c then
        local h, sat, v = hueOf(c)
        print(string.format(
            "[ОПРОС] rarity=%s source=%s rootColor=(%d,%d,%d) hsv=(%.2f,%.2f,%.2f)",
            tostring(rarity), tostring(source),
            math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255),
            h, sat, v))
    else
        print(string.format("[ОПРОС] rarity=%s source=%s rootClass=%s rootName=%s",
            tostring(rarity), tostring(source), tostring(sprout.ClassName), tostring(sprout.Name)))
    end
    local names = {}
    for _, d in ipairs(sprout:GetDescendants()) do
        if #names < 25 then table.insert(names, d.ClassName .. ":" .. d.Name) end
    end
    print("[ОПРОС] parts: " .. table.concat(names, ", "))
end

local function detectField(sprout)
    local zones = Workspace:FindFirstChild("FlowerZones")
    if not zones then return nil end

    local pos = worldPos(sprout)
    if not pos then return nil end

    local okChildren, children = pcall(function() return zones:GetChildren() end)
    if not okChildren then return nil end

    local bestName, bestDist = nil, math.huge
    for _, zone in ipairs(children) do
        local zpos = worldPos(zone)
        if zpos then
            local d = (zpos - pos).Magnitude
            if d < bestDist then
                bestDist = d
                bestName = zone.Name
            end
        end
    end
    return bestName
end

-- ══════════════════════════════════════════════════════════════════════
--  PUFFSHROOMS: только Rare / Epic / Legendary / Mythic
--  Берём признаки из имени, атрибутов и видимых Billboard/SurfaceGui текстов.
-- ══════════════════════════════════════════════════════════════════════
local PUFF_RARITY_PRIORITY = { rare = 1, epic = 2, legendary = 3, mythic = 4 }
local puffReported = {}
local function puffTextOf(root)
    local chunks = { tostring(root.Name or "") }
    local function addAttrs(obj)
        local ok, attrs = pcall(function() return obj:GetAttributes() end)
        if ok and type(attrs) == "table" then
            for k, v in pairs(attrs) do
                local key = string.lower(tostring(k))
                if string.find(key, "rarity", 1, true) or string.find(key, "level", 1, true)
                    or string.find(key, "type", 1, true) or string.find(key, "puff", 1, true) then
                    table.insert(chunks, tostring(k) .. " " .. tostring(v))
                end
            end
        end
    end
    addAttrs(root)
    local ok, descendants = pcall(function() return root:GetDescendants() end)
    if ok then
        for _, d in ipairs(descendants) do
            if #chunks > 180 then break end
            local n = string.lower(tostring(d.Name or ""))
            if string.find(n, "puff", 1, true) or string.find(n, "rarity", 1, true)
                or string.find(n, "level", 1, true) then table.insert(chunks, tostring(d.Name)) end
            addAttrs(d)
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                pcall(function() table.insert(chunks, d.Text) end)
            end
        end
    end
    return table.concat(chunks, " | ")
end

local function isPuffshroomRoot(obj)
    local name = string.lower(tostring(obj and obj.Name or ""))
    return string.find(name, "puffshroom", 1, true) ~= nil
        or string.find(name, "puff shroom", 1, true) ~= nil
end

local function parsePuffshroom(root)
    local text = string.lower(puffTextOf(root))
    if not string.find(text, "puff", 1, true) then return nil end
    local rarity
    -- Mythic first so text with multiple labels resolves to the highest rarity.
    for _, r in ipairs({"mythic", "legendary", "epic", "rare"}) do
        if string.find(text, r, 1, true) then rarity = r; break end
    end
    if not rarity then return nil end
    local level
    -- Common attribute formats: Level=12, Lvl 12, Level 12, PuffshroomLevel.
    local patterns = {"level%s*[:=]?%s*(%d+)", "lvl%s*[:=]?%s*(%d+)", "puffshroomlevel%s*[:=]?%s*(%d+)"}
    for _, pattern in ipairs(patterns) do
        local value = string.match(text, pattern)
        if value then level = tonumber(value); break end
    end
    if not level then
        pcall(function()
            for _, obj in ipairs({root}) do
                for _, key in ipairs({"Level", "Lvl", "PuffshroomLevel"}) do
                    local v = obj:GetAttribute(key)
                    if tonumber(v) then level = tonumber(v); break end
                end
            end
        end)
    end
    if not level or level < 1 or level > 30 then return nil end
    return rarity, math.floor(level)
end

local function findPuffshroom()
    local ok, descendants = pcall(function() return Workspace:GetDescendants() end)
    if not ok then return nil end
    local candidates = {}
    for _, obj in ipairs(descendants) do
        if isPuffshroomRoot(obj) then
            -- Prefer Model roots; otherwise a named part may be the only replicated root.
            if obj:IsA("Model") then table.insert(candidates, 1, obj)
            else table.insert(candidates, obj) end
        end
    end
    for _, root in ipairs(candidates) do
        local rarity, level = parsePuffshroom(root)
        if rarity and level then return root, rarity, level end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════
--  VICIOUS BEE
--
--  В BSS это неподвижный шип, торчащий из земли. Спавнится только ночью
--  (день 14 мин / ночь 6 мин) в полях Clover, Spider, Cactus, Rose,
--  Mountain Top. Даёт Стинжеры.
--
--  Ключевое: если пчела заспавнилась ДО твоего захода на сервер, шип
--  уходит под землю и визуально не отображается. Но сам объект остаётся
--  в Workspace.Particles — поэтому поиск по имени работает всегда.
-- ══════════════════════════════════════════════════════════════════════
local freshVicious = nil

local function isViciousPart(obj)
    if not obj then return false end
    local ok, name = pcall(function() return obj.Name end)
    return ok and type(name) == "string"
        and string.find(string.lower(name), "vicious", 1, true) ~= nil
end

local function viciousCandidateScore(obj)
    if not isViciousPart(obj) then return -1 end
    local score = 0
    local name = string.lower(tostring(obj.Name or ""))
    if name == "vicious" then score += 100 end
    if worldPos(obj) then score += 30 end -- предпочтительнее объект с координатами
    if obj:IsA("BasePart") or obj:IsA("Model") then score += 10 end
    return score
end

local function findVicious()
    -- Проверяем кэш, но не доверяем ему, если имя/объект уже изменились.
    if freshVicious and freshVicious.Parent and isViciousPart(freshVicious) then
        return freshVicious
    end
    freshVicious = nil

    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        log("Vicious", "Workspace.Particles пока не найден")
        return nil
    end

    local ok, descendants = pcall(function() return particles:GetDescendants() end)
    if not ok then
        log("Vicious", "Не удалось прочитать Particles: " .. tostring(descendants))
        return nil
    end

    local best, bestScore = nil, -1
    for _, child in ipairs(descendants) do
        local score = viciousCandidateScore(child)
        if score > bestScore then
            best, bestScore = child, score
        end
    end

    if best then
        freshVicious = best
        local pos = worldPos(best)
        log("Vicious", string.format(
            "Найден объект: %s | Class=%s | координаты=%s",
            tostring(best:GetFullName()), tostring(best.ClassName),
            pos and string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z) or "нет"))
    end
    return best
end

-- Подписываемся и на прямых детей, и на вложенные объекты:
-- некоторые версии/скрипты BSS создают эффект внутри Folder/Model.
task.spawn(function()
    for _ = 1, 60 do
        if not alive() then return end
        local particles = Workspace:FindFirstChild("Particles")
        if particles then
            local function onAdded(obj)
                if not alive() or not isViciousPart(obj) then return end
                freshVicious = obj
                log("Vicious", "Событие появления: " .. tostring(obj:GetFullName()) ..
                    " [" .. tostring(obj.ClassName) .. "]")
            end
            local function onRemoving(obj)
                if freshVicious == obj then
                    freshVicious = nil
                    log("Vicious", "Объект удаляется: " .. tostring(obj.Name))
                end
            end
            trackConn(particles.ChildAdded:Connect(onAdded))
            trackConn(particles.DescendantAdded:Connect(onAdded))
            trackConn(particles.ChildRemoved:Connect(onRemoving))
            trackConn(particles.DescendantRemoving:Connect(onRemoving))
            log("Vicious", "Мониторинг запущен: Workspace.Particles")
            -- Важно: сразу сканируем уже существующие объекты, не только новые.
            findVicious()
            return
        end
        task.wait(1)
    end
    log("Vicious", "Workspace.Particles не появился за 60 секунд")
end)

-- Проверяет именно видимое системное сообщение об окончании Vicious.
-- Без этого сообщения сервер не меняется.
local function viciousDefeatedMessageVisible()
    local needles = { "vicious bee has been defeated", "vicious bee defeated" }
    local roots = {}
    pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
    pcall(function() table.insert(roots, player:FindFirstChildOfClass("PlayerGui")) end)

    for _, root in ipairs(roots) do
        if root then
            local ok, descendants = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, node in ipairs(descendants) do
                    if node:IsA("TextLabel") or node:IsA("TextButton") then
                        local txt = string.lower(tostring(node.Text or ""))
                        for _, needle in ipairs(needles) do
                            if string.find(txt, needle, 1, true) and node.Visible then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function waitForViciousDefeated(timeout)
    local started = os.clock()
    while alive() and os.clock() - started < (timeout or 900) do
        if viciousDefeatedMessageVisible() then return true end
        task.wait(0.35)
    end
    return false
end

-- Редкость Vicious: обычный дикий или Rogue (мини-босс)
local function detectViciousKind(obj)
    local name = string.lower(obj.Name or "")
    if string.find(name, "rogue", 1, true) then return "rogue" end
    return "wild"
end

local function dumpVicious(obj)
    print("-------- VICIOUS DUMP --------")
    print("Name  : " .. tostring(obj.Name))
    print("Class : " .. tostring(obj.ClassName))
    local p = worldPos(obj)
    if p then print(string.format("Pos   : %.0f, %.0f, %.0f", p.X, p.Y, p.Z)) end
    print("Field : " .. tostring(detectField(obj)))
    print("Kind  : " .. detectViciousKind(obj))
    print("-------- END DUMP --------")
end

local function dumpSprout(sprout)
    print("ParentPath: " .. tostring(sprout:FindFirstAncestorWhichIsA("Model")
        and sprout:GetFullName() or "n/a"))
    print("Class : " .. tostring(sprout.ClassName))
    print("Name  : " .. tostring(sprout.Name))
    print("Full  : " .. tostring(sprout:GetFullName()))
    print("MeshId: " .. tostring(sprout.MeshId))
    print("Color : " .. tostring(sprout.Color))
    print("Attrs :")
    for k, v in pairs(sprout:GetAttributes()) do
        print("   " .. tostring(k) .. " = " .. tostring(v))
    end
    print("Children:")
    for _, d in ipairs(sprout:GetDescendants()) do
        local line = "   " .. d.ClassName .. " -> " .. d.Name
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            line = line .. '  Text="' .. tostring(d.Text) .. '"'
        elseif d:IsA("Decal") or d:IsA("Texture") then
            line = line .. "  Image=" .. tostring(d.Texture)
        elseif d:IsA("ParticleEmitter") then
            line = line .. "  Texture=" .. tostring(d.Texture)
        end
        print(line)
    end
    print("------ END DUMP --------")
end

local function getServerList()
    local ok, res = pcall(function()
        return game:HttpGet("https://games.roblox.com/v1/games/" ..
            tostring(CONFIG.PLACE_ID) ..
            "/servers/Public?sortOrder=Asc&limit=100")
    end)
    if not ok then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 or not data or not data.data then return nil end
    return data.data
end

-- ══════════════════════════════════════════════════════════════════════
--  ЗАЩИТА ТЕЛЕПОРТОВ
-- ══════════════════════════════════════════════════════════════════════
local failedServers = {}
local attemptCounter = 0
local lastTeleportAt = 0
local lastAttemptId = 0

local function rememberFailure(jobId)
    if jobId then failedServers[jobId] = os.clock() end
    attemptCounter += 1
end

local function clearFailures()
    failedServers = {}
    attemptCounter = 0
end

local function isFailed(jobId)
    return jobId ~= nil and failedServers[jobId] ~= nil
end

local function pruneFailures()
    local now = os.clock()
    local ttl = tonumber(CONFIG.FAILED_TTL) or 90
    for id, t in pairs(failedServers) do
        if now - t > ttl then failedServers[id] = nil end
    end
end

local function getCandidateServers()
    pruneFailures()
    local servers = getServerList()
    if not servers then return nil end
    local out = {}
    for _, s in ipairs(servers) do
        if s.id ~= game.JobId
            and not isFailed(s.id)
            and s.playing < s.maxPlayers
            and s.playing > 0 then
            table.insert(out, { id = s.id, ping = s.ping or 999 })
        end
    end

    if #out == 0 then return out end

    -- Низкий пинг = выше шанс нормально подключиться.
    -- Высокий пинг чаще означает перегруженный или уже умирающий сервер.
    table.sort(out, function(a, b) return a.ping < b.ping end)

    -- Берём из лучшей половины списка
    local limit = math.max(1, math.floor(#out / 2))
    local best = {}
    for i = 1, limit do
        table.insert(best, out[i].id)
    end
    return best
end

-- Сторож подключения: работает постоянно в фоне.
--
-- Логика: если мы вызвали Teleport*, а через CONNECT_TIMEOUT секунд
-- клиент всё ещё жив — значит хоп НЕ произошёл (например ошибка 279,
-- "Connection Failed"). Уходим на другой сервер.
--
-- Проверять ReplicatedFirst:IsFinishedLoading() бесполезно: он описывает
-- текущий клиент, который уже успешно загрузился на старый сервер.
local pendingTarget = nil
local pendingAt = 0

-- Счётчик повторных входов после временных ошибок.
-- Объявлен ДО markTeleport, потому что markTeleport его вызывает.
local rejoinTries = 0

local function resetRejoinTries()
    if rejoinTries > 0 then
        log("TP", "Вход удался, сбрасываю счётчик повторов")
        rejoinTries = 0
    end
end

local function markTeleport(targetJobId)
    pendingTarget = targetJobId
    pendingAt = os.clock()
    resetRejoinTries()
end

local function clearTeleport()
    pendingTarget = nil
    pendingAt = 0
end

local function hopTo(jobId, placeId)
    if not jobId then return false end

    if isFailed(jobId) then
        log("TP", "Сервер в blacklist: " .. tostring(jobId):sub(1, 8))
        return false
    end

    lastAttemptId += 1
    lastTeleportAt = os.clock()
    markTeleport(jobId)

    -- Телепорт уничтожает клиент. Всё, что не записано сейчас,
    -- будет потеряно навсегда — пишем синхронно перед хопом.
    flushSettings()

    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            placeId or CONFIG.PLACE_ID, jobId, player)
    end)

    if not ok then
        rememberFailure(jobId)
        log("TP", "TeleportToPlaceInstance упал")
        return false
    end

    return true
end

function hopRandom()
    local candidates = getCandidateServers()
    if candidates and #candidates > 0 then
        local target = candidates[math.random(1, #candidates)]
        if hopTo(target) then return end
    end

    if attemptCounter >= (tonumber(CONFIG.MAX_ATTEMPTS) or 3) then
        log("TP", "Слишком много неудач, откат на Teleport()")
        clearFailures()
    end

    lastAttemptId += 1
    lastTeleportAt = os.clock()
    markTeleport(nil)
    flushSettings()
    pcall(function() TeleportService:Teleport(CONFIG.PLACE_ID, player) end)
end

-- Фоновый сторож: если клиент пережил таймаут после хопа — хоп не вышел
task.spawn(function()
    while true do
    if not alive() then return end
        task.wait(1)

        if pendingAt > 0 then
            local timeout = tonumber(CONFIG.CONNECT_TIMEOUT) or 20
            local waited = os.clock() - pendingAt
            if waited >= timeout then
                local target = pendingTarget
                clearTeleport()

                if target then
                    rememberFailure(target)
                    log("TP", string.format(
                        "Сервер не подключил за %dс — в blacklist, ищу другой",
                        timeout))
                else
                    log("TP", string.format(
                        "Teleport() не сработал за %dс — пробую снова", timeout))
                end

                hopRandom()
            end
        end
    end
end)

local function rejoinSame()
    local servers = getServerList()
    if servers then
        pruneFailures()
        for _, s in ipairs(servers) do
            if s.playing < s.maxPlayers and not isFailed(s.id) then
                hopTo(s.id)
                return
            end
        end
    end
    pcall(function() TeleportService:Teleport(CONFIG.PLACE_ID, player) end)
end

-- Коды ошибок телепорта, при которых сервер НЕ мёртвый, а Roblox
-- временно отказал (троттлинг, перегрузка). В таких случаях повторяем
-- попытку на том же сервере, а не ищем другой.
local RETRYABLE_TELEPORT_CODES = {
    [2] = true,   -- throttled / temporary reject
    [3] = true,
}

local MAX_REJOIN_TRIES = 4

-- Повторный вход на тот же сервер после временной ошибки
local function rejoinRetry(code)
    rejoinTries += 1
    local attempt = rejoinTries

    local waitTime = 3 + attempt * 2
    log("TP", string.format(
        "Ошибка %s — временная, повторный вход через %dс (попытка %d/%d)",
        tostring(code), waitTime, attempt, MAX_REJOIN_TRIES))

    task.wait(waitTime)

    if attempt >= MAX_REJOIN_TRIES then
        log("TP", "Повторы исчерпаны, ищу другой сервер")
        rejoinTries = 0
        clearTeleport()
        hopRandom()
        return
    end

    clearTeleport()
    rejoinSame()
end

local teleportLock = false
local function handleTeleportFailure(reason)
    if teleportLock then return end
    teleportLock = true

    -- Отказ пойман сигналом — фоновый сторож ждать не должен
    clearTeleport()

    log("TP", reason .. " — перезапуск через 2с")
    task.wait(2)

    if attemptCounter >= (tonumber(CONFIG.MAX_ATTEMPTS) or 3) then
        clearFailures()
    end

    rejoinSame()
    teleportLock = false
end

-- Все подключения через safeConnect — executor'ы любят падать на редких сигналах
local function safeConnect(obj, signal, fn, name)
    local ok, err = pcall(function()
        trackConn(obj[signal]:Connect(fn))
    end)
    if not ok then
        log("TP", "Не удалось подписаться на " .. name .. ": " .. tostring(err))
    end
end

safeConnect(TeleportService, "TeleportInitFailed", function(plr, result, msg)
    if plr ~= player then return end

    local code = tonumber(result)
    log("TP", "TeleportInitFailed: " .. tostring(result) ..
        " (" .. tostring(msg) .. ")")

    -- Ошибка 2 (и 3) — временный отказ, сервер живой: повторяем вход
    if code and RETRYABLE_TELEPORT_CODES[code] then
        task.spawn(rejoinRetry, code)
        return
    end

    rememberFailure(nil)
    task.spawn(handleTeleportFailure, "TeleportInitFailed")
end, "TeleportInitFailed")

safeConnect(player, "OnTeleport", function(state)
    if state == Enum.TeleportState.Failed then
        rememberFailure(nil)
        task.spawn(handleTeleportFailure, "OnTeleport Failed")
    end
end, "OnTeleport")

safeConnect(game, "Close", function()
    log("TP", "Игра закрывается, сохраняю и пробую вернуться")
    flushSettings()
    markTeleport(nil)
    pcall(function() TeleportService:Teleport(CONFIG.PLACE_ID, player) end)
end, "game.Close")

safeConnect(game, "ErrorOccurred", function(err)
    log("ERR", tostring(err):sub(1, 120))
end, "ErrorOccurred")

-- ══════════════════════════════════════════════════════════════════════
--  РАЗНОВИДНОСТИ СПРУТОВ
--
--  В Bee Swarm Simulator спрут различается ЦВЕТОМ:
--    Common   — зелёный
--    Rare     — серебристый
--    Epic     — золотой
--    Legendary— бирюзовый (teal)
--    Supreme  — светящийся зелёный
--    Moon     — светящийся синий
--
--  Определяем по оттенку (Hue), а не по точному RGB — так устойчиво
--  к освещению, материалу и времени суток.
-- ══════════════════════════════════════════════════════════════════════

-- Приоритет для лутающего: чем больше значение, тем раньше берёт
local RARITY_PRIORITY = {
    gummy     = 7,
    supreme   = 6,
    legendary = 5,
    epic      = 4,
    rare      = 3,
    basic     = 2,
    moon      = 1,
}

local RARITY_LABEL = {
    gummy     = "🍬 Gummy",
    supreme   = "🌟 Supreme",
    legendary = "💠 Legendary",
    epic      = "🥇 Epic",
    rare      = "🥈 Rare",
    basic     = "🌱 Basic",
    moon      = "🌙 Moon",
}

local function hueOf(color)
    local h, s, v = Color3.toHSV(color)
    return h or 0, s or 0, v or 0
end

-- Слова-маркеры редкости. Порядок важен: более специфичные вперёд,
-- чтобы не спутать "Legendary" с чем-то общим.
local RARITY_WORDS = {
    { level = "gummy",     words = { "gummy" } },
    { level = "supreme",   words = { "supreme" } },
    { level = "legendary", words = { "legendary" } },
    { level = "epic",      words = { "epic" } },
    { level = "rare",      words = { "uncommon", "rare" } },
    { level = "moon",      words = { "moon", "lunar" } },
    { level = "basic",     words = { "common", "normal", "basic" } },
}

-- В фильтре используются только шесть требуемых уровней:
-- Moon → Basic/Common → Rare → Epic → Legendary → Supreme.
-- Gummy/Festive/Sticker/Debug — отдельные варианты, не маскируем их под Basic.
local EXTRA_RARITY = { gummy = "gummy" }

-- Ищем слово-маркер в строке
local function matchWords(text)
    if not text or text == "" then return nil end
    local low = string.lower(text)
    for _, entry in ipairs(RARITY_WORDS) do
        for _, w in ipairs(entry.words) do
            if string.find(low, w, 1, true) then return entry.level end
        end
    end
    for word, level in pairs(EXTRA_RARITY) do
        if string.find(low, word, 1, true) then return level end
    end
    return nil
end

-- Определяет разновидность по цвету.
-- ВНИМАНИЕ: у спрутов базовый цвет часто белый по умолчанию, поэтому
-- белый/серый НЕ считаем "rare" — иначе всегда будет rare.
-- Возвращаем nil, если не уверены.
local function rarityFromColor(color)
    if not color then return nil end

    local h, s, v = hueOf(color)
    local deg = h * 360
    local r, g, b = color.R, color.G, color.B

    -- Настоящий серый: каналы почти равны
    local isGrey = math.abs(r - g) < 0.06 and math.abs(g - b) < 0.06

    -- Gummy: pink/magenta. This is only a fallback; explicit name/text wins.
    -- Keep a high saturation threshold to avoid classifying pale lighting as Gummy.
    if (deg >= 285 and deg <= 350) and s >= 0.48 and v >= 0.35 then
        return "gummy"
    end

    -- Золотой
    if deg >= 28 and deg <= 62 and s > 0.4 then
        return "epic"
    end

    -- Бирюзовый (Legendary): бирюза стоит около 180°, но при подсветке
    -- смещается к 195-200. Верхнюю границу держим ниже 197.
    if deg >= 150 and deg <= 197 and s > 0.30 then
        return "legendary"
    end

    -- Синий (Moon): светящийся синий ~215-245, но может уходить в 205
    if deg >= 203 and deg <= 270 and s > 0.20 then
        return "moon"
    end

    -- Зона 198-202 — неоднозначная, не угадываем
    if deg > 197 and deg < 203 then
        return nil
    end

    -- Зелёный: обычный тусклый = common, яркий светящийся = supreme
    if deg > 62 and deg < 150 and s > 0.25 then
        if v >= 0.70 and s >= 0.85 then return "supreme" end
        return "basic"
    end

    -- Серебристый — только если это правда серый, а не белый по умолчанию
    if isGrey and s < 0.18 and v >= 0.55 and v <= 0.92 then
        return "rare"
    end

    -- Белый по умолчанию — это НЕ признак редкости
    if isGrey and v > 0.92 then return nil end

    return nil
end

-- Полное определение разновидности
local function detectRarity(sprout)
    if not sprout then return nil, "no-object" end

    -- 1) Используем имя корневого объекта только если в нём явно указана редкость.
    -- "Sprout" само по себе не означает Rare.
    local ownName = string.lower(tostring(sprout.Name or ""))
    local own = matchWords(ownName)
    if own then return own, "own-name" end

    -- 2) Текстовые метки: требуем явное название типа спрута.
    local okFind, billboard = pcall(function()
        return sprout:FindFirstChildWhichIsA("BillboardGui", true)
    end)
    if okFind and billboard then
        for _, d in ipairs(billboard:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text then
                local txt = string.lower(tostring(d.Text))
                -- Не считаем одиночные декоративные слова/проценты маркером редкости.
                if string.find(txt, "sprout", 1, true) then
                    local found = matchWords(txt)
                    if found then return found, "billboard-explicit" end
                end
            end
        end
    end

    -- 3) Проверяем только явно названные атрибуты типа/редкости.
    local okAttr, attrs = pcall(function() return sprout:GetAttributes() end)
    if okAttr then
        for k, v in pairs(attrs) do
            local key = string.lower(tostring(k))
            if key == "rarity" or key == "sprouttype" or key == "sproutrarity" then
                local found = matchWords(tostring(v))
                if found then return found, "attribute:" .. key end
            end
        end
    end

    -- 4) Считаем цветные детали модели целиком, а не возвращаем результат
    -- по первой случайной серой/белой детали. Серый цвет сам по себе
    -- НЕ доказывает Rare: у обычных моделей много нейтральных деталей.
    local counts = { gummy = 0, basic = 0, supreme = 0, epic = 0, legendary = 0, moon = 0 }
    local okDesc, descendants = pcall(function() return sprout:GetDescendants() end)
    if okDesc then
        local function addPart(part)
            local rarity = rarityFromColor(part.Color)
            if rarity and rarity ~= "rare" then
                counts[rarity] = (counts[rarity] or 0) + 1
            end
        end
        if sprout:IsA("BasePart") then addPart(sprout) end
        for _, d in ipairs(descendants) do
            if d:IsA("BasePart") then addPart(d) end
        end

        local best, bestCount = nil, 0
        for rarity, count in pairs(counts) do
            if count > bestCount then
                best, bestCount = rarity, count
            end
        end
        if best and bestCount >= 2 then
            return best, "dominant-part-color"
        end
    end

    -- Важнее неизвестная редкость, чем ложный Rare из-за белой/серой детали.
    return nil, "unconfirmed"
end

-- ══════════════════════════════════════════════════════════════════════
--  РЕЖИМ: 🔍 ИЩУЩИЙ
-- ══════════════════════════════════════════════════════════════════════
local Searcher = {}
trace("Режимы определены")
local Hopper -- forward declaration for Searcher/Looter/Solo callbacks

Searcher.__index = Searcher

function Searcher.New()
    return setmetatable({
        thread = nil,
        stats = {
            serversChecked = 0, reportsSent = 0,
            viciousFound = 0,
            lastSprout = nil, lastVicious = nil,
            currentStatus = "Готов к работе",
        },
    }, Searcher)
end

-- Общий HTTP-клиент: сначала API executor'а (с HTTP-кодом), затем Roblox HttpPost.
local function postJson(path, body)
    local url = CONFIG.API_URL:gsub("/+$", "") .. path
    log("HTTP", "POST " .. url .. " | payloadBytes=" .. tostring(#body))
    local req = (syn and syn.request) or http_request or request
    if type(req) == "function" then
        log("HTTP", "Используется executor request API")
        local response = req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
            Body = body,
        })
        local status = tonumber(response and (response.StatusCode or response.Status)) or 0
        local responseBody = tostring(response and (response.Body or response.body) or "")
        log("HTTP", "Ответ получен: status=" .. tostring(status) .. " | body=" .. string.sub(responseBody, 1, 500))
        if status < 200 or status >= 300 then
            error("HTTP " .. tostring(status) .. ": " .. responseBody)
        end
        return responseBody, status
    end

    log("HTTP", "Executor request API недоступен; использую game:HttpPost (HTTP-код не предоставляется)")
    local responseBody = game:HttpPost(url, body, "application/json")
    responseBody = tostring(responseBody or "")
    log("HTTP", "game:HttpPost вернул: " .. string.sub(responseBody, 1, 500))
    return responseBody, 200
end

local function responseRejected(resp)
    local lower = string.lower(tostring(resp or ""))
    return string.find(lower, '"error"', 1, true) ~= nil
        or string.find(lower, '"success":false', 1, true) ~= nil
        or string.find(lower, '"ok":false', 1, true) ~= nil
        or string.find(lower, "unauthorized", 1, true) ~= nil
        or string.find(lower, "invalid api key", 1, true) ~= nil
end

function Searcher:report(jobId, rarity, fieldName)
    local body = HttpService:JSONEncode({
        apiKey      = CONFIG.API_KEY,
        jobId       = jobId,
        level       = rarity or "unknown",
        placeId     = CONFIG.PLACE_ID,
        fieldName   = fieldName or "unknown",
        searcherTag = CONFIG.SELF_TAG,
    })

    local lastError = "неизвестная ошибка"
    for attempt = 1, 3 do
        local ok, resp = pcall(function()
            local responseBody = postJson("/report", body)
            return responseBody
        end)
        if ok and not responseRejected(resp) then
            self.stats.reportsSent += 1
            self.stats.lastSprout = { fieldName = "отправлено" }
            log("Ищущий", "API принял репорт о ростке: " .. tostring(resp))
            return true
        end
        lastError = ok and tostring(resp) or tostring(resp)
        log("Ищущий", "Ошибка отправки репорта, попытка " .. tostring(attempt) .. "/3: " .. lastError)
        if attempt < 3 then task.wait(attempt * 1.5) end
    end
    log("Ищущий", "ОШИБКА: API не подтвердил репорт о ростке: " .. tostring(lastError))
    return false
end

function Searcher:reportVicious(jobId, kind, fieldName)
    log("Vicious", "Подготовка репорта | kind=" .. tostring(kind) .. " | field=" .. tostring(fieldName) ..
        " | placeId=" .. tostring(CONFIG.PLACE_ID) .. " | jobId=" .. tostring(jobId) ..
        " | apiUrl=" .. tostring(CONFIG.API_URL) .. " | channelConfigured=" .. tostring(CONFIG.VICIOUS_CHANNEL_ID ~= ""))
    local body = HttpService:JSONEncode({
        apiKey      = CONFIG.API_KEY,
        jobId       = jobId,
        kind        = kind or "wild",
        placeId     = CONFIG.PLACE_ID,
        fieldName   = fieldName or "unknown",
        searcherTag = CONFIG.SELF_TAG,
        viciousChannelId = (CONFIG.VICIOUS_CHANNEL_ID ~= "" and CONFIG.VICIOUS_CHANNEL_ID) or nil,
    })

    -- Executor request APIs return the HTTP status; game:HttpPost often hides it.
    -- Retry transient failures so a brief network hiccup does not lose the Vicious report.
    local lastError = "unknown error"
    for attempt = 1, 3 do
        local ok, result = pcall(function()
            local responseBody, status = postJson("/vicious", body)
            return responseBody ~= "" and responseBody or ("HTTP " .. tostring(status))
        end)

        if ok then
            local resp = tostring(result)
            -- Accept the known queue response, and other successful 2xx API responses.
            -- A backend response that explicitly says error/failed is not treated as success.
            local lower = string.lower(resp)
            local explicitFailure = string.find(lower, '"error"', 1, true)
                or string.find(lower, '"success":false', 1, true)
                or string.find(lower, '"ok":false', 1, true)
                or string.find(lower, "unauthorized", 1, true)
                or string.find(lower, "invalid api key", 1, true)
            if not explicitFailure then
                self.stats.viciousFound += 1
                self.stats.lastVicious = { fieldName = fieldName, kind = kind }
                log("Vicious", "API принял репорт (попытка " .. tostring(attempt) .. "): " .. resp)
                return true
            end
            lastError = resp
        else
            lastError = tostring(result)
        end

        log("Vicious", "Не удалось отправить репорт, попытка " .. tostring(attempt) .. "/3: " .. lastError)
        if attempt < 3 then task.wait(attempt * 1.5) end
    end

    log("Vicious", "ОШИБКА: Vicious найден, но API не подтвердил репорт: " .. tostring(lastError))
    return false
end

function Searcher:reportPuffshroom(jobId, rarity, level, fieldName)
    if not PUFF_RARITY_PRIORITY[rarity] then return false end
    local body = HttpService:JSONEncode({
        apiKey = CONFIG.API_KEY,
        jobId = jobId,
        placeId = CONFIG.PLACE_ID,
        fieldName = fieldName or "unknown",
        rarity = rarity,
        level = level,
        searcherTag = CONFIG.SELF_TAG,
        puffshroomChannelId = CONFIG.PUFFSHROOM_CHANNEL_ID,
    })
    local ok, resp = pcall(function() return postJson("/puffshroom", body) end)
    if ok and not responseRejected(resp) then
        log("Puffshroom", "Репорт отправлен: " .. rarity .. " level " .. tostring(level) .. " | " .. tostring(fieldName))
        self.stats.reportsSent += 1
        return true
    end
    log("Puffshroom", "Ошибка репорта: " .. tostring(resp))
    return false
end

function Searcher:Start()
    self:Stop()
    local s = self.stats
    s.serversChecked, s.reportsSent = 0, 0
    s.viciousFound = 0
    s.lastSprout, s.lastVicious = nil, nil

    self.thread = task.spawn(function()
        s.currentStatus = "Запуск сканирования..."
        task.wait(tonumber(CONFIG.INITIAL_CHECK) or 1)

        log("Ищущий", "Цикл поиска запущен | CHECK_VICIOUS=" .. tostring(CONFIG.CHECK_VICIOUS) ..
            " | CHECK_SPROUTS=" .. tostring(CONFIG.CHECK_SPROUTS) .. " | CHECK_PUFFSHROOMS=" .. tostring(CONFIG.CHECK_PUFFSHROOMS) .. " | USE_ATLAS=" .. tostring(CONFIG.USE_ATLAS))
        while true do
        if not alive() then log("Ищущий", "Цикл остановлен: alive() вернул false"); return end
            local phase = "начало цикла"
            local ok, err = pcall(function()
                phase = "увеличение счётчика серверов"
                s.serversChecked += 1
                log("Ищущий", "Начало сканирования сервера #" .. tostring(s.serversChecked) ..
                    " | jobId=" .. tostring(game.JobId))

                -- Ищем оба объекта до принятия решения: если на одном сервере
                -- есть и Vicious Bee, и росток, должны уйти ДВА отдельных репорта.
                phase = "поиск ростка"
                local sprout = CONFIG.CHECK_SPROUTS and findSprout() or nil

                -- Puffshroom репортится независимо от того, найден ли спрут/Vicious.
                phase = "поиск Puffshroom"
                if false and CONFIG.CHECK_PUFFSHROOMS then
                    local puff, puffRarity, puffLevel = findPuffshroom()
                    local minimumPuff = PUFF_RARITY_PRIORITY[CONFIG.PUFF_MIN_RARITY] or 1
                    local foundPuff = puffRarity and (PUFF_RARITY_PRIORITY[puffRarity] or 0) >= minimumPuff
                    if puff and foundPuff and puffLevel then
                        local key = tostring(game.JobId) .. "|" .. tostring(puff:GetFullName()) .. "|" .. puffRarity .. "|" .. tostring(puffLevel)
                        if not puffReported[key] then
                            puffReported[key] = os.clock()
                            local puffField = detectField(puff)
                            log("Puffshroom", "Найден " .. puffRarity .. " level " .. tostring(puffLevel) .. " | поле=" .. tostring(puffField))
                            self:reportPuffshroom(game.JobId, puffRarity, puffLevel, puffField)
                        end
                    elseif puff and puffRarity then
                        log("Puffshroom", "Пропущен " .. puffRarity .. ": ниже выбранного порога " .. tostring(CONFIG.PUFF_MIN_RARITY))
                    end
                end

                -- 1) Сначала Vicious Bee — он ценнее и живёт ночью
                if CONFIG.CHECK_VICIOUS then
                    phase = "поиск Vicious Bee"
                    log("Vicious", "Начинаю поиск Vicious Bee в Workspace.Particles")
                    local vic = findVicious()
                    if vic then
                        log("Vicious", "Кандидат найден; начинаю определение вида и поля")
                        phase = "определение Vicious Bee"
                        local kind = detectViciousKind(vic)
                        local vField = detectField(vic)
                        if CONFIG.DEBUG_SPROUT then pcall(dumpVicious, vic) end

                        s.currentStatus = "🐝 Vicious " .. kind .. " — запускаю Atlas"
                        log("Vicious", "Подтверждено обнаружение: kind=" .. tostring(kind) ..
                            " | field=" .. tostring(vField or "unknown") ..
                            " | jobId=" .. tostring(game.JobId))
                        phase = "отправка Discord/API-репорта Vicious"
                        local reportOk = self:reportVicious(game.JobId, kind, vField)
                        if not reportOk then
                            log("Vicious", "Обнаружение есть, но API-репорт не подтвердился; продолжаю ожидать бой")
                        end

                        -- Не теряем росток на сервере с Vicious: отправляем отдельное
                        -- сообщение о ростке, даже если далее остаёмся ради боя с Vicious.
                        if sprout then
                            if CONFIG.DEBUG_SPROUT then pcall(dumpSprout, sprout) end
                            local rarity, source = detectRarity(sprout)
                            local fieldName = detectField(sprout)
                            if CONFIG.DEBUG_SPROUT then
                                pcall(detectionReport, sprout, rarity, source)
                                log("Ищущий", string.format(
                                    "Одновременно найден росток: %s (%s) | Поле: %s",
                                    tostring(rarity), tostring(source), tostring(fieldName or "unknown")))
                            end
                            local sproutReportOk = rarity and self:report(game.JobId, rarity, fieldName) or false
                            if sproutReportOk then
                                s.lastSprout = {
                                    fieldName = (RARITY_LABEL[rarity] or rarity) ..
                                        " @ " .. tostring(fieldName or "?"),
                                }
                                log("Ищущий", "Отдельный репорт о ростке отправлен вместе с репортом Vicious")
                            else
                                log("Ищущий", "Росток найден рядом с Vicious, но репорт о ростке не подтвердился")
                            end
                        end

                        -- Atlas запускается на лутающем аккаунте после его перехода на сервер Vicious.
                        -- Ищущий не ждёт конца боя и продолжает сканировать следующие серверы.
                        s.currentStatus = "Vicious отправлен лутающему — продолжаю поиск"
                        log("Vicious", "Задача передана через /vicious; ищущий не ждёт убийства")
                        task.wait(tonumber(CONFIG.REPORT_DELAY) or 2.5)
                        hopRandom()
                        return
                    end
                end

                if sprout then
                    if CONFIG.DEBUG_SPROUT then pcall(dumpSprout, sprout) end

                    local rarity, source = detectRarity(sprout)
                    local fieldName = detectField(sprout)
                    if CONFIG.DEBUG_SPROUT then
                        pcall(detectionReport, sprout, rarity, source)
                        log("Ищущий", string.format(
                            "Разновидность: %s (%s) | Поле: %s",
                            tostring(rarity), tostring(source), tostring(fieldName)))
                    end

                    if rarity then
                        s.currentStatus = "Репортую " .. (RARITY_LABEL[rarity] or rarity)
                        if self:report(game.JobId, rarity, fieldName) then
                            s.lastSprout = {
                                fieldName = (RARITY_LABEL[rarity] or rarity) ..
                                    " @ " .. tostring(fieldName or "?"),
                            }
                            s.currentStatus = "Репорт отправлен, хопаю"
                        else
                            s.currentStatus = "Репорт не дошёл, хопаю"
                        end
                    else
                        -- Never send an unconfirmed type: the API intentionally rejects unknown.
                        s.currentStatus = "Росток найден, тип не подтверждён — без репорта"
                        log("Ищущий", "Тип ростка не подтверждён; не отправляю ложную редкость")
                    end

                    task.wait(tonumber(CONFIG.REPORT_DELAY) or 2.5)
                    hopRandom()
                else
                    s.currentStatus = "Сервер #" .. tostring(s.serversChecked) ..
                        " — спрута нет"
                    hopRandom()
                end
            end)

            if not ok then
                log("Ищущий", "Ошибка цикла на этапе [" .. tostring(phase) .. "]: " .. tostring(err))
                s.currentStatus = "Ошибка: " .. tostring(phase) .. " — см. лог"
                task.wait(3)
                hopRandom()
            end

            task.wait(tonumber(CONFIG.HOP_DELAY) or 1.5)
        end
    end)
end

function Searcher:Stop()
    if self.thread then
        pcall(task.cancel, self.thread)
        self.thread = nil
    end
    self.stats.currentStatus = "Остановлен"
end

function Searcher:GetStats() return self.stats end

-- ══════════════════════════════════════════════════════════════════════
--  РЕЖИМ: 💰 ЛУТАЮЩИЙ
-- ══════════════════════════════════════════════════════════════════════
local Looter = {}
Looter.__index = Looter

function Looter.New()
    return setmetatable({
        thread = nil,
        stats = {
            tasksReceived = 0, teleports = 0, serversChecked = 0,
            sproutsHarvested = 0,
            lastTask = nil, currentStatus = "Готов к работе",
        },
        atlasSource = nil,
        atlasReady = false,
        atlasLoaded = false,
    }, Looter)
end

-- ── Atlas для лутающего ──
function Looter:preloadAtlas()
    if not CONFIG.USE_ATLAS then return end
    task.spawn(function()
        local ok, src = pcall(function() return game:HttpGet(CONFIG.ATLAS_URL) end)
        if ok and src and src ~= "" then
            self.atlasSource, self.atlasReady = src, true
            log("Лутающий", string.format("Atlas предзагружен (%d байт)", #src))
        else
            log("Лутающий", "Atlas недоступен")
        end
    end)
end

function Looter:runAtlas()
    if self.atlasLoaded or not CONFIG.USE_ATLAS then return end
    self.stats.currentStatus = "Запускаю Atlas..."
    task.spawn(function()
        local source = self.atlasSource
        if not (self.atlasReady and source and source ~= "") then
            local waited = 0
            while not self.atlasReady and waited < 5 do
                task.wait(0.05)
                waited += 0.05
            end
            source = (self.atlasReady and self.atlasSource) or nil
        end
        if not source or source == "" then
            local okFetch, fetched = pcall(function() return game:HttpGet(CONFIG.ATLAS_URL) end)
            if okFetch and type(fetched) == "string" and fetched ~= "" then
                source = fetched
            else
                log("Atlas", "ОШИБКА загрузки исходника: " .. tostring(fetched))
                self.stats.currentStatus = "Ошибка загрузки Atlas — см. лог"
                self.atlasLoaded = false
                return
            end
        end
        if type(loadstring) ~= "function" then
            log("Atlas", "ОШИБКА: executor не поддерживает loadstring")
            self.stats.currentStatus = "Executor не поддерживает Atlas"
            self.atlasLoaded = false
            return
        end
        local okCompile, chunk = pcall(loadstring, source)
        if not okCompile or type(chunk) ~= "function" then
            log("Atlas", "ОШИБКА компиляции: " .. tostring(chunk))
            self.stats.currentStatus = "Ошибка компиляции Atlas — см. лог"
            self.atlasLoaded = false
            return
        end
        local okRun, result = pcall(chunk)
        if not okRun then
            log("Atlas", "ОШИБКА выполнения: " .. tostring(result))
            self.stats.currentStatus = "Ошибка запуска Atlas — см. лог"
            self.atlasLoaded = false
            return
        end
        self.atlasLoaded = true
        log("Atlas", "Скрипт Atlas успешно запущен")
    end)
end

-- ── Лутаем спрут на текущем сервере, никуда не переходим ──
-- Правило: уйти можно ТОЛЬКО когда спрут сломан И прошло BROKEN_WAIT.
function Looter:harvest()
    self:runAtlas()

    local s = self.stats
    local sawSprout = false
    local brokenAt = nil
    local waitedNoSprout = 0
    local brokenWait = tonumber(CONFIG.BROKEN_WAIT) or 20
    local graceLimit = math.max(30, brokenWait * 2)
    -- Some client-side Sprout instances remain in Workspace after being harvested.
    -- Do not wait forever on a stale instance.
    local targetSprout = nil
    local targetSince = nil
    local staleSproutLimit = math.max(90, graceLimit * 3)
    local countedSprouts = {}

    while true do
        if not alive() then return end
        local sprout = findSprout()

        if sprout then
            if sprout ~= targetSprout then
                targetSprout = sprout
                targetSince = os.clock()
                sawSprout = true
                brokenAt = nil
                countedSprouts[sprout] = true
                s.sproutsHarvested += 1
                log("Лутающий", "Отслеживаю спрут: " .. tostring(sprout:GetFullName()))
            end

            waitedNoSprout = 0
            local rar = detectRarity(sprout)
            s.lastSprout = { fieldName = RARITY_LABEL[rar] or "спрут" }
            s.currentStatus = "Лутаю " .. (RARITY_LABEL[rar] or "спрут") .. " (жду разрушения)"

            if targetSince and os.clock() - targetSince >= staleSproutLimit then
                log("Лутающий", "Объект спрута не исчезает более " ..
                    tostring(staleSproutLimit) .. "с; считаю устаревшим и продолжаю")
                s.currentStatus = "Спрут не обновляется — ищу новую задачу"
                return
            end

        elseif sawSprout then
            if brokenAt == nil then
                brokenAt = os.clock()
                log("Лутающий", "Спрут исчез, жду " .. tostring(brokenWait) .. "с перед уходом")
            end

            local left = math.ceil(brokenWait - (os.clock() - brokenAt))
            if left <= 0 then
                s.currentStatus = "Спрут сломан — иду за новой задачей"
                log("Лутающий", "Спрут исчез и таймер завершён; продолжаю очередь")
                return
            end
            s.currentStatus = string.format("Спрут сломан, жду %dс", left)

        else
            waitedNoSprout += 1
            s.currentStatus = string.format("Жду спрут на сервере, %ds/%ds", waitedNoSprout, graceLimit)
            if waitedNoSprout >= graceLimit then
                log("Лутающий", "Спрут не появился; продолжаю очередь")
                s.currentStatus = "Спрута нет — ищу новую задачу"
                return
            end
        end

        task.wait(1)
    end
end

function Looter:fetchNextVicious()
    local ok, res = pcall(function()
        return game:HttpGet(CONFIG.API_URL .. "/vicious-next?apiKey=" .. CONFIG.API_KEY)
    end)
    if not ok then return nil, "HTTP Vicious: " .. tostring(res) end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 or not data then return nil, "плохой JSON Vicious" end
    if data.empty or not data.jobId then return nil, nil end
    -- Если задача указывает на текущий сервер, просто продолжаем проверку обычной очереди.
    if data.jobId == game.JobId then return nil, nil end
    data.isVicious = true
    return data, nil
end

function Looter:fetchNext()
    local ok, res = pcall(function()
        return game:HttpGet(CONFIG.API_URL .. "/next?apiKey=" .. CONFIG.API_KEY)
    end)
    if not ok then return nil, "HTTP: " .. tostring(res) end

    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 or not data then return nil, "плохой JSON" end
    if data.empty or not data.jobId then return nil, nil end
    if data.jobId == game.JobId then return nil, "уже на этом сервере" end

    -- Редкостный фильтр отключён: принимаем любую задачу из очереди.
    return data, nil
end

-- Возврат задачи в очередь, если на сервер не смогли попасть
function Looter:returnTask(taskData, reason)
    if not taskData or not taskData.jobId then return false end

    local endpoint, body
    if taskData.isVicious then
        endpoint = "/vicious"
        body = HttpService:JSONEncode({
            apiKey = CONFIG.API_KEY,
            jobId = taskData.jobId,
            kind = taskData.kind or "wild",
            placeId = taskData.placeId or CONFIG.PLACE_ID,
            fieldName = taskData.fieldName or "unknown",
            searcherTag = CONFIG.SELF_TAG,
        })
    else
        endpoint = "/return"
        body = HttpService:JSONEncode({
            apiKey = CONFIG.API_KEY,
            jobId = taskData.jobId,
            level = taskData.level,
            placeId = taskData.placeId or CONFIG.PLACE_ID,
            fieldName = taskData.fieldName or "unknown",
            searcherTag = CONFIG.SELF_TAG,
        })
    end

    local ok, res = pcall(function()
        return game:HttpPost(CONFIG.API_URL .. endpoint, body, "application/json")
    end)

    if ok then
        local resp = tostring(res)
        log("Лутающий", "Задача возвращена (" .. tostring(reason) .. "): " .. resp)
        return true
    end

    log("Лутающий", "Не удалось вернуть задачу: " .. tostring(res))
    return false
end

function Looter:Start()
    self:Stop()
    local s = self.stats
    s.tasksReceived, s.teleports, s.lastTask = 0, 0, nil
    s.sproutsHarvested = 0
    self.atlasLoaded = false
    self:preloadAtlas()

    self.thread = task.spawn(function()
        -- Если лутающий прибыл на сервер с Vicious, запускаем Atlas именно на нём.
        if CONFIG.CHECK_VICIOUS then
            local vicious = findVicious()
            if vicious then
                local kind = detectViciousKind(vicious)
                local field = detectField(vicious)
                log("Лутающий", "Сервер с Vicious найден (" .. tostring(kind) .. ", " .. tostring(field) .. "); запускаю Atlas")
                s.currentStatus = "Vicious найден — запускаю Atlas"
                if CONFIG.USE_ATLAS then self:runAtlas() end
                while alive() and findVicious() do
                    s.currentStatus = "Atlas работает на сервере Vicious"
                    task.wait(2)
                end
                log("Лутающий", "Vicious больше не обнаруживается; возвращаюсь к очереди")
            end
        end

        -- Спруты обрабатываем только если включён сбор ростков.
        if CONFIG.CHECK_SPROUTS and findSprout() then
            log("Лутающий", "На текущем сервере есть спрут — лутаю")
            local got = pcall(function() self:harvest() end)
            if not got then log("Лутающий", "Ошибка при лутании") end
        end

        s.currentStatus = "Подключаюсь к боту..."

        while true do
        if not alive() then return end
            local ok, err = pcall(function()
                s.serversChecked += 1

                -- Проверяем Vicious и в основном цикле: после телепорта объект может появиться не сразу.
                if CONFIG.CHECK_VICIOUS then
                    local vicious = findVicious()
                    if vicious then
                        local kind = detectViciousKind(vicious)
                        local field = detectField(vicious)
                        log("Лутающий", "Обнаружил Vicious на текущем сервере (" .. tostring(kind) .. ", " .. tostring(field) .. "); запускаю Atlas")
                        s.currentStatus = "Vicious найден — запускаю Atlas"
                        if CONFIG.USE_ATLAS then self:runAtlas() end
                        while alive() and findVicious() do
                            s.currentStatus = "Atlas работает на сервере Vicious"
                            task.wait(2)
                        end
                        log("Лутающий", "Vicious исчез; возвращаюсь к поиску задач")
                        return
                    end
                end

                -- Если сбор ростков включён, лутаем спрут на текущем сервере.
                -- Если выключён, полностью игнорируем спруты и берём только Vicious-задачи.
                if CONFIG.CHECK_SPROUTS and findSprout() then
                    local got, hErr = pcall(function() self:harvest() end)
                    if not got then
                        log("Лутающий", "Ошибка лутания: " .. tostring(hErr))
                        task.wait(3)
                    end
                    return
                end

                -- Vicious имеет приоритет над спрутами: лутающий забирает эту очередь первой.
                local taskData, skipReason = self:fetchNextVicious()
                if not taskData and not skipReason and CONFIG.CHECK_SPROUTS then
                    taskData, skipReason = self:fetchNext()
                elseif not taskData and not skipReason and not CONFIG.CHECK_SPROUTS then
                    s.currentStatus = "Сбор ростков выключен — жду только Vicious Bee"
                end

                if skipReason then
                    s.currentStatus = skipReason
                    task.wait(tonumber(CONFIG.POLL_INTERVAL) or 3)
                    return
                end

                if not taskData then
                    s.currentStatus = "Очередь пуста, жду задачу..."
                    task.wait(tonumber(CONFIG.POLL_INTERVAL) or 3)
                    return
                end

                if isFailed(taskData.jobId) then
                    s.currentStatus = "Сервер в blacklist, беру другую задачу"
                    task.wait(tonumber(CONFIG.POLL_INTERVAL) or 3)
                    return
                end

                s.tasksReceived += 1
                s.lastTask = {
                    fieldName = taskData.isVicious and ("Vicious Bee @ " .. tostring(taskData.fieldName or "unknown"))
                        or (RARITY_LABEL[taskData.level] or taskData.level or "спрут"),
                    jobId = taskData.jobId, age = taskData.age,
                }
                s.currentStatus = string.format("Телепорт к %s (%sс назад)",
                    taskData.isVicious and "Vicious Bee" or "спруту", tostring(taskData.age or 0))
                log("Лутающий", (taskData.isVicious and "Задача Vicious jobId=" or "Задача jobId=") .. tostring(taskData.jobId))

                s.teleports += 1
                if not hopTo(taskData.jobId, taskData.placeId) then
                    s.currentStatus = "Телепорт не удался, возвращаю задачу"
                    self:returnTask(taskData, "teleport failed")
                    task.wait(tonumber(CONFIG.POLL_INTERVAL) or 3)
                    return
                end

                -- Если за 15 сек скрипт не перезапустился — хоп не вышел.
                -- Возвращаем задачу, чтобы её взял другой аккаунт.
                task.wait(15)
                s.currentStatus = "Телепорт не завершён, возвращаю задачу"
                self:returnTask(taskData, "teleport timeout")
            end)

            if not ok then
                log("Лутающий", "Ошибка цикла: " .. tostring(err))
                s.currentStatus = "Ошибка — перезапуск через 5с"
                task.wait(5)
            end
        end
    end)
end

function Looter:Stop()
    if self.thread then
        pcall(task.cancel, self.thread)
        self.thread = nil
    end
    self.stats.currentStatus = "Остановлен"
end

function Looter:GetStats() return self.stats end

-- ══════════════════════════════════════════════════════════════════════
--  РЕЖИМ: 🎮 СОЛО
-- ══════════════════════════════════════════════════════════════════════
local Solo = {}
Solo.__index = Solo

function Solo.New()
    return setmetatable({
        thread = nil,
        stats = {
            serversChecked = 0, sproutsFound = 0, hops = 0,
            lastSprout = nil, currentStatus = "Готов к работе",
        },
        atlasSource = nil, atlasReady = false, atlasLoaded = false,
    }, Solo)
end

function Solo:preloadAtlas()
    if not CONFIG.USE_ATLAS then return end
    task.spawn(function()
        local ok, src = pcall(function() return game:HttpGet(CONFIG.ATLAS_URL) end)
        if ok and src and src ~= "" then
            self.atlasSource, self.atlasReady = src, true
            log("Соло", string.format("Atlas предзагружен (%d байт)", #src))
        else
            log("Соло", "Atlas недоступен")
        end
    end)
end

function Solo:runAtlas()
    if self.atlasLoaded or not CONFIG.USE_ATLAS then return end
    task.spawn(function()
        local source = self.atlasSource
        if not (self.atlasReady and source and source ~= "") then
            local waited = 0
            while not self.atlasReady and waited < 5 do
                task.wait(0.05)
                waited += 0.05
            end
            source = (self.atlasReady and self.atlasSource) or nil
        end
        if not source or source == "" then
            local okFetch, fetched = pcall(function() return game:HttpGet(CONFIG.ATLAS_URL) end)
            if okFetch and type(fetched) == "string" and fetched ~= "" then source = fetched
            else log("Atlas", "ОШИБКА загрузки исходника (Solo): " .. tostring(fetched)); self.atlasLoaded = false; return end
        end
        if type(loadstring) ~= "function" then log("Atlas", "ОШИБКА: executor не поддерживает loadstring"); self.atlasLoaded = false; return end
        local okCompile, chunk = pcall(loadstring, source)
        if not okCompile or type(chunk) ~= "function" then log("Atlas", "ОШИБКА компиляции (Solo): " .. tostring(chunk)); self.atlasLoaded = false; return end
        local okRun, result = pcall(chunk)
        if not okRun then log("Atlas", "ОШИБКА выполнения (Solo): " .. tostring(result)); self.atlasLoaded = false; return end
        self.atlasLoaded = true
        log("Atlas", "Скрипт Atlas успешно запущен (Solo)")
    end)
end

function Solo:Start()
    self:Stop()
    local s = self.stats
    s.serversChecked, s.sproutsFound, s.hops, s.lastSprout = 0, 0, 0, nil
    self.atlasLoaded = false
    self:preloadAtlas()

    self.thread = task.spawn(function()
        local sproutSeen = false
        local brokenAt = nil
        local viciousSeen = false
        s.currentStatus = "Проверяю сервер..."
        task.wait(tonumber(CONFIG.INITIAL_CHECK) or 1)

        while true do
        if not alive() then return end
            local ok, err = pcall(function()
                s.serversChecked += 1

                local vicious = CONFIG.CHECK_VICIOUS and findVicious() or nil
                if vicious then
                    if not viciousSeen then
                        viciousSeen = true
                        local kind = detectViciousKind(vicious)
                        local field = detectField(vicious)
                        s.currentStatus = "🐝 Vicious " .. tostring(kind) .. " — запускаю Atlas"
                        log("Соло/Vicious", "Обнаружена Vicious Bee | kind=" .. tostring(kind) ..
                            " | field=" .. tostring(field or "unknown") .. " | jobId=" .. tostring(game.JobId))
                        local searcher = Hopper.instances and Hopper.instances.searcher
                        if searcher and type(searcher.reportVicious) == "function" then
                            local reportOk = searcher:reportVicious(game.JobId, kind, field)
                            log("Соло/Vicious", "Результат репорта: " .. tostring(reportOk))
                        else
                            log("Соло/Vicious", "Репорт не вызван: Searcher.reportVicious недоступен")
                        end
                        if CONFIG.USE_ATLAS then self:runAtlas() end
                    end
                    s.currentStatus = "Vicious найден — остаюсь на сервере"
                    task.wait(1)
                    return
                else
                    viciousSeen = false
                end

                local sprout = CONFIG.CHECK_SPROUTS and findSprout() or nil
                if sprout then
                    self:runAtlas()
                    sproutSeen = true
                    brokenAt = nil
                    s.sproutsFound += 1
                    local rar = detectRarity(sprout)
                    s.lastSprout = {
                        fieldName = RARITY_LABEL[rar] or "спрут найден",
                    }
                    s.currentStatus = RARITY_LABEL[rar] or "Спрут найден — остаюсь"
                elseif sproutSeen then
                    if not brokenAt then brokenAt = os.clock() end
                    local elapsed = os.clock() - brokenAt
                    local left = math.max(0,
                        math.ceil((tonumber(CONFIG.BROKEN_WAIT) or 20) - elapsed))
                    if elapsed >= (tonumber(CONFIG.BROKEN_WAIT) or 20) then
                        s.hops += 1
                        s.currentStatus = "Хопаю (спрут сломан)"
                        task.wait(0.5)
                        hopRandom()
                    else
                        s.currentStatus = string.format(
                            "Спрут пропал — хоп через %dс", left)
                    end
                else
                    s.hops += 1
                    s.currentStatus = "Спрута нет — хоп"
                    task.wait(0.5)
                    hopRandom()
                end
            end)

            if not ok then
                log("Соло", "Ошибка цикла: " .. tostring(err))
                s.currentStatus = "Ошибка — перезаход"
                task.wait(2)
                hopRandom()
                break
            end

            task.wait(0.3)
        end
    end)
end

function Solo:Stop()
    if self.thread then
        pcall(task.cancel, self.thread)
        self.thread = nil
    end
    self.stats.currentStatus = "Остановлен"
end

function Solo:GetStats() return self.stats end

-- Менеджер режимов объявлен заранее: методы Searcher обращаются к Hopper.instances.
-- Без forward declaration Lua искал бы глобальный Hopper (nil) из-за области видимости.
-- ══════════════════════════════════════════════════════════════════════
--  МЕНЕДЖЕР РЕЖИМОВ
-- ══════════════════════════════════════════════════════════════════════
Hopper = { Mode = nil, currentKey = nil }

Hopper.instances = {
    searcher = Searcher.New(),
    looter   = Looter.New(),
    solo     = Solo.New(),
}

function Hopper.SwitchMode(mode, skipSave)
    -- Сохраняем выбранный пользователем режим ДО остановки старого потока.
    -- Поэтому следующий инжект восстановит именно последний выбор (searcher/looter/solo).
    if mode ~= "off" and Hopper.instances[mode] then
        lastMode = mode
        CONFIG.MODE = mode
        pcall(saveNow)
    end

    if Hopper.Mode then pcall(function() Hopper.Mode:Stop() end) end

    if mode == "off" or not Hopper.instances[mode] then
        Hopper.Mode = nil
        Hopper.currentKey = nil
        -- Выключение временное: lastMode остаётся последним выбранным режимом.
        if Hopper.OnModeChanged then Hopper.OnModeChanged("off") end
        if not skipSave then saveNow() end
        log("Hopper", "Выключено; сохранённый режим: " .. tostring(lastMode))
        return
    end

    Hopper.Mode = Hopper.instances[mode]
    Hopper.currentKey = mode
    Hopper.Mode:Start()
    if Hopper.OnModeChanged then Hopper.OnModeChanged(mode) end
    saveNow()
    log("Hopper", "Режим запущен и сохранён: " .. mode)
end

-- Супервизор: если поток режима умер (ошибка, краш, вмешательство
-- стороннего скрипта) — поднимаем его заново, не дожидаясь перезахода.
local supervisorLog = false

function Hopper.Supervise()
    if not Hopper.Mode or not Hopper.currentKey then return end

    local thread = Hopper.Mode.thread
    local alive = false
    if thread then
        local ok, status = pcall(coroutine.status, thread)
        alive = ok and status ~= "dead"
    end

    if not alive then
        local key = Hopper.currentKey
        if not supervisorLog then
            log("Hopper", "!! Поток режима '" .. key ..
                "' умер — перезапускаю")
            supervisorLog = true
        end
        Hopper.SwitchMode(key, true)
    end
end

-- Переключатель для ПКМ: тот же режим или выключение
function Hopper.Toggle()
    if Hopper.Mode then
        Hopper.SwitchMode("off")
    else
        Hopper.SwitchMode(lastMode ~= "off" and lastMode or "searcher")
    end
end

-- modeButtons читается в boot(), который выполняется уже ПОСЛЕ блока GUI.
-- showPage/refresh/setWindow нужны и обработчикам кнопок (выше их
-- определения), и boot()/экспортам (ниже всего блока).
-- Всё это обязано быть объявлено СНАРУЖИ pcall-обёртки, иначе Lua
-- сделает глобальные переменные (nil) и обращения упадут.
local modeButtons = {}
local readyPill
local isOpen = true
local refresh
local showPage
local setWindow

local C
local gui

local guiOk, guiErr = pcall(function()

-- ══════════════════════════════════════════════════════════════════════
--  GUI — ГОРИЗОНТАЛЬНЫЙ, С БОКОВОЙ ПАНЕЛЬЮ
-- ══════════════════════════════════════════════════════════════════════
local PlayerGui = player:WaitForChild("PlayerGui")
trace("PlayerGui получен")
local old = PlayerGui:FindFirstChild("BssHopperGui")
if old then old:Destroy() end

C = {
    -- Спокойная графитовая палитра с зелёным акцентом
    bg      = Color3.fromRGB(7, 11, 18),
    panel   = Color3.fromRGB(10, 16, 25),
    sidebar = Color3.fromRGB(8, 14, 23),
    card    = Color3.fromRGB(16, 25, 37),
    cardHi  = Color3.fromRGB(13, 43, 34),
    field   = Color3.fromRGB(11, 18, 29),
    text    = Color3.fromRGB(239, 243, 248),
    dim     = Color3.fromRGB(148, 160, 178),
    accent  = Color3.fromRGB(105, 235, 145),
    accent2 = Color3.fromRGB(54, 184, 105),
    danger  = Color3.fromRGB(255, 105, 112),
    warn    = Color3.fromRGB(255, 198, 100),
}

local function new(class, props)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    return o
end
local function round(o, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 12), Parent = o })
end
local function stroke(o, c, t)
    new("UIStroke", {
        Color = c or Color3.fromRGB(48, 62, 72),
        Thickness = t or 1, Transparency = 0.22, Parent = o,
    })
end

gui = new("ScreenGui", {
    Name = "BssHopperGui", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = PlayerGui,
})

-- ── Кнопка-змейка по центру сверху ──
local SNAKE_SIZE = 54
local snake = new("TextButton", {
    Name = "Snake",
    Size = UDim2.new(0, SNAKE_SIZE, 0, SNAKE_SIZE),
    Position = uiState.snakePos or UDim2.new(0.5, -SNAKE_SIZE / 2, 0, 56),
    BackgroundColor3 = C.bg,
    Text = "🐍", Font = Enum.Font.GothamBold, TextSize = 27,
    TextColor3 = C.text, BorderSizePixel = 0,
    Draggable = true, Active = true, Parent = gui,
})
round(snake, SNAKE_SIZE / 2)
stroke(snake, C.accent2, 2)

local dot = new("Frame", {
    Size = UDim2.new(0, 13, 0, 13),
    Position = UDim2.new(1, -15, 1, -15),
    BackgroundColor3 = C.danger, BorderSizePixel = 0, Parent = snake,
})
round(dot, 7)
new("UIStroke", { Color = C.bg, Thickness = 2, Parent = dot })

local hint = new("TextLabel", {
    Size = UDim2.new(0, 280, 0, 14),
    Position = UDim2.new(0.5, -140, 0, 56 + SNAKE_SIZE),
    BackgroundTransparency = 1,
    Text = "ЛКМ — вкл/выкл   •   ПКМ/F — меню",
    TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
    TextTransparency = 0.35, Parent = gui,
})

trace("ScreenGui создан")

-- ══════════════════════════════════════════════════════════════════════
--  ОКНО
-- ══════════════════════════════════════════════════════════════════════
local WIN_W, WIN_H = 960, 500
local HEADER_H = 66
local SIDEBAR_W = 180

local win = new("Frame", {
    Name = "Win",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = uiState.winPos or UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0, Visible = true, Active = true,
    ClipsDescendants = true, Parent = gui,
})
round(win, 16)
stroke(win, Color3.fromRGB(38, 40, 52))
-- Нижние углы должны быть круглыми — перекрываем заголовком
round(win, 16)

-- ── Заголовок ──
local head = new("Frame", {
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = win,
})
head.ClipsDescendants = true
round(head, 16)
new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 29, 35)),
        ColorSequenceKeypoint.new(0.55, C.panel),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 23, 34)),
    }),
    Rotation = 0, Parent = head,
})
new("Frame", {
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 0, 1, -18),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = head,
})
-- Градиентная полоска под заголовком
new("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = C.accent2, BorderSizePixel = 0,
    BackgroundTransparency = 0.55, Parent = head,
})

local logo = new("TextLabel", {
    Size = UDim2.new(0, 42, 1, 0), Position = UDim2.new(0, 16, 0, 0),
    BackgroundTransparency = 1, Text = "🐍",
    Font = Enum.Font.GothamBold, TextSize = 25,
    TextColor3 = C.accent, Parent = head,
})
new("TextLabel", {
    Size = UDim2.new(0, 220, 0, 25), Position = UDim2.new(0, 58, 0, 10),
    BackgroundTransparency = 1, Text = "BSS Hopper",
    TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 24,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
})
local subTitle = new("TextLabel", {
    Size = UDim2.new(0, 380, 0, 18), Position = UDim2.new(0, 58, 0, 36),
    BackgroundTransparency = 1, Text = "",
    TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = head,
})

readyPill = new("Frame", {
    Name = "SystemReadyPill", Size = UDim2.new(0, 142, 0, 34),
    Position = UDim2.new(1, -286, 0, 16), BackgroundColor3 = Color3.fromRGB(12, 35, 29),
    BorderSizePixel = 0, Parent = head,
})
round(readyPill, 17)
stroke(readyPill, Color3.fromRGB(36, 111, 76), 1)
new("Frame", {
    Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(0, 12, 0.5, -4),
    BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = readyPill,
})
round(readyPill:FindFirstChildOfClass("Frame"), 4)
new("TextLabel", {
    Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 26, 0, 0),
    BackgroundTransparency = 1, Text = "Система готова", TextColor3 = C.accent,
    Font = Enum.Font.GothamMedium, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = readyPill,
})

local gearBtn = new("TextButton", {
    Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(1, -82, 0, 14),
    BackgroundColor3 = C.card, Text = "⚙", TextColor3 = C.dim,
    Font = Enum.Font.GothamBold, TextSize = 15,
    BorderSizePixel = 0, Parent = head,
})
round(gearBtn, 9)

-- ── Кнопка Discord ──
local DISCORD_URL = "https://discord.gg/2YmPh2wExu"

-- Пробуем всё, что умеет конкретный executor.
-- Эмодзи-логотип надёжнее картинки с ассета: ассеты Roblox
-- периодически отдают пустоту и кнопка выглядит как просто синий квадрат.
local function openUrl(url)
    local attempts = {}
    if type(loadurl) == "function" then
        table.insert(attempts, function() return loadurl(url) end)
    end
    if type(open_url) == "function" then
        table.insert(attempts, function() return open_url(url) end)
    end
    -- Some executors expose request as a function, but it is an HTTP API,
    -- not a URL launcher; do not call it to open Discord links.

    for _, fn in ipairs(attempts) do
        local ok, result = pcall(fn)
        if ok and result ~= false then return true end
    end

    -- Крайний случай: копируем ссылку, чтобы открыть вручную
    if type(setclipboard) == "function" then
        pcall(setclipboard, url)
    end
    return false
end

local discordBtn = new("TextButton", {
    Name = "DiscordBtn",
    Size = UDim2.new(0, 38, 0, 38),
    Position = UDim2.new(1, -130, 0, 14),
    BackgroundColor3 = Color3.fromRGB(88, 101, 242),
    Text = "", BorderSizePixel = 0, Parent = head,
})
round(discordBtn, 9)

new("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Text = "💬", Font = Enum.Font.GothamBold, TextSize = 15,
    TextColor3 = Color3.fromRGB(255, 255, 255), Parent = discordBtn,
})

discordBtn.MouseButton1Click:Connect(function()
    if not openUrl(DISCORD_URL) then
        log("GUI", "Ссылка скопирована в буфер: " .. DISCORD_URL)
    end
end)

-- Мягкая подсветка при наведении
discordBtn.MouseEnter:Connect(function()
    TweenService:Create(discordBtn, TweenInfo.new(0.15),
        { BackgroundColor3 = Color3.fromRGB(112, 126, 255) }):Play()
end)
discordBtn.MouseLeave:Connect(function()
    TweenService:Create(discordBtn, TweenInfo.new(0.15),
        { BackgroundColor3 = Color3.fromRGB(88, 101, 242) }):Play()
end)

local closeBtn = new("TextButton", {
    Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(1, -46, 0, 14),
    BackgroundColor3 = C.card, Text = "✕", TextColor3 = C.dim,
    Font = Enum.Font.GothamBold, TextSize = 13,
    BorderSizePixel = 0, Parent = head,
})
round(closeBtn, 9)

-- ══════════════════════════════════════════════════════════════════════
--  БОКОВАЯ ПАНЕЛЬ (КОЛОНКИ)
-- ══════════════════════════════════════════════════════════════════════
local sidebar = new("Frame", {
    Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundColor3 = C.sidebar, BorderSizePixel = 0, Parent = win,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 4), Parent = sidebar,
})
new("UIPadding", {
    PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
    PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
    Parent = sidebar,
})

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = "РАЗДЕЛЫ", TextColor3 = C.dim, Font = Enum.Font.GothamBold,
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    LayoutOrder = 0, Parent = sidebar,
})

local tabButtons = {}
local tabOrder = 10

local function makeTab(icon, label, key, locked)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = C.panel, Text = "",
        BorderSizePixel = 0, LayoutOrder = tabOrder,
        AutoButtonColor = not locked, Parent = sidebar,
    })
    tabOrder += 1
    round(b, 10)

    -- Индикатор активного раздела
    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 1, -16),
        Position = UDim2.new(0, 0, 0, 8),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
        Visible = false, Parent = b,
    })
    round(bar, 2)

    local ico = new("TextLabel", {
        Size = UDim2.new(0, 26, 1, 0), Position = UDim2.new(0, 6, 0, 0),
        BackgroundTransparency = 1, Text = icon,
        Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = C.dim, Parent = b,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -34, 1, 0), Position = UDim2.new(0, 32, 0, 0),
        BackgroundTransparency = 1, Text = label,
        TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = b,
    })

    tabButtons[key] = { btn = b, bar = bar, icon = ico, label = lbl, locked = locked }
    return b
end

makeTab("⌂", "Main", "main")
makeTab("🌱", "Спруты", "sprouts")
makeTab("⚙", "Настройки", "settings")

-- Дополнительные вкладки; Vicious Bee остаётся отдельным рабочим разделом
for i = 1, 5 do
    local key = "soon" .. i
    local icon, label = "🔒", "Скоро"
    if i == 1 then
        icon, label = "🐝", "Vicious Bee"
    elseif i == 2 then
        icon, label = "🔒", "Puffshrooms (временно отключено)"
    end

    local b = makeTab(icon, label, key, true)

    local badge = new("TextLabel", {
        Size = UDim2.new(0, 20, 0, 16),
        Position = UDim2.new(1, -22, 0.5, -8),
        BackgroundColor3 = C.cardHi, Text = tostring(i),
        TextColor3 = C.dim, Font = Enum.Font.GothamBold, TextSize = 9,
        BorderSizePixel = 0, Visible = true, Parent = b,
    })
    round(badge, 6)
end

trace("Боковая панель готова")

-- ══════════════════════════════════════════════════════════════════════
--  ОБЛАСТЬ СОДЕРЖИМОГО
-- ══════════════════════════════════════════════════════════════════════
local content = new("ScrollingFrame", {
    Name = "Content",
    Size = UDim2.new(1, -SIDEBAR_W - 12, 1, -HEADER_H - 8),
    Position = UDim2.new(0, SIDEBAR_W + 6, 0, HEADER_H + 4),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = C.accent2,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Parent = win,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
    Parent = content,
})
new("UIPadding", {
    PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 6), Parent = content,
})

-- Разделитель между панелью и содержимым
new("Frame", {
    Size = UDim2.new(0, 1, 1, -HEADER_H - 10),
    Position = UDim2.new(0, SIDEBAR_W, 0, HEADER_H + 5),
    BackgroundColor3 = Color3.fromRGB(38, 40, 52),
    BorderSizePixel = 0, Parent = win,
})

local function section(txt, order)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
        Text = txt, TextColor3 = C.dim, Font = Enum.Font.GothamBold,
        TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order, Parent = content,
    })
end

-- ── Карточки-режимы (две в ряд) ──
local MODE_META = {
    searcher = {
        icon = "🔍", name = "Ищущий",
        desc = "Сканирует серверы, репортит находки боту",
    },
    looter = {
        icon = "💰", name = "Лутающий",
        desc = "Берёт задачи и лутает спрут через Atlas",
    },
    solo = {
        icon = "🎮", name = "Соло",
        desc = "Сам ищет и лутает спруты + Atlas",
    },
}

local secModes = section("РЕЖИМ РАБОТЫ", 1)

local modeRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 1,
    LayoutOrder = 2, Parent = content,
})
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8), Parent = modeRow,
})

local order = 10
for _, key in ipairs({ "searcher", "looter", "solo" }) do
    local m = MODE_META[key]
local b = new("TextButton", {
        Size = UDim2.new(1 / 3, -6, 1, 0),
        BackgroundColor3 = C.card, Text = "", BorderSizePixel = 0, AutoButtonColor = false,
        LayoutOrder = order, Parent = modeRow,
    })
    order += 1
    round(b, 12)
    local modeStroke = new("UIStroke", {
        Color = Color3.fromRGB(39, 57, 75), Thickness = 1,
        Transparency = 0.12, Parent = b,
    })

    new("TextLabel", {
        Size = UDim2.new(0, 40, 0, 34), Position = UDim2.new(0, 16, 0, 14),
        BackgroundTransparency = 1, Text = m.icon,
        Font = Enum.Font.GothamBold, TextSize = 23,
        TextColor3 = C.text, Parent = b,
    })
    local tl = new("TextLabel", {
        Size = UDim2.new(1, -32, 0, 24), Position = UDim2.new(0, 16, 0, 54),
        BackgroundTransparency = 1, Text = m.name,
        TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = b,
    })
    new("TextLabel", {
        Size = UDim2.new(1, -32, 0, 42), Position = UDim2.new(0, 16, 0, 82),
        BackgroundTransparency = 1, Text = m.desc, TextWrapped = true,
        TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, Parent = b,
    })

    local bar = new("Frame", {
        Size = UDim2.new(1, -24, 0, 3),
        Position = UDim2.new(0, 12, 1, -8),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
        Visible = false, Parent = b,
    })
    round(bar, 2)

    -- Ненавязчивая подсветка: без постоянного неонового свечения
    b.MouseEnter:Connect(function()
        if Hopper.Mode ~= Hopper.instances[key] then
            TweenService:Create(b, TweenInfo.new(0.14), {
                BackgroundColor3 = C.cardHi,
            }):Play()
        end
    end)
    b.MouseLeave:Connect(function()
        if Hopper.Mode ~= Hopper.instances[key] then
            TweenService:Create(b, TweenInfo.new(0.14), {
                BackgroundColor3 = C.card,
            }):Play()
        end
    end)

    b.MouseButton1Click:Connect(function()
        if Hopper.Mode == Hopper.instances[key] then
            Hopper.SwitchMode("off")
        else
            Hopper.SwitchMode(key)
        end
    end)
    modeButtons[key] = { btn = b, title = tl, bar = bar, outline = modeStroke }
end

local secStatus = section("СТАТУС", 20)

local statusBox = new("Frame", {
    Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.card,
    BorderSizePixel = 0, LayoutOrder = 21, Parent = content,
})
round(statusBox, 12)
stroke(statusBox)
new("TextLabel", {
    Size = UDim2.new(0, 90, 0, 64), Position = UDim2.new(0, 16, 0, 0),
    BackgroundTransparency = 1, Text = "СТАТУС",
    TextColor3 = C.dim, Font = Enum.Font.GothamBold, TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center, Parent = statusBox,
})
local statusVal = new("TextLabel", {
    Size = UDim2.new(1, -130, 0, 64), Position = UDim2.new(0, 110, 0, 0),
    BackgroundTransparency = 1, Text = "-", TextWrapped = true,
    TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center, Parent = statusBox,
})

local secStats = section("СТАТИСТИКА", 30)

-- Четыре метрики в ряд
local statRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 1,
    LayoutOrder = 31, Parent = content,
})
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8), Parent = statRow,
})

local metrics = {}
local vicMetric
local vicToggle
local function addMetric(label, key)
local box = new("Frame", {
        Size = UDim2.new(1 / 4, -6, 1, 0), BackgroundColor3 = C.card,
        BorderSizePixel = 0, Parent = statRow,
    })
    round(box, 12)
    stroke(box)
    new("TextLabel", {
        Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 14),
        BackgroundTransparency = 1, Text = label,
        TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = box,
    })
    local v = new("TextLabel", {
        Size = UDim2.new(1, -24, 0, 32), Position = UDim2.new(0, 12, 0, 42),
        BackgroundTransparency = 1, Text = "0", TextColor3 = C.accent,
        Font = Enum.Font.GothamBold, TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
    })
    metrics[key] = v
    return v
end

addMetric("СЕРВЕРОВ", "servers")
addMetric("ХОПОВ", "hops")
addMetric("РЕПОРТОВ", "reports")
addMetric("СПРУТОВ", "sprouts")

local secLast = section("ПОСЛЕДНЯЯ ЗАДАЧА", 40)

local lastBox = new("Frame", {
    Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = C.card,
    BorderSizePixel = 0, LayoutOrder = 41, Parent = content,
})
round(lastBox, 12)
stroke(lastBox)
local lastVal = new("TextLabel", {
    Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1, Text = "—", TextWrapped = true,
    TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center, Parent = lastBox,
})

trace("GUI собран, кнопки подключены")

-- ══════════════════════════════════════════════════════════════════════
--  КОНСТРУКТОРЫ ЭЛЕМЕНТОВ НАСТРОЕК
-- ══════════════════════════════════════════════════════════════════════
local settingsOpen = false

local function makeField(parent, label, value, placeholder, order, secret)
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = C.card,
        BorderSizePixel = 0, LayoutOrder = order, Parent = parent,
    })
    round(box, 12)
    stroke(box)

    new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 13), Position = UDim2.new(0, 10, 0, 6),
        BackgroundTransparency = 1, Text = label,
        TextColor3 = C.dim, Font = Enum.Font.GothamBold, TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
    })

    local tb = new("TextBox", {
        Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 21),
        BackgroundColor3 = C.field, Text = tostring(value or ""),
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = Color3.fromRGB(85, 88, 102),
        TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 11,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0, Parent = box,
    })
    round(tb, 6)
    if secret then
        tb.Text = ""
        tb.PlaceholderText = tostring(value or "")
        tb.PlaceholderColor3 = C.text
        tb.TextTransparency = 0.6
    end

    return tb
end

local function makeToggle(parent, label, value, order, onChanged)
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.card,
        BorderSizePixel = 0, LayoutOrder = order, Parent = parent,
    })
    round(box, 12)
    stroke(box)

    new("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Text = label, TextColor3 = C.text,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, Parent = box,
    })

    local state = value and true or false
    local knob = new("TextButton", {
        Size = UDim2.new(0, 44, 0, 20),
        Position = UDim2.new(1, -52, 0.5, -10),
        BackgroundColor3 = state and C.accent2 or C.cardHi,
        Text = state and "ВКЛ" or "ВЫКЛ",
        TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 9,
        BorderSizePixel = 0, Parent = box,
    })
    round(knob, 10)

    knob.MouseButton1Click:Connect(function()
        state = not state
        knob.BackgroundColor3 = state and C.accent2 or C.cardHi
        knob.Text = state and "ВКЛ" or "ВЫКЛ"
        if onChanged then pcall(onChanged, state) end
    end)

    return function() return state end
end

local function makeBtn(parent, txt, cb, col, order)
    local b = new("TextButton", {
        Size = UDim2.new(0.5, -4, 1, 0),
        BackgroundColor3 = col or C.card, Text = txt,
        TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 11,
        BorderSizePixel = 0, LayoutOrder = order, Parent = parent,
    })
    round(b, 10)
    stroke(b)
    b.MouseButton1Click:Connect(cb)
    return b
end

-- ══════════════════════════════════════════════════════════════════════
--  РАЗДЕЛ: НАСТРОЙКИ
-- ══════════════════════════════════════════════════════════════════════
local pageSettings = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Visible = false, Parent = content,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
    Parent = pageSettings,
})

section("АККАУНТ И БОТ", 1).Parent = pageSettings

local fTag  = makeField(pageSettings, "ТЕГ АККАУНТА (уникальный для каждого)",
    CONFIG.SELF_TAG, "searcher1", 10)
local fUrl  = makeField(pageSettings, "URL БОТА", CONFIG.API_URL,
    "https://...", 11)
local fKey  = makeField(pageSettings, "API KEY", CONFIG.API_KEY, "ключ", 12, true)
local fViciousChannel = makeField(pageSettings, "DISCORD CHANNEL ID — VICIOUS BEE",
    CONFIG.VICIOUS_CHANNEL_ID, "ID канала Discord для уведомлений Vicious", 14, true)

-- Поля идут в две колонки
local acctRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1,
    LayoutOrder = 13, Parent = pageSettings,
})
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8), Parent = acctRow })

local colA, colB = new("Frame", { Size = UDim2.new(0.5, -4, 1, 0),
    BackgroundTransparency = 1, Parent = acctRow }),
    new("Frame", { Size = UDim2.new(0.5, -4, 1, 0),
        BackgroundTransparency = 1, Parent = acctRow })
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8), Parent = colA })
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8), Parent = colB })

-- Переносим уже созданные поля в колонки
fTag.Parent = colA
fUrl.Parent = colB
fKey.Parent = colA
fViciousChannel.Parent = colB

section("ТАЙМИНГИ", 20).Parent = pageSettings

local fHop   = makeField(pageSettings, "ЗАДЕРЖКА ХОПА (сек)",
    CONFIG.HOP_DELAY, "1.5", 21)
local fPoll  = makeField(pageSettings, "ОПРОС БОТА (сек)",
    CONFIG.POLL_INTERVAL, "3", 22)
local fWait  = makeField(pageSettings, "ЖДАТЬ СЛОМАНОГО СПРУТА (сек)",
    CONFIG.BROKEN_WAIT, "20", 23)
local fConn  = makeField(pageSettings, "ТАЙМАУТ ПОДКЛЮЧЕНИЯ (сек)",
    CONFIG.CONNECT_TIMEOUT, "20", 24)
local fPlace = makeField(pageSettings, "PLACE ID", CONFIG.PLACE_ID,
    "1537690962", 25)

-- Выбор редкости ростков удалён: обработка больше не фильтруется настройкой MIN_RARITY.

section("ОПЦИИ", 40).Parent = pageSettings

local getAtlas = makeToggle(pageSettings, "Внедрять Atlas (Соло / Лутающий)",
    CONFIG.USE_ATLAS, 41, function(v) CONFIG.USE_ATLAS = v; saveNow() end)
local getDebug = makeToggle(pageSettings, "Диагностика спрута в консоли",
    CONFIG.DEBUG_SPROUT, 42, function(v) CONFIG.DEBUG_SPROUT = v; saveNow() end)
local getAuto  = makeToggle(pageSettings, "Автозапуск после перезахода",
    CONFIG.AUTO_START, 43, function(v) CONFIG.AUTO_START = v; saveNow() end)

local function applySettings()
    local num = function(v, def)
        local n = tonumber(v)
        if n and n > 0 then return n end
        return def
    end

    CONFIG.SELF_TAG      = (fTag.Text ~= "" and fTag.Text) or CONFIG.SELF_TAG
    CONFIG.API_URL       = (fUrl.Text ~= "" and fUrl.Text) or CONFIG.API_URL
    if fKey.Text ~= "" then CONFIG.API_KEY = fKey.Text end
    CONFIG.VICIOUS_CHANNEL_ID = (fViciousChannel.Text ~= "" and fViciousChannel.Text) or CONFIG.VICIOUS_CHANNEL_ID
    CONFIG.HOP_DELAY      = num(fHop.Text, 1.5)
    CONFIG.POLL_INTERVAL  = num(fPoll.Text, 3)
    CONFIG.BROKEN_WAIT    = num(fWait.Text, 20)
    CONFIG.CONNECT_TIMEOUT = num(fConn.Text, 20)
    CONFIG.PLACE_ID       = (fPlace.Text ~= "" and fPlace.Text) or CONFIG.PLACE_ID
CONFIG.USE_ATLAS      = getAtlas()
    CONFIG.DEBUG_SPROUT   = getDebug()
    CONFIG.AUTO_START     = getAuto()
    CONFIG.CHECK_VICIOUS  = vicToggle and vicToggle() or CONFIG.CHECK_VICIOUS

    log("CFG", "Настройки применены (Atlas=" .. tostring(CONFIG.USE_ATLAS) ..
        ", Диагностика=" .. tostring(CONFIG.DEBUG_SPROUT) ..
        ", Автозапуск=" .. tostring(CONFIG.AUTO_START) ..
        ", Vicious=" .. tostring(CONFIG.CHECK_VICIOUS) .. ")")
end

local btnRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
    LayoutOrder = 50, Parent = pageSettings,
})
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8), Parent = btnRow,
})

makeBtn(btnRow, "💾 Сохранить", function()
    applySettings()
    if saveNow() then
        statusVal.Text = "Настройки сохранены"
        statusVal.TextColor3 = C.accent
    else
        statusVal.Text = "Не удалось сохранить (нет ФС executor'а)"
        statusVal.TextColor3 = C.warn
    end
end, C.accent2)

makeBtn(btnRow, "↺ Сбросить", function()
    pcall(function()
        if type(delfile) == "function" then delfile(SAVE_FILE) end
    end)
    statusVal.Text = "Файл настроек удалён, перезапусти скрипт"
    statusVal.TextColor3 = C.warn
end, Color3.fromRGB(80, 40, 40))

-- ══════════════════════════════════════════════════════════════════════
--  РАЗДЕЛЫ «СКОРО»
-- ══════════════════════════════════════════════════════════════════════
local soonPages = {}
for i = 1, 5 do
    local p = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = false, Parent = content,
    })
    new("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
        Parent = p,
    })

    if i == 1 then
        -- ── Рабочий раздел: Vicious Bee ──
        section("ПОИСК VICIOUS BEE", 1).Parent = p

        local vicInfo = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = C.card,
            Text = "🐝  Дикий шип торчит из земли ночью. Даёт Стинжеры.",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            BorderSizePixel = 0, LayoutOrder = 2, Parent = p,
        })
        round(vicInfo, 12)
        stroke(vicInfo)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            Parent = vicInfo,
        })

        local vicFields = new("Frame", {
            Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.card,
            BorderSizePixel = 0, LayoutOrder = 3, Parent = p,
        })
        round(vicFields, 12)
        stroke(vicFields)
        new("TextLabel", {
            Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Text = "Поля: Mountain Top ⭐⭐⭐⭐⭐  •  Rose ⭐⭐⭐⭐  •  " ..
                "Cactus ⭐⭐⭐  •  Spider ⭐⭐  •  Clover ⭐",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = vicFields,
        })

        -- Настройка «Лутать Vicious Bee» находится только на вкладке Main.
        vicToggle = nil

        section("НАЙДЕНО", 10).Parent = p
        local vicStats = new("Frame", {
            Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = C.card,
            BorderSizePixel = 0, LayoutOrder = 11, Parent = p,
        })
        round(vicStats, 12)
        stroke(vicStats)
        vicMetric = new("TextLabel", {
            Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1, Text = "Vicious ещё не найдено",
            TextColor3 = C.dim, Font = Enum.Font.GothamBold, TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center, Parent = vicStats,
        })

    elseif i == 2 then
        -- ── Рабочий раздел: Puffshrooms ──
        section("ПОИСК PUFFSHROOMS", 1).Parent = p
        local puffInfo = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 68), BackgroundColor3 = C.card,
            Text = "🍄 Автопоиск Puffshroom. В Discord отправляются только Rare, Epic, Legendary и Mythic; в уведомлении указан уровень гриба.",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            BorderSizePixel = 0, LayoutOrder = 2, Parent = p,
        })
        round(puffInfo, 12)
        stroke(puffInfo)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            Parent = puffInfo,
        })

        makeToggle(p, "Искать Puffshrooms", CONFIG.CHECK_PUFFSHROOMS, 3, function(v)
            CONFIG.CHECK_PUFFSHROOMS = v
            saveNow()
        end)

        section("МИНИМАЛЬНАЯ РЕДКОСТЬ PUFFSHROOM", 4).Parent = p
        local puffRarityOrder = { "rare", "epic", "legendary", "mythic" }
        local puffRarityLabels = { rare = "Rare", epic = "Epic", legendary = "Legendary", mythic = "Mythic" }
        local puffRarityColors = {
            rare = Color3.fromRGB(90, 180, 255),
            epic = Color3.fromRGB(180, 115, 255),
            legendary = Color3.fromRGB(255, 190, 75),
            mythic = Color3.fromRGB(255, 95, 180),
        }
        local puffRarityRow = new("Frame", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1,
            LayoutOrder = 5, Parent = p,
        })
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6), Parent = puffRarityRow,
        })
        local puffRarityButtons = {}
        local function paintPuffRarity()
            for _, rarityName in ipairs(puffRarityOrder) do
                local button = puffRarityButtons[rarityName]
                local selected = CONFIG.PUFF_MIN_RARITY == rarityName
                button.BackgroundColor3 = selected and C.cardHi or C.field
                button.TextColor3 = puffRarityColors[rarityName]
                local outline = button:FindFirstChildOfClass("UIStroke")
                if outline then outline.Thickness = selected and 2 or 1 end
            end
        end
        for index, rarityName in ipairs(puffRarityOrder) do
            local button = new("TextButton", {
                Size = UDim2.new(0.25, -5, 1, 0),
                BackgroundColor3 = C.field, Text = puffRarityLabels[rarityName],
                TextColor3 = puffRarityColors[rarityName], Font = Enum.Font.GothamBold,
                TextSize = 10, AutoButtonColor = false, BorderSizePixel = 0,
                LayoutOrder = index, Parent = puffRarityRow,
            })
            round(button, 8)
            stroke(button, puffRarityColors[rarityName], 1)
            puffRarityButtons[rarityName] = button
            button.MouseButton1Click:Connect(function()
                CONFIG.PUFF_MIN_RARITY = rarityName
                paintPuffRarity()
                saveNow()
            end)
        end
        if not PUFF_RARITY_PRIORITY[CONFIG.PUFF_MIN_RARITY] then
            CONFIG.PUFF_MIN_RARITY = "rare"
        end
        paintPuffRarity()
        local puffRarityHelp = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1,
            Text = "Учитывать только выбранную редкость и выше: например, Epic = Epic, Legendary и Mythic.",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 10,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 6, Parent = p,
        })

        section("НАСТРОЙКИ УВЕДОМЛЕНИЙ", 10).Parent = p
        local puffChannel = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.card,
            Text = "Discord channel ID: " .. tostring(CONFIG.PUFFSHROOM_CHANNEL_ID) .. "\nКанал задаётся в конфигурации скрипта.",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            BorderSizePixel = 0, LayoutOrder = 11, Parent = p,
        })
        round(puffChannel, 12)
        stroke(puffChannel)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            Parent = puffChannel,
        })

    else
        local card = new("Frame", {
            Size = UDim2.new(1, 0, 0, 132), BackgroundColor3 = C.card,
            BorderSizePixel = 0, LayoutOrder = 1, Parent = p,
        })
        round(card, 12)
        stroke(card)

        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 24),
            BackgroundTransparency = 1, Text = "🔒",
            Font = Enum.Font.GothamBold, TextSize = 26, TextColor3 = C.cardHi,
            Parent = card,
        })
        new("TextLabel", {
            Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 62),
            BackgroundTransparency = 1, Text = "Раздел " .. i .. " в разработке",
            TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
        })
        new("TextLabel", {
            Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 0, 84),
            BackgroundTransparency = 1,
            Text = "Скоро здесь появится новый инструмент",
            TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
        })
    end

    soonPages["soon" .. i] = p
end

-- ══════════════════════════════════════════════════════════════════════
--  ПЕРЕКЛЮЧЕНИЕ РАЗДЕЛОВ
-- ══════════════════════════════════════════════════════════════════════
local PAGE_HOME = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Visible = false, Parent = content,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
    Parent = PAGE_HOME,
})
section("ОСНОВНЫЕ ФУНКЦИИ", 1).Parent = PAGE_HOME
makeToggle(PAGE_HOME, "Лутать Vicious Bee", CONFIG.CHECK_VICIOUS, 2, function(v)
    CONFIG.CHECK_VICIOUS = v
    saveNow()
end)
makeToggle(PAGE_HOME, "Лутать ростки", CONFIG.CHECK_SPROUTS, 4, function(v)
    CONFIG.CHECK_SPROUTS = v
    saveNow()
end)
local homeInfo = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = C.card,
    Text = "Включи нужные цели здесь. Настройки сохраняются между запусками, если executor поддерживает файловые функции.",
    TextColor3 = C.dim, Font = Enum.Font.Gotham, TextSize = 11,
    TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center, BorderSizePixel = 0,
    LayoutOrder = 5, Parent = PAGE_HOME,
})
round(homeInfo, 12)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = homeInfo })

local PAGE_MAIN = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Parent = content,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
    Parent = PAGE_MAIN,
})

-- Переносим блоки раздела «Спруты» на отдельную страницу
for _, obj in ipairs({
    secModes, modeRow, secStatus, statusBox, secLast, lastBox,
}) do
    if obj then obj.Parent = PAGE_HOME end
end
-- Порядок на Main: целевые переключатели, режимы, статус, последняя задача.
secModes.LayoutOrder = 10
modeRow.LayoutOrder = 11
secStatus.LayoutOrder = 20
statusBox.LayoutOrder = 21
secLast.LayoutOrder = 30
lastBox.LayoutOrder = 31
-- Статистика удалена из интерфейса по просьбе пользователя.
if secStats then secStats:Destroy() end
if statRow then statRow:Destroy() end

showPage = function(which)
    PAGE_HOME.Visible = (which == "main")
    PAGE_MAIN.Visible = (which == "sprouts")
    pageSettings.Visible = (which == "settings")
    for key, pg in pairs(soonPages) do
        pg.Visible = (key == which)
    end
    settingsOpen = (which == "settings")

    for key, t in pairs(tabButtons) do
        local on = (key == which)
        t.bar.Visible = on
        t.btn.BackgroundColor3 = on and C.cardHi or C.panel
        t.icon.TextColor3 = on and C.accent or C.dim
        t.label.TextColor3 = on and C.text or C.dim
    end

    content.CanvasPosition = Vector2.new(0, 0)
    refresh()
end

for key, t in pairs(tabButtons) do
    if not t.locked then
        t.btn.MouseButton1Click:Connect(function()
            if not isOpen then setWindow(true) end
            showPage(key)
        end)
    end
end

gearBtn.MouseButton1Click:Connect(function()
    if not isOpen then setWindow(true) end
    showPage("settings")
end)

-- Клик по свободному месту заголовка — свернуть/развернуть
head.InputBegan:Connect(function(inp)
    -- ПКМ по верхней полосе всегда разворачивает свёрнутое окно.
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        if not isOpen then setWindow(true) end
        return
    end

    if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
        local overButton = false
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("TextButton") then
                local c = child.AbsolutePosition + child.AbsoluteSize / 2
                local r = math.max(child.AbsoluteSize.X,
                    child.AbsoluteSize.Y) / 2 + 4
                if (inp.Position - c).Magnitude <= r then
                    overButton = true
                    break
                end
            end
        end
        if not overButton then setWindow(not isOpen) end
    end
end)

-- ── ЛКМ по змейке → только вкл/выкл ──
snake.MouseButton1Click:Connect(function()
    Hopper.Toggle()
end)

local function openMenu()
    if not isOpen then setWindow(true) end
    showPage("sprouts")
end

snake.MouseButton2Click:Connect(openMenu)

-- Надёжный перехват ПКМ (MouseButton2Click глотают часть executor'ов)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

    local ok, center = pcall(function()
        return snake.AbsolutePosition + snake.AbsoluteSize / 2
    end)
    if not ok or not center then return end

    local radius = math.max(snake.AbsoluteSize.X, snake.AbsoluteSize.Y) / 2 + 8
    if (input.Position - center).Magnitude <= radius then
        openMenu()
        return
    end

    -- ПКМ по верхней полосе свёрнутого/открытого окна.
    local p = input.Position
    local wp, ws = win.AbsolutePosition, win.AbsoluteSize
    if p.X >= wp.X and p.X <= wp.X + ws.X
        and p.Y >= wp.Y and p.Y <= wp.Y + HEADER_H then
        if not isOpen then setWindow(true) end
    end
end)

UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.Escape and isOpen then
        setWindow(false)
    end
    if inp.KeyCode == Enum.KeyCode.F then openMenu() end
    if inp.KeyCode == Enum.KeyCode.P then Hopper.Toggle() end
end)

closeBtn.MouseButton1Click:Connect(function() setWindow(false) end)

-- ══════════════════════════════════════════════════════════════════════
--  ОКНО: закатывается в заголовок
-- ══════════════════════════════════════════════════════════════════════
setWindow = function(show)
    isOpen = show
    TweenService:Create(win,
        TweenInfo.new(0.3, Enum.EasingStyle.Quart,
            show and Enum.EasingDirection.Out or Enum.EasingDirection.In),
        { Size = UDim2.new(0, WIN_W, 0, show and WIN_H or HEADER_H) }):Play()

    -- Боковая панель и содержимое прячем, иначе они просвечивают
    -- сквозь шапку в свёрнутом виде
    sidebar.Visible = show
    content.Visible = show

    hint.Text = show and "ЛКМ — вкл/выкл   •   ПКМ/F — меню"
        or "Нажми на заголовок чтобы развернуть"

    uiState.winOpen = show
    saveNow()
end

-- ══════════════════════════════════════════════════════════════════════
--  ПЕРЕТАСКИВАНИЕ
-- ══════════════════════════════════════════════════════════════════════
snake:GetPropertyChangedSignal("Position"):Connect(function()
    uiState.snakePos = snake.Position
    saveNow()
end)

local function rememberWinPos()
    local cam = workspace.CurrentCamera
    local viewX = cam and cam.ViewportSize.X or 1920
    local viewY = cam and cam.ViewportSize.Y or 1080

    uiState.winPos = UDim2.new(
        win.Position.X.Scale,
        math.max(0, math.min(win.Position.X.Offset, viewX - WIN_W)),
        win.Position.Y.Scale,
        math.max(0, math.min(win.Position.Y.Offset, viewY - 60))
    )
    saveNow()
end

do
    local dragging, dragInput, dragStart, startPos
    head.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = win.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    rememberWinPos()
                end
            end)
        end
    end)
    head.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp == dragInput then
            local d = inp.Position - dragStart
            win.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════
--  ОБНОВЛЕНИЕ ИНТЕРФЕЙСА
-- ══════════════════════════════════════════════════════════════════════
refresh = function()
    for k, v in pairs(modeButtons) do
        local on = (k == lastMode and Hopper.Mode ~= nil)
        v.bar.Visible = on
        v.btn.BackgroundColor3 = on and C.cardHi or C.card
        v.title.TextColor3 = on and C.accent or C.text
        if v.outline then
            v.outline.Color = on and C.accent2 or Color3.fromRGB(55, 72, 79)
            v.outline.Thickness = on and 1.5 or 1
            v.outline.Transparency = on and 0.05 or 0.22
        end
    end

    dot.BackgroundColor3 = Hopper.Mode and C.accent or C.danger
    if readyPill then
        local pillLabel = readyPill:FindFirstChildWhichIsA("TextLabel")
        if pillLabel then
            pillLabel.Text = Hopper.Mode and "Система активна" or "Система готова"
            pillLabel.TextColor3 = Hopper.Mode and C.accent or C.dim
        end
    end

    local meta = MODE_META[lastMode]
    if Hopper.Mode and meta then
        subTitle.Text = meta.icon .. "  " .. meta.name .. " — " .. meta.desc
        subTitle.TextColor3 = C.accent
    else
        subTitle.Text = "Выключено — ЛКМ по змейке чтобы включить"
        subTitle.TextColor3 = C.dim
    end

    if not Hopper.Mode then
        statusVal.Text = "Остановлено"
        statusVal.TextColor3 = C.dim
        lastVal.Text = "—"
        lastVal.TextColor3 = C.dim
        return
    end

local s = Hopper.Mode:GetStats()
    local st = s.currentStatus or ""

    -- Счётчик Vicious виден всегда, даже когда вкладка закрыта
    if vicMetric then
        local vf = s.viciousFound or 0
        if vf > 0 then
            local lv = s.lastVicious
            vicMetric.Text = string.format("Найдено Vicious: %d   •   последнее: %s (%s)",
                vf, tostring(lv and lv.fieldName or "?"),
                tostring(lv and lv.kind or "?"))
            vicMetric.TextColor3 = C.accent
        else
            vicMetric.Text = "Vicious ещё не найдено"
            vicMetric.TextColor3 = C.dim
        end
    end

    if settingsOpen then return end

    statusVal.Text = st
    statusVal.TextColor3 = (string.find(st, "Ошибка", 1, true)
        or string.find(st, "не дошёл", 1, true)) and C.danger or C.accent

    if s.lastTask then
        lastVal.Text = string.format("%s   •   %s   •   %ds назад",
            tostring(s.lastTask.fieldName or "?"),
            tostring(s.lastTask.jobId or ""):sub(1, 14),
            s.lastTask.age or 0)
        lastVal.TextColor3 = C.warn
    elseif s.lastSprout then
        lastVal.Text = tostring(s.lastSprout.fieldName or "найден спрут")
        lastVal.TextColor3 = C.accent
    else
        lastVal.Text = "Пока нет данных"
        lastVal.TextColor3 = C.dim
    end
end

task.spawn(function()
    local lastWatch = 0
    while gui and gui.Parent do
        if not alive() then return end
        refresh()

        -- Раз в 3 секунды проверяем, что поток режима жив
        if Hopper.Mode and os.clock() - lastWatch >= 3 then
            lastWatch = os.clock()
            pcall(Hopper.Supervise)
        end

        task.wait(0.5)
    end
end)
end)
if not guiOk then showFatal(guiErr) end

-- ══════════════════════════════════════════════════════════════════════
--  СТАРТ
-- ══════════════════════════════════════════════════════════════════════
local function boot()
    -- Настройки уже загружены до создания GUI.

    -- OnModeChanged нужен в любом случае, иначе GUI не обновляется
    Hopper.OnModeChanged = function(mode)
        if mode == "searcher" or mode == "looter" or mode == "solo" then
            lastMode = mode
            CONFIG.MODE = mode
        end
        showPage("main")
        local accentColor = (C and C.accent) or Color3.fromRGB(70, 220, 145)
        local normalTextColor = (C and C.text) or Color3.fromRGB(210, 218, 230)
        for k, v in pairs(modeButtons or {}) do
            if v then
                if v.bar then v.bar.Visible = (k == mode) end
                if v.title then
                    v.title.TextColor3 = (k == mode) and accentColor or normalTextColor
                end
            end
        end
        refresh()
    end

    -- Всегда восстанавливаем последний рабочий режим при инжекте.
    -- Не позволяем старому AUTO_START=false из устаревшего конфига
    -- оставлять интерфейс в состоянии "Остановлено" после перезахода.
    CONFIG.AUTO_START = true
    local startMode = lastMode
    if not Hopper.instances[startMode] then startMode = CONFIG.MODE end
    if not Hopper.instances[startMode] then startMode = "searcher" end
    if Hopper.instances[startMode] then
        log("CFG", "Автозапуск: включаю сохранённый режим " .. tostring(startMode))
        Hopper.SwitchMode(startMode, true)
        saveNow()
    else
        log("ERR", "Автозапуск не выполнен: режим не найден, включаю Ищущий")
        CONFIG.MODE = "searcher"
        lastMode = "searcher"
        Hopper.SwitchMode("searcher", true)
        saveNow()
    end

    -- Стартуем открытым (или в сохранённом состоянии)
    isOpen = true
    setWindow(true)
end

local okBoot, errBoot = pcall(boot)
if not okBoot then
    log("ERR", "Ошибка запуска: " .. tostring(errBoot))
    if Hopper.OnModeChanged then
        pcall(function() Hopper.OnModeChanged("off") end)
    end
end

trace("Запуск завершён, ошибок: " .. (okBoot and "нет" or "есть"))

print("=====================================================")
print("  BSS HOPPER v3.1 ЗАГРУЖЕН")
print("  Тег      : " .. tostring(CONFIG.SELF_TAG))
print("  Бот      : " .. tostring(CONFIG.API_URL))
print("  Настройки: " .. (HAS_FS and "сохраняются в " .. SAVE_FILE or "НЕ сохраняются (нет writefile)"))
print("  ЛКМ змейка — вкл/выкл | ПКМ или F — меню | P — вкл/выкл")
print("=====================================================")

-- Управление из консоли
_G.BSS_Hopper = {
    Switch = Hopper.SwitchMode,
    Toggle = Hopper.Toggle,
    Open = function() setWindow(true) showPage("main") end,
    Close = function() setWindow(false) end,
    Save = saveNow,
    Mode = function() return lastMode end,
    Destroy = stopEverything,
    Config = CONFIG,
}