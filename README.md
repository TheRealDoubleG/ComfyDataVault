# ComfyDataVault

**Version 0.1 – Beta**  
**Target: World of Warcraft: Forever 1.60.1 / Interface 16001**

ComfyDataVault is the independent backup/recovery companion for **ComfyData**.

It has no normal configuration UI. It stores up to **five full validated snapshots** in a separate WoW SavedVariables file: `ComfyDataVaultDB.lua`.

## Why it is separate

ComfyData and ComfyDataVault intentionally use different SavedVariables. A broken migration or accidental reset of the live ComfyData table therefore does not automatically destroy the last Vault snapshots.

Updating/replacing addon folders inside `Interface/AddOns` does not overwrite either database. WoW stores them below the account's `WTF` folder.

## Commands

- `/cdvault` – status
- `/cdvault snapshot` – manual snapshot
- `/cdvault restore` – restore the newest valid snapshot in memory; then use `/reload`

For protection against a complete WTF-folder loss, back up the WTF folder externally as well.
