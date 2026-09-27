# ComfyDataVault

**Version 0.2 – Beta**  
**Target: World of Warcraft: Forever 1.60.1 / Interface 16001**

ComfyDataVault is the independent backup/recovery companion for **ComfyData**.

It has no normal configuration UI. It stores up to **five rolling validated snapshots** plus a separately protected **latest pre-migration snapshot** in a different WoW SavedVariables file: `ComfyDataVaultDB.lua`.

## Why it is separate

ComfyData and ComfyDataVault intentionally use different SavedVariables. A broken migration or accidental reset of the live ComfyData table therefore does not automatically destroy the last Vault snapshots.

Updating/replacing addon folders inside `Interface/AddOns` does not overwrite either database. WoW stores them below the account's `WTF` folder.

## Commands

- `/cdvault` – status
- `/cdvault snapshot` – manual snapshot
- `/cdvault restore` – restore the newest valid rolling snapshot in memory; then use `/reload`
- `/cdvault restore-migration` – restore the protected latest pre-migration snapshot

For protection against a complete WTF-folder loss, back up the WTF folder externally as well.
