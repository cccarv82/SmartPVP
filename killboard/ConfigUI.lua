local addonName, PVPSC = ...

local configFrame = nil

local PSC_CONFIG_HEADER_R = 1.0
local PSC_CONFIG_HEADER_G = 0.82
local PSC_CONFIG_HEADER_B = 0.0

local HEADER_ELEMENT_SPACING = 15
local CHECKBOX_SPACING = 5
local MESSAGE_TEXTFIELD_SPACING = 40

local function CreateAndShowStaticPopup(dialogName, text, onAcceptFunc)
    StaticPopupDialogs[dialogName] = {
        text = text,
        button1 = "Yes",
        button2 = "No",
        OnAccept = onAcceptFunc,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,

        OnShow = function(self)
            if configFrame then
                configFrame:EnableKeyboard(false)
            end
        end,

        OnHide = function()
            if configFrame and configFrame:IsVisible() then
                configFrame:EnableKeyboard(true)

                C_Timer.After(0.05, function()
                    if configFrame:IsVisible() then
                        PSC_FrameManager:BringToFront("ConfigUI")
                    end
                end)
            end
        end
    }

    local popup = StaticPopup_Show(dialogName)

    if popup then
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(2000)
        popup:SetPoint("CENTER", UIParent, "CENTER")
        popup:Raise()

        popup:SetPropagateKeyboardInput(false)
        popup:EnableKeyboard(true)

        popup:SetScript("OnKeyDown", nil)
    end

    return popup
end

local function ShowResetStatsConfirmation()
    CreateAndShowStaticPopup("PSC_RESET_STATS",
        "Are you sure you want to reset all kill/death statistics? This cannot be undone.", function()
            ResetAllStatsToDefault()
        end)
end

local function ResetAllSettingsToDefault()
    PSC_LoadDefaultSettings()
    ReloadUI()
end

local function ShowResetDefaultsConfirmation()
    CreateAndShowStaticPopup("PSC_RESET_DEFAULTS",
        "Are you sure you want to reset all settings to defaults? This will not affect your kill/death statistics. Forces a UI reload!",
        function()
            ResetAllSettingsToDefault()
        end)
end

local function CreateSectionHeader(parent, text, xOffset, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    header:SetText(text)
    header:SetTextColor(PSC_CONFIG_HEADER_R, PSC_CONFIG_HEADER_G, PSC_CONFIG_HEADER_B)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetSize(parent:GetWidth() - (xOffset * 2), 1)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.7)

    return header
end

local function CreateInputField(parent, labelText, width, initialValue, onTextChangedFunc)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 50)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    editBox:SetSize(width - 20, 20)
    editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -5)
    editBox:SetAutoFocus(false)
    editBox:SetText(initialValue or "")

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(initialValue)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if onTextChangedFunc then
            onTextChangedFunc(self:GetText())
        end
    end)

    return container, editBox
end

local function CreateCheckbox(parent, labelText, initialValue, onClickFunc)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    checkbox:SetChecked(initialValue)
    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        onClickFunc(checked)
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    label:SetText(labelText)

    return checkbox, label
end

local function CreateButton(parent, text, width, height, onClickFunc)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:SetScript("OnClick", onClickFunc)

    return button
end

local function CreateDropdown(parent, labelText, options, initialValue, onSelectionChangedFunc)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 40)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -5)
    label:SetText(labelText)

    local dropdownName = "PSC_Dropdown_" .. tostring(math.random(1000000, 9999999))
    local dropdown = CreateFrame("Frame", dropdownName, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -18, -5)
    UIDropDownMenu_SetWidth(dropdown, 150)

    local function InitializeDropdown(self, level)
        for i, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, option.value)
                if onSelectionChangedFunc then
                    onSelectionChangedFunc(option.value)
                end
            end
            info.checked = (option.value == UIDropDownMenu_GetSelectedValue(dropdown))
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, initialValue)

    return container, dropdown
end

local function CreateAnnouncementSection(parent, yOffset)
    local announcementSettingsHeader = CreateSectionHeader(parent, SmartPVP_L("cfg_sec_announce"), 20, yOffset)

    local enableKillAnnounceCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_announce_kills"), PSC_DB.EnableKillAnnounceMessages,
        function(checked)
            PSC_DB.EnableKillAnnounceMessages = checked
        end)
    enableKillAnnounceCheckbox:SetPoint("TOPLEFT", announcementSettingsHeader, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 10)
    parent.enableKillAnnounceCheckbox = enableKillAnnounceCheckbox
    enableKillAnnounceCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_announce_kills"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_announce_kills"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableKillAnnounceCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local includePlayerDetailsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_incl_player"),
        PSC_DB.IncludePlayerDetailsInAnnounce,
        function(checked)
            PSC_DB.IncludePlayerDetailsInAnnounce = checked
        end)
    includePlayerDetailsCheckbox:SetPoint("TOPLEFT", enableKillAnnounceCheckbox, "BOTTOMLEFT", 40, -CHECKBOX_SPACING + 5)
    parent.includePlayerDetailsCheckbox = includePlayerDetailsCheckbox
    includePlayerDetailsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SmartPVP_L("cfg_tt_incl_player"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_incl_player"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    includePlayerDetailsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local includeGuildDetailsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_incl_guild"),
        PSC_DB.IncludeGuildDetailsInAnnounce,
        function(checked)
            PSC_DB.IncludeGuildDetailsInAnnounce = checked
        end)
    includeGuildDetailsCheckbox:SetPoint("TOPLEFT", includePlayerDetailsCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 5)
    parent.includeGuildDetailsCheckbox = includeGuildDetailsCheckbox
    includeGuildDetailsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SmartPVP_L("cfg_tt_incl_guild"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_incl_guild"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    includeGuildDetailsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local enableRecordAnnounceCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_announce_pb"),
        PSC_DB.EnableRecordAnnounceMessages, function(checked)
            PSC_DB.EnableRecordAnnounceMessages = checked
        end)
    enableRecordAnnounceCheckbox:SetPoint("TOPLEFT", includeGuildDetailsCheckbox, "BOTTOMLEFT", -40, -CHECKBOX_SPACING)
    parent.enableRecordAnnounceCheckbox = enableRecordAnnounceCheckbox
    enableRecordAnnounceCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_pb"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_pb_streak"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableRecordAnnounceCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local enableMultiKillAnnounceCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_announce_multi"),
        PSC_DB.EnableMultiKillAnnounceMessages, function(checked)
            PSC_DB.EnableMultiKillAnnounceMessages = checked
        end)
    enableMultiKillAnnounceCheckbox:SetPoint("TOPLEFT", enableKillAnnounceCheckbox, "TOPLEFT", 300, 0)
    parent.enableMultiKillAnnounceCheckbox = enableMultiKillAnnounceCheckbox
    enableMultiKillAnnounceCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_pb"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_pb_multi"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableMultiKillAnnounceCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local slider = CreateFrame("Slider", "PSC_MultiKillThresholdSlider", parent, "OptionsSliderTemplate")
    slider:SetWidth(200)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", announcementSettingsHeader, "TOPLEFT", 305, -CHECKBOX_SPACING - 74)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(2, 10)
    slider:SetValueStep(1)
    slider:SetValue(PSC_DB.MultiKillThreshold or 3)
    getglobal(slider:GetName() .. "Low"):SetText("Double")
    getglobal(slider:GetName() .. "High"):SetText("Deca")
    getglobal(slider:GetName() .. "Text"):SetText(SmartPVP_L("cfg_sl_multikill") .. (PSC_DB.MultiKillThreshold or 3))
    parent.multiKillSlider = slider

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        self:SetValue(value)
        getglobal(self:GetName() .. "Text"):SetText(SmartPVP_L("cfg_sl_multikill") .. value)
        PSC_DB.MultiKillThreshold = value
    end)

    local announceChannelOptions = {
        {text = SmartPVP_L("cfg_dd_group"), value = "GROUP"},
        {text = SmartPVP_L("cfg_dd_raid"),  value = "RAID"},
        {text = SmartPVP_L("cfg_dd_guild"), value = "GUILD"},
        {text = SmartPVP_L("cfg_dd_self"),  value = "SELF"}
    }
    local announceChannelLabelByValue = {
        GROUP = SmartPVP_L("cfg_dd_group"), RAID = SmartPVP_L("cfg_dd_raid"),
        GUILD = SmartPVP_L("cfg_dd_guild"), SELF = SmartPVP_L("cfg_dd_self"),
    }

    local announceChannelContainer, announceChannelDropdown = CreateDropdown(parent, SmartPVP_L("cfg_dd_label"),
        announceChannelOptions, PSC_DB.AnnounceChannel or "GROUP", function(selectedValue)
            PSC_DB.AnnounceChannel = selectedValue
            UIDropDownMenu_SetText(announceChannelDropdown, announceChannelLabelByValue[selectedValue])
        end)
    announceChannelContainer:SetPoint("TOPLEFT", enableRecordAnnounceCheckbox, "BOTTOMLEFT", 303, 44)
    parent.announceChannelDropdown = announceChannelDropdown

    -- Ensure the dropdown shows the correct initial value
    if announceChannelDropdown and announceChannelDropdown:GetName() then
        local cur = PSC_DB.AnnounceChannel or "GROUP"
        UIDropDownMenu_SetSelectedValue(announceChannelDropdown, cur)
        UIDropDownMenu_SetText(announceChannelDropdown, announceChannelLabelByValue[cur])
    end

    announceChannelContainer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_channel"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_channel_group"), 1, 1, 1, true)
        GameTooltip:AddLine("\n", 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_channel_raid"), 1, 1, 1, true)
        GameTooltip:AddLine("\n", 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_channel_guild"), 1, 1, 1, true)
        GameTooltip:AddLine("\n", 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_channel_self"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    announceChannelContainer:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local battlegroundModeHeader = CreateSectionHeader(parent, SmartPVP_L("cfg_sec_bgmode"), 20, -195)

    local autoBGModeCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_auto_bg"), PSC_DB.AutoBattlegroundMode,
        function(checked)
            PSC_DB.AutoBattlegroundMode = checked
            PSC_CheckBattlegroundStatus()
        end)
    autoBGModeCheckbox:SetPoint("TOPLEFT", battlegroundModeHeader, "BOTTOMLEFT", 0, -HEADER_ELEMENT_SPACING)
    parent.autoBGModeCheckbox = autoBGModeCheckbox

    autoBGModeCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_auto_bg"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_auto_bg"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoBGModeCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local assistsInBGCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_count_assist"),
        PSC_DB.CountAssistsInBattlegrounds, function(checked)
            PSC_DB.CountAssistsInBattlegrounds = checked
        end)
    assistsInBGCheckbox:SetPoint("TOPLEFT", autoBGModeCheckbox, "BOTTOMLEFT", 40, -CHECKBOX_SPACING + 5)
    parent.assistsInBGCheckbox = assistsInBGCheckbox

    assistsInBGCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_assist"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_assist"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    assistsInBGCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local forceEnableBGModeCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_always_bg"),
        PSC_DB.ForceBattlegroundMode, function(checked)
            PSC_DB.ForceBattlegroundMode = checked
            PSC_CheckBattlegroundStatus()
        end)
    forceEnableBGModeCheckbox:SetPoint("TOPLEFT", assistsInBGCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 5)
    parent.manualBGModeCheckbox = forceEnableBGModeCheckbox

    forceEnableBGModeCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tt_always_bg"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_always_bg"), 1, 1, 1, false)
        GameTooltip:Show()
    end)
    forceEnableBGModeCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local trackBGKillsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_count_bgkills"),
        PSC_DB.CountKillsInBattlegrounds, function(checked)
            PSC_DB.CountKillsInBattlegrounds = checked
        end)
    trackBGKillsCheckbox:SetPoint("TOPLEFT", assistsInBGCheckbox, "TOPLEFT", 260, 0)
    parent.trackBGKillsCheckbox = trackBGKillsCheckbox

    trackBGKillsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_count_bgkills"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_bgkills"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    trackBGKillsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local trackBGDeathsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_count_bgdeaths"),
        PSC_DB.CountDeathsInBattlegrounds, function(checked)
            PSC_DB.CountDeathsInBattlegrounds = checked
        end)
    trackBGDeathsCheckbox:SetPoint("TOPLEFT", trackBGKillsCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.trackBGDeathsCheckbox = trackBGDeathsCheckbox

    trackBGDeathsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_count_bgdeaths"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_bgdeaths"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    trackBGDeathsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local killMilestonesHeader = CreateSectionHeader(parent, SmartPVP_L("cfg_sec_milestones"), 610, -40) -- SmartPVP: coluna direita

    local showKillMilestonesCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_show_milestones"), PSC_DB.ShowKillMilestones,
        function(checked)
            PSC_DB.ShowKillMilestones = checked
        end)
    showKillMilestonesCheckbox:SetPoint("TOPLEFT", killMilestonesHeader, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 10)
    parent.showKillMilestonesCheckbox = showKillMilestonesCheckbox

    showKillMilestonesCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_show_milestones"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_milestones1"), 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_milestones2"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    showKillMilestonesCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local killMilestoneSoundsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_milestone_sound"),
        PSC_DB.EnableKillMilestoneSound, function(checked)
            PSC_DB.EnableKillMilestoneSound = checked
        end)
    killMilestoneSoundsCheckbox:SetPoint("TOPLEFT", showKillMilestonesCheckbox, "BOTTOMLEFT", 40, -CHECKBOX_SPACING + 5)
    parent.killMilestoneSoundsCheckbox = killMilestoneSoundsCheckbox

    killMilestoneSoundsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_milestone_sound"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_milestone_sound"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    killMilestoneSoundsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local showMilestoneForFirstKillCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_milestone_first"),
        PSC_DB.ShowMilestoneForFirstKill, function(checked)
            PSC_DB.ShowMilestoneForFirstKill = checked
        end)
    showMilestoneForFirstKillCheckbox:SetPoint("TOPLEFT", killMilestoneSoundsCheckbox, "BOTTOMLEFT", 0,
        -CHECKBOX_SPACING + 5)
    parent.showMilestoneForFirstKillCheckbox = showMilestoneForFirstKillCheckbox

    showMilestoneForFirstKillCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_milestone_first"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_milestone_first"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    showMilestoneForFirstKillCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local milestoneIntervalSlider =
        CreateFrame("Slider", "PSC_MilestoneIntervalSlider", parent, "OptionsSliderTemplate")
    milestoneIntervalSlider:SetWidth(200)
    milestoneIntervalSlider:SetHeight(16)
    milestoneIntervalSlider:SetPoint("TOPLEFT", killMilestonesHeader, "BOTTOMLEFT", 310, -CHECKBOX_SPACING - 25)
    milestoneIntervalSlider:SetOrientation("HORIZONTAL")
    milestoneIntervalSlider:SetMinMaxValues(3, 10)
    milestoneIntervalSlider:SetValueStep(1)
    milestoneIntervalSlider:SetValue(PSC_DB.KillMilestoneInterval or 5)
    getglobal(milestoneIntervalSlider:GetName() .. "Low"):SetText("3")
    getglobal(milestoneIntervalSlider:GetName() .. "High"):SetText("10")
    getglobal(milestoneIntervalSlider:GetName() .. "Text"):SetText(
        SmartPVP_L("cfg_sl_interval_pre") .. (PSC_DB.KillMilestoneInterval or 5) .. SmartPVP_L("cfg_sl_interval_post"))
    parent.milestoneIntervalSlider = milestoneIntervalSlider

    milestoneIntervalSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        self:SetValue(value)
        getglobal(self:GetName() .. "Text"):SetText(SmartPVP_L("cfg_sl_interval_pre") .. value .. SmartPVP_L("cfg_sl_interval_post"))
        PSC_DB.KillMilestoneInterval = value
    end)

    local milestoneAutoHideTimeSlider =
        CreateFrame("Slider", "PSC_MilestoneTimeSlider", parent, "OptionsSliderTemplate")
    milestoneAutoHideTimeSlider:SetWidth(200)
    milestoneAutoHideTimeSlider:SetHeight(16)
    milestoneAutoHideTimeSlider:SetPoint("TOPLEFT", milestoneIntervalSlider, "BOTTOMLEFT", 0, -30)
    milestoneAutoHideTimeSlider:SetOrientation("HORIZONTAL")
    milestoneAutoHideTimeSlider:SetMinMaxValues(1, 15)
    milestoneAutoHideTimeSlider:SetValueStep(1)
    milestoneAutoHideTimeSlider:SetValue(PSC_DB.KillMilestoneAutoHideTime or 5)
    getglobal(milestoneAutoHideTimeSlider:GetName() .. "Low"):SetText(SmartPVP_L("cfg_sl_1sec"))
    getglobal(milestoneAutoHideTimeSlider:GetName() .. "High"):SetText(SmartPVP_L("cfg_sl_15sec"))
    getglobal(milestoneAutoHideTimeSlider:GetName() .. "Text"):SetText(
        SmartPVP_L("cfg_sl_hide_pre") .. (PSC_DB.KillMilestoneAutoHideTime or 5) .. SmartPVP_L("cfg_sl_hide_post"))
    parent.milestoneAutoHideTimeSlider = milestoneAutoHideTimeSlider

    milestoneAutoHideTimeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        self:SetValue(value)
        getglobal(self:GetName() .. "Text"):SetText(SmartPVP_L("cfg_sl_hide_pre") .. value .. SmartPVP_L("cfg_sl_hide_post"))
        PSC_DB.KillMilestoneAutoHideTime = value
    end)

    local testButton = CreateButton(parent, SmartPVP_L("cfg_btn_show_milestone"), 160, 22, function()
        local testKillCounts = {1, PSC_DB.KillMilestoneInterval, PSC_DB.KillMilestoneInterval * 2}
        local index = math.random(1, 3)

        if not PSC_DB.ShowMilestoneForFirstKill and testKillCounts[index] == 1 then
            index = 2
        end

        local classes = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
        local randomClass = classes[math.random(1, #classes)]

        local useHorde = (math.random(1, 2) == 1)

        local rank
        if math.random(1, 10) <= 3 then
            rank = 0
        else
            local rankRoll = math.random(1, 100)
            if rankRoll <= 50 then
                rank = math.random(1, 4)
                rank = math.random(5, 8)
            elseif rankRoll <= 90 then
                rank = math.random(9, 11)
            else
                rank = math.random(12, 14)
            end
        end

        PSC_ShowKillMilestone("TestPlayer", 60, randomClass, rank, testKillCounts[index])
    end)
    testButton:SetPoint("TOPLEFT", milestoneAutoHideTimeSlider, "BOTTOMLEFT", -2, -20)
    parent.milestoneTestButton = testButton

    local generalSectionHeader = CreateSectionHeader(parent, SmartPVP_L("cfg_sec_general"), 610, -235) -- SmartPVP: coluna direita

    local tooltipKillInfoCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_tooltip_kills"),
        PSC_DB.ShowScoreInPlayerTooltip, function(checked)
            PSC_DB.ShowScoreInPlayerTooltip = checked
        end)
    tooltipKillInfoCheckbox:SetPoint("TOPLEFT", generalSectionHeader, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 5)
    parent.tooltipKillInfoCheckbox = tooltipKillInfoCheckbox

    tooltipKillInfoCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tooltip_kills"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_tooltip_kills"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tooltipKillInfoCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local tooltipExtendedInfoCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_tooltip_deaths"),
        PSC_DB.ShowExtendedTooltipInfo or true, function(checked)
            PSC_DB.ShowExtendedTooltipInfo = checked
        end)
    tooltipExtendedInfoCheckbox:SetPoint("TOPLEFT", tooltipKillInfoCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.tooltipExtendedInfoCheckbox = tooltipExtendedInfoCheckbox

    tooltipExtendedInfoCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_tooltip_deaths"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_tooltip_deaths"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tooltipExtendedInfoCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local showAccountWideStatsCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_accountwide"),
        PSC_DB.ShowAccountWideStats, function(checked)
            PSC_DB.ShowAccountWideStats = checked
        end)
    showAccountWideStatsCheckbox:SetPoint("TOPLEFT", tooltipKillInfoCheckbox, "TOPLEFT", 300, 0)
    parent.showAccountWideStatsCheckbox = showAccountWideStatsCheckbox
    showAccountWideStatsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_accountwide"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_accountwide1"), 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_accountwide2"), 1, 1, 1, true)
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_accountwide3"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    showAccountWideStatsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local autoOpenKillStreakCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_autoopen_streak"),
        PSC_DB.AutoOpenKillStreakPopup, function(checked)
            PSC_DB.AutoOpenKillStreakPopup = checked
        end)
    autoOpenKillStreakCheckbox:SetPoint("TOPLEFT", showAccountWideStatsCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.autoOpenKillStreakCheckbox = autoOpenKillStreakCheckbox
    autoOpenKillStreakCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_autoopen_streak"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_autoopen_streak"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoOpenKillStreakCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local capAchievementProgressCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_cap_achv"),
        PSC_DB.CapAchievementProgress, function(checked)
            PSC_DB.CapAchievementProgress = checked
        end)
    capAchievementProgressCheckbox:SetPoint("TOPLEFT", tooltipExtendedInfoCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.capAchievementProgressCheckbox = capAchievementProgressCheckbox
    capAchievementProgressCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_cap_achv"))
        GameTooltip:AddLine(SmartPVP_L("cfg_tb_cap_achv"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    capAchievementProgressCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- SmartPVP: toggle do HUD de sessao (sem precisar de /spvp hud)
    local showHUDCheckbox, _ = CreateCheckbox(parent, SmartPVP_L("cfg_show_hud"),
        SmartPVP_IsHUDShown and SmartPVP_IsHUDShown() or false, function(checked)
            if SmartPVP_SetHUD then SmartPVP_SetHUD(checked) end
        end)
    showHUDCheckbox:SetPoint("TOPLEFT", capAchievementProgressCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.showHUDCheckbox = showHUDCheckbox
    showHUDCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_show_hud"))
        GameTooltip:AddLine(SmartPVP_L("cfg_hud_tip"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    showHUDCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- SmartPVP: seletor de idioma EN/PT (troca = reload)
    local function langLabel()
        local lang = SmartPVP_Lang and SmartPVP_Lang() or "en"
        return SmartPVP_L("cfg_language") .. "  " .. (lang == "pt" and "Portugues" or "English")
    end
    local langButton = CreateButton(parent, langLabel(), 220, 22, function()
        SmartPVP_SetLang((SmartPVP_Lang and SmartPVP_Lang() == "en") and "pt" or "en")
        if parent.langButton then parent.langButton:SetText(langLabel()) end
        print("|cff00ccff[SmartPVP]|r " .. SmartPVP_L("cfg_lang_reload"))
    end)
    langButton:SetPoint("TOPLEFT", showHUDCheckbox, "BOTTOMLEFT", 6, -12)
    parent.langButton = langButton
    langButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SmartPVP_L("cfg_language"))
        GameTooltip:AddLine(SmartPVP_L("cfg_lang_reload"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    langButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return 320
end

local function CreateSoundsSection(parent, yOffset)
    local soundsHeader = CreateSectionHeader(parent, "Multi-Kill Sounds", 20, yOffset)

    local enableMultiKillSoundsCheckbox, _ = CreateCheckbox(parent, "Enable multi-kill sound effects",
        PSC_DB.EnableMultiKillSounds, function(checked)
            PSC_DB.EnableMultiKillSounds = checked
            if parent.soundPackDropdown and parent.soundPackDropdown:GetName() then
                if checked then
                    UIDropDownMenu_EnableDropDown(parent.soundPackDropdown)
                else
                    UIDropDownMenu_DisableDropDown(parent.soundPackDropdown)
                end
            end
        end)
    enableMultiKillSoundsCheckbox:SetPoint("TOPLEFT", soundsHeader, "BOTTOMLEFT", 0, -CHECKBOX_SPACING - 10)
    parent.enableMultiKillSoundsCheckbox = enableMultiKillSoundsCheckbox

    enableMultiKillSoundsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enable multi-kill sound effects")
        GameTooltip:AddLine("Play sound effects when you achieve a multi-kill.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableMultiKillSoundsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local soundPackOptions = {
        {text = "League of Legends", value = "LoL"},
        {text = "Unreal Tournament", value = "UT"}
    }

    local soundPackContainer, soundPackDropdown = CreateDropdown(parent, "Sound Pack:", soundPackOptions,
        PSC_DB.SoundPack or "LoL", function(selectedValue)
            PSC_DB.SoundPack = selectedValue
        end)
    soundPackContainer:SetPoint("TOPLEFT", enableMultiKillSoundsCheckbox, "BOTTOMLEFT", 40, -20)
    parent.soundPackDropdown = soundPackDropdown

    if not PSC_DB.EnableMultiKillSounds and soundPackDropdown:GetName() then
        UIDropDownMenu_DisableDropDown(soundPackDropdown)
    end

    local testSoundButton = CreateButton(parent, "Preview Sound Effect", 140, 22, function()
        local soundPack = PSC_DB.SoundPack or "LoL"
        local soundFile
        if soundPack == "LoL" then
            local lolSounds = {"double_kill.mp3", "triple_kill.mp3", "quadra_kill.mp3", "penta_kill.mp3"}
            local randomIndex = math.random(1, #lolSounds)
            soundFile = "Interface\\AddOns\\SmartPVP\\killboard\\sounds\\LoL\\" .. lolSounds[randomIndex]
        else
            local utSounds = {"first-blood.mp3", "head-hunter.mp3", "dominating.mp3", "double-kill.mp3", "combowhore.mp3", "triple-kill.mp3", "holy-shit.mp3", "unreal.mp3", "ultra-kill.mp3", "mega-kill.mp3", "ludicrous-kill.mp3", "monster-kill.mp3"}
            local randomIndex = math.random(1, #utSounds)
            soundFile = "Interface\\AddOns\\SmartPVP\\killboard\\sounds\\UT\\" .. utSounds[randomIndex]
        end
        PlaySoundFile(soundFile, "Master")
    end)
    testSoundButton:SetPoint("TOPLEFT", soundPackContainer, "BOTTOMLEFT", 0, -10)
    parent.testSoundButton = testSoundButton

    local enableDeathSoundsCheckbox, _ = CreateCheckbox(parent, "Play death sound effects",
        PSC_DB.EnableDeathSounds, function(checked)
            PSC_DB.EnableDeathSounds = checked
        end)
    enableDeathSoundsCheckbox:SetPoint("TOPLEFT", testSoundButton, "BOTTOMLEFT", 0, -20)
    parent.enableDeathSoundsCheckbox = enableDeathSoundsCheckbox

    enableDeathSoundsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Play death sound effects")
        GameTooltip:AddLine("Play a sound effect when you die.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableDeathSoundsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local enableSingleKillSoundsCheckbox, _ = CreateCheckbox(parent, "Play single kill sound effects",
        PSC_DB.EnableSingleKillSounds, function(checked)
            PSC_DB.EnableSingleKillSounds = checked
        end)
    enableSingleKillSoundsCheckbox:SetPoint("TOPLEFT", enableDeathSoundsCheckbox, "BOTTOMLEFT", 0, -CHECKBOX_SPACING + 2)
    parent.enableSingleKillSoundsCheckbox = enableSingleKillSoundsCheckbox

    enableSingleKillSoundsCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Play single kill sound effects")
        GameTooltip:AddLine("Play a sound effect when you get a kill (not part of a multi-kill).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enableSingleKillSoundsCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local descriptionText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descriptionText:SetPoint("TOPLEFT", enableSingleKillSoundsCheckbox, "BOTTOMLEFT", 0, -20)
    descriptionText:SetText("League of Legends: Classic structured announcements (Double Kill, Triple Kill, Quadra Kill, Penta Kill, Hexa Kill, Legendary Kill) with iconic LoL sounds for single kills and deaths.\n\nUnreal Tournament: Chaotic variety with multiple random sound options per kill count, offering unpredictable and diverse audio experiences.")
    descriptionText:SetJustifyH("LEFT")
    descriptionText:SetWidth(450)

    return 320
end

local function CreateMessageTemplatesSection(parent, yOffset)
    yOffset = yOffset

    local header, line = CreateSectionHeader(parent, SmartPVP_L("cfg_msg_header"), 20, yOffset)

    local killMsgContainer, killMsgEditBox = CreateInputField(parent, SmartPVP_L("cfg_msg_kill_label"), 560,
        PSC_DB.KillAnnounceMessage, function(text)
            PSC_DB.KillAnnounceMessage = text
        end)
    killMsgContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -HEADER_ELEMENT_SPACING - 10)

    local killAnnounceMessageDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    killAnnounceMessageDesc:SetPoint("TOPLEFT", killMsgEditBox, "BOTTOMLEFT", -4, -5)
    killAnnounceMessageDesc:SetText(SmartPVP_L("cfg_msg_kill_desc"))
    killAnnounceMessageDesc:SetJustifyH("LEFT")

    local streakEndedContainer, streakEndedEditBox = CreateInputField(parent, SmartPVP_L("cfg_msg_streak_label"), 560,
        PSC_DB.KillStreakEndedMessage, function(text)
            PSC_DB.KillStreakEndedMessage = text
        end)
    streakEndedContainer:SetPoint("TOPLEFT", killMsgContainer, "BOTTOMLEFT", 0, -MESSAGE_TEXTFIELD_SPACING)

    local streakEndedMessageDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    streakEndedMessageDesc:SetPoint("TOPLEFT", streakEndedEditBox, "BOTTOMLEFT", -4, -5)
    streakEndedMessageDesc:SetText(SmartPVP_L("cfg_msg_streak_desc"))
    streakEndedMessageDesc:SetJustifyH("LEFT")

    local newStreakContainer, newStreakEditBox = CreateInputField(parent, SmartPVP_L("cfg_msg_newstreak_label"), 560,
        PSC_DB.NewKillStreakRecordMessage, function(text)
            PSC_DB.NewKillStreakRecordMessage = text
        end)
    newStreakContainer:SetPoint("TOPLEFT", streakEndedContainer, "BOTTOMLEFT", 0, -MESSAGE_TEXTFIELD_SPACING)

    local newStreakMessageDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newStreakMessageDesc:SetPoint("TOPLEFT", newStreakEditBox, "BOTTOMLEFT", -4, -5)
    newStreakMessageDesc:SetText(SmartPVP_L("cfg_msg_streak_desc"))
    newStreakMessageDesc:SetJustifyH("LEFT")

    local multiKillContainer, multiKillEditBox = CreateInputField(parent, SmartPVP_L("cfg_msg_multikill_label"), 560,
        PSC_DB.NewMultiKillRecordMessage, function(text)
            PSC_DB.NewMultiKillRecordMessage = text
        end)
    multiKillContainer:SetPoint("TOPLEFT", newStreakContainer, "BOTTOMLEFT", 0, -MESSAGE_TEXTFIELD_SPACING)

    local multiKillMessageDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    multiKillMessageDesc:SetPoint("TOPLEFT", multiKillEditBox, "BOTTOMLEFT", -4, -5)
    multiKillMessageDesc:SetText(SmartPVP_L("cfg_msg_multikill_desc"))
    multiKillMessageDesc:SetJustifyH("LEFT")

    return {
        killMsg = killMsgEditBox,
        streakEnded = streakEndedEditBox,
        newStreak = newStreakEditBox,
        multiKill = multiKillEditBox
    }
end

local function CreateActionButtons(parent)
    local buttonContainer = CreateFrame("Frame", nil, parent)
    buttonContainer:SetSize(335, 30)
    buttonContainer:SetPoint("BOTTOM", parent, "BOTTOM", 0, 24) -- SmartPVP: Reset no rodape do General

    local buttonWidth = 160
    local buttonHeight = 25
    local buttonSpacing = 15

    local resetStatsBtn = CreateButton(buttonContainer, SmartPVP_L("cfg_btn_reset_stats"), buttonWidth, buttonHeight, function()
        ShowResetStatsConfirmation()
    end)

    local defaultsBtn = CreateButton(buttonContainer, SmartPVP_L("cfg_btn_reset_defaults"), buttonWidth, buttonHeight, function()
        ShowResetDefaultsConfirmation()
    end)

    resetStatsBtn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    defaultsBtn:SetPoint("LEFT", resetStatsBtn, "RIGHT", buttonSpacing, 0)

    return {
        resetBtn = resetStatsBtn,
        defaultsBtn = defaultsBtn
    }
end

local currentTestAchievement = 1

local function CreateTestAchievementButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(200, 22)
    button:SetText("Test Achievement Popup")
    button:SetPoint("TOPLEFT", 20, -240)

    button:SetScript("OnClick", function()
        -- Use our new test achievement function
        PVPSC.AchievementSystem:TestAchievementPopup()
    end)

    -- Create a simple explanation text
    local helpText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -5)
    helpText:SetText("Press to display a randomly styled test achievement popup")
    helpText:SetTextColor(0.8, 0.8, 0.8)

    return button
end

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "PSC_ConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1180, 560) -- SmartPVP: 2 colunas + Reset no rodape
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.CloseButton:SetScript("OnClick", function()
        PSC_FrameManager:HideFrame("ConfigUI")
    end)

    tinsert(UISpecialFrames, "PSC_ConfigFrame")

    frame.TitleText:SetText(SmartPVP_L("cfg_title"))

    return frame
end

function PSC_UpdateConfigUI()
    if not configFrame then
        return
    end

    configFrame.autoBGModeCheckbox:SetChecked(PSC_DB.AutoBattlegroundMode)
    configFrame.assistsInBGCheckbox:SetChecked(PSC_DB.CountAssistsInBattlegrounds)
    configFrame.manualBGModeCheckbox:SetChecked(PSC_DB.ForceBattlegroundMode)
    configFrame.tooltipKillInfoCheckbox:SetChecked(PSC_DB.ShowScoreInPlayerTooltip)
    configFrame.tooltipExtendedInfoCheckbox:SetChecked(PSC_DB.ShowExtendedTooltipInfo)
    configFrame.showKillMilestonesCheckbox:SetChecked(PSC_DB.ShowKillMilestones)
    configFrame.killMilestoneSoundsCheckbox:SetChecked(PSC_DB.EnableKillMilestoneSound)
    configFrame.showMilestoneForFirstKillCheckbox:SetChecked(PSC_DB.ShowMilestoneForFirstKill)
    configFrame.enableKillAnnounceCheckbox:SetChecked(PSC_DB.EnableKillAnnounceMessages)
    configFrame.includePlayerDetailsCheckbox:SetChecked(PSC_DB.IncludePlayerDetailsInAnnounce)
    configFrame.includeGuildDetailsCheckbox:SetChecked(PSC_DB.IncludeGuildDetailsInAnnounce)
    configFrame.enableRecordAnnounceCheckbox:SetChecked(PSC_DB.EnableRecordAnnounceMessages)
    configFrame.enableMultiKillAnnounceCheckbox:SetChecked(PSC_DB.EnableMultiKillAnnounceMessages)
    configFrame.showAccountWideStatsCheckbox:SetChecked(PSC_DB.ShowAccountWideStats)
    configFrame.trackBGKillsCheckbox:SetChecked(PSC_DB.CountKillsInBattlegrounds)
    configFrame.trackBGDeathsCheckbox:SetChecked(PSC_DB.CountDeathsInBattlegrounds)
    configFrame.autoOpenKillStreakCheckbox:SetChecked(PSC_DB.AutoOpenKillStreakPopup)

    if configFrame.capAchievementProgressCheckbox then
        configFrame.capAchievementProgressCheckbox:SetChecked(PSC_DB.CapAchievementProgress)
    end

    if configFrame.enableMultiKillSoundsCheckbox then
        configFrame.enableMultiKillSoundsCheckbox:SetChecked(PSC_DB.EnableMultiKillSounds)
    end

    if configFrame.enableDeathSoundsCheckbox then
        configFrame.enableDeathSoundsCheckbox:SetChecked(PSC_DB.EnableDeathSounds)
    end

    if configFrame.enableSingleKillSoundsCheckbox then
        configFrame.enableSingleKillSoundsCheckbox:SetChecked(PSC_DB.EnableSingleKillSounds)
    end

    if configFrame.soundPackDropdown and configFrame.soundPackDropdown:GetName() then
        UIDropDownMenu_SetSelectedValue(configFrame.soundPackDropdown, PSC_DB.SoundPack or "LoL")
        if PSC_DB.EnableMultiKillSounds then
            UIDropDownMenu_EnableDropDown(configFrame.soundPackDropdown)
        else
            UIDropDownMenu_DisableDropDown(configFrame.soundPackDropdown)
        end
    end

    if configFrame.multiKillSlider and configFrame.multiKillSlider:GetName() then
        configFrame.multiKillSlider:SetValue(PSC_DB.MultiKillThreshold or 3)
        getglobal(configFrame.multiKillSlider:GetName() .. "Text"):SetText(
            "Multi-Kill announce threshold: " .. (PSC_DB.MultiKillThreshold or 3))
    end

    if configFrame.announceChannelDropdown and configFrame.announceChannelDropdown:GetName() then
        local channelValue = PSC_DB.AnnounceChannel or "GROUP"
        UIDropDownMenu_SetSelectedValue(configFrame.announceChannelDropdown, channelValue)

        -- Set the display text based on the value
        local displayText = "Group Chat"
        if channelValue == "GUILD" then
            displayText = "Guild Chat"
        elseif channelValue == "RAID" then
            displayText = "Raid Chat"
        elseif channelValue == "SELF" then
            displayText = "Myself"
        end
        UIDropDownMenu_SetText(configFrame.announceChannelDropdown, displayText)
    end

    if configFrame.milestoneIntervalSlider and configFrame.milestoneIntervalSlider:GetName() then
        configFrame.milestoneIntervalSlider:SetValue(PSC_DB.KillMilestoneInterval or 5)
        getglobal(configFrame.milestoneIntervalSlider:GetName() .. "Text"):SetText(
            "Milestone interval: Every " .. (PSC_DB.KillMilestoneInterval or 5) .. " kills")
    end

    if configFrame.milestoneAutoHideTimeSlider and configFrame.milestoneAutoHideTimeSlider:GetName() then
        configFrame.milestoneAutoHideTimeSlider:SetValue(PSC_DB.KillMilestoneAutoHideTime or 5)
        getglobal(configFrame.milestoneAutoHideTimeSlider:GetName() .. "Text"):SetText(
            "Hide notification after: " .. (PSC_DB.KillMilestoneAutoHideTime or 5) .. " seconds")
    end

    configFrame.editBoxes.killMsg:SetText(PSC_DB.KillAnnounceMessage)
    configFrame.editBoxes.streakEnded:SetText(PSC_DB.KillStreakEndedMessage)
    configFrame.editBoxes.newStreak:SetText(PSC_DB.NewKillStreakRecordMessage)
    configFrame.editBoxes.multiKill:SetText(PSC_DB.NewMultiKillRecordMessage)
end

local function CreateTabSystem(parent)
    local tabWidth = 85
    local tabHeight = 32
    local tabs = {}
    local tabFrames = {}

    -- SmartPVP: estilo flat das abas (dourado no ativo, cinza no inativo)
    local function styleConfigTabs(sel)
        for i, t in ipairs(tabs) do
            local txt = _G[t:GetName() .. "Text"]
            if i == sel then
                if txt then txt:SetTextColor(1, 0.82, 0) end
                if t.spvpUnderline then t.spvpUnderline:Show() end
            else
                if txt then txt:SetTextColor(0.55, 0.55, 0.6) end
                if t.spvpUnderline then t.spvpUnderline:Hide() end
            end
        end
    end

    local tabContainer = CreateFrame("Frame", nil, parent)
    tabContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, -58) -- SmartPVP: espaco p/ abas no topo
    tabContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -7, 7)

    local tabNames = {SmartPVP_L("cfg_tab_general"), SmartPVP_L("cfg_tab_messages")} -- SmartPVP: sem About/Sounds/Reset (Reset foi p/ o rodape do General)
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", parent:GetName() .. "Tab" .. i, parent, "CharacterFrameTabButtonTemplate")
        tab:SetText(name)
        tab:SetID(i)

        tab:SetSize(tabWidth, tabHeight)

        -- SmartPVP: achata a aba (limpa texturas da Blizzard + underline dourado)
        for _, sfx in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled",
                               "SelectedLeft", "SelectedMiddle", "SelectedRight" }) do
            local r = _G[tab:GetName() .. sfx]
            if r then r:SetTexture(nil) end
        end
        if tab.GetHighlightTexture and tab:GetHighlightTexture() then
            tab:GetHighlightTexture():SetTexture(nil)
        end
        if not tab.spvpUnderline then
            tab.spvpUnderline = tab:CreateTexture(nil, "OVERLAY")
            tab.spvpUnderline:SetTexture(1, 0.82, 0)
            tab.spvpUnderline:SetHeight(2)
            tab.spvpUnderline:SetPoint("BOTTOMLEFT", 8, 6)
            tab.spvpUnderline:SetPoint("BOTTOMRIGHT", -8, 6)
            tab.spvpUnderline:Hide()
        end

        local tabMiddle = _G[tab:GetName() .. "Middle"]
        local tabLeft = _G[tab:GetName() .. "Left"]
        local tabRight = _G[tab:GetName() .. "Right"]
        local tabSelectedMiddle = _G[tab:GetName() .. "SelectedMiddle"]
        local tabSelectedLeft = _G[tab:GetName() .. "SelectedLeft"]
        local tabSelectedRight = _G[tab:GetName() .. "SelectedRight"]
        local tabText = _G[tab:GetName() .. "Text"]

        if tabMiddle then
            tabMiddle:ClearAllPoints()
            tabMiddle:SetPoint("LEFT", tabLeft, "RIGHT", 0, 0)
            tabMiddle:SetWidth(tabWidth - 31)
        end
        if tabSelectedMiddle then
            tabSelectedMiddle:ClearAllPoints()
            tabSelectedMiddle:SetPoint("LEFT", tabSelectedLeft, "RIGHT", 0, 0)
            tabSelectedMiddle:SetWidth(tabWidth - 31)
        end

        if i == 1 then
            tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -28) -- SmartPVP: abas no topo
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -8, 0)
        end

        if tabText then
            tabText:ClearAllPoints()
            tabText:SetPoint("CENTER", tab, "CENTER", 0, 2)
            tabText:SetJustifyH("CENTER")
            tabText:SetWidth(tabWidth - 40)
        end

        local contentFrame = CreateFrame("Frame", nil, tabContainer)
        contentFrame:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, -5)
        contentFrame:SetPoint("BOTTOMRIGHT", tabContainer, "BOTTOMRIGHT")
        contentFrame:Hide()

        tabFrames[i] = contentFrame
        table.insert(tabs, tab)

        tab:SetScript("OnClick", function()
            PanelTemplates_SetTab(parent, i)
            styleConfigTabs(i)
            for index, frame in ipairs(tabFrames) do
                if index == i then
                    frame:Show()
                    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
                else
                    frame:Hide()
                end
            end
        end)
        tab:SetScript("OnEnter", function(self)
            local txt = _G[self:GetName() .. "Text"]
            if txt and self.spvpUnderline and not self.spvpUnderline:IsShown() then
                txt:SetTextColor(0.9, 0.9, 0.95)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            local txt = _G[self:GetName() .. "Text"]
            if txt and self.spvpUnderline and not self.spvpUnderline:IsShown() then
                txt:SetTextColor(0.55, 0.55, 0.6)
            end
        end)
    end

    parent.tabs = tabs
    parent.numTabs = #tabs
    PanelTemplates_SetNumTabs(parent, #tabs)
    PanelTemplates_SetTab(parent, 1)
    tabFrames[1]:Show()

    for i, tab in ipairs(tabs) do
        PanelTemplates_TabResize(tab, 0)
    end
    styleConfigTabs(1) -- SmartPVP: estado inicial das abas flat

    return tabFrames
end

local function CreateCopyableField(parent, label, text, anchorTo, xOffset, yOffset, customWidth)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset, yOffset)
    labelText:SetText(label)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    local width = customWidth or 285
    editBox:SetSize(width, 20)
    editBox:SetPoint("TOPLEFT", labelText, "TOPLEFT", labelText:GetStringWidth() + 10, 5)
    editBox:SetText(text)
    editBox:SetTextColor(0.3, 0.6, 1.0)

    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
    end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(text)
            self:HighlightText()
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return labelText, editBox
end

local function CreateAboutTab(parent)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", parent, "TOP", 0, -20)
    header:SetText("PvP Stats (Classic)")
    header:SetTextColor(PSC_CONFIG_HEADER_R, PSC_CONFIG_HEADER_G, PSC_CONFIG_HEADER_B)

    local versionText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("TOP", header, "BOTTOM", 0, -5)
    versionText:SetText("Version: " .. PSC_GetAddonVersion())
    versionText:SetTextColor(1, 1, 1)

    local creditsHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    creditsHeader:SetPoint("TOP", header, "BOTTOM", 0, -60)
    creditsHeader:SetText("Credits")
    creditsHeader:SetTextColor(PSC_CONFIG_HEADER_R, PSC_CONFIG_HEADER_G, PSC_CONFIG_HEADER_B)

    local logo = parent:CreateTexture(nil, "ARTWORK")
    logo:SetSize(240, 240)
    logo:SetPoint("TOP", creditsHeader, "BOTTOM", 0, -10)
    logo:SetTexture("Interface\\AddOns\\SmartPVP\\killboard\\img\\RedridgePoliceLogo.blp")

    local hunterColor = RAID_CLASS_COLORS["HUNTER"] or {
        r = 0.67,
        g = 0.83,
        b = 0.45
    }

    local contentWidth = 300
    local creditsContainer = CreateFrame("Frame", nil, parent)
    creditsContainer:SetSize(contentWidth, 200)
    creditsContainer:SetPoint("TOP", logo, "BOTTOM", 29, -10)

    local devsLabel = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    devsLabel:SetPoint("TOPLEFT", creditsContainer, "TOPLEFT", 0, 0)
    devsLabel:SetText("Developed by:")

    local firstAuthorText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    firstAuthorText:SetPoint("TOPLEFT", devsLabel, "TOPRIGHT", 5, 0)
    firstAuthorText:SetText("Severussnipe")
    firstAuthorText:SetTextColor(hunterColor.r, hunterColor.g, hunterColor.b)

    local andText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    andText:SetPoint("TOPLEFT", firstAuthorText, "TOPRIGHT", 5, 0)
    andText:SetText("&")
    andText:SetTextColor(1, 1, 1) -- Set color to white

    local secondAuthorText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secondAuthorText:SetPoint("TOPLEFT", andText, "TOPRIGHT", 5, 0)
    secondAuthorText:SetText("Hkfarmer")
    secondAuthorText:SetTextColor(hunterColor.r, hunterColor.g, hunterColor.b)

    local guildText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildText:SetPoint("TOPLEFT", devsLabel, "BOTTOMLEFT", 0, -10)
    guildText:SetText("Guild: ")
    guildText:SetTextColor(PSC_CONFIG_HEADER_R, PSC_CONFIG_HEADER_G, PSC_CONFIG_HEADER_B)

    local guildNameText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildNameText:SetPoint("TOPLEFT", guildText, "TOPRIGHT", 0, 0)
    guildNameText:SetText("<Redridge Police>")
    guildNameText:SetTextColor(1, 1, 1) -- Set color to white

    local realmText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    realmText:SetPoint("TOPLEFT", guildText, "BOTTOMLEFT", 0, -10)
    realmText:SetText("Realm: ")
    realmText:SetTextColor(PSC_CONFIG_HEADER_R, PSC_CONFIG_HEADER_G, PSC_CONFIG_HEADER_B)

    local realmNameText = creditsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    realmNameText:SetPoint("TOPLEFT", realmText, "TOPRIGHT", 0, 0)
    realmNameText:SetText("Spineshatter (EU)")
    realmNameText:SetTextColor(1, 1, 1) -- Set color to white

    local discordLabel, discordField = CreateCopyableField(creditsContainer, "Discord:", "https://discord.gg/ZBaN2xk5h3",
        realmText, -60, -50)
    local githubLabel, githubField = CreateCopyableField(creditsContainer, "GitHub: ",
        "github.com/randomdude163/WoWClassic_PvPStats", discordLabel, 0, -20)
    local contactLabel, contactField = CreateCopyableField(creditsContainer, "Contact:", "redridgepolice@outlook.com",
        githubLabel, 0, -20)
    local curseforgeLabel, curseforgeField = CreateCopyableField(creditsContainer, "CurseForge:", "curseforge.com/wow/addons/pvp-stats-classic",
        contactLabel, 0, -20, 265)

    return parent
end

function PSC_CreateConfigFrame()
    if configFrame then
        configFrame:Show()
        return
    end

    configFrame = CreateMainFrame()
    PSC_FrameManager:RegisterFrame(configFrame, "ConfigUI")

    local tabFrames = CreateTabSystem(configFrame)

    local currentY = -10
    local announcementHeight = CreateAnnouncementSection(tabFrames[1], currentY)

    configFrame.autoBGModeCheckbox = tabFrames[1].autoBGModeCheckbox
    configFrame.assistsInBGCheckbox = tabFrames[1].assistsInBGCheckbox
    configFrame.manualBGModeCheckbox = tabFrames[1].manualBGModeCheckbox
    configFrame.tooltipKillInfoCheckbox = tabFrames[1].tooltipKillInfoCheckbox
    configFrame.showKillMilestonesCheckbox = tabFrames[1].showKillMilestonesCheckbox
    configFrame.killMilestoneSoundsCheckbox = tabFrames[1].killMilestoneSoundsCheckbox
    configFrame.showMilestoneForFirstKillCheckbox = tabFrames[1].showMilestoneForFirstKillCheckbox
    configFrame.enableKillAnnounceCheckbox = tabFrames[1].enableKillAnnounceCheckbox
    configFrame.includePlayerDetailsCheckbox = tabFrames[1].includePlayerDetailsCheckbox
    configFrame.includeGuildDetailsCheckbox = tabFrames[1].includeGuildDetailsCheckbox
    configFrame.enableRecordAnnounceCheckbox = tabFrames[1].enableRecordAnnounceCheckbox
    configFrame.enableMultiKillAnnounceCheckbox = tabFrames[1].enableMultiKillAnnounceCheckbox
    configFrame.showAccountWideStatsCheckbox = tabFrames[1].showAccountWideStatsCheckbox
    configFrame.autoOpenKillStreakCheckbox = tabFrames[1].autoOpenKillStreakCheckbox
    configFrame.trackBGKillsCheckbox = tabFrames[1].trackBGKillsCheckbox
    configFrame.trackBGDeathsCheckbox = tabFrames[1].trackBGDeathsCheckbox
    configFrame.milestoneIntervalSlider = tabFrames[1].milestoneIntervalSlider
    configFrame.milestoneAutoHideTimeSlider = tabFrames[1].milestoneAutoHideTimeSlider
    configFrame.multiKillSlider = tabFrames[1].multiKillSlider
    configFrame.tooltipExtendedInfoCheckbox = tabFrames[1].tooltipExtendedInfoCheckbox
    configFrame.announceChannelDropdown = tabFrames[1].announceChannelDropdown

    configFrame.editBoxes = CreateMessageTemplatesSection(tabFrames[2], -10)

    -- SmartPVP: aba Sounds removida (som nao funciona no CoA). Reset agora e tab 3.

    local resetButtons = CreateActionButtons(tabFrames[1]) -- SmartPVP: Reset fundido no General
    configFrame.resetButtons = resetButtons

    -- SmartPVP: aba About removida (CreateAboutTab nao e mais chamada)

    PanelTemplates_SetTab(configFrame, 1)
    tabFrames[1]:Show()

    PSC_UpdateConfigUI()

    return configFrame
end

function PSC_CreateConfigUI()
    if configFrame then
        PSC_FrameManager:ShowFrame("ConfigUI")
        return
    end

    PSC_CreateConfigFrame()
end
