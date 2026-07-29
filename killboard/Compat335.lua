-- Compat335.lua
-- Camada de compatibilidade: roda o PvPStatsClassic (Interface 11508/20505 = Classic Era/TBC)
-- no client 3.3.5a (Interface 30300, WotLK). Puramente ADITIVO: define APIs modernas que
-- faltam no 3.3.5. Nenhum arquivo original do addon foi alterado (fora o .toc).
-- Carregado PRIMEIRO no .toc para que os globals existam antes das Libs/modulos usarem.
--
-- Cobre: C_Timer, CombatLogGetCurrentEventInfo (reordenado p/ layout WotLK),
--        C_Map, C_ChatInfo, securecallfunction.
-- BackdropTemplateMixin fica NIL de proposito: o addon usa o idiom guardado
--   CreateFrame(..., BackdropTemplateMixin and "BackdropTemplate")
-- entao nil => template nil => SetBackdrop nativo do 3.3.5. Nao definir.

local _G = _G

-- ---------------------------------------------------------------------------
-- securecallfunction(func, ...) -> chama e retorna. (moderno; 3.3.5 nao tem)
-- CallbackHandler-1.0 e ChatThrottleLib fazem cache disso no load => precisa
-- existir ANTES delas carregarem.
-- ---------------------------------------------------------------------------
if not _G.securecallfunction then
    function _G.securecallfunction(func, ...)
        return func(...)
    end
end

-- ---------------------------------------------------------------------------
-- C_Timer: After / NewTimer / NewTicker via um unico driver OnUpdate.
-- ---------------------------------------------------------------------------
if not _G.C_Timer then
    local C_Timer = {}
    _G.C_Timer = C_Timer

    local timers = {}
    local driver = CreateFrame("Frame")

    local TimerMT = {}
    TimerMT.__index = TimerMT
    function TimerMT:Cancel()
        self._cancelled = true
        timers[self] = nil
    end
    function TimerMT:IsCancelled()
        return self._cancelled == true
    end

    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        for t in pairs(timers) do
            if not t._cancelled and now >= t._at then
                -- ponytail: callback pode agendar novo timer; sera visto no proximo frame.
                t._callback(t)
                if t._ticker and not t._cancelled then
                    if t._iterations then
                        t._iterations = t._iterations - 1
                        if t._iterations <= 0 then
                            t._cancelled = true
                            timers[t] = nil
                        else
                            t._at = now + t._duration
                        end
                    else
                        t._at = now + t._duration
                    end
                else
                    timers[t] = nil
                end
            end
        end
    end)

    local function new(duration, callback, iterations, isTicker)
        local t = setmetatable({
            _at = GetTime() + (duration or 0),
            _duration = duration or 0,
            _callback = callback,
            _iterations = iterations,
            _ticker = isTicker,
        }, TimerMT)
        timers[t] = true
        return t
    end

    function C_Timer.After(duration, callback)
        new(duration, callback, nil, false)
    end
    function C_Timer.NewTimer(duration, callback)
        return new(duration, callback, nil, false)
    end
    function C_Timer.NewTicker(duration, callback, iterations)
        return new(duration, callback, iterations, true)
    end
end

-- ---------------------------------------------------------------------------
-- CombatLogGetCurrentEventInfo(): moderno le o evento via chamada de funcao.
-- No 3.3.5 os args chegam direto no handler de COMBAT_LOG_EVENT_UNFILTERED e o
-- layout NAO tem hideCaster nem raidFlags. Capturamos num frame proprio
-- (registrado primeiro => dispara antes do handler do addon) e reemitimos no
-- layout moderno que o addon espera.
--
-- WotLK 3.3.5 args:  1 timestamp, 2 event, 3 srcGUID, 4 srcName, 5 srcFlags,
--                    6 dstGUID, 7 dstName, 8 dstFlags, 9.. params
-- Layout moderno:    timestamp, event, hideCaster, srcGUID, srcName, srcFlags,
--                    srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, param1..
-- ---------------------------------------------------------------------------
if not _G.CombatLogGetCurrentEventInfo then
    local c = {}
    local n = 0
    local capture = CreateFrame("Frame")
    capture:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    capture:SetScript("OnEvent", function(_, _, ...)
        n = select("#", ...)
        for i = 1, n do
            c[i] = select(i, ...)
        end
    end)

    function _G.CombatLogGetCurrentEventInfo()
        -- flags nil->0: 3.3.5 manda nil p/ eventos sem alvo; API real normaliza p/ 0.
        -- Sem isso, PSC_IsValidTarget faz bit.band(nil,...) e crasha.
        return c[1], c[2], nil,             -- timestamp, event, hideCaster
               c[3], c[4], c[5] or 0, nil,  -- srcGUID, srcName, srcFlags, srcRaidFlags
               c[6], c[7], c[8] or 0, nil,  -- dstGUID, dstName, dstFlags, dstRaidFlags
               c[9], c[10], c[11], c[12], c[13], c[14], c[15], c[16] -- param1..8
    end
end

-- CoA (client custom 3.3.5) TEM CombatLogGetCurrentEventInfo NATIVO, entao o
-- "if not" acima nao instala nada. Mas o nativo devolve flags NIL em eventos
-- sem alvo -> PSC_IsValidTarget faz bit.band(nil,...) e crasha. Embrulhamos
-- SEMPRE o que existir (nativo OU shim) normalizando srcFlags(6)/destFlags(10)
-- p/ 0. Layout moderno: 6=srcFlags, 10=destFlags.
do
    local base = _G.CombatLogGetCurrentEventInfo
    if base then
        _G.CombatLogGetCurrentEventInfo = function()
            local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12,
                  a13, a14, a15, a16, a17, a18, a19, a20, a21, a22 = base()
            return a1, a2, a3, a4, a5, a6 or 0, a7, a8, a9, a10 or 0, a11, a12,
                   a13, a14, a15, a16, a17, a18, a19, a20, a21, a22
        end
    end
end

-- ---------------------------------------------------------------------------
-- C_Map: so o que o addon usa (posicao do player + "melhor mapa").
-- GetPlayerMapPosition global existe no 3.3.5 e retorna x,y em 0-1 do mapa atual.
-- ---------------------------------------------------------------------------
if not _G.C_Map then
    _G.C_Map = {}
end
if not _G.C_Map.GetBestMapForUnit then
    function _G.C_Map.GetBestMapForUnit(_unit)
        -- Deteccao de battleground: o addon compara este retorno contra uma lista
        -- de uiMapIDs de retail (91, 1460, ...) em PSC_CheckBattlegroundStatus.
        -- No 3.3.5 nao existe uiMapID, mas IsInInstance() da o tipo. Se estamos
        -- num BG, devolvemos 91 (que ESTA na lista do addon) => o modo BG liga
        -- e "so seus killing blows contam". Fora de BG, area atual (nao-nil).
        local _, instanceType = IsInInstance()
        if instanceType == "pvp" then
            return 91
        end
        return (GetCurrentMapAreaID and GetCurrentMapAreaID()) or 0
    end
end
if not _G.C_Map.GetPlayerMapPosition then
    function _G.C_Map.GetPlayerMapPosition(_mapID, unit)
        local x, y = GetPlayerMapPosition(unit or "player")
        if not x or (x == 0 and y == 0) then
            return nil
        end
        return { x = x, y = y }
    end
end

-- ---------------------------------------------------------------------------
-- C_ChatInfo: usado pelo AceComm. 3.3.5 tem SendAddonMessage global e NAO tem
-- RegisterAddonMessagePrefix (adicionado no 4.1) -> o fallback else do AceComm
-- quebraria. Definir C_ChatInfo faz o addon pegar o branch certo.
-- ---------------------------------------------------------------------------
if not _G.C_ChatInfo then
    _G.C_ChatInfo = {
        SendAddonMessage = function(prefix, text, channel, target)
            return SendAddonMessage(prefix, text, channel, target)
        end,
        RegisterAddonMessagePrefix = function(_prefix)
            return true -- 3.3.5 nao precisa registrar prefixo
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Metodos de Frame modernos (Legion+) ausentes no 3.3.5: adiciona no PROTOTYPE
-- (metatable do Frame) SO se faltarem, como no-op.
-- IMPORTANTE: NAO hookamos CreateFrame globalmente. Substituir o CreateFrame
-- global TAINTA todo frame que a Blizzard cria depois -> erro "AddOn 'SmartPVP'
-- prevented the call of the secure function 'CompactPartyFrameMemberX:Show()'"
-- (frames seguros de raid/party bloqueados em combate). Patch de metatable nao
-- tainta. O TitleText/CloseButton do BasicFrameTemplateWithInset agora vem do
-- OnLoad do template (matches/embeds.xml).
-- ---------------------------------------------------------------------------
do
    local function noop() end
    -- Frame: os 4 metodos (incl. SetPropagateKeyboardInput p/ os StaticPopups do
    -- killboard). Comportamento ORIGINAL conhecido-bom.
    local ok, sample = pcall(CreateFrame, "Frame")
    if ok and sample then
        local mt = getmetatable(sample)
        local proto = mt and mt.__index
        if type(proto) == "table" then
            local methods = {
                "SetPropagateKeyboardInput", "SetClipsChildren",
                "SetIgnoreParentScale", "SetIgnoreParentAlpha",
            }
            for i = 1, #methods do
                if type(proto[methods[i]]) ~= "function" then
                    proto[methods[i]] = noop
                end
            end
        end
    end
    -- ScrollFrame tem prototype proprio e o matches chama scrollFrame:SetClipsChildren
    -- (era o abort que travava a aba Matches em "loading"). SO metodos de LAYOUT aqui:
    -- NADA de teclado, e NAO amostrar EditBox (autoFocus rouba o teclado do jogo!).
    local ok2, sf = pcall(CreateFrame, "ScrollFrame")
    if ok2 and sf then
        local mt2 = getmetatable(sf)
        local p = mt2 and mt2.__index
        if type(p) == "table" then
            local layout = { "SetClipsChildren", "SetIgnoreParentScale", "SetIgnoreParentAlpha" }
            for i = 1, #layout do
                if type(p[layout[i]]) ~= "function" then
                    p[layout[i]] = noop
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Metatables de regioes (FontString/Texture):
--  * 3.3.5 NAO aceita SetParent(nil) em fonte/textura ("Cannot set a 'nil'
--    parent for fonts or textures"). Rotinas de cleanup do addon fazem isso.
--    -> SetParent(nil) vira no-op (Hide()/ClearAllPoints ja limpam).
--  * FontString NAO tem SetScript no 3.3.5 (o addon tenta hover em labels).
--    -> SetScript em FontString vira no-op (perde tooltip do label, sem crash).
-- Patch feito no prototype (uma vez), cobre todas as ocorrencias.
-- ---------------------------------------------------------------------------
do
    local function patchRegion(sample, addSetScript)
        if not sample then return end
        local mt = getmetatable(sample)
        local proto = mt and mt.__index
        if type(proto) ~= "table" then return end
        local origSetParent = proto.SetParent
        if origSetParent then
            proto.SetParent = function(self, parent)
                if parent == nil then return end
                return origSetParent(self, parent)
            end
        end
        if addSetScript and type(proto.SetScript) ~= "function" then
            proto.SetScript = function() end
        end
    end

    local okF, fs = pcall(UIParent.CreateFontString, UIParent, nil, "BACKGROUND")
    if okF then patchRegion(fs, true) end
    local okT, tex = pcall(UIParent.CreateTexture, UIParent, nil, "BACKGROUND")
    if okT then patchRegion(tex, false) end
end

-- ---------------------------------------------------------------------------
-- Som: o CoA e um cliente 3.3.5 MODERNIZADO -> PlaySound usa ID NUMERICO
-- (SoundKitID), nao nome de string. O crash original era PlaySound(nil), porque
-- SOUNDKIT no CoA nao tinha a chave que o addon usava. Fix:
--   (a) preencher os SOUNDKIT.* usados pelo addon com o ID numerico padrao;
--   (b) PlaySound/PlaySoundFile so guardam contra nil e passam o resto DIRETO
--       (numero moderno chega intacto no engine).
-- ---------------------------------------------------------------------------
if not _G.SOUNDKIT then _G.SOUNDKIT = {} end
do
    -- SoundKitIDs padrao; so define se o CoA nao tiver um numero valido.
    local defaults = {
        IG_MAINMENU_OPTION_CHECKBOX_ON  = 856,
        IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
        IG_CHARACTER_INFO_TAB           = 841,
    }
    for k, v in pairs(defaults) do
        if type(SOUNDKIT[k]) ~= "number" then
            SOUNDKIT[k] = v
        end
    end

    local origPlaySound = _G.PlaySound
    if origPlaySound then
        _G.PlaySound = function(sound, ...)
            if sound == nil then return end -- evita "Usage: PlaySound(sound)"
            return origPlaySound(sound, ...)
        end
    end

    local origPlaySoundFile = _G.PlaySoundFile
    if origPlaySoundFile then
        _G.PlaySoundFile = function(file, ...)
            if file == nil then return end
            return origPlaySoundFile(file, ...)
        end
    end
end
