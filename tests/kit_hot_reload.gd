extends SceneTree
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	var folder := "res://exports/kit_reload_validation/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder+"live_kit.gd"
	FileAccess.open(path,FileAccess.WRITE).store_string("@tool\nextends Resource\n@export var data: Resource\nvar _meshes: Dictionary={}\nvar _shapes: Dictionary={}\n")
	var script: GDScript=load(path);var live: Resource=script.new()
	var base: Resource=load("res://assets/environment/modular_2m/default_kit.tres");live.data=base.data
	script.source_code=FileAccess.get_file_as_string("res://scripts/modular_map/kit.gd")
	FileAccess.open(path,FileAccess.WRITE).store_string(script.source_code)
	check(script.reload(true)==OK,"A kit open before the module-override feature can reload its script")
	var before: int=typeof(live.get("module_overrides"))
	check(live.mesh_for("wall_loop")!=null and live.shape_for("wall_loop")!=null,"Live pre-existing kit rebuilds meshes and collisions after adding exported properties")
	check(live.mesh_for("missing_module")==null and live.shape_for("missing_module")==null,"Missing modules return cleanly without a null mesh method call")
	var overrides: Dictionary[String,Resource]={"wall_loop":null};live.module_overrides=overrides
	check(live.mesh_for("wall_loop")!=null,"Empty optional overrides fall back to the base module")
	var Layout: Script=load("res://scripts/modular_map/layout.gd");var Map: Script=load("res://scripts/modular_map/map_3d.gd")
	var map: Node3D=Map.new();map.layout=Layout.new();map.kit=live
	var room: int=map.layout.add_room();map.layout.paint_cell(Vector2i.ZERO,room);root.add_child(map)
	check(map.layout.paint_edge("v:0:0",Layout.Kind.PASSAGE,"").is_empty(),"Passage paint accepts the edge")
	map.layout.emit_changed();await process_frame;await process_frame
	check(not map.generated.has_node("Bord_v_0_0"),"Painting a passage removes its wall after hot reload")
	map.free();live=null;script=null;await process_frame
	var result := {"ok":errors.is_empty(),"errors":errors,"override_type_after_reload":before}
	FileAccess.open("res://docs/kit-hot-reload-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("KIT_HOT_RELOAD_OK " if errors.is_empty() else "KIT_HOT_RELOAD_FAILED ",JSON.stringify(result));quit(0 if errors.is_empty() else 1)
