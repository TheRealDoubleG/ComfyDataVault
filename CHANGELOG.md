# ComfyDataVault Changelog

## 0.3 Beta – 28.09.2026
- Registered ComfyDataVault in Blizzard's AddOns settings list.
- Added a lightweight status page showing rolling snapshot state and recovery commands.


## 0.2 Beta – 28.09.2026
- Added a separately protected latest pre-migration snapshot that is not removed by rolling-snapshot pruning.
- Added restore-migration recovery command.
- Kept five rolling snapshots for normal session/manual recovery.


## 0.1 Beta – 28.09.2026
- Initial independent ComfyData backup/recovery service.
- Keeps up to five deep-copy snapshots.
- Validates snapshots before accepting/restoring them.
- Separate SavedVariables file from the live ComfyData database.
- Added manual status, snapshot and restore commands.
