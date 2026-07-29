-- SmartPVP.lua
-- Entrada unica: 1 botao de minimapa + comando /spvp, ambos abrindo o HUB
-- (janela unica com abas — ver SmartPVP_Hub.lua). Esconde o botao do killboard.

-- Indices das abas (mesma ordem do TABS em SmartPVP_Hub.lua):
-- 1 Partidas  2 Kills  3 Leaderboard  4 Estatisticas  5 Achievements  6 Config

-- ---------------------------------------------------------------------------
-- Comando /spvp
-- ---------------------------------------------------------------------------
local function route(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" then
        if SmartPVP_ToggleHub then SmartPVP_ToggleHub() end
        return
    end

    if msg == "hud" then
        if SmartPVP_ToggleHUD then SmartPVP_ToggleHUD() end
        return
    end

    if msg == "hudreset" or msg == "reset" then
        if SmartPVP_ResetHUDSession then SmartPVP_ResetHUDSession() end
        print("|cff00ccff[SmartPVP]|r HUD session reset.")
        return
    end

    if msg == "debug" then
        SmartPVPDB = SmartPVPDB or {}
        SmartPVPDB.debug = not SmartPVPDB.debug
        PSC_Debug = SmartPVPDB.debug  -- liga tambem o debug do killboard
        print("|cff00ccff[SmartPVP]|r debug = " .. tostring(SmartPVPDB.debug)
            .. " (mata 1 player e me manda a linha [SmartPVP dbg])")
        return
    end

    if msg == "wipe" then
        print("|cffff3333[SmartPVP]|r Isso ZERA TUDO: kills, mortes, streaks, partidas e historico. Nao da pra desfazer.")
        print("Confirma com: |cff00ff00/spvp wipe yes|r")
        return
    end
    if msg == "wipe yes" then
        -- killboard (account-wide): ResetAllStatsToDefault ja limpa e reconstroi a
        -- estrutura. NAO setar nil (quebra NetworkHandler/Statistics no load).
        if ResetAllStatsToDefault then pcall(ResetAllStatsToDefault) end
        if PSC_DB then PSC_DB.PlayerInfoCache = {} end
        -- matches (per-char)
        mbgstatsDB = {}
        mbgstatsDB_Instances = {}
        mbgstatsDB_InstanceCounter = 0
        mbgstatsDB_Partitions = {}
        mbgstatsDB_PartitionCounter = 0
        mbgstatsDB_InstancePartitions = {}
        mbgstatsDB_Milestones = {}
        mbgstatsDB_RecordingSeasonId = nil
        -- HUD de sessao
        if SmartPVP_ResetHUDSession then SmartPVP_ResetHUDSession() end
        print("|cff00ccff[SmartPVP]|r Tudo zerado. Recarregando...")
        ReloadUI()
        return
    end

    local tab
    if msg == "partidas" or msg == "matches" or msg == "bg" then tab = 1
    elseif msg == "kills" or msg == "kb" or msg == "killboard" or msg == "psc" then tab = 2
    elseif msg == "board" or msg == "leaderboard" then tab = 3
    elseif msg == "stats" or msg == "estatisticas" then tab = 4
    elseif msg == "nemesis" or msg == "rivalidades" or msg == "rival" then tab = 5
    elseif msg == "winrate" or msg == "wr" then tab = 6
    elseif msg == "leveling" or msg == "xp" then tab = 7
    elseif msg == "config" or msg == "cfg" then tab = 8
    end

    if tab then
        if SmartPVP_OpenTab then SmartPVP_OpenTab(tab) end
        return
    end

    if msg == "help" or msg == "?" then
        print("|cff00ccff[SmartPVP]|r " .. SmartPVP_L("help_header"))
        print("  |cff00ff00/spvp|r          - " .. SmartPVP_L("help_hub"))
        print("  |cff00ff00/spvp kills|r     - " .. SmartPVP_L("help_kills"))
        print("  |cff00ff00/spvp board|r     - " .. SmartPVP_L("help_board"))
        print("  |cff00ff00/spvp stats|r     - " .. SmartPVP_L("help_stats"))
        print("  |cff00ff00/spvp config|r    - " .. SmartPVP_L("help_config"))
        return
    end

    -- desconhecido: so abre o hub
    if SmartPVP_ToggleHub then SmartPVP_ToggleHub() end
end

SLASH_SMARTPVP1 = "/spvp"
SLASH_SMARTPVP2 = "/smartpvp"
SlashCmdList["SMARTPVP"] = route

-- ---------------------------------------------------------------------------
-- 1 botao de minimapa (esconde o do killboard). LibDataBroker + LibDBIcon vem
-- do modulo killboard.
-- ---------------------------------------------------------------------------
local function hideKillboardButton()
    if PSC_DB then
        PSC_DB.minimapButton = PSC_DB.minimapButton or {}
        PSC_DB.minimapButton.hide = true
    end
    local iconLib = LibStub and LibStub("LibDBIcon-1.0", true)
    if iconLib then pcall(function() iconLib:Hide("PvPStatsClassic") end) end
end

local function setupMinimap()
    if not LibStub then return end
    local ldbLib = LibStub("LibDataBroker-1.1", true)
    local iconLib = LibStub("LibDBIcon-1.0", true)
    if not ldbLib or not iconLib then return end

    hideKillboardButton()

    if not SmartPVP_LDB then
        SmartPVP_LDB = ldbLib:NewDataObject("SmartPVP", {
            type = "data source",
            text = "SmartPVP",
            icon = "Interface\\AddOns\\SmartPVP\\killboard\\img\\minimap",
            OnClick = function(_, _button)
                if SmartPVP_ToggleHub then SmartPVP_ToggleHub() end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("|cff00ccffSmartPVP|r")
                tt:AddLine("Click: abre o hub (partidas, kills, leaderboard, stats...)", 1, 1, 1)
            end,
        })
    end

    SmartPVPDB = SmartPVPDB or {}
    SmartPVPDB.minimap = SmartPVPDB.minimap or {}
    if not iconLib:IsRegistered("SmartPVP") then
        iconLib:Register("SmartPVP", SmartPVP_LDB, SmartPVPDB.minimap)
    end
    iconLib:Show("SmartPVP")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    setupMinimap()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, hideKillboardButton) -- caso o killboard registre depois de nos
    end
    print("|cff00ccff[SmartPVP]|r " .. SmartPVP_L("ready"))
end)
