param(
    [Parameter(Mandatory=$true)][string]$WoWRoot,
    [Parameter(Mandatory=$true)][string]$BackupRoot
)
# Run this after logging out or /reload with the client fully closed.
# Never deletes an existing backup; creates a uniquely named new directory.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path (Resolve-Path -LiteralPath $WoWRoot).Path 'WTF'
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "WTF folder not found under '$WoWRoot'."
}
if (Get-Process -Name Wow, WowB -ErrorAction SilentlyContinue) {
    throw "Close World of Warcraft first, so SavedVariables are flushed to disk."
}
if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
}
$backupBase = (Resolve-Path -LiteralPath $BackupRoot).Path
if ($backupBase.StartsWith($source, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "BackupRoot must not be inside the WoW WTF source directory."
}
$folder = 'ComfyWTF-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 6))
$destination = Join-Path (Join-Path $backupBase $folder) 'WTF'
New-Item -ItemType Directory -Path $destination -Force | Out-Null

& robocopy.exe $source $destination /E /XJ /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NP /NFL /NDL
if ($LASTEXITCODE -ge 8) {
    throw "Robocopy failed with exit code $LASTEXITCODE. Backup folder preserved for inspection."
}
$files = @(Get-ChildItem -LiteralPath $destination -File -Recurse | Where-Object {
    $_.Name -in @('ComfyData.lua', 'ComfyData.lua.bak', 'ComfyDataVault.lua', 'ComfyDataVault.lua.bak')
})
if ($files.Count -eq 0) {
    throw "No ComfyData SavedVariables found. Verify addons have been loaded, then /reload or log out."
}
$manifest = foreach ($file in $files) {
    [pscustomobject]@{
        Path = $file.FullName.Substring($destination.Length).TrimStart('\')
        Bytes = $file.Length
        SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}
$manifest | Export-Csv -LiteralPath (Join-Path (Split-Path $destination -Parent) 'comfy-sha256.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Backup OK: $destination"
Write-Host "$($files.Count) ComfyData/Vault SavedVariables files in manifest."
