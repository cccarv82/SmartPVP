-- SmartPVP_XP.lua
-- Tracker de eficiencia de leveling: XP e honra ganhos por ATIVIDADE
-- (Battleground / Arena / Dungeon / Mundo Aberto) + tempo ATIVO, pra calcular
-- XP/hora e honra/hora. Persistente (SmartPVPDB.xp). Locale enUS p/ o parse.
-- "Tempo ativo" = so conta enquanto houve XP nos ultimos 2 min (exclui fila/AFK).

local GOLD = { 1, 0.82, 0 }
local ACTIVE_WINDOW = 120

local CTX_ORDER = { "bg", "arena", "dungeon", "world" }
local CTX_NAME = { bg = "Battleground", arena = "Arena", dungeon = "Dungeon", world = "Mundo Aberto" }

local lastGain = 0
local frame

local function currentCtx()
    local _, t = IsInInstance()
    if t == "pvp" then return "bg" end
    if t == "arena" then return "arena" end
    if t == "party" or t == "raid" then return "dungeon" end
    return "world"
end

local function xpdb()
    SmartPVPDB = SmartPVPDB or {}
    SmartPVPDB.xp = SmartPVPDB.xp or {}
    return SmartPVPDB.xp
end
local function ctxData(c)
    local d = xpdb()
    d[c] = d[c] or { xp = 0, honor = 0, seconds = 0 }
    return d[c]
end

-- ---- captura ----
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
ev:SetScript("OnEvent", function(_, event, msg)
    local d = ctxData(currentCtx())
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local amt = tonumber(msg and msg:match("(%d+)%s+[eE]xperience"))
        if amt then d.xp = d.xp + amt; lastGain = GetTime() end
    else
        local amt = tonumber(msg and msg:match("(%d+)"))
        if amt then d.honor = d.honor + amt end
    end
end)

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 5 then
        if (GetTime() - lastGain) < ACTIVE_WINDOW then
            ctxData(currentCtx()).seconds = ctxData(currentCtx()).seconds + acc
        end
        acc = 0
    end
end)

-- ---- helpers ----
local function perHour(total, seconds)
    if not seconds or seconds < 60 then return nil end
    return total / (seconds / 3600)
end
local function fmt(n)
    n = math.floor((n or 0) + 0.5)
    local s = tostring(n)
    while true do
        local ns, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2"); s = ns
        if k == 0 then break end
    end
    return s
end
local function fmtTime(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh%02dm", h, m) end
    return string.format("%dm", m)
end

-- ---- UI ----
local CARD_W = 760
local ROW_H = 30
local COL = { name = 16, xp = 210, xph = 360, hph = 520, time = 660 }

local function cell(parent, x, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

local function makeRow()
    local row = CreateFrame("Frame", nil, frame.card)
    row:SetSize(CARD_W - 4, ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = cell(row, COL.name)
    row.xp = cell(row, COL.xp)
    row.xph = cell(row, COL.xph)
    row.hph = cell(row, COL.hph)
    row.time = cell(row, COL.time)
    return row
end

local function buildFrame()
    frame = CreateFrame("Frame", "SmartPVPXP", UIParent)
    frame:SetSize(1140, 560)
    frame:SetPoint("CENTER")
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cffffd700" .. SmartPVP_L("leveling_title") .. "|r")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -5)
    sub:SetText(SmartPVP_L("leveling_sub"))
    sub:SetTextColor(0.7, 0.7, 0.7)

    frame.best = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.best:SetPoint("TOP", sub, "BOTTOM", 0, -8)

    local card = CreateFrame("Frame", nil, frame)
    card:SetSize(CARD_W, 210)
    card:SetPoint("TOP", frame.best, "BOTTOM", 0, -18)
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
    card:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    frame.card = card

    local function hcell(x, text)
        local fs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -12)
        fs:SetText(text); fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    end
    hcell(COL.name, SmartPVP_L("col_activity"))
    hcell(COL.xp, SmartPVP_L("col_xptotal"))
    hcell(COL.xph, SmartPVP_L("col_xph"))
    hcell(COL.hph, SmartPVP_L("col_hph"))
    hcell(COL.time, SmartPVP_L("col_time"))
    local sep = card:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(GOLD[1], GOLD[2], GOLD[3], 0.3); sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -30)
    sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -30)

    frame.rows = {}
end

local function refresh()
    if not frame then return end
    local d = xpdb()
    local bestCtx, bestRate = nil, 0
    for _, c in ipairs(CTX_ORDER) do
        local dd = d[c]
        local xph = dd and perHour(dd.xp, dd.seconds)
        if xph and xph > bestRate then bestRate = xph; bestCtx = c end
    end

    if bestCtx then
        frame.best:SetText(string.format("%s |cff33cc33%s|r  (%s XP/h)", SmartPVP_L("best_leveling"), SmartPVP_L("act_" .. bestCtx), fmt(bestRate)))
    else
        frame.best:SetText("|cffaaaaaa" .. SmartPVP_L("collect_data") .. "|r")
    end

    for i, c in ipairs(CTX_ORDER) do
        local dd = d[c] or { xp = 0, honor = 0, seconds = 0 }
        local row = frame.rows[i] or makeRow()
        frame.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.card, "TOPLEFT", 2, -38 - (i - 1) * ROW_H)
        -- destaque da melhor atividade em verde
        if c == bestCtx then
            row.bg:SetTexture(0.2, 0.9, 0.3, 0.12)
        else
            row.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.0)
        end
        local xph = perHour(dd.xp, dd.seconds)
        local hph = perHour(dd.honor, dd.seconds)
        row.name:SetText(SmartPVP_L("act_" .. c)); row.name:SetTextColor(1, 1, 1)
        row.xp:SetText(fmt(dd.xp)); row.xp:SetTextColor(0.85, 0.85, 0.85)
        row.xph:SetText(xph and (fmt(xph) .. "/h") or "—")
        row.xph:SetTextColor(xph and 0.3 or 0.5, xph and 0.9 or 0.5, xph and 0.4 or 0.5)
        row.hph:SetText(hph and (fmt(hph) .. "/h") or "—"); row.hph:SetTextColor(0.9, 0.75, 0.2)
        row.time:SetText(fmtTime(dd.seconds)); row.time:SetTextColor(0.7, 0.7, 0.7)
        row:Show()
    end
end

function SmartPVP_OpenXP()
    if not frame then buildFrame() end
    refresh()
    frame:Show()
end

function SmartPVP_ResetXP()
    SmartPVPDB = SmartPVPDB or {}
    SmartPVPDB.xp = {}
    if frame then refresh() end
    print("|cff00ccff[SmartPVP]|r " .. SmartPVP_L("xp_reset"))
end
