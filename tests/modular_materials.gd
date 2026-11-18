extends SceneTree
var errors: Array[String]=[]
var checked_uvs := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func run() -> void:
	var base := "res://assets/environment/modular_2m/"
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"kit_source.json"))
	var kit: Resource=load(base+"default_kit.tres")
	var reload_kit: Resource=kit.duplicate(); reload_kit.data=kit.data.duplicate()
	var old_mesh: Mesh=reload_kit.mesh_for("door_glass")
	reload_kit.data.source_sha256+="_reload_test"
	check(reload_kit.mesh_for("door_glass")!=old_mesh,"Source resource reload invalidates cached meshes and notifies edited maps")
	var counts := {}
	for name: String in ["door_02","window_glass"]:
		var glass_triangles := 0; var opaque_triangles := 0; var uv_ok := true; var material_ok := true
		for index: String in data.modules[name].surfaces:
			var row: Dictionary=data.modules[name].surfaces[index]; var material: Material=kit.data.materials[int(index)]
			var glass: bool=material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA
			for source: String in row.source_materials:
				material_ok=material_ok and glass==source.to_lower().contains("glass")
				if glass: glass_triangles+=1
				else: opaque_triangles+=1
			var page_index: int=data.materials[int(index)].page
			if page_index<0: continue
			var page: Array=data.pages[page_index].rect
			var atlas_size: Array=data.pages[page_index].atlas_size
			for vertex in row.uv.size():
				var uv: Array=row.uv[vertex]; var original: Array=row.source_uv[vertex]
				var restored := Vector2((page[0]+uv[0]*page[2])/atlas_size[0],(page[1]+(1-uv[1])*page[3])/atlas_size[1])
				uv_ok=uv_ok and restored.distance_to(Vector2(original[0],original[1]))<.000001
				checked_uvs+=1
		check(material_ok and opaque_triangles>0 and glass_triangles>0,"Only Blender's glass faces are transparent: "+name)
		check(uv_ok,"Every opaque UV reconstructs the exact Blender atlas coordinate: "+name)
		counts[name]={"glass_triangles":glass_triangles,"opaque_triangles":opaque_triangles}
	# Render the actual exported parts using the same native path as the editor.
	var renderer_script: Script=load("res://scripts/psx_renderer.gd")
	var light_script: Script=load("res://scripts/psx_light_3d.gd")
	var viewport := SubViewport.new(); viewport.size=Vector2i(320,240); viewport.own_world_3d=true; viewport.world_2d=World2D.new(); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var mesh := MeshInstance3D.new(); stage.add_child(mesh)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.fov=42
	var lamp: Node3D=light_script.new(); stage.add_child(lamp); lamp.light_energy=2; lamp.light_range=8
	var renderer: Node=renderer_script.new(); viewport.add_child(renderer); renderer.ambient_light_color=Color(.3,.3,.3); renderer.fog_enabled=false; renderer.dithering=false
	for name: String in ["door_glass","window_glass"]:
		mesh.mesh=kit.mesh_for(name)
		var bounds: AABB=mesh.mesh.get_aabb(); var center := bounds.get_center()
		camera.position=center+Vector3(.4,0,3.7); camera.look_at(center); lamp.position=center+Vector3(-.3,.4,2)
		renderer.setup_editor(stage,camera)
		var glass_entries := 0; var frame_entries := 0
		for entry in renderer.entries:
			if entry.node!=mesh: continue
			if entry.translucent:
				glass_entries+=1; check(not entry.light_occluder,"Glass transmits vertex lights")
			else:
				frame_entries+=1; check(entry.light_occluder,"Opaque framing still blocks vertex lights")
		check(glass_entries==1 and frame_entries>0,"Native renderer keeps separate glass and opaque packets: "+name)
		for frame in 3: renderer.render_editor(); await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://docs/modular-corrected-"+name+".png")
		for side in [1,-1]:
			camera.position=center+Vector3(.4,0,3.7*side); camera.look_at(center); lamp.position=center+Vector3(-.3,.4,2*side)
			renderer.render_editor()
			var glass_packets := 0
			for batch: Dictionary in renderer.primitives:
				for vertex in range(0,batch.colors.size(),3):
					if roundi(batch.colors[vertex].a*255)&32: glass_packets+=1
			check(glass_packets>0,"Blender's two-sided glass remains visible from both rooms: "+name+" side "+str(side))
	viewport.queue_free(); await process_frame
	check(data.get("source_unchanged_on_export",false),"Export does not overwrite the artist's Blender scene")
	var result := {"ok":errors.is_empty(),"errors":errors,"source_uvs_checked":checked_uvs,"parts":counts}
	FileAccess.open("res://docs/modular-material-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MODULAR_MATERIALS_OK " if errors.is_empty() else "MODULAR_MATERIALS_FAILED ",JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
