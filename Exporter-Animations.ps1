param(
    [Parameter(Mandatory=$true)][string]$BlendFile,
    [ValidateSet('both','player','weapon')][string]$Mode='player',
    [string]$Clip='',
    [string]$NlaStrip='',
    [int]$StartFrame=-2147483648,
    [int]$EndFrame=-2147483648,
    [switch]$UpdateBase,
    [switch]$Template,
    [string]$Blender='C:\Program Files\Blender Foundation\Blender 5.2\blender.exe',
    [string]$Godot='C:\Users\sheensaw\MyApps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
)
$ErrorActionPreference='Stop'
$sourceFile=(Resolve-Path -LiteralPath $BlendFile).Path
if (-not (Test-Path -LiteralPath $Blender -PathType Leaf)) { throw "Blender introuvable : $Blender" }
$exportScript=Join-Path $PSScriptRoot 'tools\export_split_rig.py'
$exportArguments=@('--background',$sourceFile,'--python-exit-code','1','--python',$exportScript,'--','--mode',$Mode)
if ($Clip) { $exportArguments+=@('--clip',$Clip) }
if ($NlaStrip) { $exportArguments+=@('--nla-strip',$NlaStrip) }
if ($StartFrame -ne -2147483648) { $exportArguments+=@('--start',"$StartFrame") }
if ($EndFrame -ne -2147483648) { $exportArguments+=@('--end',"$EndFrame") }
if ($UpdateBase) { $exportArguments+='--update-base' }
if ($Template) { $exportArguments+='--template' }
& $Blender @exportArguments
if ($LASTEXITCODE -ne 0) { throw "Echec de l'export Blender ($LASTEXITCODE)." }
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot introuvable : $Godot. GLB exporte, configuration d'import a terminer." }
& $Godot --headless --path $PSScriptRoot --script res://tools/configure_animation_imports.gd
if ($LASTEXITCODE -ne 0) { throw "Echec de la configuration d'import Godot." }
Write-Host 'Export termine. Godot reimporte automatiquement les fichiers GLB.'
