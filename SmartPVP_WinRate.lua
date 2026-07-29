-- SmartPVP_WinRate.lua
-- Registro de Win Rate por Battleground. Le mbgstatsDB_Instances, filtra BGs e
-- agrega por mapa: Wins / Losses / Forfeits / Win%, + geral no topo.
-- Frame proprio no tema dark; o hub reparenteia como as outras abas.
-- Leitura DEFENSIVA (campos variam).

local GOLD = { 1, 0.82, 0 }
local frame

-- ---- dados ----
local function matchResult(inst)
    if type(inst) ~= "table" then return "?" end
    if (inst._forfeits or 0) > 0 then return "F" end
    if (inst.wins or 0) > 0 then return "W" end
    if (inst.losses or 0) > 0 then return "L" end
    if inst.winningFaction ~= nil and inst.playerFaction ~= nil then
        return inst.winningFaction == inst.playerFaction and "W" or "L"
    end
    return "?"
end

local function isBattleground(inst)
    local t = inst.instanceType
    if t == "battleground" or t == "pvp" then return true end
    if not t and ((inst.wins or 0) + (inst.losses or 0) + (inst._forfeits or 0)) > 0 then return true end
    return false
end

local function aggregate()
    local byMap, totalW, totalL = {}, 0, 0
    local instances = _G.mbgstatsDB_Instances
    if type(instances) == "table" then
        for _, inst in ipairs(instances) do
            if type(inst) == "table" and isBattleground(inst) then
                local map = inst.map or inst.customName or "Unknown"
                local rec = byMap[map]
                if not rec then rec = { map = map, w = 0, l = 0, f = 0 }; byMap[map] = rec end
                local r = matchResult(inst)
                if r == "W" then rec.w = rec.w + 1; totalW = totalW + 1
                elseif r == "L" then rec.l = rec.l + 1; totalL = totalL + 1
                elseif r == "F" then rec.f = rec.f + 1 end
            end
        end
    end
    local list = {}
    for _, rec in pairs(byMap) do rec.games = rec.w + rec.l + rec.f; list[#list + 1] = rec end
    table.sort(list, function(a, b) return a.games > b.games end)
    return list, totalW, totalL
end

local function pctColor(w, l)
    local g = w + l
    if g == 0 then return "—", 0.7, 0.7, 0.7 end
    local p = w / g * 100
    if p > 55 then return string.format("%.0f%%", p), 0.30, 0.90, 0.30 end
    if p < 45 then return string.format("%.0f%%", p), 0.95, 0.35, 0.35 end
    return string.format("%.0f%%", p), GOLD[1], GOLD[2], GOLD[3]
end

-- ---- UI ----
local CARD_W = 680
local ROW_H = 24
local COL = { name = 16, v = 380, d = 440, f = 500, pct = 585 }

local function cell(parent, x, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local function makeRow()
    local row = CreateFrame("Frame", nil, frame.card)
    row:SetSize(CARD_W - 4, ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = cell(row, COL.name)
    row.v = cell(row, COL.v, 0.30, 0.90, 0.30)
    row.d = cell(row, COL.d, 0.95, 0.35, 0.35)
    row.f = cell(row, COL.f, 1.0, 0.60, 0.0)
    row.pct = cell(row, COL.pct)
    return row
end

local function buildFrame()
    frame = CreateFrame("Frame", "SmartPVPWinRate", UIParent)
    frame:SetSize(1140, 560)
    frame:SetPoint("CENTER")
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cffffd700" .. SmartPVP_L("winrate_title") .. "|r")

    frame.overall = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.overall:SetPoint("TOP", title, "BOTTOM", 0, -10)

    local card = CreateFrame("Frame", nil, frame)
    card:SetSize(CARD_W, 430)
    card:SetPoint("TOP", frame.overall, "BOTTOM", 0, -20)
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
    card:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    frame.card = card

    -- header
    local function hcell(x, text)
        local fs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -12)
        fs:SetText(text)
        fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    end
    hcell(COL.name, SmartPVP_L("col_bg"))
    hcell(COL.v, SmartPVP_L("col_w"))
    hcell(COL.d, SmartPVP_L("col_l"))
    hcell(COL.f, SmartPVP_L("col_ff"))
    hcell(COL.pct, SmartPVP_L("col_winpct"))
    local sep = card:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -30)
    sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -30)

    frame.rows = {}
end

local function refresh()
    if not frame then return end
    local list, tW, tL = aggregate()

    local p, r, g, b = pctColor(tW, tL)
    frame.overall:SetText(string.format("%s  |cff%02x%02x%02x%s|r   (%d-%d)", SmartPVP_L("overall"), r * 255, g * 255, b * 255, p, tW, tL))

    for _, row in ipairs(frame.rows) do row:Hide() end
    if #list == 0 then
        if not frame.empty then
            frame.empty = frame.card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.empty:SetPoint("TOP", frame.card, "TOP", 0, -70)
            frame.empty:SetTextColor(0.7, 0.7, 0.7)
            frame.empty:SetText(SmartPVP_L("no_bg"))
        end
        frame.empty:Show()
        return
    end
    if frame.empty then frame.empty:Hide() end

    for i = 1, math.min(#list, 15) do
        local rec = list[i]
        local row = frame.rows[i] or makeRow()
        frame.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.card, "TOPLEFT", 2, -38 - (i - 1) * ROW_H)
        row.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.0) -- listra alternada
        local name = rec.map
        if #name > 34 then name = name:sub(1, 33) .. "…" end
        row.name:SetText(name)
        row.v:SetText(tostring(rec.w))
        row.d:SetText(tostring(rec.l))
        row.f:SetText(tostring(rec.f))
        local wp, wr, wg, wb = pctColor(rec.w, rec.l)
        row.pct:SetText(wp)
        row.pct:SetTextColor(wr, wg, wb)
        row:Show()
    end
end

function SmartPVP_OpenWinRate()
    if not frame then buildFrame() end
    refresh()
    frame:Show()
end
