param(
    [string]$Distro = 'Dafeiyu-Ubuntu',
    [string]$DiskDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dafeiyu-wsl'),
    [switch]$RestartWslService
)
$ErrorActionPreference = 'Stop'
$resultPath = Join-Path $PSScriptRoot 'wsl-service-refresh-result.txt'
try {
    $diskPath = (Resolve-Path -LiteralPath $DiskDirectory).Path
    if (-not (Test-Path -LiteralPath (Join-Path $diskPath 'ext4.vhdx') -PathType Leaf)) { throw 'Disk not found' }
    $keys = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Where-Object {
        (Get-ItemProperty -LiteralPath $_.PSPath).DistributionName -eq $Distro
    })
    if ($keys.Count -ne 1) { throw 'Expected exactly one matching WSL distribution' }
    $entry = Get-ItemProperty -LiteralPath $keys[0].PSPath
    $backupPath = Join-Path $PSScriptRoot ('wsl-path-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [pscustomobject]@{DistributionName=$Distro;RegistryPath=$keys[0].Name;BasePath=$entry.BasePath} |
        ConvertTo-Json | Set-Content -LiteralPath $backupPath -Encoding utf8
    Set-ItemProperty -LiteralPath $keys[0].PSPath -Name BasePath -Value $diskPath
    if ($RestartWslService) { Restart-Service -Name WslService -Force }
    'SUCCESS' | Set-Content -LiteralPath $resultPath -Encoding ascii
} catch {
    ('FAILED: ' + $_.Exception.Message) | Set-Content -LiteralPath $resultPath -Encoding utf8
    exit 1
}