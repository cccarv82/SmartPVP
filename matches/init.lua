-- ============================
-- meebeegeeStats Core Tracker
-- ============================
-- Main addon file for battleground statistics tracking
-- Handles session management, data persistence, and UI components

local addonName, mbgstats = ...
mbgstats = mbgstats or {}
_G.mbgstats = mbgstats

-- ============================
-- Saved Variables Initialization
-- ============================
-- WPvP sidelined for ship — set true in init.lua WPvP section to re-enable.
-- SmartPVP: ligado (open-world PvP tracking pedido pelo user). Precisa teste.
local MBG_WPVP_ENABLED = true

mbgstatsDB = mbgstatsDB or {}
mbgstatsDB_Instances = mbgstatsDB_Instances or {}
mbgstatsDB_InstanceCounter = mbgstatsDB_InstanceCounter or 0

-- Partition system data structures
mbgstatsDB_Partitions = mbgstatsDB_Partitions or {}
mbgstatsDB_PartitionCounter = mbgstatsDB_PartitionCounter or 0
mbgstatsDB_InstancePartitions = mbgstatsDB_InstancePartitions or {} -- Maps instance ID to partition ID

-- Filter state persistence
mbgstatsDB_ShowArenas = mbgstatsDB_ShowArenas ~= nil and mbgstatsDB_ShowArenas or true
mbgstatsDB_ShowBattlegrounds = mbgstatsDB_ShowBattlegrounds ~= nil and mbgstatsDB_ShowBattlegrounds or true
mbgstatsDB_PopupMode = mbgstatsDB_PopupMode or "smart"  -- "always" or "smart" (default: smart)
mbgstatsDB_CategoryTab = mbgstatsDB_CategoryTab or nil  -- "all", "battleground", "arena", "wpvp"
mbgstatsDB_Milestones = mbgstatsDB_Milestones or {}
mbgstatsDB_RecordingSeasonId = mbgstatsDB_RecordingSeasonId or nil

-- ============================
-- UI Theme (shared — Release 2–3)
-- ============================

local MBGTheme = {
    frameBg = { 0.08, 0.08, 0.10, 0.95 },
    panelBg = { 0.05, 0.05, 0.07, 0.92 },
    tabInactive = { 0.45, 0.45, 0.48 },
    tabActiveGold = { 1.0, 0.84, 0.0 },
    buttonHover = { 0.85, 0.85, 0.85 },
}

local function getMBGFactionAccentRGB()
    local faction = UnitFactionGroup("player")
    if faction == "Alliance" then
        return 0.15, 0.35, 0.75
    end
    if faction == "Horde" then
        return 0.75, 0.15, 0.15
    end
    return 0.55, 0.45, 0.15
end

local function createMBGTextButton(parent, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 72, height or 24)
    btn._active = false
    btn:EnableMouse(true)
    -- LeftButtonUp only — AnyDown/Down+Up pairs fire OnClick twice and break toggles (Instances, This Week)
    btn:RegisterForClicks("LeftButtonUp")

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("CENTER", 0, 0)

    btn.underline = btn:CreateTexture(nil, "ARTWORK")
    btn.underline:SetHeight(2)
    btn.underline:SetPoint("BOTTOMLEFT", 2, 1)
    btn.underline:SetPoint("BOTTOMRIGHT", -2, 1)
    btn.underline:Hide()

    function btn:SetMBGLabel(text)
        self.label:SetText(text)
    end

    function btn:SetMBGActive(active)
        self._active = active
        if active then
            local r, g, b = getMBGFactionAccentRGB()
            self.label:SetTextColor(r, g, b)
            self.underline:SetColorTexture(r, g, b, 1)
            self.underline:Show()
        else
            self.label:SetTextColor(MBGTheme.tabInactive[1], MBGTheme.tabInactive[2], MBGTheme.tabInactive[3])
            self.underline:Hide()
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self._active then
            self.label:SetTextColor(MBGTheme.buttonHover[1], MBGTheme.buttonHover[2], MBGTheme.buttonHover[3])
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetMBGActive(self._active)
    end)

    return btn
end

local function lerpColor(from, to, t)
    return from + (to - from) * t
end

-- Muted faction tint for map picker rows — readable, not full saturation.
local function getMBGMapPickPalette(hover)
    local ar, ag, ab = getMBGFactionAccentRGB()
    local panel = MBGTheme.panelBg
    local neutralText = { 0.78, 0.76, 0.73 }
    local neutralBorder = { 0.36, 0.34, 0.38 }
    local tint = hover and 0.32 or 0.14

    local textR = lerpColor(neutralText[1], ar, tint)
    local textG = lerpColor(neutralText[2], ag, tint)
    local textB = lerpColor(neutralText[3], ab, tint)

    local borderTint = hover and 0.38 or 0.18
    local borderR = lerpColor(neutralBorder[1], ar, borderTint)
    local borderG = lerpColor(neutralBorder[2], ag, borderTint)
    local borderB = lerpColor(neutralBorder[3], ab, borderTint)

    local bgTint = hover and 0.055 or 0.028
    return {
        text = { textR, textG, textB },
        bg = { panel[1] + ar * bgTint, panel[2] + ag * bgTint, panel[3] + ab * bgTint, hover and 0.96 or 0.90 },
        border = { borderR, borderG, borderB, hover and 0.55 or 0.38 },
    }
end

local function createMBGMapPickButton(parent, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 430, height or 26)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()

    btn.border = btn:CreateTexture(nil, "BORDER")
    btn.border:SetPoint("TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", 1, -1)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", 10, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWidth((width or 430) - 36)

    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -10, 0)
    btn.arrow:SetText("›")

    local function applyMapPickColors(hover)
        local palette = getMBGMapPickPalette(hover)
        btn.label:SetTextColor(palette.text[1], palette.text[2], palette.text[3])
        btn.arrow:SetTextColor(
            lerpColor(MBGTheme.tabInactive[1], MBGTheme.tabActiveGold[1], hover and 0.7 or 0.45),
            lerpColor(MBGTheme.tabInactive[2], MBGTheme.tabActiveGold[2], hover and 0.7 or 0.45),
            lerpColor(MBGTheme.tabInactive[3], MBGTheme.tabActiveGold[3], hover and 0.7 or 0.45))
        btn.bg:SetColorTexture(palette.bg[1], palette.bg[2], palette.bg[3], palette.bg[4])
        btn.border:SetColorTexture(palette.border[1], palette.border[2], palette.border[3], palette.border[4])
    end

    function btn:SetMapPickLabel(text)
        btn._mapName = text
        btn.label:SetText(text)
        applyMapPickColors(false)
    end

    btn:SetScript("OnEnter", function()
        applyMapPickColors(true)
    end)
    btn:SetScript("OnLeave", function()
        applyMapPickColors(false)
    end)

    applyMapPickColors(false)
    return btn
end

local function applyMBGDialogTheme(frame)
    if not frame or not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(MBGTheme.frameBg[1], MBGTheme.frameBg[2], MBGTheme.frameBg[3], MBGTheme.frameBg[4])
    local br, bg, bb = getMBGFactionAccentRGB()
    frame:SetBackdropBorderColor(br, bg, bb, 0.85)
end

-- ============================
-- Addon State Variables
-- ============================
mbgstats.playSession = { start = time(), duration = 0 }
mbgstats.battlegroundSession = {}
mbgstats.currentMap = nil
mbgstats.suggestedResult = nil
mbgstats.inBG = false
mbgstats.bfWasActive = false
mbgstats.inWPvP = false
mbgstats.wpvpSession = {}
mbgstats.popupMode = mbgstatsDB_PopupMode  -- "always" = always show popup, "smart" = only for arenas/forfeits
mbgstats.currentPartitionFilter = nil -- View filter only (nil = All Data)
mbgstats.recordingSeasonId = mbgstatsDB_RecordingSeasonId -- New matches auto-tag here
mbgstats.dateFilter = nil -- nil = all dates, "week" = last 7 days

mbgstats.showArenas = mbgstatsDB_ShowArenas -- Legacy sync from category tab
mbgstats.showBattlegrounds = mbgstatsDB_ShowBattlegrounds

local function syncLegacyTogglesFromCategoryTab(tab)
    if tab == "battleground" then
        mbgstats.showArenas = false
        mbgstats.showBattlegrounds = true
    elseif tab == "arena" then
        mbgstats.showArenas = true
        mbgstats.showBattlegrounds = false
    else
        mbgstats.showArenas = true
        mbgstats.showBattlegrounds = true
    end
    mbgstatsDB_ShowArenas = mbgstats.showArenas
    mbgstatsDB_ShowBattlegrounds = mbgstats.showBattlegrounds
end

local function initCategoryTab()
    if mbgstatsDB_CategoryTab then
        mbgstats.categoryTab = mbgstatsDB_CategoryTab
    elseif mbgstatsDB_ShowBattlegrounds and not mbgstatsDB_ShowArenas then
        mbgstats.categoryTab = "battleground"
    elseif mbgstatsDB_ShowArenas and not mbgstatsDB_ShowBattlegrounds then
        mbgstats.categoryTab = "arena"
    else
        mbgstats.categoryTab = "all"
    end
    mbgstatsDB_CategoryTab = mbgstats.categoryTab
    if not MBG_WPVP_ENABLED and mbgstats.categoryTab == "wpvp" then
        mbgstats.categoryTab = "all"
        mbgstatsDB_CategoryTab = "all"
        syncLegacyTogglesFromCategoryTab("all")
    else
        syncLegacyTogglesFromCategoryTab(mbgstats.categoryTab)
    end
end

local function resetMainViewState()
    if not MBGStatsUI then
        return
    end
    MBGStatsUI.mapListVisible = false
    MBGStatsUI.currentView = "main"
    MBGStatsUI.lastSpecificMap = nil
    if MBGStatsUI.mapButtons then
        for _, button in ipairs(MBGStatsUI.mapButtons) do
            button:Hide()
        end
    end
    if MBGStatsUI.backButton then
        MBGStatsUI.backButton:Hide()
    end
end

mbgstats.refreshFightRecordUI = function()
    if not MBGStatsUI then
        if SmartPVPDB and SmartPVPDB.debug then print("|cff00ccff[SmartPVP dbg]|r refresh: MBGStatsUI nil") end
        return
    end
    local fn = MBGStatsUI.UpdateList or MBGStatsUI_UpdateList
    if not fn then
        if SmartPVPDB and SmartPVPDB.debug then print("|cff00ccff[SmartPVP dbg]|r refresh: UpdateList nil") end
        return
    end
    fn()
end

mbgstats.applyCategoryTypeFilter = function(tab, label)
    if not MBG_WPVP_ENABLED and tab == "wpvp" then
        tab = "all"
        label = "All Types"
    end
    if tab ~= "all" and tab ~= "battleground" and tab ~= "arena" and tab ~= "wpvp" then
        return
    end
    mbgstats.categoryTab = tab
    mbgstatsDB_CategoryTab = tab
    syncLegacyTogglesFromCategoryTab(tab)
    resetMainViewState()
    if MBGStatsUI then
        MBGStatsUI.mapListVisible = false
        if label and MBGStatsUI.typeDropDown then
            UIDropDownMenu_SetText(MBGStatsUI.typeDropDown, label)
        end
        if MBGStatsUI.updateCategoryTabVisuals then
            MBGStatsUI.updateCategoryTabVisuals()
        end
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end
    end
    mbgstats.refreshFightRecordUI()
end

mbgstats.setCategoryTab = function(tab)
    mbgstats.applyCategoryTypeFilter(tab, nil)
end

initCategoryTab()

-- ============================
-- Utility Functions
-- ============================

-- Format seconds into HH:MM:SS display format
local function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

-- Format numbers with comma separators
function commaValue(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function truncateText(text, maxLen)
    if not text or #tostring(text) <= maxLen then
        return text or ""
    end
    text = tostring(text)
    return text:sub(1, maxLen - 3) .. "..."
end

-- Append non-zero objective lines (one per stat, matching NovaInstanceTracker pattern)
local function appendObjectivesDisplay(text, objectives)
    if not objectives or type(objectives) ~= "table" then
        return text
    end
    for _, obj in ipairs(objectives) do
        if obj.score and obj.score > 0 and obj.text then
            text = text .. string.format("\n   %s: %d", obj.text, obj.score)
        end
    end
    return text
end

-- Instance win/loss/forfeit label and color
local function getInstanceResult(instance)
    if (instance._forfeits or 0) > 0 then
        return "F", "|cffffaa00", "Forfeit"
    end
    if (instance.wins or 0) > 0 then
        return "W", "|cff00ff00", "Win"
    end
    if (instance.losses or 0) > 0 then
        return "L", "|cffff0000", "Loss"
    end
    if instance.winningFaction ~= nil and instance.playerFaction ~= nil then
        if instance.winningFaction == instance.playerFaction then
            return "W", "|cff00ff00", "Win"
        end
        return "L", "|cffff0000", "Loss"
    end
    return "?", "|cffaaaaaa", "Unknown"
end

local function instanceMatchesDateFilter(instance)
    if not mbgstats.dateFilter then
        return true
    end
    if mbgstats.dateFilter == "week" then
        local epoch = instance.startEpoch or instance.start or 0
        return epoch >= (time() - 7 * 86400)
    end
    return true
end

local function computeGloryStats(instances)
    local glory = {
        wins = 0, losses = 0, totalKB = 0, totalHealing = 0, games = 0,
        killsByClass = {}, bestKB = 0, bestMatch = nil,
        bestHealing = 0, bestHealMatch = nil,
        topClass = nil, topClassCount = 0,
    }
    for _, instance in ipairs(instances) do
        glory.totalKB = glory.totalKB + (instance.kb or instance.kills or 0)
        glory.totalHealing = glory.totalHealing + (instance.healing or 0)
        glory.wins = glory.wins + (instance.wins or 0)
        glory.losses = glory.losses + (instance.losses or 0)
        if (instance.wins or 0) + (instance.losses or 0) > 0 or (instance._forfeits or 0) > 0 then
            glory.games = glory.games + 1
        end
        if instance.killsByClass then
            for class, count in pairs(instance.killsByClass) do
                glory.killsByClass[class] = (glory.killsByClass[class] or 0) + count
            end
        end
        local kb = instance.kb or instance.kills or 0
        if kb > glory.bestKB then
            glory.bestKB = kb
            glory.bestMatch = instance
        end
        local healing = instance.healing or 0
        if healing > glory.bestHealing then
            glory.bestHealing = healing
            glory.bestHealMatch = instance
        end
    end
    for class, count in pairs(glory.killsByClass) do
        if count > glory.topClassCount then
            glory.topClass = class
            glory.topClassCount = count
        end
    end
    return glory
end

local function aggregateSpellTotalsFromInstances(instances)
    local damageBySpell, healBySpell = {}, {}
    for _, instance in ipairs(instances) do
        if instance.damageBySpell then
            for spellName, amount in pairs(instance.damageBySpell) do
                damageBySpell[spellName] = (damageBySpell[spellName] or 0) + amount
            end
        end
        if instance.healBySpell then
            for spellName, amount in pairs(instance.healBySpell) do
                healBySpell[spellName] = (healBySpell[spellName] or 0) + amount
            end
        end
    end
    return damageBySpell, healBySpell
end

local function topSpellFromTotals(totals)
    local bestName, bestTotal = nil, 0
    for spellName, total in pairs(totals) do
        if total > bestTotal then
            bestName, bestTotal = spellName, total
        end
    end
    return bestName, bestTotal
end

local function computeAllTimeFavoriteSpells()
    local damageBySpell, healBySpell = aggregateSpellTotalsFromInstances(mbgstatsDB_Instances)
    local attackName, attackTotal = topSpellFromTotals(damageBySpell)
    local healName, healTotal = topSpellFromTotals(healBySpell)
    return attackName, attackTotal, healName, healTotal
end

local function formatGloryWinRate(glory)
    local winRate = "—"
    local record = string.format("%d-%d", glory.wins, glory.losses)
    if glory.wins + glory.losses > 0 then
        winRate = string.format("%.0f%%", (glory.wins / (glory.wins + glory.losses)) * 100)
    end
    return winRate, record
end

local function getAllDataInstancesForGlory()
    local savedDateFilter = mbgstats.dateFilter
    mbgstats.dateFilter = nil
    local instances = getInstancesByPartition(nil)
    mbgstats.dateFilter = savedDateFilter
    return instances
end

local function formatGlorySummary(glory, instancesForSpells)
    if glory.games == 0 and glory.totalKB == 0 and glory.totalHealing == 0 then
        return "|cffffd700Glory:|r No fights recorded yet."
    end
    local winRate, record = formatGloryWinRate(glory)
    local kbPerGame = glory.games > 0 and string.format("%.1f", glory.totalKB / glory.games) or "0"
    local healPerGame = glory.games > 0 and commaValue(math.floor(glory.totalHealing / glory.games)) or "0"
    local lines = {
        string.format("|cffffd700Glory:|r Win Rate: %s (%s) | KB/Game: %s | Heal/Game: %s",
            winRate, record, kbPerGame, healPerGame),
    }
    if glory.topClass and glory.topClassCount > 0 then
        table.insert(lines, string.format("Top Prey: %s (%d)", glory.topClass, glory.topClassCount))
    end
    if glory.bestMatch and glory.bestKB > 0 then
        table.insert(lines, string.format("Most Kills: %s — %d KB",
            glory.bestMatch.map or "Unknown", glory.bestKB))
    end
    if glory.bestHealMatch and glory.bestHealing > 0 then
        table.insert(lines, string.format("Most Healing: %s — %s",
            glory.bestHealMatch.map or "Unknown", commaValue(glory.bestHealing)))
    end
    local attackName, attackTotal, healName, healTotal
    if instancesForSpells then
        local damageBySpell, healBySpell = aggregateSpellTotalsFromInstances(instancesForSpells)
        attackName, attackTotal = topSpellFromTotals(damageBySpell)
        healName, healTotal = topSpellFromTotals(healBySpell)
    else
        attackName, attackTotal, healName, healTotal = computeAllTimeFavoriteSpells()
    end
    if attackName and attackTotal > 0 then
        table.insert(lines, "Favorite Attack: " .. truncateText(tostring(attackName), 28)
            .. " — " .. commaValue(attackTotal))
    end
    if healName and healTotal > 0 then
        table.insert(lines, "Favorite Heal: " .. truncateText(tostring(healName), 28)
            .. " — " .. commaValue(healTotal))
    end
    return table.concat(lines, "\n")
end

local MBG_TOOLTIP_LABEL = "|cFF9CD6DE"
local MBG_TOOLTIP_VALUE = "|cFFFFFFFF"

local function getFilterLabel()
    if mbgstats.dateFilter == "week" then
        return "This Week"
    end
    if mbgstats.currentPartitionFilter then
        local partition = mbgstatsDB_Partitions[mbgstats.currentPartitionFilter]
        if partition and partition.name then
            return partition.name
        end
    end
    return "All Data"
end

local function getRecordingSeasonLabel()
    if not mbgstats.recordingSeasonId then
        return nil
    end
    local partition = mbgstatsDB_Partitions[mbgstats.recordingSeasonId]
    if partition and partition.name then
        return partition.name
    end
    return nil
end

local function setRecordingSeason(partitionId)
    mbgstats.recordingSeasonId = partitionId
    mbgstatsDB_RecordingSeasonId = partitionId
end

local function closeRecordingSeason()
    if not mbgstats.recordingSeasonId then
        print("[SmartPVP] No active recording season — new matches are already unassigned.")
        return
    end
    local partition = mbgstatsDB_Partitions[mbgstats.recordingSeasonId]
    local name = partition and partition.name or "Season"
    mbgstats.recordingSeasonId = nil
    mbgstatsDB_RecordingSeasonId = nil
    print(string.format(
        "[SmartPVP] Closed |cff00ff00%s|r — new matches will no longer be tagged to a season.",
        name))
    if MBGStatsUI and MBGStatsUI.updateFilterButtonStates then
        MBGStatsUI.updateFilterButtonStates()
    end
    mbgstats.refreshFightRecordUI()
end

local function clearViewFilters()
    mbgstats.currentPartitionFilter = nil
    mbgstats.dateFilter = nil
end

local function formatInstanceShortDate(instance)
    local startTime = instance.startTime
    if not startTime then
        return "?"
    end
    local _, month, day, hour, minute = startTime:match("(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
    if month and day and hour and minute then
        return string.format("%s/%s %s:%s", month, day, hour, minute)
    end
    return truncateText(startTime, 14)
end

local function formatEmptyWPvPHelpText()
    return table.concat({
        "No world PvP recorded yet.",
        "Outdoor fights against players appear here automatically.",
        "",
        "Optional: |cff00ff00/mbg declare [name]|r to name a fight",
        "or |cff00ff00/mbg stop|r to end the current session early.",
    }, "\n")
end

local function formatEmptySeasonHelpText()
    return table.concat({
        "No matches in this season yet.",
        "",
        "Your other matches are still saved — nothing was deleted.",
        "Click |cff00ff00All Data|r (left toolbar) to return to your full record.",
        "Use |cff00ff00Instances|r (top right) to browse individual fights.",
    }, "\n")
end

-- Determine if an instance is an arena or battleground (must be before formatInstanceRowSummary)
local function normalizeStoredInstanceType(instanceType)
    if instanceType == "pvp" then
        return "battleground"
    end
    return instanceType
end

local function getInstanceType(instanceData)
    if not instanceData then return "unknown" end

    if instanceData.instanceType then
        return normalizeStoredInstanceType(instanceData.instanceType) or "unknown"
    end

    if instanceData.customName or instanceData.declared then
        return "wpvp"
    end

    local mapName = instanceData.map or ""
    local lowerMapName = string.lower(mapName)

    if lowerMapName:find("ruins of lordaeron") or
       lowerMapName:find("circle of blood") or
       lowerMapName:find("blade's edge arena") or
       lowerMapName:find("nagrand arena") or
       lowerMapName:find("dalaran sewers") or
       lowerMapName:find("the ring of valor") or
       lowerMapName:find("tol'viron arena") or
       lowerMapName:find("tiger's peak") or
       lowerMapName:find("blackrook hold arena") or
       lowerMapName:find("ashran") or
       lowerMapName:find("mugambala") or
       lowerMapName:find("hook point") or
       lowerMapName:find("empyrean domain") or
       lowerMapName:find("maldraxxus coliseum") or
       lowerMapName:find("enigma crucible") or
       lowerMapName:find("nokhudon proving grounds") or
       lowerMapName:find("oribos arena") or
       lowerMapName:find("ashen vale") or
       lowerMapName:find("dalaran arena") then
        return "arena"
    end

    if lowerMapName:find("warsong gulch") or
       lowerMapName:find("arathi basin") or
       lowerMapName:find("eye of the storm") or
       lowerMapName:find("alterac valley") or
       lowerMapName:find("strand of the ancients") or
       lowerMapName:find("isle of conquest") or
       lowerMapName:find("twin peaks") or
       lowerMapName:find("battle for gilneas") or
       lowerMapName:find("silvershard mines") or
       lowerMapName:find("temple of kotmogu") or
       lowerMapName:find("deepwind gorge") or
       lowerMapName:find("seething shore") or
       lowerMapName:find("wintergrasp") or
       lowerMapName:find("tol barad") or
       lowerMapName:find("korrak's revenge") or
       lowerMapName:find("comp stomp") or
       lowerMapName:find("classic warsong gulch") or
       lowerMapName:find("classic arathi basin") or
       lowerMapName:find("classic alterac valley") then
        return "battleground"
    end

    return "unknown"
end

local function formatInstanceRowSummary(instance)
    local resultCode, color = getInstanceResult(instance)
    local displayName = instance.customName or instance.map or "Unknown"
    local mapName = truncateText(displayName, 22)
    if getInstanceType(instance) == "wpvp" and resultCode == "?" then
        resultCode = "PvP"
        color = "|cFFCCCCCC"
    end
    return color .. resultCode .. "|r " .. color .. mapName .. "|r "
        .. formatInstanceShortDate(instance) .. "; "
        .. formatTime(instance.timePlayed or 0)
end

local function recordKillByClass(session, destGUID)
    if not SmartPVP_IsPlayerGUID(destGUID) then -- SmartPVP: aceita GUID hex do 3.3.5
        return
    end
    session._killsByClassGUIDs = session._killsByClassGUIDs or {}
    if session._killsByClassGUIDs[destGUID] then
        return
    end
    session._killsByClassGUIDs[destGUID] = true

    local localizedClass, classFile = GetPlayerInfoByGUID(destGUID)
    local class = localizedClass or classFile
    if class then
        session.killsByClass[class] = (session.killsByClass[class] or 0) + 1
    end
end

local function recordPlayerKillingBlowFromCombatLog(session, subevent, combatLogData)
    local destGUID = combatLogData[8]
    if subevent == "PARTY_KILL" then
        recordKillByClass(session, destGUID)
        return
    end

    local overkill
    if subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" then
        overkill = combatLogData[13]
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
        overkill = combatLogData[16]
    end
    -- overkill is -1 unless this hit was the killing blow
    if overkill and overkill >= 0 then
        recordKillByClass(session, destGUID)
    end
end

-- NIT-style rich tooltip text (NovaInstanceTracker pattern)
local function buildInstanceTooltipText(instance)
    local kbLabel = KILLING_BLOWS or "Killing Blows"
    local hkLabel = HONORABLE_KILLS or "Honorable Kills"
    local deathsLabel = DEATHS or "Deaths"
    local damageLabel = DAMAGE or "Damage"
    local healingLabel = SHOW_COMBAT_HEALING or SHOW_COMBAT_HEALING_TEXT or "Healing"

    local text = "|cffffd700" .. (instance.map or "Unknown") .. "|r"
    text = text .. "\n" .. MBG_TOOLTIP_LABEL .. "ID:|r " .. MBG_TOOLTIP_VALUE .. tostring(instance.id or "?") .. "|r"
    text = text .. "\n" .. MBG_TOOLTIP_LABEL .. "Date:|r " .. MBG_TOOLTIP_VALUE .. (instance.startTime or "?") .. "|r"
    text = text .. "\n" .. MBG_TOOLTIP_LABEL .. "Time:|r " .. MBG_TOOLTIP_VALUE .. formatTime(instance.timePlayed or 0) .. "|r"

    if (instance._forfeits or 0) > 0 then
        text = text .. "\n|cffffaa00Forfeit|r"
    elseif (instance.wins or 0) > 0 then
        text = text .. "\n|cFF00C800Won|r"
    elseif (instance.losses or 0) > 0 then
        text = text .. "\n|cFFFF2222Lost|r"
    elseif instance.winningFaction ~= nil and instance.playerFaction ~= nil then
        if instance.winningFaction == instance.playerFaction then
            text = text .. "\n|cFF00C800Won|r"
        else
            text = text .. "\n|cFFFF2222Lost|r"
        end
    end

    if instance.damage and instance.damage > 0 then
        text = text .. "\n\n" .. MBG_TOOLTIP_LABEL .. damageLabel .. ":|r " .. MBG_TOOLTIP_VALUE .. commaValue(instance.damage) .. "|r"
        text = text .. "\n" .. MBG_TOOLTIP_LABEL .. healingLabel .. ":|r " .. MBG_TOOLTIP_VALUE .. commaValue(instance.healing or 0) .. "|r"
    end
    if instance.hk and instance.hk > 0 then
        text = text .. "\n" .. MBG_TOOLTIP_LABEL .. hkLabel .. ":|r " .. MBG_TOOLTIP_VALUE .. instance.hk .. "|r"
    end
    if (instance.kb or instance.kills or 0) > 0 then
        text = text .. "\n" .. MBG_TOOLTIP_LABEL .. kbLabel .. ":|r " .. MBG_TOOLTIP_VALUE .. (instance.kb or instance.kills or 0) .. "|r"
    end
    if instance.deaths and instance.deaths > 0 then
        text = text .. "\n" .. MBG_TOOLTIP_LABEL .. deathsLabel .. ":|r " .. MBG_TOOLTIP_VALUE .. instance.deaths .. "|r"
    end
    if instance.objectives and type(instance.objectives) == "table" then
        for _, obj in ipairs(instance.objectives) do
            if obj.score and obj.score > 0 and obj.text then
                local objLine = MBG_TOOLTIP_LABEL .. "-"
                if obj.icon then
                    objLine = objLine .. "|T" .. obj.icon .. ":13:13:0:0|t "
                end
                objLine = objLine .. obj.text .. ":|r " .. MBG_TOOLTIP_VALUE .. obj.score .. "|r"
                text = text .. "\n" .. objLine
            end
        end
    end
    if instance.killsByClass and next(instance.killsByClass) then
        text = text .. "\n\n|cFFFFFF00Kills by Class:|r"
        local sorted = {}
        for class, count in pairs(instance.killsByClass) do
            table.insert(sorted, { class = class, count = count })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i = 1, math.min(#sorted, 8) do
            local className = sorted[i].class
            local classLine = " " .. className
            if GetClassColor then
                local _, _, _, classColorHex = GetClassColor(className)
                if classColorHex then
                    classLine = " |c" .. classColorHex .. className .. "|r"
                end
            end
            text = text .. "\n" .. classLine .. " " .. MBG_TOOLTIP_VALUE .. sorted[i].count .. "|r"
        end
    end
    if instance.damageBySpell and next(instance.damageBySpell) then
        text = text .. "\n\n|cFFFFFF00Top Damage:|r"
        local sorted = {}
        for spell, damage in pairs(instance.damageBySpell) do
            table.insert(sorted, { name = spell, damage = damage })
        end
        table.sort(sorted, function(a, b) return a.damage > b.damage end)
        for i = 1, math.min(#sorted, 5) do
            text = text .. "\n " .. MBG_TOOLTIP_LABEL .. sorted[i].name .. ":|r " .. MBG_TOOLTIP_VALUE .. commaValue(sorted[i].damage) .. "|r"
        end
    end
    if instance.healBySpell and next(instance.healBySpell) then
        text = text .. "\n\n|cFFFFFF00Top Healing:|r"
        local sorted = {}
        for spell, healing in pairs(instance.healBySpell) do
            table.insert(sorted, { name = spell, healing = healing })
        end
        table.sort(sorted, function(a, b) return a.healing > b.healing end)
        for i = 1, math.min(#sorted, 5) do
            text = text .. "\n " .. MBG_TOOLTIP_LABEL .. sorted[i].name .. ":|r " .. MBG_TOOLTIP_VALUE .. commaValue(sorted[i].healing) .. "|r"
        end
    end
    if instance.honor and instance.honor > 0 then
        text = text .. "\n\n|cFFFFFF00Honor:|r"
        text = text .. "\n " .. MBG_TOOLTIP_LABEL .. "+" .. instance.honor .. "|r"
    end
    return text
end

local function sizeMBGInstanceTooltip(tooltip)
    local fs = tooltip.fs
    tooltip:SetWidth(math.max(160, fs:GetStringWidth() + 18))
    tooltip:SetHeight(fs:GetStringHeight() + 12)
end

local function positionMBGInstanceTooltip(tooltip)
    local scale, x, y = tooltip:GetEffectiveScale(), GetCursorPosition()
    tooltip:ClearAllPoints()
    tooltip:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", (x / scale) - 2, y / scale)
end

local function updateInstanceRowTooltip(tooltip, instance)
    if not tooltip or not instance then
        return
    end
    tooltip.fs:SetText(buildInstanceTooltipText(instance))
    sizeMBGInstanceTooltip(tooltip)
end

-- Print stats for a specific map (missing function that was referenced)
local function printStats(map, stats)
    if not stats then
        print(string.format("[SmartPVP] No stats found for %s", map))
        return
    end
    
    local games = (stats.wins or 0) + (stats.losses or 0)
    print(string.format("|cff00ff00[MBG Stats]|r %s:", map))
    print(string.format("  KB: %d | HK: %d | Deaths: %d | Honor: %d", stats.kb or stats.kills or 0, stats.hk or 0, stats.deaths or 0, stats.honor or 0))
    if stats.damage and stats.damage > 0 then
        print(string.format("  Damage: %s | Healing: %s", commaValue(stats.damage), commaValue(stats.healing)))
    end
    print(string.format("  Wins: %d | Losses: %d | Forfeits: %d", stats.wins or 0, stats.losses or 0, stats._forfeits or 0))
    print(string.format("  Alliance Wins: %d | Horde Wins: %d", stats.allianceWins or 0, stats.hordeWins or 0))
    print(string.format("  Time Played: %s", formatTime(stats.timePlayed or 0)))
    if games > 0 then
        print(string.format("  Average Duration: %s", formatTime(math.floor((stats.timePlayed or 0) / games))))
    end
    
    if stats.killsByClass and next(stats.killsByClass) then
        print("  Kills by Class:")
        for class, count in pairs(stats.killsByClass) do
            print(string.format("    %s: %d", class, count))
        end
    end
end

-- Get current map/instance name with fallback
local function getCurrentMapName()
    local mapName = GetInstanceInfo()
    return mapName or "Unknown"
end

-- Ensure map statistics table exists with proper structure
local function ensureMapStats(store, map)
    if not store[map] then
        store[map] = {
            kills = 0, deaths = 0, honor = 0,
            wins = 0, losses = 0,
            allianceWins = 0, hordeWins = 0,
            timePlayed = 0, killsByClass = {},
            damageBySpell = {},  -- Track damage by spell name
            healBySpell = {},  -- Track healing by spell name
            _forfeits = 0,
            -- New Battlefield API fields
            damage = 0,
            healing = 0,
            kb = 0,  -- Killing blows (this is the kills stat)
            hk = 0  -- Honorable kills (tracked separately)
        }
    end
end

-- ============================
-- World PvP Session Management (Release 3) — SIDELINED
-- ============================
-- Set MBG_WPVP_ENABLED (top of file) = true to re-enable auto tracking, Declare Battle, WPvP tab.

local WPVP_IDLE_SECONDS = 420
local MBG_ADDON_VERSION = "1.9.0"
local COMBATLOG_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local COMBATLOG_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040

local function mbgSessionLog(...)
    print("|cff00ff00[SmartPVP]|r", ...)
end

local function isInArena()
    if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then
        return true
    end
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

-- NovaInstanceTracker pattern: IsInInstance + UnitInBattleground + IsActiveBattlefieldArena
local function getPvPInstanceKind()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        local _, infoType = GetInstanceInfo()
        if infoType == "pvp" or infoType == "arena" then
            inInstance = true
            instanceType = infoType
        else
            return nil
        end
    end
    if instanceType ~= "pvp" and instanceType ~= "arena" then
        return nil
    end
    if isInArena() or instanceType == "arena" then
        return "arena"
    end
    if UnitInBattleground and UnitInBattleground("player") then
        return "battleground"
    end
    if instanceType == "pvp" then
        return "battleground"
    end
    return nil
end

local function isInstancedPvP()
    return getPvPInstanceKind() ~= nil
end

local function isPlayerGUID(guid)
    return SmartPVP_IsPlayerGUID(guid) -- SmartPVP: aceita GUID hex do 3.3.5, nao so "Player-"
end

local function isHostilePlayerTarget(destFlags, destGUID)
    if not isPlayerGUID(destGUID) then
        return false
    end
    if destFlags and bit.band(destFlags, COMBATLOG_PLAYER) > 0 then
        if bit.band(destFlags, COMBATLOG_HOSTILE) > 0 then
            return true
        end
        if COMBATLOG_OBJECT_AFFILIATION_OUTSIDER and bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 then
            return true
        end
    end
    return false
end

local function newCombatSessionSkeleton(instanceType)
    return {
        id = mbgstatsDB_InstanceCounter + 1,
        startTime = date("%Y-%m-%d %H:%M:%S"),
        startEpoch = time(),
        start = time(),
        kills = 0, deaths = 0, honor = 0,
        allianceWins = 0, hordeWins = 0,
        wins = 0, losses = 0,
        _forfeits = 0,
        killsByClass = {},
        damageBySpell = {},
        healBySpell = {},
        damage = 0,
        healing = 0,
        kb = 0,
        hk = 0,
        instanceType = instanceType,
        lastCombatTime = time(),
    }
end

local function getOpenWorldZoneName()
    return GetZoneText() or GetRealZoneText() or "Open World"
end

local function wpvpSessionHasActivity(session)
    if not session then
        return false
    end
    return (session.kb or session.kills or 0) > 0
        or (session.hk or 0) > 0
        or (session.deaths or 0) > 0
        or (session.honor or 0) > 0
        or (session.damage or 0) > 0
        or (session.healing or 0) > 0
end

local function processCombatLogForSession(session, combatLogData)
    if not session then
        return
    end
    local subevent = combatLogData[2]
    local sourceName = combatLogData[5]
    local destGUID = combatLogData[8]
    local destFlags = combatLogData[10]

    if sourceName and UnitIsUnit(sourceName, "player") then
        recordPlayerKillingBlowFromCombatLog(session, subevent, combatLogData)
        if subevent == "PARTY_KILL" and isPlayerGUID(destGUID) then
            session.kills = (session.kills or 0) + 1
            session.kb = session.kills
        else
            local overkill
            if subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" then
                overkill = combatLogData[13]
            elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
                overkill = combatLogData[16]
            end
            if overkill and overkill >= 0 and isPlayerGUID(destGUID) then
                session.kills = (session.kills or 0) + 1
                session.kb = session.kills
            end
        end

        local amount, spellName
        if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
            spellName = combatLogData[13]
            amount = combatLogData[15]
        elseif subevent == "SWING_DAMAGE" then
            spellName = "Melee"
            amount = combatLogData[12]
        elseif subevent == "RANGE_DAMAGE" then
            spellName = "Ranged"
            amount = combatLogData[12]
        elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
            spellName = combatLogData[13]
            amount = combatLogData[15]
            if amount and amount > 0 then
                session.healing = (session.healing or 0) + amount
                session.healBySpell = session.healBySpell or {}
                session.healBySpell[spellName] = (session.healBySpell[spellName] or 0) + amount
            end
        end
        if amount and amount > 0 and spellName then
            session.damageBySpell = session.damageBySpell or {}
            session.damageBySpell[spellName] = (session.damageBySpell[spellName] or 0) + amount
            session.damage = (session.damage or 0) + amount
        end
    end

    if destGUID == UnitGUID("player") and sourceName and not UnitIsUnit(sourceName, "player") then
        if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
            or subevent == "RANGE_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
            session.lastCombatTime = time()
        end
    end

    if sourceName and UnitIsUnit(sourceName, "player") and isHostilePlayerTarget(destFlags, destGUID) then
        if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
            or subevent == "RANGE_DAMAGE" or subevent == "PARTY_KILL" or subevent == "SPELL_BUILDING_DAMAGE" then
            session.lastCombatTime = time()
        end
    end
end

-- Deep copy table for data preservation (must be before mergeSessionRecord)
local function copyTable(sourceTable)
    local copy = {}
    for key, value in pairs(sourceTable) do
        if type(value) == "table" then
            copy[key] = copyTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function assignInstanceToPartition(instanceId, partitionId)
    local currentPartitionId = mbgstatsDB_InstancePartitions[instanceId]
    if currentPartitionId and mbgstatsDB_Partitions[currentPartitionId] then
        mbgstatsDB_Partitions[currentPartitionId].instanceCount =
            math.max(0, mbgstatsDB_Partitions[currentPartitionId].instanceCount - 1)
    end
    mbgstatsDB_InstancePartitions[instanceId] = partitionId
    if mbgstatsDB_Partitions[partitionId] then
        mbgstatsDB_Partitions[partitionId].instanceCount =
            (mbgstatsDB_Partitions[partitionId].instanceCount or 0) + 1
    end
end

local function mergeSessionRecord(session, mapKey, clearBattlegroundSession)
    if not session or not session.start or not mapKey then
        return
    end

    session.timePlayed = session.timePlayed or (time() - (session.start or time()))
    session.kb = session.kb or session.kills or 0

    local instanceCopy = copyTable(session)
    instanceCopy._killsByClassGUIDs = nil
    if instanceCopy.instanceType then
        instanceCopy.instanceType = normalizeStoredInstanceType(instanceCopy.instanceType)
    else
        instanceCopy.instanceType = getInstanceType(instanceCopy)
    end
    mbgstatsDB_Instances[#mbgstatsDB_Instances + 1] = instanceCopy
    if instanceCopy.id then
        mbgstats.lastConfirmedInstanceId = instanceCopy.id
    end

    if mbgstats.recordingSeasonId and instanceCopy.id then
        assignInstanceToPartition(instanceCopy.id, mbgstats.recordingSeasonId)
    end

    ensureMapStats(mbgstatsDB, mapKey)
    local overall = mbgstatsDB[mapKey]

    for key, value in pairs(session) do
        if type(value) == "number" then
            overall[key] = (overall[key] or 0) + value
        elseif type(value) == "table" and key == "killsByClass" then
            overall[key] = overall[key] or {}
            for class, count in pairs(value) do
                overall[key][class] = (overall[key][class] or 0) + count
            end
        elseif type(value) == "table" and key == "damageBySpell" then
            overall[key] = overall[key] or {}
            for spellName, damage in pairs(value) do
                overall[key][spellName] = (overall[key][spellName] or 0) + damage
            end
        elseif type(value) == "table" and key == "healBySpell" then
            overall[key] = overall[key] or {}
            for spellName, healing in pairs(value) do
                overall[key][spellName] = (overall[key][spellName] or 0) + healing
            end
        end
    end

    if mbgstats.evaluateMilestones then
        mbgstats.evaluateMilestones(instanceCopy)
    end

    if clearBattlegroundSession then
        if mbgstats.apiUpdateTimer then
            mbgstats.apiUpdateTimer:Cancel()
            mbgstats.apiUpdateTimer = nil
        end
        mbgstats.battlegroundSession = {}
    end
end

local function startWPvPSession(customName, declared)
    if not MBG_WPVP_ENABLED then return end
    local session = newCombatSessionSkeleton("wpvp")
    mbgstatsDB_InstanceCounter = mbgstatsDB_InstanceCounter + 1
    session.map = getOpenWorldZoneName()
    session.zoneName = session.map
    session.customName = customName
    session.declared = declared or false
    mbgstats.wpvpSession = session
    mbgstats.inWPvP = true
    ensureMapStats(mbgstatsDB, session.map)
    return session
end

local function endWPvPSession(saveIfActive, silent)
    if not MBG_WPVP_ENABLED then return end
    if not mbgstats.inWPvP or not mbgstats.wpvpSession then
        mbgstats.inWPvP = false
        mbgstats.wpvpSession = {}
        return
    end

    local session = mbgstats.wpvpSession
    if saveIfActive and wpvpSessionHasActivity(session) then
        session.timePlayed = time() - (session.start or time())
        local mapKey = session.customName or session.map or getOpenWorldZoneName()
        mergeSessionRecord(session, mapKey, false)
        if not silent then
            local label = session.customName or session.map
            print(string.format("[SmartPVP] World PvP saved: %s (%d KB, %s)",
                label, session.kb or session.kills or 0, formatTime(session.timePlayed or 0)))
        end
    end

    mbgstats.wpvpSession = {}
    mbgstats.inWPvP = false
end

local function touchWPvPCombat()
    if not MBG_WPVP_ENABLED then return end
    if isInstancedPvP() then
        return
    end
    if not mbgstats.inWPvP or not mbgstats.wpvpSession or not mbgstats.wpvpSession.start then
        startWPvPSession(nil, false)
    else
        mbgstats.wpvpSession.lastCombatTime = time()
    end
end

local function combatLogQualifiesForWPvP(combatLogData)
    local subevent = combatLogData[2]
    local sourceName = combatLogData[5]
    local destGUID = combatLogData[8]
    local destFlags = combatLogData[10]
    local playerGUID = UnitGUID("player")

    if sourceName and UnitIsUnit(sourceName, "player") and isHostilePlayerTarget(destFlags, destGUID) then
        if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
            or subevent == "RANGE_DAMAGE" or subevent == "PARTY_KILL" or subevent == "SPELL_BUILDING_DAMAGE" then
            return true
        end
    end

    if destGUID == playerGUID and sourceName and not UnitIsUnit(sourceName, "player") then
        if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
            or subevent == "RANGE_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
            return true
        end
    end
    return false
end

local function handleWPvPCombatLogEvent(combatLogData)
    if not MBG_WPVP_ENABLED then return end
    if isInstancedPvP() then
        return
    end
    if not combatLogQualifiesForWPvP(combatLogData) then
        return
    end
    touchWPvPCombat()
    processCombatLogForSession(mbgstats.wpvpSession, combatLogData)
end

mbgstats.declareBattle = function(name)
    if not MBG_WPVP_ENABLED then
        print("[SmartPVP] World PvP is sidelined for now — BG/Arena tracking unchanged.")
        return
    end
    if isInstancedPvP() then
        print("[SmartPVP] Cannot declare battle inside a BG or arena.")
        return
    end
    if mbgstats.inWPvP then
        endWPvPSession(true, true)
    end
    local zone = getOpenWorldZoneName()
    local label = (name and name ~= "") and name or ("Battle in " .. zone)
    startWPvPSession(label, true)
    print(string.format("[SmartPVP] Declared battle: |cff00ff00%s|r", label))
end

mbgstats.stopWPvPBattle = function(silent)
    if not MBG_WPVP_ENABLED then
        if not silent then
            print("[SmartPVP] World PvP is sidelined for now — BG/Arena tracking unchanged.")
        end
        return
    end
    endWPvPSession(true, silent)
    if not silent then
        print("[SmartPVP] World PvP session ended.")
    end
end

-- ============================
-- Play Session Management
-- ============================

-- Start tracking overall play session
local function startPlaySession()
    mbgstats.playSession.start = time()
end

-- End play session and calculate duration
local function endPlaySession()
    if mbgstats.playSession.start then
        mbgstats.playSession.duration = time() - mbgstats.playSession.start
    end
end

-- ============================
-- Battleground Session Management
-- ============================

local function battlegroundSessionIsActive(session)
    session = session or mbgstats.battlegroundSession
    return session and session.start ~= nil
end

local endBGSession

local function resolveMatchOutcome(session, played)
    if session.playerFaction ~= nil and session.winningFaction ~= nil then
        if session.playerFaction == session.winningFaction then
            return "win"
        end
        return "loss"
    end
    if played < 300 then
        return "forfeit"
    end
    return "unknown"
end

local function saveActiveBattlegroundSession(map, resultLabel)
    local session = mbgstats.battlegroundSession
    if not battlegroundSessionIsActive(session) or not map then
        return false
    end
    mergeSessionRecord(session, map, true)
    mbgSessionLog("Match saved:", map, resultLabel or "")
    mbgstats.currentMap = nil
    mbgstats.suggestedResult = nil
    mbgstats.inBG = false
    mbgstats.finalizeScheduled = false
    mbgstats.refreshFightRecordUI()
    return true
end

local function isResultPopupWaiting()
    return MBGResultPopup and MBGResultPopup:IsShown()
end

local function applyMatchOutcome(outcome, map, playerFaction)
    if outcome == "win" then
        if playerFaction == "Alliance" then
            mbgstats.ConfirmResult("alliance")
        elseif playerFaction == "Horde" then
            mbgstats.ConfirmResult("horde")
        else
            saveActiveBattlegroundSession(map, "(win, unknown faction)")
        end
    elseif outcome == "loss" then
        if playerFaction == "Alliance" then
            mbgstats.ConfirmResult("loss_alliance")
        elseif playerFaction == "Horde" then
            mbgstats.ConfirmResult("loss_horde")
        else
            saveActiveBattlegroundSession(map, "(loss, unknown faction)")
        end
    elseif outcome == "forfeit" then
        mbgstats.ConfirmResult("forfeit")
    else
        saveActiveBattlegroundSession(map, "(unknown result)")
    end
end

-- Initialize new battleground session
local function startBGSession(pvpKind)
    if battlegroundSessionIsActive() then
        mbgSessionLog("Saving previous match before starting a new one...")
        endBGSession()
    end

    mbgstats.battlegroundSession = {
        id = mbgstatsDB_InstanceCounter + 1,
        startTime = date("%Y-%m-%d %H:%M:%S"),
        startEpoch = time(),
        start = time(),
        kills = 0, deaths = 0, honor = 0,
        allianceWins = 0, hordeWins = 0,
        wins = 0, losses = 0,
        _forfeits = 0,
        killsByClass = {},
        damageBySpell = {},  -- Track damage by spell name
        healBySpell = {},  -- Track healing by spell name
        -- New Battlefield API fields
        damage = 0,
        healing = 0,
        kb = 0,  -- Killing blows from scoreboard (this becomes kills)
        hk = 0,  -- Honorable kills from scoreboard (tracked separately)
        playerFaction = nil,  -- 0 = Horde, 1 = Alliance
        winningFaction = nil, -- 0 = Horde, 1 = Alliance (from GetBattlefieldWinner)
        objectives = {},  -- Objective-specific stats (flag captures, bases held, etc.)
        -- API tracking flags
        killsFromAPI = false,  -- True if kills (KB) came from API
        deathsFromAPI = false,  -- True if deaths came from API
        honorFromAPI = false,  -- True if honor (bonus) came from API
        honorFromKills = 0,  -- Track honor gained from kills (added to API bonus honor for total)
        bonusHonor = 0  -- Bonus honor from API (objectives, win bonus, etc.)
    }

    mbgstatsDB_InstanceCounter = mbgstatsDB_InstanceCounter + 1
    mbgstats.currentMap = getCurrentMapName()
    mbgstats.battlegroundSession.map = mbgstats.currentMap

    if pvpKind == "arena" then
        mbgstats.battlegroundSession.instanceType = "arena"
    elseif pvpKind == "battleground" then
        mbgstats.battlegroundSession.instanceType = "pvp"
    else
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType then
            mbgstats.battlegroundSession.instanceType = instanceType
        else
            mbgstats.battlegroundSession.instanceType = getInstanceType({map = mbgstats.currentMap})
        end
    end

    if mbgstats.apiUpdateTimer then
        mbgstats.apiUpdateTimer:Cancel()
        mbgstats.apiUpdateTimer = nil
    end
    if C_Timer and C_Timer.NewTicker then
        mbgstats.apiUpdateTimer = C_Timer.NewTicker(5, function()
            if battlegroundSessionIsActive() and mbgstats.inBG then
                pcall(recordBattlefieldStats)
            end
        end)
    end

    ensureMapStats(mbgstatsDB, mbgstats.currentMap)
end

endBGSession = function()
    if not battlegroundSessionIsActive() then
        mbgstats.inBG = false
        return
    end

    if isResultPopupWaiting() then
        pcall(recordBattlefieldStats)
        return
    end

    if not mbgstats.currentMap then
        mbgstats.currentMap = mbgstats.battlegroundSession.map
    end
    if not mbgstats.currentMap then
        mbgstats.currentMap = "Unknown"
    end

    local map = mbgstats.currentMap
    local session = mbgstats.battlegroundSession
    
    session.timePlayed = time() - (session.start or time())

    local _, faction = UnitFactionGroup("player")
    if not faction then
        faction = "Unknown"
    end
    local played = session.timePlayed or 0
    
    -- Try to get final result from Battlefield API one last time (may not work if already left BG)
    local success, err = pcall(recordBattlefieldStats)
    if not success then
        -- Silently handle error
    end
    
    local outcome = resolveMatchOutcome(session, played)
    if outcome == "forfeit" then
        mbgstats.suggestedResult = "forfeit"
    elseif outcome == "win" then
        if session.playerFaction == 0 then
            mbgstats.suggestedResult = "horde"
        elseif session.playerFaction == 1 then
            mbgstats.suggestedResult = "alliance"
        else
            mbgstats.suggestedResult = "unknown"
        end
    elseif outcome == "loss" then
        if session.playerFaction == 0 then
            mbgstats.suggestedResult = "alliance"
        elseif session.playerFaction == 1 then
            mbgstats.suggestedResult = "horde"
        else
            mbgstats.suggestedResult = "unknown"
        end
    else
        mbgstats.suggestedResult = "unknown"
    end

    -- Determine if popup should be shown
    local shouldShowPopup = false
    if mbgstats.popupMode == "always" then
        shouldShowPopup = true
    elseif mbgstats.popupMode == "smart" then
        -- Smart mode: show popup for arenas or forfeits
        local instanceType = getInstanceType(session)
        local isForfeit = (mbgstats.suggestedResult == "forfeit")
        local isArena = (instanceType == "arena")
        shouldShowPopup = isArena or isForfeit
    end
    
    -- Show confirmation popup if needed (once — do not re-open while user is choosing)
    if shouldShowPopup and mbgstats.ShowResultConfirmation then
        if isResultPopupWaiting() then
            return
        end
        local popupSuccess, popupErr = pcall(mbgstats.ShowResultConfirmation, mbgstats.suggestedResult, faction)
        if not popupSuccess then
            saveActiveBattlegroundSession(map, "(popup error fallback)")
            print("|cffff0000[SmartPVP]|r Popup error: " .. tostring(popupErr))
        end
        return
    else
        local ok, err = pcall(applyMatchOutcome, outcome, map, faction)
        if not ok then
            print("|cffff0000[SmartPVP]|r Save error: " .. tostring(err))
            saveActiveBattlegroundSession(map, "(save error fallback)")
        end
    end

    if battlegroundSessionIsActive() and not isResultPopupWaiting() then
        mbgSessionLog("Session still open after finalize — run /mbg flush if needed")
    end
end

-- ============================
-- Data Management Functions
-- ============================

-- Merge session data into overall statistics
local function mergeSessionIntoOverall(map)
    local session = mbgstats.battlegroundSession
    if not session then
        return
    end
    mergeSessionRecord(session, map, true)
end

-- ============================
-- Partition Management Functions
-- ============================

-- Create a new partition
local function createPartition(name)
    mbgstatsDB_PartitionCounter = mbgstatsDB_PartitionCounter + 1
    local partitionId = mbgstatsDB_PartitionCounter
    
    mbgstatsDB_Partitions[partitionId] = {
        id = partitionId,
        name = name,
        created = time(),
        active = true,
        instanceCount = 0
    }
    
    return partitionId
end

local function startNewSeason()
    local name = "Season " .. date("%m/%d/%y")
    local partitionId = createPartition(name)
    setRecordingSeason(partitionId)
    mbgstats.currentPartitionFilter = nil
    mbgstats.dateFilter = nil
    resetMainViewState()
    print(string.format(
        "[SmartPVP] Now recording to |cff00ff00%s|r. Your full history stays visible under |cff00ff00All Data|r.",
        name))
    if MBGStatsUI then
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end
        mbgstats.refreshFightRecordUI()
    end
end
local function getPartition(partitionId)
    return mbgstatsDB_Partitions[partitionId]
end

-- Get all active partitions
local function getActivePartitions()
    local activePartitions = {}
    for id, partition in pairs(mbgstatsDB_Partitions) do
        if partition.active then
            table.insert(activePartitions, partition)
        end
    end
    -- Sort by creation time (newest first)
    table.sort(activePartitions, function(a, b) return a.created > b.created end)
    return activePartitions
end

-- Assign instance to partition (mutually exclusive) — see early definition before mergeSessionRecord

-- Remove instance from partition
local function removeInstanceFromPartition(instanceId)
    local partitionId = mbgstatsDB_InstancePartitions[instanceId]
    if partitionId and mbgstatsDB_Partitions[partitionId] then
        mbgstatsDB_Partitions[partitionId].instanceCount = 
            math.max(0, mbgstatsDB_Partitions[partitionId].instanceCount - 1)
    end
    mbgstatsDB_InstancePartitions[instanceId] = nil
end

-- Get partition ID for an instance
local function getInstancePartition(instanceId)
    return mbgstatsDB_InstancePartitions[instanceId]
end

local function instanceMatchesCategoryTab(instance)
    local tab = mbgstats.categoryTab or "all"
    if tab == "all" then
        return true
    end
    local instanceType = getInstanceType(instance)
    if tab == "battleground" then
        return instanceType == "battleground"
    end
    if tab == "arena" then
        return instanceType == "arena"
    end
    if tab == "wpvp" then
        return instanceType == "wpvp"
    end
    return false
end

-- Filter instances by partition and instance type
local function getInstancesByPartition(partitionId)
    local filteredInstances = {}
    
    -- First filter by partition
    local partitionFilteredInstances = {}
    if not partitionId then
        -- All Data = every stored match, regardless of season assignment or active state
        for i, instance in ipairs(mbgstatsDB_Instances) do
            table.insert(partitionFilteredInstances, instance)
        end
    else
        -- Return instances from the specific partition (regardless of active status)
        for i, instance in ipairs(mbgstatsDB_Instances) do
            if mbgstatsDB_InstancePartitions[instance.id] == partitionId then
                table.insert(partitionFilteredInstances, instance)
            end
        end
    end
    
    -- Filter by category tab (All / BG / Arena)
    for i, instance in ipairs(partitionFilteredInstances) do
        if instanceMatchesCategoryTab(instance) then
            table.insert(filteredInstances, instance)
        end
    end

    if mbgstats.dateFilter then
        local dateFiltered = {}
        for _, instance in ipairs(filteredInstances) do
            if instanceMatchesDateFilter(instance) then
                table.insert(dateFiltered, instance)
            end
        end
        return dateFiltered
    end
    
    return filteredInstances
end

-- Filter overall stats by partition and instance type
local function getOverallStatsByPartition(partitionId)
    local filteredStats = {}
    
    -- First, get all instances that match the partition filter (without instance type filtering)
    local partitionFilteredInstances = {}
    
    if not partitionId then
        -- All Data = every stored match, regardless of season assignment or active state
        for i, instance in ipairs(mbgstatsDB_Instances) do
            table.insert(partitionFilteredInstances, instance)
        end
    else
        -- Return instances from the specific partition (regardless of active status)
        for i, instance in ipairs(mbgstatsDB_Instances) do
            if mbgstatsDB_InstancePartitions[instance.id] == partitionId then
                table.insert(partitionFilteredInstances, instance)
            end
        end
    end
    
    -- Now apply instance type filtering and aggregate
    for _, instance in ipairs(partitionFilteredInstances) do
        if not instanceMatchesDateFilter(instance) then
            -- skip instances outside date filter
        else
        local instanceType = getInstanceType(instance)
        local shouldInclude = instanceMatchesCategoryTab(instance)
        -- Unknown types only appear under All tab
        if instanceType == "unknown" and (mbgstats.categoryTab or "all") ~= "all" then
            shouldInclude = false
        end
        
        if shouldInclude then
            local map = instance.map or "Unknown"
            if not filteredStats[map] then
                filteredStats[map] = {
                    kills = 0, deaths = 0, honor = 0,
                    wins = 0, losses = 0,
                    allianceWins = 0, hordeWins = 0,
                    timePlayed = 0, killsByClass = {},
                    damageBySpell = {},
                    healBySpell = {},
                    _forfeits = 0,
                    -- API fields
                    kb = 0,  -- Killing blows
                    hk = 0,  -- Honorable kills
                    damage = 0,
                    healing = 0
                }
            end
            
            -- Aggregate instance stats
            local kbWasAdded = false
            for key, value in pairs(instance) do
                if type(value) == "number" then
                    -- Aggregate all numeric fields (kb, hk, damage, healing, etc.)
                    if filteredStats[map][key] ~= nil then
                        filteredStats[map][key] = filteredStats[map][key] + value
                        if key == "kb" then
                            kbWasAdded = true
                        end
                    end
                elseif type(value) == "table" and key == "killsByClass" then
                    for class, count in pairs(value) do
                        filteredStats[map][key][class] = (filteredStats[map][key][class] or 0) + count
                    end
                elseif type(value) == "table" and key == "damageBySpell" then
                    filteredStats[map][key] = filteredStats[map][key] or {}
                    for spellName, damage in pairs(value) do
                        filteredStats[map][key][spellName] = (filteredStats[map][key][spellName] or 0) + damage
                    end
                elseif type(value) == "table" and key == "healBySpell" then
                    filteredStats[map][key] = filteredStats[map][key] or {}
                    for spellName, healing in pairs(value) do
                        filteredStats[map][key][spellName] = (filteredStats[map][key][spellName] or 0) + healing
                    end
                end
            end
            
            -- Handle legacy instances: if instance has kills but no kb, use kills as kb
            -- This ensures old instances with only "kills" field are properly aggregated
            if not kbWasAdded and instance.kills and instance.kills > 0 then
                filteredStats[map].kb = filteredStats[map].kb + instance.kills
            end
        end
        end
    end
    
    return filteredStats
end

local function getCategoryTabLabel()
    local tab = mbgstats.categoryTab or "all"
    if tab == "battleground" then
        return "Battlegrounds"
    end
    if tab == "arena" then
        return "Arenas"
    end
    if tab == "wpvp" then
        return "World PvP"
    end
    return "All Types"
end

local function getViewFilterLabel()
    if mbgstats.dateFilter == "week" then
        return "This Week"
    end
    if mbgstats.currentPartitionFilter then
        local partition = mbgstatsDB_Partitions[mbgstats.currentPartitionFilter]
        if partition and partition.name then
            return partition.name
        end
    end
    return "All Data"
end

local function countViewMatches()
    return #getInstancesByPartition(mbgstats.currentPartitionFilter)
end

local function getInstancesForMap(mapName)
    local filtered = {}
    if not mapName then
        return filtered
    end
    for _, instance in ipairs(getInstancesByPartition(mbgstats.currentPartitionFilter)) do
        if (instance.map or "Unknown") == mapName then
            table.insert(filtered, instance)
        end
    end
    return filtered
end

local function formatViewScopeBar()
    if MBGStatsUI and MBGStatsUI.currentView == "specific" and MBGStatsUI.lastSpecificMap then
        local mapName = MBGStatsUI.lastSpecificMap
        local count = #getInstancesForMap(mapName)
        local view = getViewFilterLabel()
        local cat = getCategoryTabLabel()
        return string.format(
            "|cffFFD700View:|r |cffFFFFFF%s|r — |cffFFD700%s|r |cff888888(%d matches · %s)|r",
            view, mapName, count, cat)
    end
    local view = getViewFilterLabel()
    local count = countViewMatches()
    local cat = getCategoryTabLabel()
    return string.format(
        "|cffFFD700View:|r |cffFFFFFF%s|r |cff888888(%d matches · %s)|r",
        view, count, cat)
end

local function formatRecordingBar()
    if not mbgstats.recordingSeasonId then
        return nil
    end
    local label = getRecordingSeasonLabel()
    if not label then
        return nil
    end
    if mbgstats.currentPartitionFilter == mbgstats.recordingSeasonId then
        return nil
    end
    return string.format(
        "|cff888888New matches save to → |cff00ff00%s|r  |cff666666(not what you are viewing)|r",
        label)
end

local function updateScopeDisplay(totalKills, totalHK, totalHonor, totalWins, totalLosses)
    if not MBGStatsUI then
        return
    end
    if MBGStatsUI.scopeText then
        MBGStatsUI.scopeText:SetText(formatViewScopeBar())
    end
    if MBGStatsUI.recordingText then
        local recordingLine = formatRecordingBar()
        if recordingLine then
            MBGStatsUI.recordingText:SetText(recordingLine)
            MBGStatsUI.recordingText:Show()
            if MBGStatsUI.gloryText then
                MBGStatsUI.gloryText:ClearAllPoints()
                MBGStatsUI.gloryText:SetPoint("TOP", MBGStatsUI.recordingText, "BOTTOM", 0, -4)
            end
        else
            MBGStatsUI.recordingText:Hide()
            if MBGStatsUI.gloryText then
                MBGStatsUI.gloryText:ClearAllPoints()
                MBGStatsUI.gloryText:SetPoint("TOP", MBGStatsUI.scopeText, "BOTTOM", 0, -4)
            end
        end
    end
    if MBGStatsUI.overallText then
        MBGStatsUI.overallText:SetText(string.format(
            "KB: %d | HK: %d | Honor: %d | W: %d | L: %d",
            totalKills, totalHK, totalHonor, totalWins, totalLosses))
    end
end

local function refreshGloryPanel(instances)
    if not MBGStatsUI then
        return
    end
    instances = instances or {}
    local glory = computeGloryStats(instances)
    if MBGStatsUI.gloryText then
        local ok, summary = pcall(formatGlorySummary, glory, instances)
        if ok then
            MBGStatsUI.gloryText:SetText(summary)
        else
            MBGStatsUI.gloryText:SetText("|cffffd700Glory:|r (summary unavailable)")
            print("|cff00ff00[SmartPVP]|r Glory summary error: " .. tostring(summary))
        end
    end
    local totalKills, totalHonor, totalWins, totalLosses, totalHK = 0, 0, 0, 0, 0
    for _, instance in ipairs(instances) do
        totalKills = totalKills + (instance.kb or instance.kills or 0)
        totalHonor = totalHonor + (instance.honor or 0)
        totalWins = totalWins + (instance.wins or 0)
        totalLosses = totalLosses + (instance.losses or 0)
        totalHK = totalHK + (instance.hk or 0)
    end
    updateScopeDisplay(totalKills, totalHK, totalHonor, totalWins, totalLosses)
end

local function showAllDataView()
    clearViewFilters()
    resetMainViewState()
    if MBGStatsUI and MBGStatsUI.updateFilterButtonStates then
        MBGStatsUI.updateFilterButtonStates()
    end
    mbgstats.refreshFightRecordUI()
end

-- Toggle partition active status
local function togglePartitionActive(partitionId)
    if mbgstatsDB_Partitions[partitionId] then
        mbgstatsDB_Partitions[partitionId].active = not mbgstatsDB_Partitions[partitionId].active
    end
end

-- Delete partition and clean up all references
local function deletePartition(partitionId)
    if not mbgstatsDB_Partitions[partitionId] then
        return false
    end
    
    -- Remove all instance assignments for this partition
    for instanceId, assignedPartitionId in pairs(mbgstatsDB_InstancePartitions) do
        if assignedPartitionId == partitionId then
            mbgstatsDB_InstancePartitions[instanceId] = nil
        end
    end
    
    -- Remove the partition
    mbgstatsDB_Partitions[partitionId] = nil
    
    -- Clear current filter if it was the deleted partition
    if mbgstats.currentPartitionFilter == partitionId then
        mbgstats.currentPartitionFilter = nil
    end
    if mbgstats.recordingSeasonId == partitionId then
        mbgstats.recordingSeasonId = nil
        mbgstatsDB_RecordingSeasonId = nil
    end
    
    return true
end

-- ============================
-- Result Confirmation System
-- ============================

-- Process confirmed match result and update statistics
mbgstats.ConfirmResult = function(result)
    local session = mbgstats.battlegroundSession
    if not battlegroundSessionIsActive(session) then
        return
    end

    -- Update session statistics based on result
    if result == "alliance" then
        session.wins = session.wins + 1
        session.allianceWins = (session.allianceWins or 0) + 1
    elseif result == "horde" then
        session.wins = session.wins + 1
        session.hordeWins = (session.hordeWins or 0) + 1
    elseif result == "loss_alliance" then
        session.losses = session.losses + 1
        session.hordeWins = (session.hordeWins or 0) + 1
    elseif result == "loss_horde" then
        session.losses = session.losses + 1
        session.allianceWins = (session.allianceWins or 0) + 1
    elseif result == "forfeit" then
        session.losses = session.losses + 1
        session._forfeits = (session._forfeits or 0) + 1
    end

    mergeSessionRecord(session, mbgstats.currentMap, true)

    print(string.format("[SmartPVP] Result written: %s (%s)", mbgstats.currentMap, result))
    mbgstats.currentMap = nil
    mbgstats.suggestedResult = nil
    mbgstats.inBG = false
    mbgstats.finalizeScheduled = false
    mbgstats.refreshFightRecordUI()
end

-- ============================
-- Milestones (Release 3)
-- ============================

local function getRecentWinStreak()
    local streak = 0
    for i = #mbgstatsDB_Instances, 1, -1 do
        local inst = mbgstatsDB_Instances[i]
        if (inst.wins or 0) > 0 then
            streak = streak + 1
        elseif (inst.losses or 0) > 0 or (inst._forfeits or 0) > 0 then
            break
        end
    end
    return streak
end

mbgstats.evaluateMilestones = function(instance)
    if not instance then
        return
    end
    local kb = instance.kb or instance.kills or 0
    local unlocks = {}

    if kb >= 1 and not mbgstatsDB_Milestones.first_blood then
        mbgstatsDB_Milestones.first_blood = time()
        table.insert(unlocks, "First Blood")
    end
    if kb >= 3 and not mbgstatsDB_Milestones.hat_trick then
        mbgstatsDB_Milestones.hat_trick = time()
        table.insert(unlocks, "Hat Trick")
    end
    if kb >= 5 and not mbgstatsDB_Milestones.dominant_game then
        mbgstatsDB_Milestones.dominant_game = time()
        table.insert(unlocks, "Dominant Game")
    end
    if getRecentWinStreak() >= 3 and not mbgstatsDB_Milestones.win_streak then
        mbgstatsDB_Milestones.win_streak = time()
        table.insert(unlocks, "Win Streak")
    end

    for _, name in ipairs(unlocks) do
        print(string.format("|cff00ff00[SmartPVP]|r Milestone unlocked: |cffffd700%s|r", name))
    end
    if #unlocks > 0 then
        mbgstats.lastMilestoneUnlock = unlocks[#unlocks]
    end
end

-- ============================
-- Battlefield Score API Functions
-- ============================

-- Read data from Battlefield Score APIs (more accurate than chat parsing)
local function recordBattlefieldStats()
    if not battlegroundSessionIsActive() then
        return
    end
    
    local session = mbgstats.battlegroundSession
    local totalPlayers = GetNumBattlefieldScores()
    
    if totalPlayers == 0 then
        return  -- Scoreboard not available yet
    end
    
    local playerName = UnitName("player")
    local foundPlayer = false
    
    -- Iterate through all players on the scoreboard
    for i = 1, totalPlayers do
        local name, kb, hk, deaths, honor, faction, rank, race, class, classEnglish, damage, healing = GetBattlefieldScore(i)
        
        if name == playerName then
            foundPlayer = true
            
            -- Update session with scoreboard data (more accurate than chat parsing)
            if kb then 
                session.kb = kb
                session.kills = kb  -- Use API killing blows as primary kill count (matches scoreboard)
                session.killsFromAPI = true  -- Flag that API has provided kills (KB)
            end
            if hk then 
                session.hk = hk  -- Track honorable kills separately
            end
            if deaths then 
                session.deaths = deaths  -- Override chat-based deaths with scoreboard
                session.deathsFromAPI = true  -- Flag that API has provided deaths
            end
            if honor then 
                -- API honor is bonus honor (from objectives, win bonus, etc.)
                -- Total honor = bonus honor (from API) + honor from kills
                session.bonusHonor = honor
                local honorFromKills = session.honorFromKills or 0
                session.honor = honor + honorFromKills  -- Total honor = bonus + kills
                session.honorFromAPI = true  -- Flag that API has provided bonus honor
            end
            if faction ~= nil then session.playerFaction = faction end  -- 0 = Horde, 1 = Alliance
            if damage then session.damage = damage end
            if healing then session.healing = healing end
            
            -- Record objective-specific stats (flag captures, bases held, etc.)
            if GetNumBattlefieldStats and GetBattlefieldStatData and GetBattlefieldStatInfo then
                local numStats = GetNumBattlefieldStats()
                if numStats and numStats > 0 then
                    local objectives = {}
                    for j = 1, numStats do
                        local score = GetBattlefieldStatData(i, j)
                        if score and score > 0 then
                            local text, icon = GetBattlefieldStatInfo(j)
                            if text then
                                local objective = {
                                    score = score,
                                    text = text,
                                }
                                if icon then
                                    objective.icon = icon .. (faction or 0)
                                end
                                table.insert(objectives, objective)
                            end
                        end
                    end
                    if #objectives > 0 then
                        session.objectives = objectives
                    end
                end
            end
            
            break  -- Found player, no need to continue
        end
    end
    
    -- Get winner faction from API (NovaInstanceTracker: 0 = Horde, 1 = Alliance)
    local winner = GetBattlefieldWinner and GetBattlefieldWinner()
    if winner == 0 then
        session.winningFaction = 0
    elseif winner == 1 then
        session.winningFaction = 1
    end
end

local function tryLeaveInstancedPvP(source)
    if not battlegroundSessionIsActive() then
        mbgstats.inBG = false
        return
    end
    if isInstancedPvP() then
        return
    end
    if isResultPopupWaiting() then
        return
    end
    mbgstats.inBG = false
    pcall(recordBattlefieldStats)
    local ok, err = pcall(endBGSession)
    if not ok then
        print("|cffff0000[SmartPVP]|r endBGSession error: " .. tostring(err))
        local map = mbgstats.currentMap or mbgstats.battlegroundSession.map
        saveActiveBattlegroundSession(map, "(endBGSession error fallback)")
    elseif battlegroundSessionIsActive() and not isResultPopupWaiting() then
        mbgSessionLog("Leave pending — still saving (" .. tostring(source) .. ")")
    end
end

local function scheduleSessionFinalize(reason)
    if not battlegroundSessionIsActive() then
        return
    end
    if isResultPopupWaiting() then
        return
    end
    if mbgstats.finalizeScheduled then
        return
    end
    mbgstats.finalizeScheduled = true
    local delays = {0.5, 2, 6}
    for _, delay in ipairs(delays) do
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                if isResultPopupWaiting() then
                    return
                end
                if battlegroundSessionIsActive() and not isInstancedPvP() then
                    tryLeaveInstancedPvP(reason .. "+" .. delay .. "s")
                end
            end)
        end
    end
    if not IsInInstance() and not isInstancedPvP() then
        tryLeaveInstancedPvP(reason)
    end
end

local function tryEnterInstancedPvP(source, isRecheck)
    if MBG_WPVP_ENABLED and mbgstats.inWPvP then
        endWPvPSession(true, true)
    end
    if battlegroundSessionIsActive() and not isInstancedPvP() then
        tryLeaveInstancedPvP("enter-cleanup")
        return
    end
    local kind = getPvPInstanceKind()
    if not kind then
        if not isRecheck then
            local inInstance, instanceType = IsInInstance()
            if inInstance and (instanceType == "pvp" or instanceType == "arena") then
                if C_Timer and C_Timer.After then
                    C_Timer.After(2, function()
                        tryEnterInstancedPvP("recheck", true)
                    end)
                end
            end
        end
        return
    end
    if battlegroundSessionIsActive() then
        mbgstats.inBG = true
        return
    end
    local ok, err = pcall(startBGSession, kind)
    if not ok then
        mbgstats.inBG = false
        print("|cffff0000[SmartPVP]|r Failed to start session: " .. tostring(err))
        return
    end
    mbgstats.inBG = true
    mbgstats.bfWasActive = true
    mbgSessionLog("Entered:", mbgstats.currentMap or "?", "(" .. kind .. ", " .. tostring(source) .. ")")
end

local function trackBattlefieldStatus()
    if not GetMaxBattlefieldID or not GetBattlefieldStatus then
        return
    end
    local anyActive = false
    for i = 1, GetMaxBattlefieldID() do
        if GetBattlefieldStatus(i) == "active" then
            anyActive = true
            if not battlegroundSessionIsActive() then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.5, function()
                        tryEnterInstancedPvP("bfstatus", false)
                    end)
                else
                    tryEnterInstancedPvP("bfstatus", false)
                end
            end
            break
        end
    end
    if mbgstats.bfWasActive and not anyActive and battlegroundSessionIsActive() then
        scheduleSessionFinalize("bf-ended")
    end
    mbgstats.bfWasActive = anyActive
end

-- ============================
-- Event System Setup
-- ============================

-- Create main event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Hook scoreboard frame show for older expansions (when UPDATE_BATTLEFIELD_SCORE may not fire reliably)
-- This ensures we capture data when the scoreboard is manually opened
if WorldStateScoreFrame_OnShow then
    hooksecurefunc("WorldStateScoreFrame_OnShow", function()
        if battlegroundSessionIsActive() then
            recordBattlefieldStats()
        end
    end)
end

-- ============================
-- Result Confirmation Popup UI
-- ============================

local function formatPopupSummaryLine(session)
    if not session then
        return "Fight record loading..."
    end
    local mapName = session.map or "Unknown"
    local kb = session.kb or session.kills or 0
    local duration = formatTime(session.timePlayed or (time() - (session.start or time())))
    local parts = { mapName, string.format("%d KB", kb) }
    if session.objectives then
        for _, obj in ipairs(session.objectives) do
            if obj.score and obj.score > 0 and obj.text then
                table.insert(parts, string.format("%s x%d", obj.text, obj.score))
                break
            end
        end
    end
    if session.damageBySpell then
        local topSpell, topDmg = nil, 0
        for spell, dmg in pairs(session.damageBySpell) do
            if dmg > topDmg then
                topSpell, topDmg = spell, dmg
            end
        end
        if topSpell then
            table.insert(parts, "top: " .. topSpell)
        end
    end
    table.insert(parts, duration)
    return table.concat(parts, " — ")
end

local function createConfirmationPopup()
    if MBGResultPopup then 
        return 
    end

    MBGResultPopup = CreateFrame("Frame", "MBGResultPopup", UIParent, "BackdropTemplate")
    MBGResultPopup:SetSize(320, 260)
    MBGResultPopup:SetPoint("CENTER")
    applyMBGDialogTheme(MBGResultPopup)
    MBGResultPopup:Hide()

    MBGResultPopup.selectedResult = nil
    MBGResultPopup.selectedFaction = nil

    -- Helper function to update button visual state
    local function setButtonSelected(button, selected)
        if selected then
            button:SetNormalFontObject("GameFontHighlightLarge")
        else
            button:SetNormalFontObject("GameFontNormal")
        end
    end

    -- Create title
    local title = MBGResultPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Confirm Battleground Result")

    -- Post-match summary (Release 3)
    local summaryText = MBGResultPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetPoint("TOP", 0, -58)
    summaryText:SetWidth(280)
    summaryText:SetJustifyH("CENTER")
    summaryText:SetTextColor(1, 0.84, 0)
    MBGResultPopup.summaryText = summaryText

    -- Section Title: Map Result
    local resultLabel = MBGResultPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultLabel:SetPoint("TOP", 0, -88)
    resultLabel:SetText("Map Result")

    -- Win/Loss buttons
    local winButton = CreateFrame("Button", nil, MBGResultPopup, "UIPanelButtonTemplate")
    winButton:SetSize(80, 30)
    winButton:SetPoint("TOPLEFT", 30, -118)
    winButton:SetText("Win")

    local lossButton = CreateFrame("Button", nil, MBGResultPopup, "UIPanelButtonTemplate")
    lossButton:SetSize(80, 30)
    lossButton:SetPoint("TOPRIGHT", -30, -118)
    lossButton:SetText("Loss")

    -- Section Title: Faction Played
    local factionLabel = MBGResultPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    factionLabel:SetPoint("TOP", 0, -158)
    factionLabel:SetText("Faction Played")

    -- Alliance/Horde buttons
    local allianceButton = CreateFrame("Button", nil, MBGResultPopup, "UIPanelButtonTemplate")
    allianceButton:SetSize(80, 30)
    allianceButton:SetPoint("TOPLEFT", 30, -188)
    allianceButton:SetText("Alliance")

    local hordeButton = CreateFrame("Button", nil, MBGResultPopup, "UIPanelButtonTemplate")
    hordeButton:SetSize(80, 30)
    hordeButton:SetPoint("TOPRIGHT", -30, -188)
    hordeButton:SetText("Horde")

    -- Button click handlers
    winButton:SetScript("OnClick", function()
        if MBGResultPopup.selectedResult == "win" then
            MBGResultPopup.selectedResult = nil
            setButtonSelected(winButton, false)
        else
            MBGResultPopup.selectedResult = "win"
            setButtonSelected(winButton, true)
            setButtonSelected(lossButton, false)
        end
    end)

    lossButton:SetScript("OnClick", function()
        if MBGResultPopup.selectedResult == "loss" then
            MBGResultPopup.selectedResult = nil
            setButtonSelected(lossButton, false)
        else
            MBGResultPopup.selectedResult = "loss"
            setButtonSelected(lossButton, true)
            setButtonSelected(winButton, false)
        end
    end)

    allianceButton:SetScript("OnClick", function()
        if MBGResultPopup.selectedFaction == "alliance" then
            MBGResultPopup.selectedFaction = nil
            setButtonSelected(allianceButton, false)
        else
            MBGResultPopup.selectedFaction = "alliance"
            setButtonSelected(allianceButton, true)
            setButtonSelected(hordeButton, false)
        end
    end)

    hordeButton:SetScript("OnClick", function()
        if MBGResultPopup.selectedFaction == "horde" then
            MBGResultPopup.selectedFaction = nil
            setButtonSelected(hordeButton, false)
        else
            MBGResultPopup.selectedFaction = "horde"
            setButtonSelected(hordeButton, true)
            setButtonSelected(allianceButton, false)
        end
    end)

    -- Confirm button (tooltip explains flex commands — no second "Done" step)
    local confirmButton = CreateFrame("Button", nil, MBGResultPopup, "UIPanelButtonTemplate")
    confirmButton:SetSize(120, 28)
    confirmButton:SetPoint("BOTTOM", 0, 20)
    confirmButton:SetText("Confirm")
    MBGResultPopup.confirmButton = confirmButton

    confirmButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_ABOVE")
        GameTooltip:SetText("After confirming", 1, 1, 1)
        GameTooltip:AddLine("|cff00ff00/mbg last|r — flex this match (Say)", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("|cff00ff00/mbg last party|r — party, guild, etc.", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("|cff00ff00/mbg brag|r — random glory or map line", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    confirmButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    confirmButton:SetScript("OnClick", function()
        local result = MBGResultPopup.selectedResult
        local faction = MBGResultPopup.selectedFaction
        if not result or not faction then
            print("[SmartPVP] You must select both result and faction.")
            return
        end
        if result == "win" then
            mbgstats.ConfirmResult(faction)
        elseif result == "loss" then
            mbgstats.ConfirmResult("loss_" .. faction)
        end
        MBGResultPopup.savedViaConfirm = true
        MBGResultPopup:Hide()
    end)

    -- Function to show confirmation popup
    mbgstats.ShowResultConfirmation = function(suggested, faction)
        createConfirmationPopup()
        if MBGResultPopup:IsShown() then
            return
        end
        MBGResultPopup.selectedResult = nil
        MBGResultPopup.selectedFaction = nil
        MBGResultPopup.savedViaConfirm = false
        setButtonSelected(winButton, false)
        setButtonSelected(lossButton, false)
        setButtonSelected(allianceButton, false)
        setButtonSelected(hordeButton, false)
        if MBGResultPopup.summaryText and mbgstats.battlegroundSession and mbgstats.battlegroundSession.map then
            MBGResultPopup.summaryText:SetText(formatPopupSummaryLine(mbgstats.battlegroundSession))
        elseif MBGResultPopup.summaryText then
            MBGResultPopup.summaryText:SetText("")
        end

        print("[SmartPVP] Suggested outcome: " .. tostring(suggested) .. ", Faction: " .. tostring(faction))

        MBGResultPopup:Show()
    end

    MBGResultPopup:SetScript("OnHide", function()
        if MBGResultPopup.savedViaConfirm then
            MBGResultPopup.savedViaConfirm = false
            return
        end
        if not battlegroundSessionIsActive() then
            return
        end
        local map = mbgstats.currentMap or mbgstats.battlegroundSession.map
        saveActiveBattlegroundSession(map, "(confirmation dismissed)")
    end)
end

-- ============================
-- Partition Management UI
-- ============================

-- Create partition selection dialog
local function createPartitionSelectionDialog()
    if MBGPartitionDialog then 
        return 
    end

    MBGPartitionDialog = CreateFrame("Frame", "MBGPartitionDialog", UIParent, "BackdropTemplate")
    MBGPartitionDialog:SetSize(400, 500)
    MBGPartitionDialog:SetPoint("CENTER")
    applyMBGDialogTheme(MBGPartitionDialog)
    MBGPartitionDialog:SetFrameStrata("HIGH")
    MBGPartitionDialog:Hide()

    -- Title
    local title = MBGPartitionDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Seasons")

    -- Scrollable partition list
    local scrollFrame = CreateFrame("ScrollFrame", nil, MBGPartitionDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 60)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    MBGPartitionDialog.content = content
    MBGPartitionDialog.scrollFrame = scrollFrame

    -- Close button
    local closeButton = CreateFrame("Button", nil, MBGPartitionDialog, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", MBGPartitionDialog, "TOPRIGHT", -5, -5)

    local deleteHint = MBGPartitionDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deleteHint:SetPoint("BOTTOM", 0, 24)
    deleteHint:SetWidth(360)
    deleteHint:SetJustifyH("CENTER")
    deleteHint:SetTextColor(0.75, 0.75, 0.75)
    deleteHint:SetText("Deleting a season does not delete its matches.")

    -- Function to update partition list
    MBGPartitionDialog.UpdatePartitionList = function()
        -- Clear existing content using safe hide pattern
        mbgstats.HideChildren(content)

        local yOffset = 0
        local activePartitions = getActivePartitions()

        -- "All Data" option
        local allDataButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        allDataButton:SetSize(340, 30)
        allDataButton:SetPoint("TOPLEFT", 0, yOffset)
        allDataButton:SetText("All Data")
        allDataButton:SetScript("OnClick", function()
            showAllDataView()
            MBGPartitionDialog:Hide()
        end)
        yOffset = yOffset - 35

        -- Existing seasons
        for _, partition in pairs(mbgstatsDB_Partitions) do
            local partitionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            partitionButton:SetSize(200, 30)
            partitionButton:SetPoint("TOPLEFT", 0, yOffset)
            partitionButton:SetText(string.format("%s (%d matches)", partition.name, partition.instanceCount or 0))
            partitionButton:SetScript("OnClick", function()
                mbgstats.currentPartitionFilter = partition.id
                mbgstats.dateFilter = nil
                resetMainViewState()
                MBGPartitionDialog:Hide()
                if MBGStatsUI and MBGStatsUI.updateFilterButtonStates then
                    MBGStatsUI.updateFilterButtonStates()
                end
                if MBGStatsUI and MBGStatsUI:IsShown() then
                    MBGStatsUI_UpdateList()
                end
            end)
            
            -- Active/Inactive toggle button
            local toggleButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            toggleButton:SetSize(60, 30)
            toggleButton:SetPoint("TOPLEFT", 205, yOffset)
            toggleButton:SetText(partition.active and "Active" or "Inactive")
            toggleButton:SetScript("OnClick", function()
                togglePartitionActive(partition.id)
                toggleButton:SetText(partition.active and "Active" or "Inactive")
                if MBGStatsUI and MBGStatsUI:IsShown() then
                    MBGStatsUI_UpdateList()
                end
            end)
            
            -- Delete button for this partition
            local deleteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            deleteButton:SetSize(50, 30)
            deleteButton:SetPoint("TOPLEFT", 270, yOffset)
            deleteButton:SetText("Delete")
            deleteButton:SetScript("OnClick", function()
                if deletePartition(partition.id) then
                    print(string.format("[SmartPVP] Deleted season: %s", partition.name))
                    MBGPartitionDialog.UpdatePartitionList()
                    if MBGStatsUI and MBGStatsUI:IsShown() then
                        MBGStatsUI_UpdateList()
                    end
                else
                    print("[SmartPVP] Failed to delete season.")
                end
            end)
            
            yOffset = yOffset - 35
        end

        -- Set content height
        content:SetHeight(math.abs(yOffset))
    end

    -- Show function
    MBGPartitionDialog.ShowDialog = function()
        MBGPartitionDialog:Show()
        MBGPartitionDialog.UpdatePartitionList()
    end
end

-- Create season assignment dialog
local function createPartitionAssignmentDialog()
    if MBGPartitionAssignmentDialog then 
        return 
    end

    MBGPartitionAssignmentDialog = CreateFrame("Frame", "MBGPartitionAssignmentDialog", UIParent, "BackdropTemplate")
    MBGPartitionAssignmentDialog:SetSize(400, 300)
    MBGPartitionAssignmentDialog:SetPoint("CENTER")
    applyMBGDialogTheme(MBGPartitionAssignmentDialog)
    MBGPartitionAssignmentDialog:SetFrameStrata("HIGH")
    MBGPartitionAssignmentDialog:Hide()

    local title = MBGPartitionAssignmentDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Assign to Season")

    -- Scrollable partition list
    local scrollFrame = CreateFrame("ScrollFrame", nil, MBGPartitionAssignmentDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 60)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    MBGPartitionAssignmentDialog.content = content
    MBGPartitionAssignmentDialog.scrollFrame = scrollFrame

    -- Close button
    local closeButton = CreateFrame("Button", nil, MBGPartitionAssignmentDialog, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", MBGPartitionAssignmentDialog, "TOPRIGHT", 5, -5)

    -- Function to update partition list for assignment
    MBGPartitionAssignmentDialog.UpdatePartitionList = function(instanceId)
        -- Clear existing content using safe hide pattern
        mbgstats.HideChildren(content)

        local yOffset = 0
        local activePartitions = getActivePartitions()
        local currentPartitionId = getInstancePartition(instanceId)

        -- "Remove from partition" option (if currently assigned)
        if currentPartitionId then
            local removeButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            removeButton:SetSize(340, 30)
            removeButton:SetPoint("TOPLEFT", 0, yOffset)
            removeButton:SetText("Remove from season")
            removeButton:SetScript("OnClick", function()
                removeInstanceFromPartition(instanceId)
                MBGPartitionAssignmentDialog:Hide()
                if MBGStatsUI and MBGStatsUI:IsShown() then
                    MBGStatsUI_UpdateList()
                end
            end)
            yOffset = yOffset - 35
        end

        -- Existing seasons
        for _, partition in pairs(mbgstatsDB_Partitions) do
            local partitionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            partitionButton:SetSize(340, 30)
            partitionButton:SetPoint("TOPLEFT", 0, yOffset)
            local buttonText = partition.name
            if currentPartitionId == partition.id then
                buttonText = buttonText .. " (Current)"
            end
            if not partition.active then
                buttonText = buttonText .. " [Inactive]"
            end
            partitionButton:SetText(buttonText)
            partitionButton:SetScript("OnClick", function()
                assignInstanceToPartition(instanceId, partition.id)
                MBGPartitionAssignmentDialog:Hide()
                if MBGStatsUI and MBGStatsUI:IsShown() then
                    MBGStatsUI_UpdateList()
                end
            end)
            yOffset = yOffset - 35
        end

        -- Set content height
        content:SetHeight(math.abs(yOffset))
    end

    -- Show function
    MBGPartitionAssignmentDialog.ShowDialog = function(instanceId)
        MBGPartitionAssignmentDialog:Show()
        MBGPartitionAssignmentDialog.UpdatePartitionList(instanceId)
    end
end

-- ============================
-- Event Handler
-- ============================

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        mbgSessionLog("v" .. MBG_ADDON_VERSION .. " loaded — type /mbg status to check recording")
        -- Named MBGStatsUI frame survives /reload; lua callbacks and child refs do not
        if MBGStatsUI and not MBGStatsUI_UpdateList then
            MBGStatsUI.__mbgBuildVersion = nil
        end
        startPlaySession()
        createConfirmationPopup()
        createPartitionSelectionDialog()
        createPartitionAssignmentDialog()
        -- Legacy: New Season used to switch the view filter (looked like data loss)
        if mbgstats.currentPartitionFilter and not mbgstatsDB_RecordingSeasonId then
            setRecordingSeason(mbgstats.currentPartitionFilter)
            showAllDataView()
            print("[SmartPVP] View reset to All Data — your matches were never deleted.")
        end
        if MBG_WPVP_ENABLED and C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(30, function()
                if mbgstats.inWPvP and mbgstats.wpvpSession and mbgstats.wpvpSession.lastCombatTime then
                    if (time() - mbgstats.wpvpSession.lastCombatTime) >= WPVP_IDLE_SECONDS then
                        endWPvPSession(true, true)
                    end
                end
            end)
        end
        if battlegroundSessionIsActive() and not isInstancedPvP() then
            mbgSessionLog("Recovering stuck session from last match...")
            if C_Timer and C_Timer.After then
                C_Timer.After(2, function()
                    tryLeaveInstancedPvP("login-stuck")
                end)
            else
                tryLeaveInstancedPvP("login-stuck")
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        endPlaySession()
        if MBG_WPVP_ENABLED then
            endWPvPSession(true, true)
        end
        if battlegroundSessionIsActive() then
            tryLeaveInstancedPvP("logout")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, isReload = ...
        if MBG_WPVP_ENABLED and mbgstats.inWPvP then
            endWPvPSession(true, true)
        end
        if IsInInstance() then
            local source = isReload and "reload" or "enter"
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, function()
                    if IsInInstance() then
                        tryEnterInstancedPvP(source, false)
                    end
                end)
            else
                tryEnterInstancedPvP(source, false)
            end
        end
        if battlegroundSessionIsActive() and not isInstancedPvP() then
            scheduleSessionFinalize(isReload and "reload" or "left")
        end
    
    elseif event == "PLAYER_LEAVING_WORLD" then
        if battlegroundSessionIsActive() then
            pcall(recordBattlefieldStats)
            scheduleSessionFinalize("leaving")
        end

    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        trackBattlefieldStatus()

    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        recordBattlefieldStats()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if MBG_WPVP_ENABLED and mbgstats.inWPvP and mbgstats.wpvpSession then
            local zone = getOpenWorldZoneName()
            if zone ~= mbgstats.wpvpSession.map and wpvpSessionHasActivity(mbgstats.wpvpSession) then
                endWPvPSession(true, true)
            elseif zone ~= mbgstats.wpvpSession.map then
                mbgstats.wpvpSession.map = zone
                mbgstats.wpvpSession.zoneName = zone
            end
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local combatLogData = {CombatLogGetCurrentEventInfo()}
        if MBG_WPVP_ENABLED and not mbgstats.inBG then
            handleWPvPCombatLogEvent(combatLogData)
        end
        if mbgstats.battlegroundSession and mbgstats.currentMap and mbgstats.inBG then
            local session = mbgstats.battlegroundSession
            local subevent = combatLogData[2]
            local sourceName = combatLogData[5]

            if sourceName and UnitIsUnit(sourceName, "player") then
                recordPlayerKillingBlowFromCombatLog(session, subevent, combatLogData)

                local amount = nil
                local spellName = nil

                if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
                    spellName = combatLogData[13]
                    amount = combatLogData[15]
                elseif subevent == "SWING_DAMAGE" then
                    spellName = "Melee"
                    amount = combatLogData[12]
                elseif subevent == "RANGE_DAMAGE" then
                    spellName = "Ranged"
                    amount = combatLogData[12]
                elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
                    spellName = combatLogData[13]
                    amount = combatLogData[15]
                    if amount and amount > 0 then
                        session.healing = (session.healing or 0) + amount
                        session.healBySpell = session.healBySpell or {}
                        session.healBySpell[spellName] = (session.healBySpell[spellName] or 0) + amount
                    end
                end

                if amount and amount > 0 and spellName then
                    session.damageBySpell = session.damageBySpell or {}
                    session.damageBySpell[spellName] = (session.damageBySpell[spellName] or 0) + amount
                end
            end
        end

    elseif event == "PLAYER_DEAD" then
        if MBG_WPVP_ENABLED and mbgstats.inWPvP and mbgstats.wpvpSession then
            mbgstats.wpvpSession.deaths = (mbgstats.wpvpSession.deaths or 0) + 1
            mbgstats.wpvpSession.lastCombatTime = time()
        elseif mbgstats.battlegroundSession and mbgstats.currentMap then
            local session = mbgstats.battlegroundSession
            if not session.deathsFromAPI then
                session.deaths = (session.deaths or 0) + 1
            end
        end

    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local message = ...
        local honor = tonumber(string.match(message, "(%d+)%s+honor"))
        if not honor then
            return
        end
        if MBG_WPVP_ENABLED and mbgstats.inWPvP and mbgstats.wpvpSession then
            mbgstats.wpvpSession.honor = (mbgstats.wpvpSession.honor or 0) + honor
            mbgstats.wpvpSession.lastCombatTime = time()
            return
        end
        if not mbgstats.battlegroundSession or not mbgstats.currentMap then
            return
        end
        local session = mbgstats.battlegroundSession
        session.honorFromKills = (session.honorFromKills or 0) + honor
        if session.honorFromAPI then
            session.honor = (session.bonusHonor or 0) + session.honorFromKills
        else
            session.honor = session.honorFromKills
        end

    elseif event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
        if not mbgstats.battlegroundSession or not mbgstats.currentMap then
            return
        end
        local session = mbgstats.battlegroundSession
        local message = ...
        if message:find("slain") or message:find("killed") then
            if not session.killsFromAPI then
                session.kills = (session.kills or 0) + 1
            end
        end

    elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        if not mbgstats.battlegroundSession or not mbgstats.currentMap then
            return
        end
        local message = ...
        if message:find("wins") then
            if not mbgstats.suggestedResult or mbgstats.suggestedResult == "unknown" then
                if message:find("Alliance") then
                    mbgstats.suggestedResult = "alliance"
                elseif message:find("Horde") then
                    mbgstats.suggestedResult = "horde"
                end
            end
        end
    end
end)

-- ============================
-- Flex Chat Pipeline (Release 1)
-- ============================

local MBG_FLEX_CHANNEL_ALIASES = {
    ["s"] = "SAY",
    ["p"] = "PARTY",
    ["y"] = "YELL",
    ["r"] = "RAID",
    ["i"] = "INSTANCE",
    ["g"] = "GUILD",
    ["rw"] = "RAIDWARNING",
    ["say"] = "SAY",
    ["party"] = "PARTY",
    ["yell"] = "YELL",
    ["raid"] = "RAID",
    ["instance"] = "INSTANCE",
    ["guild"] = "GUILD",
    ["raidwarning"] = "RAIDWARNING",
}

local BRAG_TEMPLATES_KILLS = {
    "[SmartPVP] I NAE NAE'd ON %d bodies in %s. No revives.",
    "[SmartPVP] Dropped the DEUCE on %d fools in %s. Don't test me.",
    "[SmartPVP] They tried and failed to slay me. %d times. %s remembers.",
    "[SmartPVP] %d slayed in the slaughterhouse. %s saw that many souls claimed.",
    "[SmartPVP] %d confirmed deletions in %s. Stay back.",
    "[SmartPVP] %d bodies dropped in %s. Certified wipe.",
    "[SmartPVP] %d fools deleted in %s. Don't test me.",
    "[SmartPVP] %d slays logged in %s. Spirit healers working overtime.",
    "[SmartPVP] %d kills in %s. That graveyard belongs to me.",
    "[SmartPVP] %d souls claimed in %s. I am inevitable.",
    "[SmartPVP] %d souls educated in %s. They call me the teacher.",
    "[SmartPVP] %d players got the business in %s. I'm the CEO of violence.",
    "[SmartPVP] %d eliminations in %s. I'm basically Thanos with better stats.",
    "[SmartPVP] %d bodies hit the floor in %s. I'm the DJ of destruction.",
    "[SmartPVP] %d souls sent to timeout in %s. I'm the principal of pain.",
    "[SmartPVP] %d players learned respect in %s. The hard way.",
    "[SmartPVP] %d eliminations in %s. I'm the grim reaper's favorite customer.",
    "[SmartPVP] %d bodies stacked in %s. I'm building a monument to my greatness.",
    "[SmartPVP] %d players deleted in %s. I'm the system administrator of death.",
    "[SmartPVP] %d souls rekt in %s. I'm the destroyer of worlds, one kill at a time.",
    "[SmartPVP] %d eliminations in %s. I'm the final boss, and you're just the tutorial.",
}

local BRAG_TEMPLATES_WINS = {
    "[SmartPVP] Triumphed %d times in %s. I am inevitable.",
    "[SmartPVP] Victory tastes like sweet iced cream after %d flawless wins in %s.",
    "[SmartPVP] They never stood a chance. %d wins in %s.",
    "[SmartPVP] %d bent the knee in %s. Pathetic knaves!",
    "[SmartPVP] Ain't no stopping me—%d wins in %s. I am GOATED with the sauce",
    "[SmartPVP] %d wins secured in %s. I don't lose—I log data.",
    "[SmartPVP] %d victories in %s. I'm what balance patches fear.",
    "[SmartPVP] %d triumphs recorded in %s. My scoreboard's allergic to Ls.",
    "[SmartPVP] %d wins in %s was enough to win over ya moms!",
    "[SmartPVP] %d Ws collected in %s. I'm the undefeated champion of champions.",
    "[SmartPVP] %d victories in %s. I make winning look easy, because it is.",
    "[SmartPVP] %d wins in %s. I'm basically the Michael Jordan of battlegrounds.",
    "[SmartPVP] %d triumphs in %s. My win rate is so high, it's basically cheating.",
    "[SmartPVP] %d wins secured in %s. I'm the main character, everyone else is NPCs.",
    "[SmartPVP] %d victories logged in %s. I don't just win, I dominate.",
    "[SmartPVP] %d wins in %s. I'm the undefeated legend, the myth, the GOAT.",
    "[SmartPVP] %d victories in %s. I'm so good at winning, I should teach a class.",
    "[SmartPVP] %d wins secured in %s. I'm the victory machine, and you're the fuel.",
    "[SmartPVP] %d triumphs in %s. I don't just collect wins, I curate them.",
    "[SmartPVP] %d wins in %s. I'm the undefeated king, and this is my kingdom.",
}

local BRAG_TEMPLATES_HONOR = {
    "[SmartPVP] Walked out with %d honor in %s. Glorious.",
    "[SmartPVP] Did poi flow movements before it was cool. Earned %d honor in %s.",
    "[SmartPVP] The fools were generous—%d honor richer from %s.",
    "[SmartPVP] Medals? Try %d honor in %s.",
    "[SmartPVP] Danced to cotton-eyed joe while making eye contact with your girl. %d honor farmed in %s.",
    "[SmartPVP] %d honor earned in %s. I accept tribute in tears.",
    "[SmartPVP] %d honors collected in %s. I farm players like herbs.",
    "[SmartPVP] %d reasons to uninstall found in %s. All honorable.",
    "[SmartPVP] %d honor points in %s. I'm basically a walking ATM for honor.",
    "[SmartPVP] %d honor collected in %s. I'm the honor farmer supreme.",
    "[SmartPVP] %d honor points in %s. I make honor farming look like an art form.",
    "[SmartPVP] %d honor earned in %s. I'm the honor king, bow down peasants.",
    "[SmartPVP] %d honor points in %s. I don't just earn honor, I harvest it.",
    "[SmartPVP] %d honor collected in %s. I'm the honor collector, and you're the collection.",
    "[SmartPVP] %d honor points in %s. I'm the honor billionaire, and you're still broke.",
    "[SmartPVP] %d honor earned in %s. I'm the honor wizard, turning players into points.",
    "[SmartPVP] %d honor collected in %s. I'm the honor magnet, and you're just metal.",
    "[SmartPVP] %d honor points in %s. I'm the honor factory, and business is booming.",
    "[SmartPVP] %d honor earned in %s. I'm the honor deity, and you're just a believer.",
}

local function parseFlexChannel(subcommandTail)
    local param = subcommandTail and strtrim(subcommandTail) or ""
    if param ~= "" then
        local channel = MBG_FLEX_CHANNEL_ALIASES[string.lower(param)]
        if channel then
            return channel
        end
    end
    return "SAY"
end

local function sendFlexMessage(text, channel)
    if not text or text == "" then
        return false
    end
    SendChatMessage(text, channel)
    return true
end

local function formatMapStatBragLine(mapName, stats)
    if not stats or not mapName then
        return nil
    end
    local kills = stats.kb or stats.kills or 0
    local statTypes = {}
    if kills > 0 then table.insert(statTypes, "kills") end
    if (stats.wins or 0) > 0 then table.insert(statTypes, "wins") end
    if (stats.honor or 0) > 0 then table.insert(statTypes, "honor") end
    if #statTypes == 0 then
        return nil
    end
    local stat = statTypes[math.random(#statTypes)]
    local value = stat == "kills" and kills or stats[stat]
    local templates = stat == "kills" and BRAG_TEMPLATES_KILLS
        or stat == "wins" and BRAG_TEMPLATES_WINS
        or BRAG_TEMPLATES_HONOR
    return string.format(templates[math.random(#templates)], value, mapName)
end

local function getGloryInstancesForBrag()
    local instances = getInstancesByPartition(mbgstats.currentPartitionFilter)
    if #instances == 0 then
        instances = getAllDataInstancesForGlory()
    end
    return instances
end

local function buildGloryBragCandidates(glory, filterLabel)
    local candidates = {}
    if glory.wins + glory.losses > 0 then
        local winRate, record = formatGloryWinRate(glory)
        table.insert(candidates, string.format(
            "[SmartPVP] %s win rate (%s) in %s. Horde still queues. I don't know why.",
            winRate, record, filterLabel))
        table.insert(candidates, string.format(
            "[SmartPVP] %s (%s) in %s. The fight record speaks for itself.",
            winRate, record, filterLabel))
    end
    if glory.games > 0 and glory.totalKB > 0 then
        local kbPerGame = string.format("%.1f", glory.totalKB / glory.games)
        table.insert(candidates, string.format(
            "[SmartPVP] %s KB per game in %s. Spirit healers know my name.",
            kbPerGame, filterLabel))
    end
    if glory.games > 0 and glory.totalHealing > 0 then
        local healPerGame = commaValue(math.floor(glory.totalHealing / glory.games))
        table.insert(candidates, string.format(
            "[SmartPVP] %s healing per game in %s. I keep you alive; you keep feeding.",
            healPerGame, filterLabel))
    end
    if glory.topClass and glory.topClassCount > 0 then
        table.insert(candidates, string.format(
            "[SmartPVP] Top prey: %ss. %d confirmed in %s. They keep queuing anyway.",
            glory.topClass, glory.topClassCount, filterLabel))
        table.insert(candidates, string.format(
            "[SmartPVP] %d %s souls educated in %s. Certified farmer.",
            glory.topClassCount, glory.topClass, filterLabel))
    end
    if glory.bestMatch and glory.bestKB > 0 then
        table.insert(candidates, string.format(
            "[SmartPVP] Best fight: %d KB in one %s. That row lives in my fight record.",
            glory.bestKB, glory.bestMatch.map or "Unknown"))
        table.insert(candidates, string.format(
            "[SmartPVP] %d KB in a single %s. I didn't peek—I deleted.",
            glory.bestKB, glory.bestMatch.map or "Unknown"))
    end
    if glory.bestHealMatch and glory.bestHealing > 0 then
        table.insert(candidates, string.format(
            "[SmartPVP] Most healing: %s in one %s. You're welcome.",
            commaValue(glory.bestHealing), glory.bestHealMatch.map or "Unknown"))
    end
    return candidates
end

local function formatBragLine()
    local candidates = {}
    local filterLabel = getFilterLabel()
    local glory = computeGloryStats(getGloryInstancesForBrag())
    for _, line in ipairs(buildGloryBragCandidates(glory, filterLabel)) do
        table.insert(candidates, line)
    end
    local mapList = {}
    for map, stats in pairs(mbgstatsDB) do
        local kills = stats.kb or stats.kills or 0
        if kills > 0 or (stats.wins or 0) > 0 or (stats.honor or 0) > 0 then
            table.insert(mapList, { name = map, stats = stats })
        end
    end
    if #mapList > 0 then
        local selected = mapList[math.random(#mapList)]
        local mapLine = formatMapStatBragLine(selected.name, selected.stats)
        if mapLine then
            table.insert(candidates, mapLine)
        end
    end
    for i = #mbgstatsDB_Instances, 1, -1 do
        local inst = mbgstatsDB_Instances[i]
        if MBG_WPVP_ENABLED and getInstanceType(inst) == "wpvp" then
            local label = inst.customName or inst.map or "Open World"
            local kb = inst.kb or inst.kills or 0
            if kb > 0 then
                table.insert(candidates, string.format(
                    "[SmartPVP] %d KB in %s. Open world doesn't hide from MBG.",
                    kb, label))
            end
            break
        end
    end
    if mbgstats.lastMilestoneUnlock then
        table.insert(candidates, string.format(
            "[SmartPVP] Just unlocked: %s. Fight record keeps receipts.",
            mbgstats.lastMilestoneUnlock))
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(#candidates)]
end

local function formatWinLine()
    local glory = computeGloryStats(getAllDataInstancesForGlory())
    if glory.wins + glory.losses == 0 then
        return nil
    end
    local winRate, record = formatGloryWinRate(glory)
    return string.format("[SmartPVP] Win Rate: %s (%s)", winRate, record)
end

local function resolveMapStatsForName(mapName)
    if not mapName or mapName == "" then
        return nil, nil
    end
    if mbgstatsDB[mapName] then
        return mapName, mbgstatsDB[mapName]
    end
    local lower = mapName:lower()
    for key, stats in pairs(mbgstatsDB) do
        if key:lower() == lower then
            return key, stats
        end
    end
    return mapName, nil
end

local function getCurrentMapForFlex()
    if mbgstats.currentMap and mbgstats.currentMap ~= "Unknown" then
        return mbgstats.currentMap
    end
    return getCurrentMapName()
end

local function formatHereLine()
    local mapName = getCurrentMapForFlex()
    local resolvedName, stats = resolveMapStatsForName(mapName)
    if not stats then
        return nil, string.format("[SmartPVP] No MBG stats for %s yet. Go make some.", mapName or "this map")
    end
    local line = formatMapStatBragLine(resolvedName, stats)
    if not line then
        return nil, string.format("[SmartPVP] No MBG stats for %s yet. Go make some.", resolvedName)
    end
    return line
end

local function getTopObjectiveLabel(instance)
    if not instance.objectives or #instance.objectives == 0 then
        return nil
    end
    local best = instance.objectives[1]
    for _, obj in ipairs(instance.objectives) do
        if (obj.score or 0) > (best.score or 0) then
            best = obj
        end
    end
    if best and best.score and best.score > 0 and best.text then
        return string.format("%s x%d", best.text, best.score)
    end
    return nil
end

local function getMostRecentInstance()
    if mbgstats.lastConfirmedInstanceId then
        for i = #mbgstatsDB_Instances, 1, -1 do
            local instance = mbgstatsDB_Instances[i]
            if instance.id == mbgstats.lastConfirmedInstanceId then
                return instance
            end
        end
    end
    if #mbgstatsDB_Instances == 0 then
        return nil
    end
    local best = mbgstatsDB_Instances[#mbgstatsDB_Instances]
    for _, instance in ipairs(mbgstatsDB_Instances) do
        if (instance.id or 0) > (best.id or 0) then
            best = instance
        end
    end
    return best
end

local LAST_LINES_WIN = {
    "[SmartPVP] %s · %s · %d KB · %s · %s. Just happened. Fight record updated.",
    "[SmartPVP] %s · %s · %d KB · %s · %s. Fresh W. MBG doesn't lie.",
    "[SmartPVP] %s · %s · %d KB · %s · %s. Another one for the books.",
}

local LAST_LINES_LOSS = {
    "[SmartPVP] %s · %s · %d KB · %s · %s. We'll run it back.",
    "[SmartPVP] %s · %s · %d KB · %s · %s. MBG logged the receipt.",
}

local LAST_LINES_FORFEIT = {
    "[SmartPVP] %s · %s · %d KB · %s. Left early. Still logged.",
    "[SmartPVP] Forfeit in %s — %s on the clock. I'll be back.",
}

local function formatLastLine(instance)
    if not instance then
        return nil
    end
    local resultCode = getInstanceResult(instance)
    local mapName = instance.customName or instance.map or "Unknown"
    if instance.customName and instance.zoneName and instance.zoneName ~= instance.customName then
        mapName = instance.customName .. " (" .. instance.zoneName .. ")"
    end
    local kb = instance.kb or instance.kills or 0
    local duration = formatTime(instance.timePlayed or 0)
    local extras = {}
    local objective = getTopObjectiveLabel(instance)
    if objective then
        table.insert(extras, objective)
    end
    if (instance.honor or 0) > 0 then
        table.insert(extras, string.format("%d honor", instance.honor))
    end
    local extraText = #extras > 0 and table.concat(extras, ", ") or "no extras"
    if resultCode == "F" then
        return string.format(LAST_LINES_FORFEIT[math.random(#LAST_LINES_FORFEIT)],
            resultCode, mapName, kb, duration)
    elseif resultCode == "W" then
        return string.format(LAST_LINES_WIN[math.random(#LAST_LINES_WIN)],
            resultCode, mapName, kb, extraText, duration)
    elseif resultCode == "L" then
        return string.format(LAST_LINES_LOSS[math.random(#LAST_LINES_LOSS)],
            resultCode, mapName, kb, extraText, duration)
    end
    return string.format(
        "[SmartPVP] %s · %s · %d KB · %s · %s.",
        resultCode, mapName, kb, extraText, duration)
end

local function runFlexCommand(buildLine, subcommandTail, emptyMessage)
    local channel = parseFlexChannel(subcommandTail)
    local line, localMessage = buildLine()
    if localMessage then
        print(localMessage)
        return
    end
    if not line then
        print(emptyMessage or "[SmartPVP] Nothing to flex about... yet.")
        return
    end
    sendFlexMessage(line, channel)
end

mbgstats.sendFlexLastMatch = function(preferredChannel)
    local instance = getMostRecentInstance()
    local line = formatLastLine(instance)
    if not line then
        print("[SmartPVP] No matches recorded yet.")
        return false
    end
    local channel = preferredChannel
    if not channel then
        if IsInGroup() then
            channel = "PARTY"
        else
            channel = "SAY"
            print("[SmartPVP] Not in a group — flexing to Say.")
        end
    end
    return sendFlexMessage(line, channel)
end

-- ============================
-- Export (Release 2)
-- ============================

local function getClassColorPrefix(class)
    local key = class and class:upper()
    local info = RAID_CLASS_COLORS and key and RAID_CLASS_COLORS[key]
    if info then
        return string.format("|cff%02x%02x%02x",
            (info.r or 1) * 255, (info.g or 1) * 255, (info.b or 1) * 255)
    end
    return "|cFFFFFFFF"
end

-- ============================
-- Export (Release 2)
-- ============================

local function getExportScopeLabel(scope)
    if scope == "all" then
        return "All Data"
    end
    if scope == "last10" then
        return "Last 10 Matches"
    end
    local cat = mbgstats.categoryTab or "all"
    local catLabel = cat == "battleground" and "BG" or cat == "arena" and "Arena" or "All"
    return getFilterLabel() .. " · " .. catLabel
end

local function getInstancesForExportScope(scope)
    local savedPartition = mbgstats.currentPartitionFilter
    local savedDate = mbgstats.dateFilter
    local instances

    if scope == "all" then
        mbgstats.currentPartitionFilter = nil
        mbgstats.dateFilter = nil
        instances = getInstancesByPartition(nil)
        mbgstats.currentPartitionFilter = savedPartition
        mbgstats.dateFilter = savedDate
    else
        instances = getInstancesByPartition(mbgstats.currentPartitionFilter)
        if scope == "last10" then
            table.sort(instances, function(a, b)
                return (a.id or 0) > (b.id or 0)
            end)
            local trimmed = {}
            for i = 1, math.min(10, #instances) do
                trimmed[i] = instances[i]
            end
            instances = trimmed
        end
    end

    return instances
end

local function getAggregateStatsForExportScope(scope)
    if scope == "all" then
        local savedPartition = mbgstats.currentPartitionFilter
        local savedDate = mbgstats.dateFilter
        mbgstats.currentPartitionFilter = nil
        mbgstats.dateFilter = nil
        local stats = getOverallStatsByPartition(nil)
        mbgstats.currentPartitionFilter = savedPartition
        mbgstats.dateFilter = savedDate
        return stats
    end
    return getOverallStatsByPartition(mbgstats.currentPartitionFilter)
end

local function csvEscape(value)
    local text = tostring(value or "")
    if text:find("[,\"\n]") then
        return '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

local function buildExportText(instances, scope)
    local scopeLabel = getExportScopeLabel(scope)
    local playerName = UnitName("player") or "Unknown"
    local lines = {
        string.format("[SmartPVP] Fight Record — %s — %s", playerName, scopeLabel),
        "",
    }

    if instances and #instances > 0 then
        local glory = computeGloryStats(instances)
        local winRate, record = formatGloryWinRate(glory)
        if glory.wins + glory.losses > 0 then
            table.insert(lines, string.format("Win Rate: %s (%s) | KB/Game: %s",
                winRate, record,
                glory.games > 0 and string.format("%.1f", glory.totalKB / glory.games) or "0"))
            table.insert(lines, "")
        end
        for _, instance in ipairs(instances) do
            local resultCode = getInstanceResult(instance)
            table.insert(lines, string.format("%s | %s | %s | KB:%d HK:%d D:%d H:%d | %s",
                resultCode,
                instance.map or "?",
                instance.startTime or "?",
                instance.kb or instance.kills or 0,
                instance.hk or 0,
                instance.deaths or 0,
                instance.honor or 0,
                formatTime(instance.timePlayed or 0)))
        end
    else
        table.insert(lines, "No per-match rows in scope — map totals:")
        table.insert(lines, "")
        local aggregates = getAggregateStatsForExportScope(scope)
        for map, stats in pairs(aggregates) do
            table.insert(lines, string.format("• %s — KB:%d W:%d L:%d H:%d T:%s",
                map,
                stats.kb or stats.kills or 0,
                stats.wins or 0,
                stats.losses or 0,
                stats.honor or 0,
                formatTime(stats.timePlayed or 0)))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "Tracked by SmartPVP")
    return table.concat(lines, "\n")
end

local function buildExportCSV(instances, scope)
    local lines = {}
    if instances and #instances > 0 then
        table.insert(lines, "id,map,result,date,kb,hk,deaths,honor,damage,healing,duration_sec,wins,losses,forfeit")
        for _, instance in ipairs(instances) do
            local resultCode = getInstanceResult(instance)
            table.insert(lines, table.concat({
                csvEscape(instance.id or ""),
                csvEscape(instance.map or ""),
                csvEscape(resultCode),
                csvEscape(instance.startTime or ""),
                csvEscape(instance.kb or instance.kills or 0),
                csvEscape(instance.hk or 0),
                csvEscape(instance.deaths or 0),
                csvEscape(instance.honor or 0),
                csvEscape(instance.damage or 0),
                csvEscape(instance.healing or 0),
                csvEscape(instance.timePlayed or 0),
                csvEscape(instance.wins or 0),
                csvEscape(instance.losses or 0),
                csvEscape(instance._forfeits or 0),
            }, ","))
        end
    else
        table.insert(lines, "map,kb,hk,deaths,honor,wins,losses,alliance_wins,horde_wins,time_played_sec,avg_duration_sec")
        local aggregates = getAggregateStatsForExportScope(scope)
        for map, stats in pairs(aggregates) do
            local games = (stats.wins or 0) + (stats.losses or 0)
            local avg = games > 0 and math.floor((stats.timePlayed or 0) / games) or 0
            table.insert(lines, table.concat({
                csvEscape(map),
                csvEscape(stats.kb or stats.kills or 0),
                csvEscape(stats.hk or 0),
                csvEscape(stats.deaths or 0),
                csvEscape(stats.honor or 0),
                csvEscape(stats.wins or 0),
                csvEscape(stats.losses or 0),
                csvEscape(stats.allianceWins or 0),
                csvEscape(stats.hordeWins or 0),
                csvEscape(stats.timePlayed or 0),
                csvEscape(avg),
            }, ","))
        end
    end
    return table.concat(lines, "\n")
end

local function printLegacyChatExport()
    print("[meebeegee CSV]")
    print("Map,KB,HK,Deaths,Honor,Wins,Losses,Alliance Wins,Horde Wins,Time Played,Avg Duration")
    for map, stats in pairs(mbgstatsDB) do
        local games = stats.wins + stats.losses
        local average = games > 0 and math.floor(stats.timePlayed / games) or 0
        print(string.format("%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
            map, stats.kb or stats.kills or 0, stats.hk or 0, stats.deaths, stats.honor, stats.wins, stats.losses,
            stats.allianceWins, stats.hordeWins, stats.timePlayed, average))
    end
end

local function updateMBGExportContent(format, scope)
    if not MBGExportFrame or not MBGExportFrame.editBox then
        return
    end
    local instances = getInstancesForExportScope(scope or "current")
    local content
    if format == "csv" then
        content = buildExportCSV(instances, scope or "current")
    else
        content = buildExportText(instances, scope or "current")
    end
    MBGExportFrame.editBox:SetText(content)
    MBGExportFrame.editBox:SetCursorPosition(0)
    MBGExportFrame.editBox:HighlightText(0)
end

local function createMBGExportDialog()
    if MBGExportFrame then
        return
    end

    local frame = CreateFrame("Frame", "MBGExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 380)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(MBGTheme.frameBg[1], MBGTheme.frameBg[2], MBGTheme.frameBg[3], MBGTheme.frameBg[4])
    local br, bg, bb = getMBGFactionAccentRGB()
    frame:SetBackdropBorderColor(br, bg, bb, 0.85)
    frame:Hide()

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("MBGStats Export")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    formatLabel:SetPoint("TOPLEFT", 20, -44)
    formatLabel:SetText("Format:")

    local scopeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLabel:SetPoint("TOPLEFT", 240, -44)
    scopeLabel:SetText("Scope:")

    frame.currentFormat = "text"
    frame.currentScope = "current"

    local formatDropdown = CreateFrame("Frame", "MBGExportFormatDropdown", frame, "UIDropDownMenuTemplate")
    formatDropdown:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(formatDropdown, 140)

    local scopeDropdown = CreateFrame("Frame", "MBGExportScopeDropdown", frame, "UIDropDownMenuTemplate")
    scopeDropdown:SetPoint("TOPLEFT", scopeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(scopeDropdown, 160)

    local scrollFrame = CreateFrame("ScrollFrame", "MBGExportScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -96)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 48)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetWidth(420)
    editBox:SetHeight(800)
    if editBox.SetMaxLetters then
        editBox:SetMaxLetters(99999)
    end
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", 0, 16)
    hint:SetText("Click the box, then Ctrl+A and Ctrl+C to copy")
    hint:SetTextColor(0.7, 0.7, 0.7)

    local function refreshExport()
        updateMBGExportContent(frame.currentFormat, frame.currentScope)
    end

    UIDropDownMenu_Initialize(formatDropdown, function(self, level)
        local items = {
            { text = "Text (Discord)", value = "text" },
            { text = "CSV (Spreadsheet)", value = "csv" },
        }
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (frame.currentFormat == item.value)
            info.func = function()
                frame.currentFormat = item.value
                UIDropDownMenu_SetText(formatDropdown, item.text)
                refreshExport()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(formatDropdown, "Text (Discord)")

    UIDropDownMenu_Initialize(scopeDropdown, function(self, level)
        local items = {
            { text = "Current view", value = "current" },
            { text = "All Data", value = "all" },
            { text = "Last 10 matches", value = "last10" },
        }
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (frame.currentScope == item.value)
            info.func = function()
                frame.currentScope = item.value
                UIDropDownMenu_SetText(scopeDropdown, item.text)
                refreshExport()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(scopeDropdown, "Current view")

    frame.refreshExport = refreshExport
    MBGExportFrame = frame
end

mbgstats.openExportDialog = function(format, scope)
    createMBGExportDialog()
    MBGExportFrame.currentFormat = format or "text"
    MBGExportFrame.currentScope = scope or "current"
    local formatText = MBGExportFrame.currentFormat == "csv" and "CSV (Spreadsheet)" or "Text (Discord)"
    local scopeText = MBGExportFrame.currentScope == "all" and "All Data"
        or MBGExportFrame.currentScope == "last10" and "Last 10 matches" or "Current view"
    UIDropDownMenu_SetText(MBGExportFormatDropdown, formatText)
    UIDropDownMenu_SetText(MBGExportScopeDropdown, scopeText)
    MBGExportFrame.refreshExport()
    MBGExportFrame:Show()
end

-- ============================
-- Command System
-- ============================

-- Command state tracking
mbgstats.pendingResetAll = false

-- Main /mbg command handler
SLASH_MEEBEEGEE1 = "/mbg"
SlashCmdList["MEEBEEGEE"] = function(message)
    message = string.lower(message or ""):gsub("^%s*(.-)%s*$", "%1")

    if message == "sessionlist" then
        print("[meebeegee] Session stats:")
        for map, session in pairs(mbgstats.battlegroundSession and {[mbgstats.currentMap] = mbgstats.battlegroundSession} or {}) do
            local games = (session.wins or 0) + (session.losses or 0)
            print(string.format("• %s - KB:%d HK:%d D:%d H:%d W:%d L:%d F:%d Time:%s",
                map, session.kb or session.kills or 0, session.hk or 0, session.deaths or 0, session.honor or 0, 
                session.wins or 0, session.losses or 0, session._forfeits or 0, 
                formatTime(session.timePlayed or 0)))
        end
        
    elseif message == "popuptest" then
        if mbgstats.ShowResultConfirmation then
            mbgstats.ShowResultConfirmation("test", "alliance")
        else
            print("[SmartPVP] Popup function not available.")
        end

    elseif message == "status" then
        local inInstance, instanceType = IsInInstance()
        local _, infoType = GetInstanceInfo()
        local kind = getPvPInstanceKind()
        local uib = UnitInBattleground and UnitInBattleground("player") or "n/a"
        local arenaActive = (IsActiveBattlefieldArena and IsActiveBattlefieldArena()) and "yes" or "no"
        print(string.format("|cff00ff00[SmartPVP]|r v%s | inBG=%s | sessionActive=%s | map=%s",
            MBG_ADDON_VERSION, tostring(mbgstats.inBG), tostring(battlegroundSessionIsActive()),
            tostring(mbgstats.currentMap or mbgstats.battlegroundSession and mbgstats.battlegroundSession.map)))
        print(string.format("  IsInInstance=%s type=%s | GetInstanceInfo=%s | kind=%s | UnitInBattleground=%s | arena=%s",
            tostring(inInstance), tostring(instanceType), tostring(infoType), tostring(kind), tostring(uib), arenaActive))
        print(string.format("  stored matches: %d | bfWasActive=%s | C_Timer=%s",
            #mbgstatsDB_Instances, tostring(mbgstats.bfWasActive), (C_Timer and "yes" or "NO")))
        if battlegroundSessionIsActive() and not isInstancedPvP() then
            print("  |cffffaa00Stuck session detected — run /mbg flush to save it now|r")
        end

    elseif message == "flush" then
        if not battlegroundSessionIsActive() then
            print("[SmartPVP] No active session to flush.")
        else
            tryLeaveInstancedPvP("manual-flush")
        end

    elseif message == "popup" then
        -- Toggle between "always" and "smart" modes
        if mbgstats.popupMode == "always" then
            mbgstats.popupMode = "smart"
            mbgstatsDB_PopupMode = "smart"
            print("[SmartPVP] Popup mode: SMART (enabled for Arenas and Forfeits only)")
        else
            mbgstats.popupMode = "always"
            mbgstatsDB_PopupMode = "always"
            print("[SmartPVP] Popup mode: ALWAYS (enabled for all instances)")
        end

    elseif message == "" then
        createMBGStatsUI()
        if MBGStatsUI:IsShown() then
            MBGStatsUI:Hide()
        else
            MBGStatsUI:Show()
            -- Initialize showingInstances to false before first call
            if not MBGStatsUI.showingInstances then
                MBGStatsUI.showingInstances = false
            end
            if MBGStatsUI_UpdateList or (MBGStatsUI and MBGStatsUI.UpdateList) then
                mbgstats.refreshFightRecordUI() -- show overall view by default
            else
                print("|cff00ff00[SmartPVP]|r UI failed to initialize — try /reload")
            end
        end

    elseif message == "list" then
        print("|cff00ff00[MBG Stats Tracker]|r Tracked Battlegrounds:")
        for map, stats in pairs(mbgstatsDB) do
            local games = stats.wins + stats.losses
            print(string.format("• %s - KB:%d HK:%d D:%d H:%d W:%d L:%d Time:%s Avg:%s",
                map, stats.kb or stats.kills or 0, stats.hk or 0, stats.deaths, stats.honor, stats.wins, stats.losses,
                formatTime(stats.timePlayed), games > 0 and formatTime(math.floor(stats.timePlayed / games)) or "N/A"))
        end
    
    elseif message == "instancelist" then
    if not mbgstatsDB_Instances or #mbgstatsDB_Instances == 0 then
        print("[meebeegee] No battleground instances recorded yet.")
        return
    end

    print("|cff00ff00[MBG Stats Tracker]|r Per-Match History:")
    for i = #mbgstatsDB_Instances, 1, -1 do  -- latest first
            local session = mbgstatsDB_Instances[i]
            local map = session.map or mbgstats.currentMap or "?"
            local timeString = session.startTime or "?"
            local duration = session.timePlayed or (session.startEpoch and (time() - session.startEpoch)) or 0
        print(string.format("• #%d | %s | %s\n   KB:%d HK:%d D:%d H:%d W:%d L:%d F:%d T:%s",
                session.id or i, timeString, map,
                session.kb or session.kills or 0, session.hk or 0, session.deaths or 0, session.honor or 0,
                session.wins or 0, session.losses or 0, session._forfeits or 0,
                formatTime(duration)))
        end

    elseif message == "export" or message:match("^export") then
        if message:match("^export%s+chat") then
            printLegacyChatExport()
        else
            mbgstats.openExportDialog("text", "current")
        end

    elseif message:match("^reset%s+") then
        local mapName = message:match("^reset%s+(.+)")
        for key in pairs(mbgstatsDB) do
            if key:lower():find(mapName) then
                mbgstatsDB[key] = nil
                print("[meebeegee] Stats reset for: " .. key)
                return
            end
        end
        print("[meebeegee] Map not found: " .. mapName)

    elseif message == "resetall" then
        mbgstats.pendingResetAll = true
        print("[meebeegee] HOLY SHIT ARE YOU SURE? /confirm will delete all stat history. THIS CANNOT BE UNDONE. Type '/confirm' to proceed or '/abort' to cancel.")

    elseif message:match("^brag") then
        local tail = message:match("^brag%s*(.*)$") or ""
        runFlexCommand(formatBragLine, tail, "[SmartPVP] Nothing to brag about... yet.")

    elseif message:match("^win") then
        local tail = message:match("^win%s*(.*)$") or ""
        runFlexCommand(formatWinLine, tail, "[SmartPVP] No wins or losses recorded yet. Nothing to prove.")

    elseif message:match("^here") then
        local tail = message:match("^here%s*(.*)$") or ""
        runFlexCommand(formatHereLine, tail)

    elseif message:match("^last") then
        local tail = message:match("^last%s*(.*)$") or ""
        runFlexCommand(function()
            return formatLastLine(getMostRecentInstance())
        end, tail, "[SmartPVP] No matches recorded yet.")

    elseif message == "resetsession" then
        mbgstats.battlegroundSession = {}
        print("[meebeegee] Session stats reset.")

    elseif message == "arenas" then
        mbgstats.setCategoryTab(mbgstats.categoryTab == "arena" and "all" or "arena")
        print("[SmartPVP] Category tab: " .. (mbgstats.categoryTab or "all"))

    elseif message == "bgs" then
        mbgstats.setCategoryTab(mbgstats.categoryTab == "battleground" and "all" or "battleground")
        print("[SmartPVP] Category tab: " .. (mbgstats.categoryTab or "all"))

    elseif message:match("^declare") then
        local tail = message:match("^declare%s*(.*)$") or ""
        tail = strtrim(tail)
        mbgstats.declareBattle(tail ~= "" and tail or nil)

    elseif message == "stop" then
        if MBG_WPVP_ENABLED then
            mbgstats.stopWPvPBattle()
        else
            print("[SmartPVP] World PvP is sidelined for now — BG/Arena tracking unchanged.")
        end

    elseif message == "testdata" then
        -- Add some test data for debugging
        print("[SmartPVP] Adding test data...")
        
        -- Add test instance
        local testInstance = {
            id = 999,
            map = "Test Battleground",
            startTime = "2024-01-01 12:00:00",
            kills = 5,
            deaths = 2,
            honor = 150,
            wins = 1,
            losses = 0,
            allianceWins = 1,
            hordeWins = 0,
            timePlayed = 1800,
            _forfeits = 0,
            killsByClass = {["Warrior"] = 2, ["Mage"] = 3}
        }
        
        table.insert(mbgstatsDB_Instances, testInstance)
        
        -- Add to overall stats
        if not mbgstatsDB["Test Battleground"] then
            mbgstatsDB["Test Battleground"] = {
                kills = 0, deaths = 0, honor = 0,
                wins = 0, losses = 0,
                allianceWins = 0, hordeWins = 0,
                timePlayed = 0, killsByClass = {},
                _forfeits = 0
            }
        end
        
        local overall = mbgstatsDB["Test Battleground"]
        overall.kills = overall.kills + testInstance.kills
        overall.deaths = overall.deaths + testInstance.deaths
        overall.honor = overall.honor + testInstance.honor
        overall.wins = overall.wins + testInstance.wins
        overall.losses = overall.losses + testInstance.losses
        overall.allianceWins = overall.allianceWins + testInstance.allianceWins
        overall.hordeWins = overall.hordeWins + testInstance.hordeWins
        overall.timePlayed = overall.timePlayed + testInstance.timePlayed
        overall._forfeits = overall._forfeits + testInstance._forfeits
        
        for class, count in pairs(testInstance.killsByClass) do
            overall.killsByClass[class] = (overall.killsByClass[class] or 0) + count
        end
        
        print("[SmartPVP] Test data added.")

    elseif message == "help" then
        print("|cff00ff00[MBG Stats Tracker]|r Commands:")
        print("  /mbg              - brings up UI")
        print("  /mbg brag <channel>  - Random glory or map flex. Default Say")
        if MBG_WPVP_ENABLED then
            print("  /mbg declare [name] - Name/split a world PvP session (optional)")
            print("  /mbg stop          - End current world PvP session early")
        end
        print("  /mbg win <channel>   - Post All Data win rate. Default Say")
        print("  /mbg here <channel>  - Flex stats for the map you're in. Default Say")
        print("  /mbg last <channel>  - Flex your most recent match. Default Say")
        print("  /mbg status        - Show PvP session / detection debug info")
        print("  /mbg flush         - Force-save a stuck open session")
        print("  /mbg helpext         - Show more help!")
    
    elseif message == "helpext" then  
        print("  /mbg popup        - Toggle popup mode (ALWAYS or SMART - Arenas/Forfeits only)")
        print("  /mbg resetall     - Reset ALL stats (requires /confirm)")
        print("  /mbg export        - Open export dialog (text/CSV). /mbg export chat for legacy CSV")
        print("  UI tabs: All Types | BG | Arena — filter match type (see View line for scope)")
        print("  All Data (toolbar) = full history. All Types tab = BG+Arena mix. Seasons = filter view only.")
        print("  New Season tags new matches only — does not hide existing data.")
        print("  Close Season stops tagging new matches; past season labels are kept.")
        if MBG_WPVP_ENABLED then
            print("  World PvP tracks automatically outdoors — declare is optional")
        end
        print("  Milestones unlock from play (First Blood, Hat Trick, etc.)")
        print("  Channels: say/s, party/p, yell/y, raid/r, instance/i, guild/g, raidwarning/rw")  

    else
        for map, stats in pairs(mbgstatsDB) do
            if map:lower():find(message) then
                printStats(map, stats)
                return
            end
        end
        print("|cff00ff00[MBG Stats Tracker]|r Unknown command. Type '/mbg help' for options.")
    end
end

-- ============================
-- Confirmation Commands
-- ============================

-- Confirm resetall command
SLASH_MBGCONFIRM1 = "/confirm"
SlashCmdList["MBGCONFIRM"] = function()
    if mbgstats.pendingResetAll then
        mbgstatsDB = {}
        mbgstats.pendingResetAll = false
        print("[meebeegee] All-time stats have been reset.")
    else
        print("[meebeegee] Nothing to confirm.")
    end
end

-- Abort resetall command
SLASH_MBGABORT1 = "/abort"
SlashCmdList["MBGABORT"] = function()
    if mbgstats.pendingResetAll then
        mbgstats.pendingResetAll = false
        print("[meebeegee] Reset all-time stats cancelled.")
    else
        print("[meebeegee] Nothing to abort.")
    end
end

-- ============================
-- Main UI System
-- ============================

local MBG_UI_BUILD = 24

local function mbgUIErrorHandler(err)
    if debug and debug.traceback then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
end

local function mbgStatsUIReady()
    return MBGStatsUI
        and MBGStatsUI.__mbgBuildVersion == MBG_UI_BUILD
        and MBGStatsUI.content
        and MBGStatsUI_UpdateList
        and MBGStatsUI.updateCategoryTabVisuals
        and MBGStatsUI.typeDropDown
        and MBGStatsUI.filterBar
end

function createMBGStatsUI()
    if mbgStatsUIReady() then
        return
    end

    MBGStatsUI = CreateFrame("Frame", "MBGStatsUI", UIParent, "BackdropTemplate")
    MBGStatsUI.__mbgBuildVersion = MBG_UI_BUILD
    -- /reload reuses the named frame — drop orphaned widgets from the prior lua state
    for i = MBGStatsUI:GetNumChildren(), 1, -1 do
        local child = select(i, MBGStatsUI:GetChildren())
        child:Hide()
        child:SetParent(nil)
    end
    MBGStatsUI:SetSize(1150, 590) -- SmartPVP: preenche a largura do hub
    MBGStatsUI:SetPoint("CENTER")
    MBGStatsUI:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    MBGStatsUI:SetBackdropColor(MBGTheme.frameBg[1], MBGTheme.frameBg[2], MBGTheme.frameBg[3], MBGTheme.frameBg[4])
    local fbr, fbg, fbb = getMBGFactionAccentRGB()
    MBGStatsUI:SetBackdropBorderColor(fbr, fbg, fbb, 0.9)
    MBGStatsUI:EnableMouse(true)
    MBGStatsUI:SetMovable(true)
    MBGStatsUI:RegisterForDrag("LeftButton")
    MBGStatsUI:SetScript("OnDragStart", MBGStatsUI.StartMoving)
    MBGStatsUI:SetScript("OnDragStop", MBGStatsUI.StopMovingOrSizing)
    MBGStatsUI:Hide()

    local titleText = MBGStatsUI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetText("|cffffd700Registro de Partidas|r")

    -- Close Button
    local closeButton = CreateFrame("Button", nil, MBGStatsUI, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", MBGStatsUI, "TOPRIGHT", -2, -2)
    MBGStatsUI.CloseButton = closeButton -- SmartPVP: expoe p/ o hub esconder (usamos o X do hub)

    -- Export button (top-right)
    local exportButton = createMBGTextButton(MBGStatsUI, 64, 24)
    exportButton:SetPoint("TOPRIGHT", MBGStatsUI, "TOPRIGHT", -148, -30)
    exportButton:SetMBGLabel("Export")
    exportButton:SetScript("OnClick", function()
        mbgstats.openExportDialog("text", "current")
    end)

    local listButton = createMBGTextButton(MBGStatsUI, 96, 24)
    listButton:SetPoint("TOPRIGHT", MBGStatsUI, "TOPRIGHT", -56, -30)
    listButton:SetMBGLabel("Map Details")
    MBGStatsUI.listButton = listButton

    -- Back Button
    local backButton = createMBGTextButton(MBGStatsUI, 60, 24)
    backButton:SetPoint("TOPRIGHT", exportButton, "TOPLEFT", -8, 0)
    backButton:SetMBGLabel("Back")
    backButton:Hide()
    MBGStatsUI.backButton = backButton

    -- ====================
    -- Overall Data Box (Glory panel)
    -- ====================
    local overallStats = CreateFrame("Frame", nil, MBGStatsUI, "BackdropTemplate")
    overallStats:SetSize(1100, 110)
    overallStats:SetPoint("TOP", MBGStatsUI, "TOP", 0, -114)
    overallStats:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    overallStats:SetBackdropColor(MBGTheme.panelBg[1], MBGTheme.panelBg[2], MBGTheme.panelBg[3], MBGTheme.panelBg[4])
    overallStats:SetBackdropBorderColor(fbr, fbg, fbb, 0.35)
    overallStats:EnableMouse(false)

    local scopeText = overallStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scopeText:SetPoint("TOP", 0, -8)
    scopeText:SetWidth(1080)
    scopeText:SetJustifyH("CENTER")
    scopeText:SetText("|cffFFD700View:|r All Data")
    MBGStatsUI.scopeText = scopeText

    local recordingText = overallStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recordingText:SetPoint("TOP", scopeText, "BOTTOM", 0, -2)
    recordingText:SetWidth(1080)
    recordingText:SetJustifyH("CENTER")
    recordingText:Hide()
    MBGStatsUI.recordingText = recordingText

    local gloryText = overallStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gloryText:SetPoint("TOP", scopeText, "BOTTOM", 0, -4)
    gloryText:SetWidth(1080)
    gloryText:SetJustifyH("CENTER")
    gloryText:SetText("|cffffd700Glory:|r loading...")
    MBGStatsUI.gloryText = gloryText

    local overallText = overallStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overallText:SetPoint("BOTTOM", 0, 8)
    overallText:SetWidth(1080)
    overallText:SetJustifyH("CENTER")
    overallText:SetText("Overall Data: (loading...)")
    MBGStatsUI.overallText = overallText

    -- Type filter dropdown
    local typeBar = CreateFrame("Frame", nil, MBGStatsUI)
    typeBar:SetPoint("TOPLEFT", MBGStatsUI, "TOPLEFT", 16, -58)
    typeBar:SetPoint("TOPRIGHT", MBGStatsUI, "TOPRIGHT", -16, -58)
    typeBar:SetHeight(28)
    typeBar:EnableMouse(false)
    MBGStatsUI.typeBar = typeBar

    local typeLabel = typeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("LEFT", typeBar, "LEFT", 4, 0)
    typeLabel:SetText("|cffFFD700Type:|r")

    local typeDropDown = CreateFrame("Frame", "MBGStatsTypeDropDown", typeBar, "UIDropDownMenuTemplate")
    typeDropDown:SetPoint("LEFT", typeLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(typeDropDown, 130)
    MBGStatsUI.typeDropDown = typeDropDown

    local categoryTypeOptions = {
        { id = "all", text = "All Types" },
        { id = "battleground", text = "Battlegrounds" },
        { id = "arena", text = "Arenas" },
    }
    if MBG_WPVP_ENABLED then
        table.insert(categoryTypeOptions, { id = "wpvp", text = "World PvP" })
    end

    UIDropDownMenu_Initialize(typeDropDown, function(_, level)
        for _, item in ipairs(categoryTypeOptions) do
            local tabId = item.id
            local tabText = item.text
            local info = UIDropDownMenu_CreateInfo()
            info.text = tabText
            info.value = tabId
            info.checked = (mbgstats.categoryTab or "all") == tabId
            info.func = function()
                mbgstats.applyCategoryTypeFilter(tabId, tabText)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local function updateCategoryTabVisuals()
        if MBGStatsUI.typeDropDown then
            UIDropDownMenu_SetText(MBGStatsUI.typeDropDown, getCategoryTabLabel())
        end
    end
    MBGStatsUI.updateCategoryTabVisuals = updateCategoryTabVisuals
    updateCategoryTabVisuals()

    -- Scope filter row (All Data / This Week / Seasons / Instances)
    local filterBar = CreateFrame("Frame", nil, MBGStatsUI)
    filterBar:SetPoint("TOPLEFT", MBGStatsUI, "TOPLEFT", 16, -86)
    filterBar:SetPoint("TOPRIGHT", MBGStatsUI, "TOPRIGHT", -16, -86)
    filterBar:SetHeight(26)
    filterBar:EnableMouse(false)
    MBGStatsUI.filterBar = filterBar

    local allDataButton = createMBGTextButton(filterBar, 64, 24)
    allDataButton:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
    allDataButton:SetMBGLabel("All Data")
    allDataButton:SetScript("OnClick", function()
        showAllDataView()
    end)

    local weekButton = createMBGTextButton(filterBar, 72, 24)
    weekButton:SetPoint("LEFT", allDataButton, "RIGHT", 4, 0)
    weekButton:SetMBGLabel("This Week")

    weekButton:SetScript("OnClick", function()
        if mbgstats.dateFilter == "week" then
            mbgstats.dateFilter = nil
        else
            mbgstats.dateFilter = "week"
            mbgstats.currentPartitionFilter = nil
        end
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end
        mbgstats.refreshFightRecordUI()
    end)

    local seasonSlot = CreateFrame("Frame", nil, filterBar)
    seasonSlot:SetSize(82, 24)
    seasonSlot:SetPoint("LEFT", weekButton, "RIGHT", 4, 0)
    MBGStatsUI.seasonSlot = seasonSlot

    local newSeasonButton = createMBGTextButton(seasonSlot, 82, 24)
    newSeasonButton:SetPoint("LEFT", seasonSlot, "LEFT", 0, 0)
    newSeasonButton:SetMBGLabel("New Season")
    newSeasonButton:SetScript("OnClick", function()
        startNewSeason()
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end
    end)

    local closeSeasonButton = createMBGTextButton(seasonSlot, 78, 24)
    closeSeasonButton:SetPoint("LEFT", seasonSlot, "LEFT", 0, 0)
    closeSeasonButton:SetMBGLabel("Close Season")
    closeSeasonButton:SetScript("OnClick", function()
        closeRecordingSeason()
    end)

    local seasonsButton = createMBGTextButton(filterBar, 72, 24)
    seasonsButton:SetPoint("LEFT", seasonSlot, "RIGHT", 4, 0)
    seasonsButton:SetMBGLabel("Seasons")
    seasonsButton:SetScript("OnClick", function()
        createPartitionSelectionDialog()
        MBGPartitionDialog.ShowDialog()
        if SmartPVP_SkinFrame then SmartPVP_SkinFrame(MBGPartitionDialog, 0) end -- incorpora ao tema do addon
    end)

    -- SmartPVP: caixinha nos botoes de ACAO (New/Close Season, Seasons) pra
    -- distingui-los das abas de view (All Data / This Week), que ficam flat.
    for _, b in ipairs({ newSeasonButton, closeSeasonButton, seasonsButton }) do
        if b.SetBackdrop then
            b:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            b:SetBackdropColor(0.16, 0.16, 0.20, 1)
            b:SetBackdropBorderColor(0.30, 0.26, 0.10, 1)
        end
    end

    local toggleButton = createMBGTextButton(MBGStatsUI, 80, 24)
    toggleButton:SetPoint("RIGHT", filterBar, "RIGHT", -4, 0)
    toggleButton:SetMBGLabel("Instances")
    MBGStatsUI.toggleButton = toggleButton
    MBGStatsUI.showingInstances = false

    toggleButton:SetScript("OnClick", function()
        MBGStatsUI.showingInstances = not MBGStatsUI.showingInstances
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end
        mbgstats.refreshFightRecordUI()
    end)

    MBGStatsUI.newSeasonButton = newSeasonButton
    MBGStatsUI.closeSeasonButton = closeSeasonButton

    local function updateFilterButtonStates()
        allDataButton:SetMBGActive(mbgstats.currentPartitionFilter == nil and mbgstats.dateFilter ~= "week")
        weekButton:SetMBGActive(mbgstats.dateFilter == "week")
        local onSeason = mbgstats.currentPartitionFilter ~= nil and mbgstats.dateFilter ~= "week"
        seasonsButton:SetMBGActive(onSeason)
        if mbgstats.recordingSeasonId then
            newSeasonButton:Hide()
            closeSeasonButton:Show()
        else
            closeSeasonButton:Hide()
            newSeasonButton:Show()
        end
        toggleButton:SetMBGActive(MBGStatsUI.showingInstances)
    end
    MBGStatsUI.updateFilterButtonStates = updateFilterButtonStates
    updateFilterButtonStates()

    -- Scrollable Text Area
    local scrollFrame = CreateFrame("ScrollFrame", nil, MBGStatsUI, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -248)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 20)
    scrollFrame:SetClipsChildren(true)
    MBGStatsUI.scrollFrame = scrollFrame

    local instanceTooltip = CreateFrame("Frame", nil, UIParent, "TooltipBorderedFrameTemplate")
    instanceTooltip:SetFrameStrata("TOOLTIP")
    instanceTooltip:Hide()
    instanceTooltip.fs = instanceTooltip:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    instanceTooltip.fs:SetPoint("CENTER", 0, 0)
    instanceTooltip.fs:SetJustifyH("LEFT")
    instanceTooltip:SetScript("OnUpdate", function(self)
        if self:IsShown() then
            positionMBGInstanceTooltip(self)
        end
    end)
    MBGStatsUI.instanceTooltip = instanceTooltip

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    -- Store content reference in MBGStatsUI table for access by other functions
    MBGStatsUI.content = content

    -- Create persistent header and body containers
    MBGStatsUI.header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MBGStatsUI.header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -10)
    MBGStatsUI.header:SetJustifyH("LEFT")
    
    MBGStatsUI.body = CreateFrame("Frame", nil, content)
    MBGStatsUI.body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -30)
    MBGStatsUI.body:SetSize(1090, 1)
    
    -- Create main text area for overall mode
    MBGStatsUI.text = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MBGStatsUI.text:SetPoint("TOPLEFT", MBGStatsUI.header, "BOTTOMLEFT", 0, -10)
    MBGStatsUI.text:SetJustifyH("LEFT")
    MBGStatsUI.text:SetWidth(1080)
    
    -- Initialize row pool for instance mode (reset on rebuild — old rows orphan when scroll frame is recreated)
    MBGStatsUI.rows = {}

    MBGStatsUI.currentView = "main"
    MBGStatsUI.mapListVisible = false

    -- Row acquisition function for instance mode
    local function hideExtraInstanceRows(keepCount)
        if not MBGStatsUI.rows then
            return
        end
        for idx, row in pairs(MBGStatsUI.rows) do
            if type(idx) == "number" and idx > keepCount and row then
                row:Hide()
                row.instanceData = nil
            end
        end
    end

    local function acquireRow(i)
        local row = MBGStatsUI.rows[i]
        if row and row:GetParent() ~= MBGStatsUI.body then
            row = nil
            MBGStatsUI.rows[i] = nil
        end
        if not row then
            local row = CreateFrame("Frame", nil, MBGStatsUI.body)
            row:SetSize(1090, 24)
            row:EnableMouse(true)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)

            row.separator = row:CreateTexture(nil, "ARTWORK")
            row.separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
            row.separator:SetHeight(1)
            row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

            row:SetScript("OnEnter", function(self)
                if self.instanceData and MBGStatsUI.instanceTooltip then
                    updateInstanceRowTooltip(MBGStatsUI.instanceTooltip, self.instanceData)
                    positionMBGInstanceTooltip(MBGStatsUI.instanceTooltip)
                    MBGStatsUI.instanceTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                if MBGStatsUI.instanceTooltip then
                    MBGStatsUI.instanceTooltip:Hide()
                end
            end)

            row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.plus:SetSize(20, 20)
            row.plus:SetPoint("TOPRIGHT", -50, -2)
            row.plus:SetText("+")
            row.plus:Hide()

            row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.minus:SetSize(20, 20)
            row.minus:SetPoint("TOPRIGHT", -28, -2)
            row.minus:SetText("-")
            row.minus:Hide()

            row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delete:SetSize(18, 18)
            row.delete:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.delete:SetText("X")

            MBGStatsUI.rows[i] = row
        end
        return MBGStatsUI.rows[i]
    end

    local function hideMapPickerButtons()
        if MBGStatsUI.mapButtons then
            for _, button in ipairs(MBGStatsUI.mapButtons) do
                button:Hide()
            end
        end
    end

    local function setMapDetailsNavActive(active)
        if MBGStatsUI.listButton then
            MBGStatsUI.listButton:SetMBGActive(active)
        end
    end

    local function setMainListText(text)
        if not MBGStatsUI.text then
            return
        end
        MBGStatsUI.text:Hide()
        MBGStatsUI.text:SetText(text or "")
        MBGStatsUI.text:SetTextColor(1, 1, 1)
        MBGStatsUI.text:Show()
    end

    MBGStatsUI_UpdateList = function()
        if SmartPVPDB and SmartPVPDB.debug then print("|cff00ccff[SmartPVP dbg]|r UpdateList START") end
        local ok, err = xpcall(function()
        -- Get references from MBGStatsUI table
        local content = MBGStatsUI.content
        local toggleButton = MBGStatsUI.toggleButton
        local body = MBGStatsUI.body

        hideMapPickerButtons()
        MBGStatsUI.mapListVisible = false
        hideExtraInstanceRows(0)
        
        local totalKills, totalHonor, totalWins, totalLosses, totalAlliance, totalHorde = 0, 0, 0, 0, 0, 0

        if MBGStatsUI.showingInstances then
            -- Instance mode with partition filtering
            local database = getInstancesByPartition(mbgstats.currentPartitionFilter)
            
            if not database or #database == 0 then
                local filterLabel = getViewFilterLabel()
                if MBG_WPVP_ENABLED and (mbgstats.categoryTab or "all") == "wpvp" then
                    MBGStatsUI.header:SetText("World PvP (0 matches):")
                    setMainListText(formatEmptyWPvPHelpText())
                elseif mbgstats.currentPartitionFilter and filterLabel ~= "All Data" then
                    MBGStatsUI.header:SetText(string.format("Instances — |cff00ff00%s|r (0 matches):", filterLabel))
                    setMainListText(formatEmptySeasonHelpText())
                else
                    MBGStatsUI.header:SetText(string.format("Instances — %s (0 matches):", filterLabel))
                    setMainListText("No instances found. Complete a battleground to see data here.")
                end
                MBGStatsUI.body:Hide()
                MBGStatsUI.text:Show()
                MBGStatsUI.text:SetTextColor(1, 1, 1)
                if MBGStatsUI.gloryText then
                    local gOk, gText = pcall(function()
                        return formatGlorySummary(computeGloryStats({}))
                    end)
                    MBGStatsUI.gloryText:SetText(gOk and gText or "|cffffd700Glory:|r —")
                end
                updateScopeDisplay(0, 0, 0, 0, 0)
                toggleButton:SetMBGLabel("Overall")
                MBGStatsUI.currentView = "main"
                backButton:Hide()
                setMapDetailsNavActive(false)
                return
            end
            
            table.sort(database, function(a, b) return (a.id or 0) > (b.id or 0) end)
            
            local filterLabel = getViewFilterLabel()
            local matchCount = countViewMatches()
            if mbgstats.currentPartitionFilter and filterLabel ~= "All Data" then
                MBGStatsUI.header:SetText(string.format("Instances — |cff00ff00%s|r (%d matches):", filterLabel, matchCount))
            else
                MBGStatsUI.header:SetText(string.format("Instances — %s (%d matches):", filterLabel, matchCount))
            end
            
            for _, instance in ipairs(database) do
                totalKills = totalKills + (instance.kb or instance.kills or 0)
                totalHonor = totalHonor + (instance.honor or 0)
                totalWins = totalWins + (instance.wins or 0)
                totalLosses = totalLosses + (instance.losses or 0)
                totalAlliance = totalAlliance + (instance.allianceWins or 0)
                totalHorde = totalHorde + (instance.hordeWins or 0)
            end

            -- Per-row labels (aligned with delete buttons — single FontString drifts)
            local INSTANCE_ROW_HEIGHT = 16
            local numRows = #database

            MBGStatsUI.text:Hide()
            MBGStatsUI.body:ClearAllPoints()
            MBGStatsUI.body:SetPoint("TOPLEFT", MBGStatsUI.header, "BOTTOMLEFT", 0, -8)
            MBGStatsUI.body:SetSize(430, numRows * INSTANCE_ROW_HEIGHT)
            MBGStatsUI.body:Show()

            for i, instance in ipairs(database) do
                local row = acquireRow(i)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", MBGStatsUI.body, "TOPLEFT", 0, -((i - 1) * INSTANCE_ROW_HEIGHT))
                row:SetSize(430, INSTANCE_ROW_HEIGHT)

                row.instanceData = instance
                row.label:SetText(formatInstanceRowSummary(instance))
                row.label:Show()

                row.plus:Hide()
                row.minus:Hide()
                row.separator:Hide()
                row.delete:Show()

                -- Set up button scripts
                row.plus:SetScript("OnClick", function()
                    createPartitionAssignmentDialog()
                    MBGPartitionAssignmentDialog.ShowDialog(instance.id)
                end)
                
                row.minus:SetScript("OnClick", function()
                    removeInstanceFromPartition(instance.id)
                    MBGStatsUI_UpdateList()
                end)
                
                row.delete:SetScript("OnClick", function()
                    -- Create confirmation dialog
                    local confirmDialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                    confirmDialog:SetSize(300, 180)
                    confirmDialog:SetPoint("CENTER")
                    confirmDialog:SetBackdrop({
                        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
                        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32,
                        insets = { left = 8, right = 8, top = 8, bottom = 8 }
                    })
                    confirmDialog:SetBackdropColor(0, 0, 0, 0.95)
                    confirmDialog:SetFrameStrata("HIGH")
                    
                    -- Title
                    local title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    title:SetPoint("TOP", 0, -20)
                    title:SetText("Delete Instance")
                    
                    -- Message
                    local message = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    message:SetPoint("TOP", 0, -50)
                    message:SetText("Are you sure you want to delete this instance?")
                    
                    -- Instance details
                    local instanceDetails = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    instanceDetails:SetPoint("TOP", 0, -80)
                    local displayName = string.format("%s | ID:%d | %s", instance.map or "Unknown", instance.id or 0, instance.startTime or "?")
                    instanceDetails:SetText(displayName)
                    instanceDetails:SetTextColor(1, 1, 0) -- Yellow color for visibility
                    
                    -- Yes button
                    local yesButton = CreateFrame("Button", nil, confirmDialog, "UIPanelButtonTemplate")
                    yesButton:SetSize(80, 25)
                    yesButton:SetPoint("BOTTOMLEFT", 20, 20)
                    yesButton:SetText("Yes")
                    yesButton:SetScript("OnClick", function()
                        -- Remove from partition if assigned
                        if mbgstatsDB_InstancePartitions[instance.id] then
                            removeInstanceFromPartition(instance.id)
                        end
                        
                        -- Remove from instances array
                        for i, inst in ipairs(mbgstatsDB_Instances) do
                            if inst.id == instance.id then
                                table.remove(mbgstatsDB_Instances, i)
                                break
                            end
                        end
                        
                        -- Remove from overall stats
                        local map = instance.map or "Unknown"
                        if mbgstatsDB[map] then
                            for key, value in pairs(instance) do
                                if type(value) == "number" and mbgstatsDB[map][key] ~= nil then
                                    mbgstatsDB[map][key] = math.max(0, mbgstatsDB[map][key] - value)
                                elseif type(value) == "table" and key == "killsByClass" then
                                    for class, count in pairs(value) do
                                        if mbgstatsDB[map][key][class] then
                                            mbgstatsDB[map][key][class] = math.max(0, mbgstatsDB[map][key][class] - count)
                                        end
                                    end
                                elseif type(value) == "table" and key == "damageBySpell" then
                                    for spellName, spellAmount in pairs(value) do
                                        if mbgstatsDB[map][key] and mbgstatsDB[map][key][spellName] then
                                            mbgstatsDB[map][key][spellName] = math.max(0, mbgstatsDB[map][key][spellName] - spellAmount)
                                        end
                                    end
                                elseif type(value) == "table" and key == "healBySpell" then
                                    for spellName, spellAmount in pairs(value) do
                                        if mbgstatsDB[map][key] and mbgstatsDB[map][key][spellName] then
                                            mbgstatsDB[map][key][spellName] = math.max(0, mbgstatsDB[map][key][spellName] - spellAmount)
                                        end
                                    end
                                end
                            end
                        end
                        
                        confirmDialog:Hide()
                        print(string.format("[SmartPVP] Deleted instance: %s (ID: %d)", map, instance.id))
                        MBGStatsUI_UpdateList()
                    end)
                    
                    -- No button
                    local noButton = CreateFrame("Button", nil, confirmDialog, "UIPanelButtonTemplate")
                    noButton:SetSize(80, 25)
                    noButton:SetPoint("BOTTOMRIGHT", -20, 20)
                    noButton:SetText("No")
                    noButton:SetScript("OnClick", function()
                        confirmDialog:Hide()
                    end)
                    
                    confirmDialog:Show()
                end)
                
                row:Show()
            end

            hideExtraInstanceRows(numRows)

            local contentHeight = math.max(40, 30 + (numRows * INSTANCE_ROW_HEIGHT) + 16)
            MBGStatsUI.content:SetSize(430, contentHeight)
            if MBGStatsUI.scrollFrame then
                MBGStatsUI.scrollFrame:SetVerticalScroll(0)
            end
            
        else
            -- Overall stats mode with partition filtering
            local database = getOverallStatsByPartition(mbgstats.currentPartitionFilter)
            local viewLabel = getViewFilterLabel()
            local matchCount = countViewMatches()
            MBGStatsUI.header:SetText(string.format("Overall Stats — %s (%d matches):", viewLabel, matchCount))
            
            -- Show the persistent text area for overall mode and hide body
            MBGStatsUI.text:Show()
            MBGStatsUI.body:Hide()
            hideExtraInstanceRows(0)
            
            -- Build output string for overall stats (no header line needed)
            local output = ""
            
            for map, stats in pairs(database) do
                totalKills = totalKills + (stats.kb or stats.kills or 0)
                totalHonor = totalHonor + (stats.honor or 0)
                totalWins = totalWins + (stats.wins or 0)
                totalLosses = totalLosses + (stats.losses or 0)
                totalAlliance = totalAlliance + (stats.allianceWins or 0)
                totalHorde = totalHorde + (stats.hordeWins or 0)
                
                output = output .. string.format("• %s\n   KB:%d HK:%d D:%d H:%d W:%d L:%d F:%d T:%s\n\n",
                    map, stats.kb or stats.kills or 0, stats.hk or 0, stats.deaths or 0, stats.honor or 0,
                    stats.wins or 0, stats.losses or 0, stats._forfeits or 0, formatTime(stats.timePlayed or 0))
            end

            if matchCount == 0 then
                if mbgstats.currentPartitionFilter and viewLabel ~= "All Data" then
                    output = formatEmptySeasonHelpText()
                elseif MBG_WPVP_ENABLED and (mbgstats.categoryTab or "all") == "wpvp" then
                    output = formatEmptyWPvPHelpText()
                elseif output == "" then
                    output = "No instances found. Complete a battleground to see data here."
                end
            end
            
            MBGStatsUI.text:ClearAllPoints()
            MBGStatsUI.text:SetPoint("TOPLEFT", MBGStatsUI.header, "BOTTOMLEFT", 0, -10)
            MBGStatsUI.text:SetWidth(430)
            setMainListText(output)

            local textHeight = MBGStatsUI.text:GetStringHeight() or 1
            content:SetSize(430, math.max(40, textHeight + 24))
            if MBGStatsUI.scrollFrame then
                MBGStatsUI.scrollFrame:SetVerticalScroll(0)
            end
        end

        -- Glory panel + topline totals
        if SmartPVPDB and SmartPVPDB.debug then print("|cff00ccff[SmartPVP dbg]|r UpdateList reached glory") end
        local filteredInstances = getInstancesByPartition(mbgstats.currentPartitionFilter)
        refreshGloryPanel(filteredInstances)

        if MBGStatsUI.updateCategoryTabVisuals then
            MBGStatsUI.updateCategoryTabVisuals()
        end
        if MBGStatsUI.updateFilterButtonStates then
            MBGStatsUI.updateFilterButtonStates()
        end

        -- Update toggle button text to reflect current mode
        if MBGStatsUI.showingInstances then
            toggleButton:SetMBGLabel("Overall")
        else
            toggleButton:SetMBGLabel("Instances")
        end

        -- Force UI refresh
        MBGStatsUI:Show() -- Force refresh

        MBGStatsUI.currentView = "main"
        backButton:Hide()
        setMapDetailsNavActive(false)
        if SmartPVPDB and SmartPVPDB.debug then print("|cff00ccff[SmartPVP dbg]|r UpdateList DONE ok") end
        end, mbgUIErrorHandler)
        if not ok then
            print("|cffff3333[SmartPVP] UI update error:|r " .. tostring(err))
        end
    end
    MBGStatsUI.UpdateList = MBGStatsUI_UpdateList
    
    function MBGStatsUI_ShowMapList()
        local database = getOverallStatsByPartition(mbgstats.currentPartitionFilter)

        hideExtraInstanceRows(0)
        MBGStatsUI.body:Hide()
        MBGStatsUI.text:Hide()
        MBGStatsUI.text:SetText("")
        MBGStatsUI.header:SetText("|cffFFD700Map Details|r\n|cff888888Select a map for aggregated stats|r")

        hideMapPickerButtons()
        MBGStatsUI.mapButtons = {}

        local maps = {}
        for map in pairs(database) do
            table.insert(maps, map)
        end
        table.sort(maps)

        local prevAnchor = MBGStatsUI.header
        for i, map in ipairs(maps) do
            local button = createMBGMapPickButton(content, 430, 26)
            if i == 1 then
                button:SetPoint("TOPLEFT", MBGStatsUI.header, "BOTTOMLEFT", -5, -14)
            else
                button:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -8)
            end
            button:SetMapPickLabel(map)
            button:SetScript("OnClick", function()
                hideMapPickerButtons()
                MBGStatsUI_ShowSpecificMap(map)
            end)
            table.insert(MBGStatsUI.mapButtons, button)
            prevAnchor = button
        end

        local headerHeight = MBGStatsUI.header:GetStringHeight() or 28
        content:SetSize(430, math.max(60, headerHeight + (#maps * 34) + 24))
        if MBGStatsUI.scrollFrame then
            MBGStatsUI.scrollFrame:SetVerticalScroll(0)
        end

        MBGStatsUI.currentView = "mapList"
        MBGStatsUI.mapListVisible = true
        setMapDetailsNavActive(true)
        backButton:Show()
    end

    function MBGStatsUI_ShowSpecificMap(mapName)
        local database = getOverallStatsByPartition(mbgstats.currentPartitionFilter)
        local stats = database[mapName]
        if not stats then
            MBGStatsUI.header:SetText("|cffFFD700Map Details|r — " .. mapName)
            setMainListText("No stats for: " .. mapName)
            MBGStatsUI.currentView = "specific"
            MBGStatsUI.lastSpecificMap = mapName
            refreshGloryPanel(getInstancesForMap(mapName))
            setMapDetailsNavActive(true)
            backButton:Show()
            return
        end

        hideMapPickerButtons()
        MBGStatsUI.mapListVisible = false
        hideExtraInstanceRows(0)
        MBGStatsUI.body:Hide()

        local partitionInfo = ""
        if mbgstats.currentPartitionFilter then
            local partition = getPartition(mbgstats.currentPartitionFilter)
            if partition then
                partitionInfo = string.format(" [%s]", partition.name)
            end
        end

        MBGStatsUI.header:SetText("|cffFFD700Map Details|r — " .. mapName)

        local output = string.format("Stats for %s%s:\nKB:%d HK:%d D:%d H:%d W:%d L:%d F:%d T:%s\n\n",
            mapName, partitionInfo, stats.kb or stats.kills or 0, stats.hk or 0, stats.deaths, stats.honor, stats.wins, stats.losses, 
            stats._forfeits or 0, formatTime(stats.timePlayed or 0))

        if stats.killsByClass and next(stats.killsByClass) then
            output = output .. "Kills by Class:\n"
            local sortedClasses = {}
            for class, count in pairs(stats.killsByClass) do
                table.insert(sortedClasses, { class = class, count = count })
            end
            table.sort(sortedClasses, function(a, b) return a.count > b.count end)
            for _, entry in ipairs(sortedClasses) do
                local prefix = getClassColorPrefix(entry.class)
                output = output .. string.format("  %s%s|r: %d\n", prefix, entry.class, entry.count)
            end
        end

        if stats.damageBySpell and next(stats.damageBySpell) then
            output = output .. "\nDamage by Spell:\n"
            local sortedSpells = {}
            for spellName, damage in pairs(stats.damageBySpell) do
                table.insert(sortedSpells, {name = spellName, damage = damage})
            end
            table.sort(sortedSpells, function(a, b) return a.damage > b.damage end)
            
            for _, spell in ipairs(sortedSpells) do
                output = output .. string.format("  %s: %s\n", spell.name, commaValue(spell.damage))
            end
        end

        if stats.healBySpell and next(stats.healBySpell) then
            output = output .. "\nHealing by Spell:\n"
            local sortedSpells = {}
            for spellName, healing in pairs(stats.healBySpell) do
                table.insert(sortedSpells, {name = spellName, healing = healing})
            end
            table.sort(sortedSpells, function(a, b) return a.healing > b.healing end)

            for _, spell in ipairs(sortedSpells) do
                output = output .. string.format("  %s: %s\n", spell.name, commaValue(spell.healing))
            end
        end

        MBGStatsUI.text:ClearAllPoints()
        MBGStatsUI.text:SetPoint("TOPLEFT", MBGStatsUI.header, "BOTTOMLEFT", 0, -10)
        MBGStatsUI.text:SetWidth(430)
        setMainListText(output)
        local textHeight = MBGStatsUI.text:GetStringHeight() or 1
        content:SetSize(430, math.max(40, textHeight + 24))
        if MBGStatsUI.scrollFrame then
            MBGStatsUI.scrollFrame:SetVerticalScroll(0)
        end

        MBGStatsUI.currentView = "specific"
        MBGStatsUI.lastSpecificMap = mapName
        refreshGloryPanel(getInstancesForMap(mapName))
        setMapDetailsNavActive(true)
        backButton:Show()
    end

    listButton:SetScript("OnClick", function()
        if MBGStatsUI.currentView == "mapList" or MBGStatsUI.currentView == "specific" or MBGStatsUI.mapListVisible then
            MBGStatsUI.mapListVisible = false
            MBGStatsUI.currentView = "main"
            setMapDetailsNavActive(false)
            MBGStatsUI_UpdateList()
        else
            MBGStatsUI_ShowMapList()
        end
    end)

    backButton:SetScript("OnClick", function()
        if MBGStatsUI.currentView == "specific" then
            MBGStatsUI_ShowMapList()
        else
            MBGStatsUI.mapListVisible = false
            setMapDetailsNavActive(false)
            MBGStatsUI_UpdateList()
        end
    end)

    -- Keep header controls above the stats panel and scroll area for reliable clicks
    local baseLevel = MBGStatsUI:GetFrameLevel()
    local headerLevel = baseLevel + 40
    if MBGStatsUI.scrollFrame then
        MBGStatsUI.scrollFrame:SetFrameLevel(baseLevel + 2)
    end
    overallStats:SetFrameLevel(baseLevel + 4)
    if MBGStatsUI.typeBar then
        MBGStatsUI.typeBar:SetFrameLevel(headerLevel)
    end
    if MBGStatsUI.typeDropDown then
        MBGStatsUI.typeDropDown:SetFrameLevel(headerLevel + 2)
    end
    if MBGStatsUI.filterBar then
        MBGStatsUI.filterBar:SetFrameLevel(headerLevel)
    end
    exportButton:SetFrameLevel(headerLevel + 2)
    listButton:SetFrameLevel(headerLevel + 2)
    backButton:SetFrameLevel(headerLevel + 2)
    allDataButton:SetFrameLevel(headerLevel + 2)
    weekButton:SetFrameLevel(headerLevel + 2)
    newSeasonButton:SetFrameLevel(headerLevel + 2)
    closeSeasonButton:SetFrameLevel(headerLevel + 2)
    seasonsButton:SetFrameLevel(headerLevel + 2)
    toggleButton:SetFrameLevel(headerLevel + 2)
end

-- ============================
-- UI Utility Functions
-- ============================

-- Safely hide all children of a container without detaching them
function mbgstats.HideChildren(container)
    -- Hide all child frames
    for i = container:GetNumChildren(), 1, -1 do
        local child = select(i, container:GetChildren())
        child:Hide()
        if child.Disable then 
            child:Disable() 
        end -- Buttons
    end
    
    -- Hide all regions (FontStrings, Textures)
    for _, region in ipairs{container:GetRegions()} do
        if region.Hide then 
            region:Hide() 
        end
    end
end