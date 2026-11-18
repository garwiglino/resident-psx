param(
    [string]$ValidationFlag='--world-events-editor-test',
    [string]$LogStem='world-events-editor-test'
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$validationRoot=Join-Path $env:TEMP ('codex-world-validation-'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -Path $validationRoot -ItemType Directory | Out-Null
# Isolated editor metadata and a separate native-library path avoid conflicts
# with the artist's open editor. Shared source folders are read by this test.
foreach ($folder in @('scripts','scenes','assets','addons','tests','tools','exports','docs','shaders')) {
    New-Item -ItemType Junction -Path (Join-Path $validationRoot $folder) -Target (Join-Path $projectRoot $folder) | Out-Null
}
foreach ($file in @('project.godot','default_bus_layout.tres')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination (Join-Path $validationRoot $file)
}
$configPath=Join-Path $validationRoot 'project.godot'
$config=[System.IO.File]::ReadAllText($configPath)
$config=[regex]::Replace($config,'(?m)^config/name=.*$','config/name="PSX World Events Editor Validation"')
$config=[regex]::Replace($config,'(?m)^run/main_scene=.*\r?\n','')
$config=[regex]::Replace($config,'(?m)^buses/default_bus_layout=.*$','buses/default_bus_layout="res://default_bus_layout.tres"')
[System.IO.File]::WriteAllText($configPath,$config,[System.Text.UTF8Encoding]::new($false))
New-Item -Path (Join-Path $validationRoot 'bin') -ItemType Directory | Out-Null
$libraryManifest=[System.IO.File]::ReadAllText((Join-Path $projectRoot 'bin\psx_geometry.gdextension'))
$nativeLibrary=[regex]::Match($libraryManifest,'windows\.x86_64\s*=\s*"res://([^"]+)"').Groups[1].Value
Copy-Item -LiteralPath (Join-Path $projectRoot $nativeLibrary) -Destination (Join-Path $validationRoot ('bin\'+(Split-Path -Leaf $nativeLibrary)))
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin\psx_geometry.gdextension') -Destination (Join-Path $validationRoot 'bin\psx_geometry.gdextension')
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin\psx_geometry.gdextension.uid') -Destination (Join-Path $validationRoot 'bin\psx_geometry.gdextension.uid')
New-Item -Path (Join-Path $validationRoot '.godot') -ItemType Directory | Out-Null
New-Item -Path (Join-Path $validationRoot '.godot\editor') -ItemType Directory | Out-Null
New-Item -ItemType Junction -Path (Join-Path $validationRoot '.godot\imported') -Target (Join-Path $projectRoot '.godot\imported') | Out-Null
foreach ($file in @('extension_list.cfg','global_script_class_cache.cfg','uid_cache.bin')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('.godot\'+$file)) -Destination (Join-Path $validationRoot ('.godot\'+$file))
}
Get-ChildItem -LiteralPath (Join-Path $projectRoot '.godot\editor') -File -Filter 'filesystem_cache*' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $validationRoot '.godot\editor')
}
$validationRoot | Set-Content -LiteralPath (Join-Path $projectRoot 'docs\world-editor-validation-project.txt')
$godot='C:\Users\sheensaw\MyApps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
& $godot --path $validationRoot --editor --rendering-method gl_compatibility --position '-10000,-10000' --log-file (Join-Path $projectRoot ('docs\'+$LogStem+'.log')) -- $ValidationFlag
exit $LASTEXITCODE
