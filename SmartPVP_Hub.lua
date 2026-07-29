-- SmartPVP_Hub.lua
-- Janela unica com abas + tema dark moderno (inspirado no DragonUI: painel escuro
-- chapado, bordas finas, header, abas flat com destaque dourado). Traz as janelas
-- dos dois modulos PARA DENTRO (reparenting) e tira o backdrop parchment delas p/
-- misturarem no fundo escuro. Uma aba visivel por vez.
-- ponytail: retrabalho da SHELL (grande ganho visual, baixo risco). Polir o
-- conteudo interno de cada janela = incremental.

-- ---- Tema ----
local T = {
    bg      = { 0.055, 0.055, 0.070, 0.96 }, -- painel
    header  = { 0.100, 0.100, 0.130, 1.00 }, -- barra do topo
    tabbar  = { 0.080, 0.080, 0.100, 1.00 },
    border  = { 0.22,  0.22,  0.28,  1.00 }, -- borda sutil
    gold    = { 1.00,  0.82,  0.00 },        -- destaque / ativo
    grey    = { 0.55,  0.55,  0.60 },        -- inativo
    hover   = { 0.90,  0.90,  0.95 },
    title   = { 0.35,  0.75,  1.00 },        -- ciano do "SmartPVP"
}

local TABS = {
    { labelKey = "tab_matches",     frame = "MBGStatsUI", open = function()
        -- NAO usa o SlashCmdList MEEBEEGEE (ele TOGGLA: recria/esconde o frame e
        -- crashava antes do refresh, com o erro engolido pelo pcall). Caminho direto:
        -- cria 1x se preciso, mostra e forca o refresh (senao fica em "loading...").
        if not _G.MBGStatsUI and _G.createMBGStatsUI then _G.createMBGStatsUI() end
        if _G.MBGStatsUI and _G.MBGStatsUI.Show then _G.MBGStatsUI:Show() end
        if _G.mbgstats and _G.mbgstats.refreshFightRecordUI then _G.mbgstats.refreshFightRecordUI() end
    end },
    { labelKey = "tab_kills",       frame = "PSC_KillStatsFrame",        open = "PSC_CreateKillsListFrame" },
    { labelKey = "tab_leaderboard", frame = "PSC_LeaderboardStatsFrame", open = "PSC_CreateLeaderboardFrame" },
    { labelKey = "tab_statistics",  frame = "PSC_StatisticsFrame",       open = "PSC_CreateStatisticsFrame" },
    { labelKey = "tab_rivalries",   frame = "SmartPVPNemesis",           open = "SmartPVP_OpenNemesis" },
    { labelKey = "tab_winrate",     frame = "SmartPVPWinRate",           open = "SmartPVP_OpenWinRate" },
    { labelKey = "tab_leveling",    frame = "SmartPVPXP",                open = "SmartPVP_OpenXP" },
    { labelKey = "tab_config",      frame = "PSC_ConfigFrame",           open = "PSC_CreateConfigFrame" },
}

local hub
local tabButtons = {}
local currentIndex

-- Textura de cor solida (helper).
local function solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(r, g, b, a or 1) -- 3.3.5: cor solida sem precisar de arquivo
    return t
end

-- ---- Re-skin recursivo do conteudo interno ----
-- Troca os backdrops "parchment" das sub-janelas pelo tema dark, pra o conteudo
-- combinar com a shell. So mexe em quem JA tem backdrop (nao inventa caixa em
-- container solto). NAO toca em fontstrings: cores tem significado (win/loss).
-- ponytail: pega o maior ofensor visual (as caixas amarelas) de forma generica.
local DARK_BD = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local FLAT_BD = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Botao "UIPanelButtonTemplate" da Blizzard? (heuristica pela textura)
local function isBlizzButton(b)
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    local tex = nt and nt.GetTexture and nt:GetTexture()
    return tex and type(tex) == "string" and tex:lower():find("ui%-panel%-button") ~= nil
end

local function flattenButton(b)
    if b._spvpSkin then return end
    b._spvpSkin = true
    pcall(function()
        if b.SetNormalTexture then b:SetNormalTexture("") end
        if b.SetPushedTexture then b:SetPushedTexture("") end
        if b.SetDisabledTexture then b:SetDisabledTexture("") end
        if b.SetBackdrop then
            b:SetBackdrop(FLAT_BD)
            b:SetBackdropColor(0.16, 0.16, 0.20, 1)
            b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        end
        if b.SetHighlightTexture then
            b:SetHighlightTexture("Interface\\ChatFrame\\ChatFrameBackground")
            local ht = b:GetHighlightTexture()
            if ht then ht:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 0.16); ht:SetBlendMode("ADD") end
        end
        local fs = b.GetFontString and b:GetFontString()
        if fs then fs:SetTextColor(T.gold[1], T.gold[2], T.gold[3]) end
    end)
end

local function flattenCheck(b)
    if b._spvpSkin then return end
    b._spvpSkin = true
    pcall(function()
        if b.SetNormalTexture then b:SetNormalTexture("") end -- tira a caixa parchment; mantem o check
        if b.SetBackdrop then
            b:SetBackdrop(FLAT_BD)
            b:SetBackdropColor(0.12, 0.12, 0.15, 1)
            b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        end
    end)
end

-- EditBox (InputBoxTemplate): limpa as texturas de borda + backdrop flat.
local function flattenEditBox(e)
    if e._spvpSkin then return end
    e._spvpSkin = true
    pcall(function()
        for _, r in ipairs({ e:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetTexture(nil) end
        end
        if e.SetBackdrop then
            e:SetBackdrop(FLAT_BD)
            e:SetBackdropColor(0.10, 0.10, 0.13, 1)
            e:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        end
    end)
end

-- Slider (barra horizontal): track vira backdrop flat escuro.
local function flattenSlider(s)
    if s._spvpSkin then return end
    s._spvpSkin = true
    pcall(function()
        if s.SetBackdrop then
            s:SetBackdrop(FLAT_BD)
            s:SetBackdropColor(0.10, 0.10, 0.13, 1)
            s:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        end
    end)
end

-- Dropdown (UIDropDownMenuTemplate): Frame com regioes <nome>Middle + <nome>Button.
local function isDropdown(f)
    local nm = f.GetName and f:GetName()
    return nm and _G[nm .. "Middle"] ~= nil and _G[nm .. "Button"] ~= nil
end
local function flattenDropdown(f)
    if f._spvpSkin then return end
    f._spvpSkin = true
    pcall(function()
        local nm = f:GetName()
        -- Tinta as texturas de escuro (mantem tamanho/posicao corretos). SetBackdrop
        -- no frame inteiro vazava sobre o label (dropdown tem ~15px de padding
        -- invisivel de cada lado) e escondia o valor selecionado.
        for _, sfx in ipairs({ "Left", "Middle", "Right" }) do
            local r = _G[nm .. sfx]
            if r and r.SetVertexColor then r:SetVertexColor(0.32, 0.32, 0.38) end
        end
        local txt = _G[nm .. "Text"]; if txt then txt:SetTextColor(1, 0.82, 0) end
    end)
end

local function skinContent(frame, depth)
    depth = depth or 0
    if not frame or depth > 7 then return end
    local otype = frame.GetObjectType and frame:GetObjectType()
    if otype == "CheckButton" then
        flattenCheck(frame)
    elseif otype == "Button" then
        if isBlizzButton(frame) then flattenButton(frame) end
    elseif otype == "EditBox" then
        flattenEditBox(frame)
    elseif otype == "Slider" then
        flattenSlider(frame)
    elseif otype == "Frame" and isDropdown(frame) then
        flattenDropdown(frame)
    elseif frame.GetBackdrop and frame.SetBackdrop then
        local ok, bd = pcall(frame.GetBackdrop, frame)
        if ok and bd then
            pcall(function()
                frame:SetBackdrop(DARK_BD)
                frame:SetBackdropColor(0.09, 0.09, 0.12, 0.85)
                frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.9)
            end)
        end
    end
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        for i = 1, #kids do skinContent(kids[i], depth + 1) end
    end
end

-- Exposto p/ skinar janelas criadas FORA da arvore do hub (ex: dialog de Seasons
-- do modulo matches, que abre como frame proprio no UIParent).
SmartPVP_SkinFrame = skinContent

-- ---- Aba flat estilo moderno ----
local function createTab(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(28)
    b:RegisterForClicks("LeftButtonUp")

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(text)
    b:SetWidth(math.max(70, b.label:GetStringWidth() + 30))

    b.underline = solid(b, "OVERLAY", T.gold[1], T.gold[2], T.gold[3], 1)
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", 6, 2)
    b.underline:SetPoint("BOTTOMRIGHT", -6, 2)
    b.underline:Hide()

    function b:SetActive(active)
        self._active = active
        if active then
            self.label:SetTextColor(T.gold[1], T.gold[2], T.gold[3])
            self.underline:Show()
        else
            self.label:SetTextColor(T.grey[1], T.grey[2], T.grey[3])
            self.underline:Hide()
        end
    end
    b:SetScript("OnEnter", function(self)
        if not self._active then self.label:SetTextColor(T.hover[1], T.hover[2], T.hover[3]) end
    end)
    b:SetScript("OnLeave", function(self) self:SetActive(self._active) end)
    b:SetActive(false)
    return b
end

-- ---- Reparent / troca de aba ----
local function ensureFrame(t)
    local fn
    if type(t.open) == "function" then
        fn = t.open
    elseif type(t.open) == "string" and type(_G[t.open]) == "function" then
        fn = _G[t.open]
    end
    if fn then
        local ok, err = pcall(fn)
        if not ok then
            -- antes o erro era engolido em silencio -> aba ficava "loading" sem pista.
            print("|cffff3333[SmartPVP] open error ("..tostring(t.frame).."):|r "..tostring(err))
        end
    end
    return _G[t.frame]
end

local function selectTab(index)
    if not hub then return end
    local t = TABS[index]
    if not t then return end
    currentIndex = index

    local fr = ensureFrame(t)

    for _, o in ipairs(TABS) do
        local of = _G[o.frame]
        if of and of.Hide then pcall(function() of:Hide() end) end
        -- Alguns modulos RECRIAM o frame a cada open (ex: Statistics). O objeto
        -- antigo (mesmo nome, outro objeto) vira orfao e fica flutuando. Esconde.
        if o._lastFrame and o._lastFrame ~= of then
            pcall(function() o._lastFrame:Hide(); o._lastFrame:SetParent(UIParent) end)
        end
    end

    if fr then
        pcall(function()
            fr:SetParent(hub.content)
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", hub.content, "TOPLEFT", 0, 0)
            if fr.SetBackdrop then fr:SetBackdrop(nil) end       -- funde no fundo escuro
            if fr.SetFrameStrata then fr:SetFrameStrata("HIGH") end
            if fr.SetFrameLevel then fr:SetFrameLevel(hub:GetFrameLevel() + 5) end
            if fr.CloseButton and fr.CloseButton.Hide then fr.CloseButton:Hide() end
            if fr.SetMovable then fr:SetMovable(false) end
            fr:Show()
        end)
    else
        print("|cffff5555[SmartPVP]|r janela '" .. tostring(t.frame) .. "' indisponivel.")
    end

    if fr then
        -- scale-to-fit: encolhe a janela se for maior que a area de conteudo
        -- (~1150x588), resolvendo overflow (ex: Config). Nunca da upscale.
        pcall(function()
            local fw, fh = fr:GetWidth(), fr:GetHeight()
            if fw and fh and fw > 1 and fh > 1 then
                local s = math.min(1150 / fw, 588 / fh, 1)
                if fr.SetScale then fr:SetScale(s) end
            end
        end)
        pcall(skinContent, fr, 0) -- re-skina o conteudo interno
        t._lastFrame = fr -- lembra o objeto atual p/ esconder orfaos no proximo open
        -- Mata STRAYS: alguns modulos (Statistics) RECRIAM o frame a cada open e o
        -- antigo fica flutuando no UIParent com borda parchment. Como fr ja foi
        -- reparenteado p/ hub.content, qualquer frame de MESMO NOME ainda filho do
        -- UIParent e um orfao -> esconde.
        pcall(function()
            local kids = { UIParent:GetChildren() }
            for i = 1, #kids do
                local k = kids[i]
                if k ~= fr and k.GetName and k:GetName() == t.frame then k:Hide() end
            end
        end)
    end

    for i, b in ipairs(tabButtons) do b:SetActive(i == index) end
    hub:Show()
end

-- ---- Construcao da shell ----
local function buildHub()
    hub = CreateFrame("Frame", "SmartPVPHub", UIParent)
    hub:SetSize(1180, 690)
    hub:SetPoint("CENTER")
    hub:SetFrameStrata("HIGH")
    hub:EnableMouse(true)
    hub:SetMovable(true)
    hub:SetClampedToScreen(true)
    hub:RegisterForDrag("LeftButton")
    hub:SetScript("OnDragStart", hub.StartMoving)
    hub:SetScript("OnDragStop", hub.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SmartPVPHub")

    -- painel dark + borda fina
    if hub.SetBackdrop then
        hub:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        hub:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], T.bg[4])
        hub:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end

    -- header bar
    local header = solid(hub, "ARTWORK", T.header[1], T.header[2], T.header[3], 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(38)

    local title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 16, 0)
    title:SetText("SmartPVP")
    title:SetTextColor(T.title[1], T.title[2], T.title[3])

    local sub = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 8, 0)
    sub:SetText("PvP suite")
    sub:SetTextColor(T.grey[1], T.grey[2], T.grey[3])

    local close = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- barra de abas
    local tabbar = solid(hub, "ARTWORK", T.tabbar[1], T.tabbar[2], T.tabbar[3], 1)
    tabbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    tabbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    tabbar:SetHeight(30)

    -- linha divisoria dourada sutil sob as abas
    local sep = solid(hub, "OVERLAY", T.gold[1], T.gold[2], T.gold[3], 0.25)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", tabbar, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", tabbar, "BOTTOMRIGHT", 0, 0)

    local prev
    for i, t in ipairs(TABS) do
        local b = createTab(hub, SmartPVP_L(t.labelKey))
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", tabbar, "TOPLEFT", 12, -1)
        end
        b:SetPoint("TOP", tabbar, "TOP", 0, -1)
        b:SetScript("OnClick", function() selectTab(i) end)
        tabButtons[i] = b
        prev = b
    end

    -- area de conteudo (onde as janelas de modulo ancoram)
    local content = CreateFrame("Frame", "SmartPVPHubContent", hub)
    content:SetPoint("TOPLEFT", tabbar, "BOTTOMLEFT", 14, -12)
    content:SetPoint("BOTTOMRIGHT", hub, "BOTTOMRIGHT", -14, 14)
    hub.content = content

    hub:Hide()
end

function SmartPVP_ToggleHub()
    if not hub then buildHub() end
    if hub:IsShown() then
        hub:Hide()
    else
        selectTab(currentIndex or 1)
    end
end

function SmartPVP_OpenTab(index)
    if not hub then buildHub() end
    selectTab(index or 1)
end
