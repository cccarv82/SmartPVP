-- ClassInfo.lua
-- Resolver de classe do servidor (CoA tem classes CUSTOM, nao classless).
-- No CoA GetPlayerInfoByGUID/UnitClass devolvem um TOKEN custom (ex: "DEMONHUNTER"
-- = Felsworn, "CULTIST" = Cultist). Este modulo mapeia token->nome de exibicao +
-- cor. Dados copiados do addon LootCollector (Constants.COA_DISPLAY_NAMES +
-- Viewer.CUSTOM_CLASS_COLORS) que ja mapeia todas as classes do server.
-- SmartPVP_ClassInfo(class) -> displayName, r, g, b  (aceita token, nome custom
-- ou classe base; tolerante a espacos/caixa).

-- token -> nome de exibicao
local DISPLAY = {
    SONOFARUGAL  = "Bloodmage",
    TINKER       = "Tinker",
    PROPHET      = "Venomancer",
    RANGER       = "Ranger",
    NECROMANCER  = "Necromancer",
    WILDWALKER   = "Primalist",
    CULTIST      = "Cultist",
    GUARDIAN     = "Guardian",
    REAPER       = "Reaper",
    MONK         = "Templar",
    BARBARIAN    = "Barbarian",
    STORMBRINGER = "Stormbringer",
    SUNCLERIC    = "Sun Cleric",
    STARCALLER   = "Starcaller",
    SPIRITMAGE   = "Runemaster",
    WITCHDOCTOR  = "Witch Doctor",
    CHRONOMANCER = "Chronomancer",
    PYROMANCER   = "Pyromancer",
    FLESHWARDEN  = "Knight of Xoroth",
    DEMONHUNTER  = "Felsworn",
    WITCHHUNTER  = "Witch Hunter",
}

-- token -> cor {r,g,b}
local COLOR = {
    DEMONHUNTER  = { 0.64, 0.19, 0.79 },
    BARBARIAN    = { 0.78, 0.61, 0.43 },
    CHRONOMANCER = { 1.00, 0.96, 0.41 },
    CULTIST      = { 0.53, 0.53, 0.93 },
    NECROMANCER  = { 0.67, 0.83, 0.45 },
    WILDWALKER   = { 1.00, 0.49, 0.04 },
    PYROMANCER   = { 1.00, 0.49, 0.04 },
    RANGER       = { 0.67, 0.83, 0.45 },
    REAPER       = { 0.00, 1.00, 0.59 },
    SPIRITMAGE   = { 0.41, 0.80, 0.94 },
    STARCALLER   = { 0.41, 0.80, 0.94 },
    STORMBRINGER = { 0.00, 0.44, 0.87 },
    SUNCLERIC    = { 1.00, 0.49, 0.04 },
    MONK         = { 0.96, 0.55, 0.73 },
    TINKER       = { 1.00, 0.96, 0.41 },
    PROPHET      = { 0.67, 0.83, 0.45 },
    WITCHDOCTOR  = { 0.96, 0.55, 0.73 },
    WITCHHUNTER  = { 0.53, 0.53, 0.93 },
    GUARDIAN     = { 0.50, 0.50, 0.50 },
    FLESHWARDEN  = { 0.77, 0.12, 0.23 },
    SONOFARUGAL  = { 0.77, 0.12, 0.23 },
}

-- normaliza: caixa alta, sem espacos ("Witch Doctor" -> "WITCHDOCTOR")
local function norm(s)
    return (tostring(s):upper():gsub("[%s'%-]", ""))
end

-- nome de exibicao normalizado -> token (reverso)
local NAME_TO_TOKEN = {}
for token, name in pairs(DISPLAY) do
    NAME_TO_TOKEN[norm(name)] = token
end

-- SmartPVP_ClassInfo(class) -> displayName, r, g, b
function SmartPVP_ClassInfo(class)
    if not class or class == "" then
        return "Unknown", 0.70, 0.70, 0.70
    end
    local key = norm(class)
    -- token custom direto, ou nome custom -> token
    local token = DISPLAY[key] and key or NAME_TO_TOKEN[key]
    if token then
        local c = COLOR[token]
        local disp = DISPLAY[token] or tostring(class)
        if c then return disp, c[1], c[2], c[3] end
        return disp, 0.85, 0.85, 0.85
    end
    -- classe base do WoW (WARRIOR, MAGE, ...) -> cor padrao
    local base = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[key]
    if base then
        local loc = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[key]) or class
        return loc, base.r, base.g, base.b
    end
    -- desconhecido: devolve como veio, cinza claro
    return tostring(class), 0.85, 0.85, 0.85
end

-- nome curto p/ exibicao: corta "-Realm - Conquest of Azeroth" (CoA e single-realm,
-- o sufixo e sempre redundante). Nomes de WoW nao tem "-", entao o que vem antes do
-- 1o "-" e o personagem.
function SmartPVP_ShortName(name)
    if not name then return name end
    return (tostring(name):match("^(.-)%-")) or name
end

-- lista de nomes de exibicao das classes custom do CoA (ordenada). Usada p/
-- montar a legenda/agregacao do grafico de classes na tela Statistics.
function SmartPVP_AllClassNames()
    local t = {}
    for _, name in pairs(DISPLAY) do t[#t + 1] = name end
    table.sort(t)
    return t
end

-- "|cffRRGGBB<nome>|r" colorido (helper de conveniencia)
function SmartPVP_ClassColored(class)
    local name, r, g, b = SmartPVP_ClassInfo(class)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
end

-- GUID de player? Aceita o formato MODERNO ("Player-realm-id") E o hex do 3.3.5
-- ("0x00000000..."; tipo player = 0x00, creatures/pets = 0xF1x). O killboard so
-- testava "Player-" via strsplit -> no CoA (GUID hex) nunca batia -> 0 kills.
function SmartPVP_IsPlayerGUID(guid)
    if not guid or guid == "" then return false end
    if string.find(guid, "Player%-") then return true end       -- formato moderno
    local low = string.lower(guid)
    if string.sub(low, 1, 2) == "0x" then
        -- hex 3.3.5: creatures/pets/vehicles/objects = 0xF1.. (3o char 'f');
        -- players/items = zeros a esquerda. Robusto ao numero de zeros.
        return string.sub(low, 3, 3) ~= "f"
    end
    return false
end
