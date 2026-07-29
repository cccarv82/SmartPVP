-- SmartPVP_Nemesis.lua
-- Feature #3: painel de rivalidades. Dois cards:
--   "Suas Presas"  = quem voce mais matou   (PSC_DB...Characters[me].Kills)
--   "Seus Algozes" = quem mais te matou      (PSC_DB...Characters[me].Deaths)
-- Frame proprio no tema dark; o hub reparenteia como as outras abas.
-- Leitura DEFENSIVA (campos variam).

local GOLD = { 1, 0.82, 0 }
local nemesis

-- ---- dados ----
local function countOf(e)
    if type(e) == "number" then return e end
    if type(e) == "table" then return e.kills or e.deaths or e.count or e.total or 0 end
    return 0
end
local function baseName(key, entry)
    if type(entry) == "table" and entry.name then return entry.name end
    key = tostring(key)
    local n = key:match("^([^:]+):") or key   -- tira o ":level"
    -- CoA single-realm: corta "-Rexxar - Conquest of Azeroth" (do 1o "-"). Nomes de
    -- WoW nao tem "-", entao o que vem antes do 1o "-" e o nome do personagem.
    return (n:match("^(.-)%-")) or n
end
local function classOf(entry)
    if type(entry) == "table" then return entry.class end
    return nil
end
local function myCharData()
    if not PSC_DB or not PSC_DB.PlayerKillCounts or not PSC_DB.PlayerKillCounts.Characters then return nil end
    local key = PSC_GetCharacterKey and PSC_GetCharacterKey()
    return key and PSC_DB.PlayerKillCounts.Characters[key]
end
local function aggregate(map)
    local byName = {}
    if type(map) == "table" then
        for key, entry in pairs(map) do
            local name = baseName(key, entry)
            local c = countOf(entry)
            if c > 0 and name then
                local rec = byName[name]
                if rec then rec.count = rec.count + c
                else byName[name] = { name = name, count = c, class = classOf(entry) } end
            end
        end
    end
    local list = {}
    for _, rec in pairs(byName) do list[#list + 1] = rec end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

-- ---- UI ----
local CARD_W = 545
local ROW_H = 26
local COL = { rank = 14, name = 44, count = 470 }

local function makeRow(card)
    local row = CreateFrame("Frame", nil, card)
    row:SetSize(CARD_W - 4, ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.rank:SetPoint("LEFT", row, "LEFT", COL.rank, 0)
    row.rank:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", COL.name, 0)
    row.name:SetJustifyH("LEFT"); row.name:SetWidth(COL.count - COL.name - 10)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.count:SetPoint("LEFT", row, "LEFT", COL.count, 0)
    return row
end

local function makeCard(parent, title, subtitle, onLeft, emptyKey)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(CARD_W, 470)
    card:SetPoint("TOP", parent, "TOP", 0, -50)
    if onLeft then card:SetPoint("LEFT", parent, "LEFT", 12, 0)
    else card:SetPoint("RIGHT", parent, "RIGHT", -12, 0) end
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
    card:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)

    local hdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOP", 0, -12)
    hdr:SetText(title); hdr:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    local sub = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", hdr, "BOTTOM", 0, -2)
    sub:SetText(subtitle); sub:SetTextColor(0.65, 0.65, 0.65)

    local sep = card:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(GOLD[1], GOLD[2], GOLD[3], 0.25); sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -46)
    sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -46)

    card.rows = {}
    card._emptyKey = emptyKey or "no_data"
    return card
end

local function fillCard(card)
    local list = card._list or {}
    for _, r in ipairs(card.rows) do r:Hide() end
    if #list == 0 then
        if not card.empty then
            card.empty = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            card.empty:SetPoint("TOP", card, "TOP", 0, -80)
            card.empty:SetTextColor(0.6, 0.6, 0.6)
            card.empty:SetText(SmartPVP_L(card._emptyKey or "no_data"))
            card.empty:SetJustifyH("CENTER")
        end
        card.empty:Show()
        return
    end
    if card.empty then card.empty:Hide() end
    for i = 1, math.min(#list, 14) do
        local rec = list[i]
        local row = card.rows[i] or makeRow(card)
        card.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -54 - (i - 1) * ROW_H)
        row.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.0)
        row.rank:SetText(i .. ".")
        local name, r, g, b = rec.name, 0.85, 0.85, 0.85
        if rec.class and SmartPVP_ClassInfo then
            local _, cr, cg, cb = SmartPVP_ClassInfo(rec.class)
            r, g, b = cr, cg, cb
        end
        row.name:SetText(name or "?"); row.name:SetTextColor(r, g, b)
        row.count:SetText(tostring(rec.count)); row.count:SetTextColor(1, 1, 1)
        row:Show()
    end
end

local function buildNemesis()
    nemesis = CreateFrame("Frame", "SmartPVPNemesis", UIParent)
    nemesis:SetSize(1140, 560)
    nemesis:SetPoint("CENTER")
    nemesis:Hide()

    local title = nemesis:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffffd700" .. SmartPVP_L("rivalries_title") .. "|r")

    nemesis.preys = makeCard(nemesis, SmartPVP_L("your_preys"), SmartPVP_L("preys_sub"), true)
    nemesis.villains = makeCard(nemesis, SmartPVP_L("your_nemeses"), SmartPVP_L("nemeses_sub"), false)
end

local function refresh()
    if not nemesis then return end
    local cd = myCharData()
    nemesis.preys._list = aggregate(cd and cd.Kills)
    nemesis.villains._list = aggregate(cd and cd.Deaths)
    fillCard(nemesis.preys)
    fillCard(nemesis.villains)
end

function SmartPVP_OpenNemesis()
    if not nemesis then buildNemesis() end
    refresh()
    nemesis:Show()
end
