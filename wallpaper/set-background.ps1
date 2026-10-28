#Requires -Version 5.1
<#
.SYNOPSIS
  给 Windows Terminal 设置背景图与透明度。

.DESCRIPTION
  只改 Windows Terminal settings.json 里的 backgroundImage / backgroundImageOpacity /
  colorScheme 相关字段，改之前自动备份，写入失败自动回滚。

  本脚本用 UTF8 无 BOM 写入：PowerShell 5.1 的 Set-Content -Encoding UTF8 会加 BOM，
  而 BOM 对 JSON 解析器是非法字符，会让 Windows Terminal 读不了配置。

.EXAMPLE
  .\set-background.ps1 -Show

.EXAMPLE
  .\set-background.ps1 -Image ".\einx-wallpaper.png" -Opacity 0.20

.EXAMPLE
  .\set-background.ps1 -Reset
#>
[CmdletBinding()]
param(
    [string]$Image,
    [double]$Opacity = 0.22,
    [switch]$Reset,
    [switch]$Show,
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Resolve-WtSettings {
    if ($SettingsPath) { return $SettingsPath }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    throw '找不到 Windows Terminal 的 settings.json，用 -SettingsPath 手动指定。'
}

function Show-Current($path) {
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $d = $json.profiles.defaults
    Write-Host "配置文件: $path"
    Write-Host "  backgroundImage        : $($d.backgroundImage)"
    Write-Host "  backgroundImageOpacity : $($d.backgroundImageOpacity)"
    Write-Host "  backgroundImageStretch : $($d.backgroundImageStretchMode)"
    Write-Host "  colorScheme            : $($d.colorScheme)"
}

$wtPath = Resolve-WtSettings
if ($Show) { Show-Current $wtPath; return }

if (-not $Reset -and -not $Image) {
    Write-Host @'
用法:
  .\set-background.ps1 -Show                          看当前设置
  .\set-background.ps1 -Image <路径> [-Opacity 0.22]  设置背景图
  .\set-background.ps1 -Reset                         移除背景图，恢复纯色底

透明度参考:
  照片 / 插画壁纸  -> 0.18 ~ 0.30
  纯色块 / 极简图  -> 0.35 ~ 0.50

改完要**完全关闭 Windows Terminal 再打开**才生效。
'@
    return
}

if (-not $Reset -and -not (Test-Path -LiteralPath $Image)) { throw "找不到图片: $Image" }
$target = if ($Reset) { $null } else { (Resolve-Path -LiteralPath $Image).Path }
$op = [Math]::Round([Math]::Min(1.0, [Math]::Max(0.0, $Opacity)), 2)

$backup = "$wtPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
Copy-Item -LiteralPath $wtPath -Destination $backup -Force
if (-not (Test-Path -LiteralPath $backup)) { throw "备份失败，已中止: $backup" }

$json = Get-Content -LiteralPath $wtPath -Raw -Encoding UTF8 | ConvertFrom-Json
$d = $json.profiles.defaults
foreach ($k in @('backgroundImage','backgroundImageOpacity','backgroundImageStretchMode','backgroundImageAlignment')) {
    if ($d.PSObject.Properties.Name -contains $k) { $d.PSObject.Properties.Remove($k) }
}
if ($target) {
    $d | Add-Member -NotePropertyName backgroundImage -NotePropertyValue $target -Force
    $d | Add-Member -NotePropertyName backgroundImageOpacity -NotePropertyValue $op -Force
    $d | Add-Member -NotePropertyName backgroundImageStretchMode -NotePropertyValue 'fill' -Force
    $d | Add-Member -NotePropertyName backgroundImageAlignment -NotePropertyValue 'center' -Force
}

$jsonText = $json | ConvertTo-Json -Depth 32
try {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($wtPath, $jsonText, $enc)
}
catch {
    Write-Host "写入失败，正在回滚: $($_.Exception.Message)"
    Copy-Item -LiteralPath $backup -Destination $wtPath -Force
    throw
}

Write-Host ''
if ($target) {
    Write-Host '背景已设置:'
    Write-Host "  图片   : $target"
    Write-Host "  透明度 : $op"
}
else {
    Write-Host '背景图已移除，终端恢复纯色底。'
}
Write-Host "  备份   : $backup"
Write-Host ''
Write-Host '完全关闭 Windows Terminal 再打开才会生效。'
