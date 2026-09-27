local ADDON_NAME = ...

ComfyDataVault = ComfyDataVault or {}
local V = ComfyDataVault

V.name = ADDON_NAME or "ComfyDataVault"
V.version = "0.3"
V.maxSnapshots = 5

local function Epoch()
    return type(time) == "function" and time() or 0
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end

local function CountKeys(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function V:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200ComfyDataVault:|r " .. tostring(message))
    end
end

function V:EnsureDB()
    if type(ComfyDataVaultDB) ~= "table" then ComfyDataVaultDB = {} end
    ComfyDataVaultDB.schemaVersion = 1
    ComfyDataVaultDB.createdAt = ComfyDataVaultDB.createdAt or Epoch()
    ComfyDataVaultDB.snapshots = ComfyDataVaultDB.snapshots or {}
    ComfyDataVaultDB.meta = ComfyDataVaultDB.meta or {}
    self.db = ComfyDataVaultDB
    return self.db
end

function V:ValidateData(data)
    if type(data) ~= "table" then return false, "not a table" end
    local chars = data.characters
    if chars ~= nil and type(chars) ~= "table" then return false, "characters invalid" end
    local meta = data.meta
    if meta ~= nil and type(meta) ~= "table" then return false, "meta invalid" end
    return true
end

function V:Prune()
    local db = self:EnsureDB()
    while #db.snapshots > self.maxSnapshots do
        table.remove(db.snapshots, 1)
    end
end

function V:CreateSnapshot(data, reason)
    local ok, why = self:ValidateData(data)
    if not ok then return false, why end

    local db = self:EnsureDB()
    local snapshot = {
        createdAt = Epoch(),
        reason = tostring(reason or "manual"),
        sourceVersion = type(ComfyData) == "table" and tostring(ComfyData.version or "?") or "?",
        schemaVersion = type(data.meta) == "table" and tonumber(data.meta.schemaVersion)
            or tonumber(data.schema)
            or 0,
        characterCount = CountKeys(data.characters),
        data = DeepCopy(data),
    }

    db.snapshots[#db.snapshots + 1] = snapshot
    if snapshot.reason:match("^pre%-migration") then
        db.migrationSnapshot = DeepCopy(snapshot)
        db.meta.lastMigrationSnapshotAt = snapshot.createdAt
    end
    db.meta.lastSnapshotAt = snapshot.createdAt
    db.meta.lastReason = snapshot.reason
    self:Prune()
    return true, #db.snapshots
end

function V:GetSnapshots()
    return self:EnsureDB().snapshots
end

function V:GetLatestValidSnapshot()
    local snapshots = self:GetSnapshots()
    for i = #snapshots, 1, -1 do
        local snapshot = snapshots[i]
        if type(snapshot) == "table" then
            local ok = self:ValidateData(snapshot.data)
            if ok then return snapshot, i end
        end
    end
    return nil
end

function V:GetLatestSnapshotData()
    local snapshot = self:GetLatestValidSnapshot()
    if not snapshot then
        local migration = self:EnsureDB().migrationSnapshot
        if migration and self:ValidateData(migration.data) then snapshot = migration end
    end
    if not snapshot then return nil end
    return DeepCopy(snapshot.data), snapshot
end

function V:GetMigrationSnapshotData()
    local snapshot = self:EnsureDB().migrationSnapshot
    if not snapshot or not self:ValidateData(snapshot.data) then return nil end
    return DeepCopy(snapshot.data), snapshot
end

function V:RestoreLatestToGlobal()
    local data, snapshot = self:GetLatestSnapshotData()
    if not data then return false, "no valid snapshot" end
    ComfyDataDB = data
    self:Print("Latest valid snapshot restored in memory. Use /reload now to finish recovery.")
    return true, snapshot
end

function V:GetStatus()
    local db = self:EnsureDB()
    local latest = self:GetLatestValidSnapshot()
    return {
        snapshotCount = #db.snapshots,
        latestAt = latest and latest.createdAt or nil,
        latestReason = latest and latest.reason or nil,
        latestCharacters = latest and latest.characterCount or 0,
    }
end

function V:RegisterBlizzardSettingsCategory()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

    local canvas = CreateFrame("Frame")
    local isDE = type(GetLocale) == "function" and GetLocale() == "deDE"

    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ComfyDataVault")

    local desc = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(isDE
        and "Unabhängiger Snapshot- und Wiederherstellungsdienst für ComfyData. Die Vault-Daten liegen in einer eigenen SavedVariables-Datei."
        or "Independent snapshot and recovery service for ComfyData. Vault data is stored in its own SavedVariables file.")

    local status = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    local info = self:GetStatus()
    status:SetText(string.format("v%s  ·  snapshots %d/%d  ·  latest: %s",
        tostring(self.version), tonumber(info.snapshotCount) or 0, tonumber(self.maxSnapshots) or 5,
        tostring(info.latestReason or "none")))

    local commands = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commands:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    commands:SetText("/cdvault snapshot  ·  /cdvault restore  ·  /cdvault restore-migration")

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "ComfyDataVault")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

SLASH_COMFYDATAVAULT1 = "/comfydatavault"
SLASH_COMFYDATAVAULT2 = "/cdvault"
SlashCmdList.COMFYDATAVAULT = function(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "snapshot" then
        if type(ComfyDataDB) == "table" then
            local ok, result = V:CreateSnapshot(ComfyDataDB, "manual")
            V:Print(ok and ("Snapshot created (" .. tostring(result) .. "/" .. V.maxSnapshots .. ").") or ("Snapshot failed: " .. tostring(result)))
        else
            V:Print("ComfyDataDB is not loaded.")
        end
    elseif msg == "restore" then
        local ok, why = V:RestoreLatestToGlobal()
        if not ok then V:Print("Restore failed: " .. tostring(why)) end
    elseif msg == "restore-migration" then
        local data, snapshot = V:GetMigrationSnapshotData()
        if data then
            ComfyDataDB = data
            V:Print("Pre-migration snapshot restored in memory. Use /reload now.")
        else
            V:Print("No valid pre-migration snapshot available.")
        end
    else
        local status = V:GetStatus()
        V:Print("v" .. V.version .. " | snapshots " .. tostring(status.snapshotCount) .. "/" .. tostring(V.maxSnapshots)
            .. " | latest: " .. tostring(status.latestReason or "none"))
        V:Print("Commands: /cdvault snapshot | /cdvault restore | /cdvault restore-migration")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == V.name then V:EnsureDB(); V:RegisterBlizzardSettingsCategory() end
end)
