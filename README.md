# ComfyDataVault 0.5 (development)

WoW Forever 1.60.1 / Interface 16001. Separate SavedVariables file for
5 rotating backups and a protected pre-migration copy of ComfyDataDB.

Safety: deep-copy snapshots, deterministic two-part checksums, rejection
of empty or malformed tables, corruption detection on restore, and a
quarantine for damaged original live databases.

WoW slash commands:
- /cdvault : snapshot status
- /cdvault snapshot : save a verified snapshot
- /cdvault restore : show warning; no mutation
- /cdvault restore confirm : restore newest verified backup into RAM
- /cdvault restore-migration confirm : restore verified pre-migration copy

Run /reload after restoring. WoW writes SavedVariables at reload or logout.
An addon cannot persist immediately or protect against disk failure.

Legacy v0.4 snapshots lack a checksum and will not be automatically
restored by v0.5. Keep a copy of your previous WTF folder for manual
recovery; legacy snapshots are not deleted by the upgrade.

Windows external backup helper:
PowerShell: .\tools\backup-wtf.ps1 -WoWRoot 'D:\World of Warcraft\_classic_' -BackupRoot 'E:\WoW-WTF-Backups'
Adjust paths, then run with the WoW client CLOSED after logout.
The tool copies the entire WTF folder to a unique new directory and creates
a SHA256 manifest for ComfyData.lua / ComfyDataVault.lua and .bak variants.
PowerShell live integration has not yet been tested on the Windows gaming PC.

Offline tests:
lua5.1 tests/test_vault.lua .
lua5.4 tests/test_vault.lua .
