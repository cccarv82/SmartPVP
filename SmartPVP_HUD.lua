-- SmartPVP_HUD.lua
-- HUD de sessao (feature #4): mini-frame movivel com Kills / Deaths / K/D /
-- Streak da SESSAO atual (zera no login/reload). Rastreia por conta propria via
-- combat log, pra nao depender do killboard. Toggle: /spvp hud (ou botao no menu
-- de config futuro). Posicao e estado salvos em SmartPVPDB.hud.

local session = { kills = 0, deaths = 0, streak = 0, best = 0 }
local hud
local inPvP = false   -- estamos dentro de BG/arena?
local lastKB = 0      -- ultimo killingBlows lido do placar (p/ delta do streak)

local function solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(r, g, b, a or 1)
    return t
end

local function updateHUD()
    if not hud or not hud:IsShown() then return end
    hud.killsVal:SetText(tostring(session.kills))
    hud.deathsVal:SetText(tostring(session.deaths))
    local kd = session.deaths > 0 and (session.kills / session.deaths) or session.kills
    hud.kdVal:SetText(string.format("%.1f", kd))
    hud.streakVal:SetText(tostring(session.streak))
    -- cor do streak: dourado se >0
    if session.streak > 0 then
        hud.streakVal:SetTextColor(1, 0.82, 0)
    else
        hud.streakVal:SetTextColor(0.85, 0.85, 0.85)
    end
end

local function resetSession()
    session.kills, session.deaths, session.streak, session.best = 0, 0, 0, 0
    lastKB = 0
    updateHUD()
end
function SmartPVP_ResetHUDSession() resetSession() end

-- CoA nao dispara PARTY_KILL nem eventos de dano de inimigo -> impossivel detectar
-- killing blow pelo combat log. Honorable kill (msg de honra) = participacao/assist,
-- NAO e kill sua. A fonte confiavel de KILLING BLOWS reais e o PLACAR da BG/arena
-- (GetBattlefieldScore): lemos killingBlows + deaths do nosso proprio row.
local function setBGName()
    if not (hud and hud.bgLabel) then return end
    hud.bgLabel:SetText(inPvP and (GetRealZoneText() or GetZoneText() or "") or "")
end

local function readScoreboard()
    if not (GetNumBattlefieldScores and GetBattlefieldScore) then return end
    local me = UnitName("player")
    for i = 1, GetNumBattlefieldScores() do
        local name, kb, _hk, deaths = GetBattlefieldScore(i)
        if name then
            local base = name:match("^(.-)%-") or name -- tira o realm se vier "Nome-Realm"
            if base == me or name == me then
                kb = kb or 0
                -- streak: soma o delta de KB desde a ultima leitura; morte zera (PLAYER_DEAD)
                if kb > lastKB then
                    session.streak = session.streak + (kb - lastKB)
                    if session.streak > session.best then session.best = session.streak end
                end
                lastKB = kb
                session.kills = kb
                if deaths then session.deaths = deaths end
                updateHUD()
                setBGName()
                if SmartPVPDB and SmartPVPDB.debug then
                    print("|cff00ccff[SmartPVP dbg]|r placar KB="..kb.." D="..tostring(deaths))
                end
                return
            end
        end
    end
end

-- ticker: enquanto em BG, pede atualizacao do placar a cada 3s (o placar so
-- atualiza sob demanda via RequestBattlefieldScoreData).
local polling = false
local function pollLoop()
    if not inPvP then polling = false; return end
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    if C_Timer and C_Timer.After then C_Timer.After(3, pollLoop) end
end
local function startPolling()
    if polling then return end
    polling = true
    pollLoop()
end

-- Feed do KILLBOARD (abas Kills/Stats/Rivalidades) via msg de honra = "quem voce
-- enfrentou" (participacao/assist). NAO usa PSC_RegisterPlayerKill de proposito:
-- aquele dispara multi-kill/streak/ACHIEVEMENTS/SONS, que NAO devem contar honor-kill
-- (participacao != kill sua). Aqui so registramos a CONTAGEM por vitima (replicando
-- o minimo do killboard), sem nenhum efeito colateral. Dedup 0.5s por vitima.
local lastHonorVictim, lastHonorTime = nil, 0
local function feedKillboard(victim)
    if not victim or victim == "" then return end
    if not (PSC_GetInfoKeyFromName and PSC_GetCharacterKey and PSC_DB and PSC_DB.PlayerKillCounts) then return end
    local now = GetTime()
    if victim == lastHonorVictim and (now - lastHonorTime) < 0.5 then return end
    lastHonorVictim, lastHonorTime = victim, now

    local infoKey = PSC_GetInfoKeyFromName(victim)
    if not infoKey then return end
    PSC_DB.PlayerInfoCache = PSC_DB.PlayerInfoCache or {}
    local info = PSC_DB.PlayerInfoCache[infoKey]
    if not info then
        info = { level = 0, class = "UNKNOWN", rank = 0 }
        PSC_DB.PlayerInfoCache[infoKey] = info
    end
    local level = info.level or 0
    local nameWithLevel = infoKey .. ":" .. level

    local charKey = PSC_GetCharacterKey()
    PSC_DB.PlayerKillCounts.Characters = PSC_DB.PlayerKillCounts.Characters or {}
    local cd = PSC_DB.PlayerKillCounts.Characters[charKey]
    if not cd then
        cd = { Kills = {}, Deaths = {}, CurrentKillStreak = 0, HighestKillStreak = 0,
               HighestMultiKill = 0, GrayKillsCount = 0 }
        PSC_DB.PlayerKillCounts.Characters[charKey] = cd
    end
    cd.Kills = cd.Kills or {}
    -- replica InitializeKillCountEntryForPlayer + UpdateKillCountEntry (so a contagem)
    local e = cd.Kills[nameWithLevel]
    if not e then
        e = { kills = 0, lastKill = 0, killLocations = {}, rank = 0 }
        cd.Kills[nameWithLevel] = e
    end
    e.kills = e.kills + 1
    e.lastKill = time()
    local loc = {
        zone = (PSC_GetCurrentZoneName and PSC_GetCurrentZoneName()) or "",
        timestamp = e.lastKill, killNumber = e.kills, playerLevel = level,
    }
    if PSC_GetPlayerCoordinates then loc.x, loc.y = PSC_GetPlayerCoordinates() end
    table.insert(e.killLocations, loc)
end

-- celula "LABEL\nVALOR"
local function makeCell(parent, label)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(64, 34)
    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", 0, -2)
    lbl:SetText(label)
    lbl:SetTextColor(1, 0.82, 0)
    local val = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    val:SetPoint("BOTTOM", 0, 2)
    val:SetText("0")
    c.val = val
    return c
end

local function buildHUD()
    hud = CreateFrame("Frame", "SmartPVPHUD", UIParent)
    hud:SetSize(280, 46)
    hud:SetFrameStrata("MEDIUM")
    hud:EnableMouse(true)
    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", hud.StartMoving)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SmartPVPDB = SmartPVPDB or {}
        SmartPVPDB.hud = SmartPVPDB.hud or {}
        local point, _, relPoint, x, y = self:GetPoint()
        SmartPVPDB.hud.point, SmartPVPDB.hud.relPoint, SmartPVPDB.hud.x, SmartPVPDB.hud.y = point, relPoint, x, y
    end)
    if hud.SetBackdrop then
        hud:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        hud:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        hud:SetBackdropBorderColor(1, 0.82, 0, 0.5)
    end

    local kills = makeCell(hud, SmartPVP_L("hud_kills"));   kills:SetPoint("LEFT", hud, "LEFT", 8, 0)
    local deaths = makeCell(hud, SmartPVP_L("hud_deaths")); deaths:SetPoint("LEFT", kills, "RIGHT", 0, 0)
    local kd = makeCell(hud, SmartPVP_L("hud_kd"));         kd:SetPoint("LEFT", deaths, "RIGHT", 0, 0)
    local streak = makeCell(hud, SmartPVP_L("hud_streak")); streak:SetPoint("LEFT", kd, "RIGHT", 0, 0)
    hud.killsVal, hud.deathsVal, hud.kdVal, hud.streakVal = kills.val, deaths.val, kd.val, streak.val

    -- separadores verticais sutis
    for _, cell in ipairs({ deaths, kd, streak }) do
        local sep = solid(hud, "ARTWORK", 1, 0.82, 0, 0.18)
        sep:SetSize(1, 28)
        sep:SetPoint("LEFT", cell, "LEFT", 0, 0)
    end

    -- botao de reset (zera os numeros do HUD) no cantinho inferior direito, na borda
    local reset = CreateFrame("Button", nil, hud)
    reset:SetSize(15, 15)
    reset:SetPoint("CENTER", hud, "BOTTOMRIGHT", -4, 0)
    reset:SetFrameLevel(hud:GetFrameLevel() + 5)
    reset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    reset:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    reset:SetScript("OnClick", function() resetSession() end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(SmartPVP_Lang() == "pt" and "Zerar HUD" or "Reset HUD")
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- nome da BG atual, centralizado logo abaixo do HUD (ajuda a verificar deteccao)
    local bg = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bg:SetPoint("TOP", hud, "BOTTOM", 0, -2)
    bg:SetTextColor(1, 0.82, 0)
    bg:SetText("")
    hud.bgLabel = bg

    -- posicao salva ou default (centro-topo)
    local p = SmartPVPDB and SmartPVPDB.hud
    hud:ClearAllPoints()
    if p and p.point then
        hud:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        hud:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    hud:Hide()
end

function SmartPVP_SetHUD(shown)
    if not hud then buildHUD() end
    SmartPVPDB = SmartPVPDB or {}
    SmartPVPDB.hud = SmartPVPDB.hud or {}
    if shown then
        hud:Show(); SmartPVPDB.hud.shown = true; updateHUD()
    else
        hud:Hide(); SmartPVPDB.hud.shown = false
    end
end

function SmartPVP_ToggleHUD()
    if not hud then buildHUD() end
    SmartPVP_SetHUD(not hud:IsShown())
end

function SmartPVP_IsHUDShown()
    return (SmartPVPDB and SmartPVPDB.hud and SmartPVPDB.hud.shown) and true or false
end

-- ---- tracker de sessao (placar da BG/arena) ----
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
ev:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UPDATE_BATTLEFIELD_SCORE" then
        if inPvP then readScoreboard() end
        return
    end

    if event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        -- so alimenta o killboard (historico por vitima); nao conta no HUD
        local victim = arg1 and arg1:match("^(.-) dies, honorable kill")
        if victim then feedKillboard(victim) end
        return
    end

    if event == "PLAYER_LOGIN" then
        if SmartPVPDB and SmartPVPDB.hud and SmartPVPDB.hud.shown then
            if not hud then buildHUD() end
            hud:Show(); updateHUD()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local _, itype = IsInInstance()
        local nowPvP = (itype == "pvp" or itype == "arena")
        if nowPvP and not inPvP then
            -- entrou numa BG/arena: zera a sessao e comeca a ler o placar
            inPvP = true
            resetSession()
            startPolling()
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        elseif not nowPvP then
            inPvP = false -- saiu; para de pollar (pollLoop encerra sozinho)
        end
        setBGName()
        return
    end

    if event == "PLAYER_DEAD" then
        session.streak = 0
        if not inPvP then
            -- fora de BG nao ha placar: conta a morte na mao (kills ficam indisponiveis)
            session.deaths = session.deaths + 1
        end
        -- em BG, deaths vem do placar; pede refresh pra atualizar rapido
        if inPvP and RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        updateHUD()
        return
    end
end)

-- ---------------------------------------------------------------------------
-- NEMESES ("quem me matou"): o CoA nao da isso no combat log, MAS o DeathRecapFrame
-- popula sozinho na morte (~0.6s depois) com as ultimas fontes de dano. A entrada
-- mais recente (tempo mais proximo de 0 = golpe final) tem o KILLER entre parenteses
-- no texto "Spell (Atacante)". Extraimos e gravamos em PlayerKillCounts[me].Deaths
-- (mesma estrutura que a aba Rivalidades le).
-- ---------------------------------------------------------------------------
local function killerFromDeathRecap()
    local f = _G.DeathRecapFrame
    if type(f) ~= "table" or not f.GetChildren then return nil end
    local bestSecs, killer = math.huge, nil
    for _, child in ipairs({ f:GetChildren() }) do
        if type(child) == "table" and child.GetRegions then
            local secs, atk
            for _, r in ipairs({ child:GetRegions() }) do
                if r and r.GetText then
                    local t = r:GetText()
                    if t and t ~= "" then
                        local s = t:match("^%-?([%d%.]+)s$")   -- "-0.4s" -> 0.4
                        if s then
                            secs = tonumber(s)
                        else
                            -- ultimo grupo entre () no fim = atacante
                            -- ("Poison Quiver (DoT) (Ery)" -> "Ery")
                            local a = t:match("%(([^()]+)%)%s*$")
                            -- "Attacker" = placeholder do template (frame nao populado) -> ignora
                            if a and a ~= "Attacker" then atk = a end
                        end
                    end
                end
            end
            -- golpe final = menor tempo (mais recente) COM atacante (ignora morte
            -- por ambiente/queda que nao tem "(nome)")
            if atk and secs and secs < bestSecs then
                bestSecs, killer = secs, atk
            end
        end
    end
    -- Frame NAO populado = todas as rows no template (secs == 9.9). So aceita se o
    -- golpe final for recente de verdade (< 9.5s). Descarta o lixo "(Attacker)".
    if not killer or bestSecs >= 9.5 then return nil end
    return killer
end

local lastNemesis, lastNemesisTime = nil, 0
local function recordDeathKiller()
    local killer = killerFromDeathRecap()
    if not killer or killer == "" then return end
    local now = GetTime()
    if killer == lastNemesis and (now - lastNemesisTime) < 5 then return end -- dedup re-open
    if not (PSC_DB and PSC_DB.PlayerKillCounts and PSC_GetCharacterKey) then return end
    local key = PSC_GetCharacterKey()
    if not key then return end
    PSC_DB.PlayerKillCounts.Characters = PSC_DB.PlayerKillCounts.Characters or {}
    local cd = PSC_DB.PlayerKillCounts.Characters[key]
    if not cd then
        cd = { Kills = {}, Deaths = {}, CurrentKillStreak = 0, HighestKillStreak = 0,
               HighestMultiKill = 0, GrayKillsCount = 0 }
        PSC_DB.PlayerKillCounts.Characters[key] = cd
    end
    cd.Deaths = cd.Deaths or {}
    cd.Deaths["Attacker"] = nil -- limpa registro-lixo do template antigo
    local d = cd.Deaths[killer]
    if not d then d = { deaths = 0, name = killer }; cd.Deaths[killer] = d end
    d.deaths = d.deaths + 1
    lastNemesis, lastNemesisTime = killer, now
    if SmartPVPDB and SmartPVPDB.debug then
        print("|cff00ccff[SmartPVP dbg]|r nemesis: "..killer.." (x"..d.deaths..")")
    end
end

-- CoA: o DeathRecapFrame so carrega dado REAL quando VOCE abre o recap pelo botao
-- do jogo. Ler na morte SEM abrir pegava o recap ANTERIOR (killer errado/duplicado).
-- Entao gravamos a Nemeses SO quando voce ABRE o recap (hook OnShow = sempre correto),
-- e na morte apenas AVISAMOS pra abrir. Dedup evita contar 2x o mesmo recap reaberto.
do
    local hooked = false
    local function tryHook()
        if hooked then return end
        local f = _G.DeathRecapFrame
        if type(f) == "table" and f.HookScript then
            f:HookScript("OnShow", function()
                if C_Timer and C_Timer.After then C_Timer.After(0.15, recordDeathKiller)
                else recordDeathKiller() end
            end)
            hooked = true
        end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("PLAYER_DEAD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then tryHook(); return end
        -- PLAYER_DEAD: so em PvP (BG/arena), lembra de abrir o recap pra registrar.
        if inPvP then
            print("|cff00ccff[SmartPVP]|r " .. SmartPVP_L("nemesis_hint"))
        end
    end)
    tryHook() -- caso o DeathRecapFrame ja exista no load
end
