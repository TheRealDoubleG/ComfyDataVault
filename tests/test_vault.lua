local root = arg[1] or "."
time = function() return 100 end
ComfyDataVaultDB, ComfyDataDB, ComfyDataVault = nil, nil, nil
ComfyData = {version="0.6"}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {AddMessage=function() end}
local frames = {}
CreateFrame = function()
    local f={}
    function f:RegisterEvent(ev) self.registered=ev end
    function f:SetScript(ev,fn) self[ev]=fn end
    frames[#frames+1]=f
    return f
end
assert(loadfile(root.."/Core.lua"))("ComfyDataVault")
local V=ComfyDataVault
frames[1].OnEvent(frames[1],"ADDON_LOADED","ComfyDataVault")
local function db(name)
    return {meta={schemaVersion=2},
        characters={["Forever:"..(name or "Gerold")]={money=1500,level=20, identity={realm="Forever",class="MAGE"}}},
        kills={account={npc={count=2}}},gathering={nodes={},items={}},sessions={},accountTotals={}}
end
local tests=0
local function expect(x,message) tests=tests+1; assert(x,"Test "..tests..": "..message) end
local d=db()
local hash,why=V:Fingerprint(d)
expect(type(hash)=="string",tostring(why))
local shuffled=db();shuffled.characters["Forever:Gerold"].identity={class="MAGE",realm="Forever"}
expect(hash==V:Fingerprint(shuffled),"order-independent hashing")
expect(not V:CreateSnapshot({characters={}},"empty"),"empty rejected")
expect(not V:CreateSnapshot({characters="wrong"},"bad"),"bad characters rejected")
expect(V:CreateSnapshot(d,"manual"),"create")
expect(V:GetSnapshots()[1].checksum==hash,"checksum recorded")
local restored=V:GetLatestSnapshotData()
restored.characters["Forever:Gerold"].money=0
expect(V:GetLatestSnapshotData().characters["Forever:Gerold"].money==1500,"deep copy")
local first=V:GetSnapshots()[1]
first.data.characters["Forever:Gerold"].money=0
expect(not V:VerifySnapshot(first),"tamper detected")
expect(V:GetLatestValidSnapshot()==nil,"tamper not returned")
expect(V:CreateSnapshot(d,"manual"),"second snapshot created")
local c=db();c.self=c
expect(not V:CreateSnapshot(c,"cycle"),"cycles rejected")
local unsupported=db(); unsupported.code=function() end
expect(not V:CreateSnapshot(unsupported,"function"),"functions rejected")
for i=1,8 do expect(V:CreateSnapshot(db("Hero"..i),"session-"..i),"snapshot "..i) end
expect(#V:GetSnapshots()==5,"rolling five")
expect(V:GetSnapshots()[1].reason=="session-4","oldest pruned")
expect(V:CreateSnapshot(db("Migration"),"pre-migration-1-to-2"),"migration protected")
for i=1,9 do expect(V:CreateSnapshot(db("Later"..i),"later-"..i),"new snapshot") end
expect(V:GetMigrationSnapshotData().characters["Forever:Migration"]~=nil,"protected migration retained")
ComfyDataDB=db("LIVE")
local original=ComfyDataDB
SlashCmdList.COMFYDATAVAULT("restore")
expect(ComfyDataDB==original,"restore requires confirmation")
SlashCmdList.COMFYDATAVAULT("restore confirm")
expect(ComfyDataDB~=original,"restore confirm works")
expect(ComfyData.db==ComfyDataDB,"live handle replaced")
expect(ComfyDataDB.characters["Forever:Later9"]~=nil,"newest restored")
expect(V:QuarantineData({broken="original"},"damaged"),"first quarantine")
expect(not V:QuarantineData({broken="replacement"},"damaged"),"quarantine protected")
expect(V:EnsureDB().quarantinedData.broken=="original","quarantine retained")
expect(not V:VerifySnapshot({data=db("Legacy")}),"legacy not unverified restore")
expect(not V:VerifySnapshot({data=db("Fake"),checksum="v1-00000000-00000000"}),"checksum mismatch")
print("PASS: "..tests.." ComfyDataVault integrity/restore cases")
