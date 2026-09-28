ComfyDataVault=ComfyDataVault or {}
local V=ComfyDataVault

function V:RegisterBlizzardSettingsCategory()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

    local canvas=CreateFrame("Frame")
    local isDE=type(GetLocale)=="function" and GetLocale()=="deDE"

    local title=canvas:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",16,-16)
    title:SetText("ComfyDataVault")

    local desc=canvas:CreateFontString(nil,"ARTWORK","GameFontHighlight")
    desc:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-12)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(isDE and "Backup- und Wiederherstellungsdienst für ComfyData. Dieses Addon hat keine normalen Einstellungen." or "Backup and recovery service for ComfyData. This addon has no regular settings.")

    local version=canvas:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    version:SetPoint("TOPLEFT",desc,"BOTTOMLEFT",0,-18)
    version:SetText((isDE and "Version: " or "Version: ")..tostring(self.version or "?"))

    local category=Settings.RegisterCanvasLayoutCategory(canvas,"ComfyDataVault")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory=category
end

local eventFrame=CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent",function()
    V:RegisterBlizzardSettingsCategory()
end)

V:RegisterBlizzardSettingsCategory()
