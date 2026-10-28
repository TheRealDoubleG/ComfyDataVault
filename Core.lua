local ADDON_NAME = ...

ComfyDataVault = ComfyDataVault or {}
local V = ComfyDataVault

V.name = ADDON_NAME or "ComfyDataVault"
V.version = "0.5"
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

-- Only SavedVariables-safe primitives and tables are hashed. Traversal is
-- deterministic, including mixed-type table keys, and detects cycles.
-- This is an accidental-corruption fingerprint, not a cryptographic MAC.
local KEY_ORDER = {boolean = 1, number = 2, string = 3}
local function KeyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return KEY_ORDER[ta] < KEY_ORDER[tb] end
    if ta == "boolean" then return not a and b end
    return a < b
end

function V:Fingerprint(data)
    local h1, h2 = 2166136261, 1315423911
    local visited, count = {}, 0
    local function Feed(text)
        for i = 1, #text do
            local byte = text:byte(i)
            h1 = (h1 * 33 + byte) % 4294967291
            h2 = (h2 * 65599 + byte) % 4294967279
        end
    end
    local function Walk(value, depth)
        count = count + 1
        if count > 250000 or depth > 70 then return false, "database too deep or too large" end
        local t = type(value)
        if t == "string" then
            Feed("S" .. #value .. ":")
            Feed(value)
        elseif t == "number" then
            if value ~= value or value == math.huge or value == -math.huge then
                return false, "non-finite number"
            end
            Feed("N" .. string.format("%.17g", value) .. ";")
        elseif t == "boolean" then
            Feed(value and "B1" or "B0")
        elseif t == "table" then
            if visited[value] then return false, "circular table" end
            visited[value] = true
            local keys = {}
            for k in pairs(value) do
                if not KEY_ORDER[type(k)] then
                    visited[value] = nil
                    return false, "unsupported table key"
                end
                if type(k) == "number" and (k ~= k or k == math.huge or k == -math.huge) then
                    visited[value] = nil
                    return false, "non-finite table key"
                end
                keys[#keys + 1] = k
            end
            table.sort(keys, KeyLess)
            Feed("T" .. #keys .. "{")
            for _, key in ipairs(keys) do
                local ok, why = Walk(key, depth + 1)
                if not ok then return false, why end
                ok, why = Walk(value[key], depth + 1)
                if not ok then return false, why end
            end
            Feed("}")
            visited[value] = nil
        else
            return false, "unsupported SavedVariables value: " .. t
        end
        return true
    end
    local ok, why = Walk(data, 0)
    if not ok then return nil, why end
    return string.format("v1-%08x-%08x", h1, h2)
end

function V:EnsureDB()
    if type(ComfyDataVaultDB) ~= "table" then ComfyDataVaultDB = {} end
    ComfyDataVaultDB.schemaVersion = 2
    ComfyDataVaultDB.createdAt = ComfyDataVaultDB.createdAt or Epoch()
    if type(ComfyDataVaultDB.snapshots) ~= "table" then
        -- Preserve damaged metadata for manual inspection, never silently discard it.
        ComfyDataVaultDB.invalidSnapshots = ComfyDataVaultDB.snapshots
        ComfyDataVaultDB.snapshots = {}
    end
    if type(ComfyDataVaultDB.meta) ~= "table" then ComfyDataVaultDB.meta = {} end
    self.db = ComfyDataVaultDB
    return self.db
end

function V:ValidateData(data)
    if type(data) ~= "table" then return false, "not a table" end
    if type(data.characters) ~= "table" or next(data.characters) == nil then
        return false, "missing or empty characters"
    end
    for key, record in pairs(data.characters) do
        if type(key) ~= "string" or type(record) ~= "table" then
            return false, "invalid character record"
        end
    end
    for _, key in ipairs({"meta", "kills", "gathering", "quests", "loot", "wallet", "sessions", "accountTotals"}) do
        if data[key] ~= nil and type(data[key]) ~= "table" then
            return false, key .. " invalid"
        end
    end
    -- A checksum only proves a snapshot has not changed. It does not prove
    -- its structure is usable. Reject damaged nested records before backup
    -- or restore; tolerate missing keys from older schema versions.
    local nested = {
        kills = {"account", "characters", "sessions", "deaths"},
        gathering = {"nodes", "items", "zones", "characters", "sessions"},
        quests = {"completed", "characters"},
        loot = {"items", "characters", "sessions"},
        wallet = {"characters", "lastChanges", "currencies"},
    }
    for section, keys in pairs(nested) do
        local parent = data[section]
        if type(parent) == "table" then
            for _, key in ipairs(keys) do
                if parent[key] ~= nil and type(parent[key]) ~= "table" then
                    return false, section .. "." .. key .. " invalid"
                end
            end
        end
    end
    return true
end

function V:VerifySnapshot(snapshot)
    if type(snapshot) ~= "table" then return false, "invalid snapshot record" end
    local ok, why = self:ValidateData(snapshot.data)
    if not ok then return false, why end
    if type(snapshot.checksum) ~= "string" then
        return false, "legacy snapshot without checksum"
    end
    local actual, err = self:Fingerprint(snapshot.data)
    if not actual then return false, err end
    if actual ~= snapshot.checksum then return false, "checksum mismatch" end
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

    local copied = DeepCopy(data)
    local checksum, err = self:Fingerprint(copied)
    if not checksum then return false, err end

    local db = self:EnsureDB()
    local snapshot = {
        createdAt = Epoch(),
        reason = tostring(reason or "manual"),
        sourceVersion = type(ComfyData) == "table" and tostring(ComfyData.version or "?") or "?",
        schemaVersion = type(data.meta) == "table" and tonumber(data.meta.schemaVersion)
            or tonumber(data.schema)
            or 0,
        characterCount = CountKeys(data.characters),
        checksum = checksum,
        data = copied,
    }
    ok, why = self:VerifySnapshot(snapshot)
    if not ok then return false, why end

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
            local ok = self:VerifySnapshot(snapshot)
            if ok then return snapshot, i end
        end
    end
    return nil
end

function V:GetLatestSnapshotData()
    local snapshot = self:GetLatestValidSnapshot()
    if not snapshot then
        local migration = self:EnsureDB().migrationSnapshot
        if migration and self:VerifySnapshot(migration) then snapshot = migration end
    end
    if not snapshot then return nil end
    return DeepCopy(snapshot.data), snapshot
end

function V:GetMigrationSnapshotData()
    local snapshot = self:EnsureDB().migrationSnapshot
    if not snapshot or not self:VerifySnapshot(snapshot) then return nil end
    return DeepCopy(snapshot.data), snapshot
end

function V:ApplyRestore(data, snapshot)
    local ok, why = self:VerifySnapshot(snapshot)
    if not ok then return false, why end
    local replacement = DeepCopy(data)
    local db = self:EnsureDB()
    db.meta.lastRestoredAt = Epoch()
    db.meta.lastRestoredChecksum = snapshot.checksum
    ComfyDataDB = replacement
    if type(ComfyData) == "table" then ComfyData.db = replacement end
    self:Print("Verified snapshot restored to memory. Use /reload to save it.")
    return true, snapshot
end

function V:RestoreLatestToGlobal()
    local data, snapshot = self:GetLatestSnapshotData()
    if not data then return false, "no checksum-verified snapshot" end
    return self:ApplyRestore(data, snapshot)
end

function V:QuarantineData(data, reason)
    local db = self:EnsureDB()
    -- Never overwrite the first rescued corrupt copy in this session.
    if db.quarantinedData ~= nil then return false, "quarantine already occupied" end
    db.quarantinedData = DeepCopy(data)
    db.meta.quarantineReason = tostring(reason or "unknown")
    db.meta.quarantineAt = Epoch()
    return true
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
    commands:SetText("/cdvault snapshot  ·  /cdvault restore confirm  ·  /cdvault restore-migration confirm")

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
        V:Print("Restore replaces live data. To proceed: /cdvault restore confirm")
    elseif msg == "restore confirm" then
        local ok, why = V:RestoreLatestToGlobal()
        if not ok then V:Print("Restore failed: " .. tostring(why)) end
    elseif msg == "restore-migration" then
        V:Print("Migration restore replaces live data. To proceed: /cdvault restore-migration confirm")
    elseif msg == "restore-migration confirm" then
        local data, snapshot = V:GetMigrationSnapshotData()
        if data then
            local ok, why = V:ApplyRestore(data, snapshot)
            if not ok then V:Print("Restore failed: " .. tostring(why)) end
        else
            V:Print("No checksum-verified pre-migration snapshot available.")
        end
    else
        local status = V:GetStatus()
        V:Print("v" .. V.version .. " | snapshots " .. tostring(status.snapshotCount) .. "/" .. tostring(V.maxSnapshots)
            .. " | latest: " .. tostring(status.latestReason or "none"))
        V:Print("Commands: /cdvault snapshot | /cdvault restore confirm | /cdvault restore-migration confirm")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == V.name then V:EnsureDB(); V:RegisterBlizzardSettingsCategory() end
end)
