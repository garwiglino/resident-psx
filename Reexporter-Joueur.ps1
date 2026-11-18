param(
    [string]$BlendFile='C:\Users\sheensaw\Downloads\cop_base_2(1).blend1',
    [string]$Blender='C:\Program Files\Blender Foundation\Blender 5.1\blender.exe',
    [string]$Godot='C:\Users\sheensaw\MyApps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe',
    [string[]]$InclureVetement=@()
)
$ErrorActionPreference='Stop'
$baseSource=(Resolve-Path -LiteralPath $BlendFile).Path
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$staging=Join-Path ([System.IO.Path]::GetTempPath()) "resident-psx-player-$stamp"
$exportOptions=@('--output',$staging)
foreach ($garment in $InclureVetement) {
    if ([System.IO.Path]::GetFileName($garment) -ne $garment -or $garment -in @('.','..','cop_player','winter_jacket')) {
        throw "Nom de vetement invalide $garment."
    }
    $exportOptions+=@('--include-garment',$garment)
}
& $Blender --factory-startup --background $baseSource --python-exit-code 1 --python (Join-Path $PSScriptRoot 'tools\export_layered_player.py') -- @exportOptions
if ($LASTEXITCODE -ne 0) { throw 'Echec de l export du corps et de la veste.' }

$character=Join-Path $PSScriptRoot 'assets\character'
$backup=Join-Path $PSScriptRoot "exports\backups\player_layers_before_$stamp"
$files=@{
    'cop_player.glb' = 'cop_player.glb'
    'cop_player.json' = 'cop_player.json'
    'winter_jacket.glb' = 'clothing\winter_jacket.glb'
    'winter_jacket.json' = 'clothing\winter_jacket.json'
}
foreach ($garment in $InclureVetement) {
    $files["$garment.glb"]="clothing\$garment.glb"
    $files["$garment.json"]="clothing\$garment.json"
}
foreach ($name in $files.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $staging $name) -PathType Leaf)) {
        throw "Export incomplet. Fichier manquant $name."
    }
}
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($name in $files.Keys) {
    $destination=Join-Path $character $files[$name]
    if (Test-Path -LiteralPath $destination) {
        Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $name)
    }
}
foreach ($name in $files.Keys) {
    $destination=Join-Path $character $files[$name]
    if ($name.EndsWith('.glb') -and -not (Test-Path -LiteralPath "$destination.import")) {
        @'
[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

gltf/embedded_image_handling=3
'@ | Set-Content -LiteralPath "$destination.import" -Encoding utf8
    }
    Copy-Item -LiteralPath (Join-Path $staging $name) -Destination $destination -Force
}
& $Godot --headless --editor --path $PSScriptRoot --import
if ($LASTEXITCODE -ne 0) { throw "Echec de l import Godot. Sauvegarde dans $backup." }
Write-Host 'Corps, cheveux et doudoune reexportes. Les masques sont calcules dans Godot.'
