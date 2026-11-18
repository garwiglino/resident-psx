@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning(): await tree.process_frame
	var glb := "res://assets/character/clothing/winter_jacket.glb"
	var garment := "res://assets/character/clothing/winter_jacket.tres"
	var source_hash := FileAccess.get_sha256(glb); var item_hash := FileAccess.get_sha256(garment)
	var config := ConfigFile.new(); var error := config.load(glb+".import")
	if error==OK:
		# GLTFState's lossless embedded mode removes the extracted-image dependency.
		config.set_value("params","gltf/embedded_image_handling",GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED)
		error=config.save(glb+".import")
	if error==OK: fs.reimport_files(PackedStringArray([glb]))
	for frame in 12: await tree.process_frame
	var item: Resource=ResourceLoader.load(garment,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var dependencies := ResourceLoader.get_dependencies(glb)
	var valid := error==OK and item!=null and item.scene!=null
	for dep in dependencies:
		if String(dep).contains("winter_jacket_winter_jacket_gray_psx_256.png"): valid=false
	var scene: Node=item.scene.instantiate() if valid else null
	var meshes: Array=scene.find_children("*","MeshInstance3D",true,false) if scene else []
	valid=valid and not meshes.is_empty()
	for mesh: MeshInstance3D in meshes:
		valid=valid and mesh.skin!=null
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			valid=valid and (item.texture!=null or (material!=null and material.albedo_texture!=null))
	valid=valid and source_hash==FileAccess.get_sha256(glb) and item_hash==FileAccess.get_sha256(garment)
	var result := {"ok":valid,"error":error,"dependencies":dependencies,"glb_sha256":source_hash,"definition_unchanged":item_hash==FileAccess.get_sha256(garment),"override_texture":item.texture.resource_path if item and item.texture else "","meshes":meshes.size()}
	if scene: scene.free()
	FileAccess.open("res://docs/jacket-dependency-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("JACKET_IMPORT_OK " if valid else "JACKET_IMPORT_FAILED ",JSON.stringify(result)); tree.quit(0 if valid else 1)
