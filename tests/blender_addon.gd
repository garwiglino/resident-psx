extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var kit: Resource=load("res://assets/environment/modular_2m/default_kit.tres")
	check(kit.module_overrides.size()==11,"All eleven module categories arrive in the map kit")
	var original_floor: Mesh=kit.mesh_for("floor")
	var glass := 0;var opaque := 0
	for material: StandardMaterial3D in kit.module_overrides["door_glass"].materials:
		if material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA:glass+=1
		else:opaque+=1
		check(material.specular_mode==BaseMaterial3D.SPECULAR_DISABLED and material.metallic==0 and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,"Exported materials use the project's diffuse PSX settings")
		if material.albedo_texture:check(material.albedo_texture.get_width()<=256 and material.albedo_texture.get_height()<=256,"Texture pages preserve source texels within the native page size")
	check(glass>0 and opaque>0,"Door glass remains separate from its opaque body and handle")
	for name: String in ["door_01","door_glass"]:
		var bounds: AABB=kit.mesh_for(name).get_aabb()
		check(absf(bounds.position.x)<.001 and absf(bounds.position.y)<.001 and absf(bounds.size.x-1)<.001 and absf(bounds.size.y-2.2)<.001,"Door hinge and foot match the map's existing pivots: "+name)
	var window: AABB=kit.mesh_for("window_glass").get_aabb()
	check(window.position.y>1.1 and window.end.y<2.4,"Window panel retains its height inside the wall frame")
	for name: String in ["wall_door","wall_door_double","wall_loop","wall_loop_simple","wall_loop_window"]:
		for a in 8:
			for b in 8:
				var mesh: Mesh=kit.mesh_for(name,a,b)
				check(mesh.get_surface_count()>0,"Custom modules retain corner/T/X joint variants")
	# A source reload must invalidate the cache of every edited map using this kit.
	var previous: Mesh=kit.mesh_for("door_glass");kit.module_overrides["door_glass"].source_sha256+="_reload"
	check(previous!=kit.mesh_for("door_glass"),"Reloading an individual module invalidates cached meshes")
	check(kit.mesh_for("floor")!=original_floor,"Module reload invalidates dependent kit caches")
	for collision in ["box","trimesh","none"]:
		var path := "res://assets/props/validation_decor_%s/validation_decor_%s.tscn" % [collision,collision]
		var scene: PackedScene=load(path);var prop: Node3D=scene.instantiate()
		var visual: MeshInstance3D=prop.get_node("Modele");var mesh: Mesh=visual.mesh
		check(mesh.get_faces().size()/3>12,"Decor export evaluates the Blender bevel modifier")
		check(prop.position==Vector3.ZERO and visual.position==Vector3.ZERO,"Scene placement ignores the Blender catalogue's world translation")
		var bounds := mesh.get_aabb();check(bounds.get_center().length()<.001,"Mirrored/scaled decor retains its authored origin")
		var material: StandardMaterial3D=mesh.surface_get_material(0)
		check(material.albedo_texture.get_width()==32 and material.albedo_texture.get_height()==32,"A 32px source texture is kept at its original resolution")
		var arrays: Array=mesh.surface_get_arrays(0);var repeats := false;var correct_normals := true
		for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:repeats=repeats or uv.x>1 or uv.x<0 or uv.y>1 or uv.y<0
		for i in range(0,arrays[Mesh.ARRAY_VERTEX].size(),3):
			var p: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var n: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var geometric: Vector3=(p[i+2]-p[i]).cross(p[i+1]-p[i]).normalized()
			correct_normals=correct_normals and geometric.dot((n[i]+n[i+1]+n[i+2]).normalized())>.1
		check(repeats,"UV tiling outside 0..1 is preserved")
		check(correct_normals,"Mirrored transforms retain outward winding and Blender smooth normals")
		var shape: CollisionShape3D=prop.get_node_or_null("Collision/CollisionShape3D")
		check((shape==null) if collision=="none" else (shape!=null and (shape.shape is BoxShape3D if collision=="box" else shape.shape is ConcavePolygonShape3D)),"The selected collision mode reaches the Godot scene: "+collision)
		prop.free()
	var Map: Script=load("res://scripts/modular_map/map_3d.gd");var Layout: Script=load("res://scripts/modular_map/layout.gd")
	var map: Node3D=Map.new();map.layout=Layout.new();map.kit=kit;map.event_namespace="addon_validation"
	var room: int=map.layout.add_room();map.layout.paint_cell(Vector2i.ZERO,room);map.layout.paint_edge("h:0:0",Layout.Kind.DOOR,"glass");root.add_child(map)
	var door: Node=map.generated.get_node("Bord_h_0_0/Porte");door.duration=0
	check(door.interact() and door.is_open and door.interact() and not door.is_open,"Existing door interaction still works with an individually exported model")
	map.free()
	var before_base_rebuild: Dictionary=kit.module_overrides.duplicate()
	var material_overrides: Dictionary[String,Material]={"validation_material":StandardMaterial3D.new()};kit.material_overrides=material_overrides
	var saver: Script=load("res://tools/import_blender_asset.gd");var builder: Script=load("res://tools/build_modular_kit.gd")
	var kit_path: String=kit.resource_path;var kit_uid: int=saver.existing_uid(kit_path);saver.atomic_save(kit,kit_path)
	var rebaked: Resource=builder.bake()
	check(rebaked.module_overrides==before_base_rebuild and rebaked.material_overrides.has("validation_material"),"Rebuilding the base kit preserves individual modules and authored material overrides")
	check(saver.existing_uid(kit_path)==kit_uid,"Base rebuild preserves the kit UID used by existing maps")
	# Actual PSX native raster captures of the exported glass door and basic prop.
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var visual := MeshInstance3D.new();stage.add_child(visual)
	var camera := Camera3D.new();viewport.add_child(camera);camera.fov=42
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.ambient_light_color=Color(.65,.65,.65);renderer.fog_enabled=false
	for name: String in ["door_glass","decor"]:
		visual.mesh=kit.mesh_for(name) if name!="decor" else load("res://assets/props/validation_decor_box/validation_decor_box.mesh.res")
		var center := visual.mesh.get_aabb().get_center();camera.position=center+Vector3(.4,.15,4.3);camera.look_at(center);renderer.setup_editor(stage,camera)
		for frame in 3:renderer.render_editor();await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://docs/blender-addon-"+name+".png")
		check(renderer.native_geometry.get_statistics().triangles>0,"Exported asset is visible to the native PSX renderer: "+name)
	viewport.queue_free();await process_frame
	var result := {"ok":failures.is_empty(),"errors":failures}
	FileAccess.open("res://docs/blender-addon-godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BLENDER_ADDON_GODOT_OK " if failures.is_empty() else "BLENDER_ADDON_GODOT_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
