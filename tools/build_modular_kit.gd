extends SceneTree

const Data = preload("res://scripts/modular_map/kit_data.gd")
const Kit = preload("res://scripts/modular_map/kit.gd")
const PSX = preload("res://scripts/psx_materials.gd")
const AssetSaver = preload("res://tools/import_blender_asset.gd")
const BASE := "res://assets/environment/modular_2m/"
const STAIRS := "res://assets/props/stairs_01/"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	quit(0 if bake("--replace-overrides" in OS.get_cmdline_user_args()) else 1)


static func bake(replace_overrides := false) -> Resource:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE + "kit_source.json"))
	if not source is Dictionary or not source.get("source_unchanged_on_export", false):
		push_error("Invalid modular kit export")
		return null

	var textures: Array[Texture2D] = []
	for page: Dictionary in source.pages:
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(BASE + page.file)) != OK or maxi(image.get_width(), image.get_height()) > 256:
			push_error("Invalid modular texture page: " + page.file)
			return null
		textures.append(ImageTexture.create_from_image(image))

	var data := Data.new()
	data.source_sha256 = source.sha256
	for description: Dictionary in source.materials:
		var c: Array = description.color
		var texture: Texture2D = textures[description.page] if description.page >= 0 else null
		var material := PSX.make(Color(c[0], c[1], c[2], c[3]), texture)
		material.resource_name = description.name
		if description.get("transparent", false):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		data.materials.append(material)

	var modules := {}
	for name: String in source.modules:
		var surfaces: Array[Dictionary] = []
		for index: String in source.modules[name].surfaces:
			var row: Dictionary = source.modules[name].surfaces[index]
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uv := PackedVector2Array()
			var dx := PackedVector2Array()
			for v: Array in row.vertices: vertices.append(Vector3(v[0], v[1], v[2]))
			for v: Array in row.normals: normals.append(Vector3(v[0], v[1], v[2]))
			for v: Array in row.uv: uv.append(Vector2(v[0], v[1]))
			for v: Array in row.uv_dx: dx.append(Vector2(v[0], v[1]))
			surfaces.append({"vertices":vertices, "normals":normals, "uv":uv, "uv_dx":dx, "material":int(index)})
		modules[name] = surfaces
	for alias: String in source.aliases:
		modules[alias] = modules[source.aliases[alias]]
	data.modules = modules

	var existing := BASE + "default_kit.tres"
	var kit: Resource = load(existing).duplicate() if ResourceLoader.exists(existing) else Kit.new()
	kit.data = data
	if replace_overrides:
		var overrides: Dictionary[String, Resource] = kit.module_overrides.duplicate()
		for name: String in modules:
			if name not in source.retained_modules: overrides.erase(name)
		kit.module_overrides = overrides
	var stair_mesh: Mesh = kit.mesh_for("stairs_01")
	var stair_shape: Shape3D = kit.shape_for("stairs_collision")
	if not stair_mesh or not stair_shape:
		push_error("Missing staircase mesh or collision ramp")
		return null

	var paths: Array[String] = [BASE + "kit_data.res", existing, STAIRS + "stairs_01.mesh.res", STAIRS + "stairs_01.collision.res"]
	var saved := AssetSaver.backup(paths)
	if saved.is_empty():
		push_error("Could not back up the modular kit")
		return null
	var resources: Array[Resource] = [data, kit, stair_mesh, stair_shape]
	for i in paths.size():
		# Keep bridge-compatible resource headers for later individual stair exports.
		var flags := ResourceSaver.FLAG_COMPRESS if i == 0 else 0
		if not AssetSaver.atomic_save(resources[i], paths[i], flags):
			AssetSaver.rollback(saved)
			push_error("Could not save " + paths[i])
			return null
	print("MODULAR_BINARY_KIT_OK: ", data.modules.size(), " modules, ", textures.size(), " texture pages")
	return kit

