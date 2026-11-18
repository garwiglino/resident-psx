extends SceneTree
var errors: Array[String]=[]
var checked := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();root.add_child(viewport)
	var stage := CharacterBody3D.new();viewport.add_child(stage)
	var camera := Camera3D.new();viewport.add_child(camera);camera.position.z=3;camera.fov=45
	var light := PSXLight3D.new();light.light_type=2;stage.add_child(light)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.8,-.8,0),Vector3(-.8,.8,-.8),Vector3(.8,.8,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3(.99,0,.1).normalized()]);arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,1),Vector2.ZERO,Vector2(1,0)]);arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new();node.mesh=mesh;var material := StandardMaterial3D.new();var image := Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);material.albedo_texture=ImageTexture.create_from_image(image);node.material_override=material;stage.add_child(node)
	var renderer: Node2D=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.fog_enabled=false;renderer.ambient_light_color=Color(.2,.2,.2);renderer.anime_style=load("res://assets/rendering/anime_psx.tres").duplicate();renderer.anime_style.enabled=false;renderer.anime_style.outline_enabled=false;renderer.setup_editor(stage,camera);renderer.render_editor()
	var source: Dictionary=renderer.primitives[0]
	check(source.points.size()==3,"Synthetic perspective triangle is visible")
	var a: Vector2=source.points[0];var ab: Vector2=source.points[1]-a;var ac: Vector2=source.points[2]-a;var determinant := ab.cross(ac)
	renderer.anime_style.enabled=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	for strength in [0.0,.5,1.0]:
		renderer.affine_texture_strength=strength;renderer.render_editor()
		check(renderer.native_geometry.get_statistics().anime_triangles==1,"The cel palette shades the original triangle at affine strength "+str(strength))
		check(renderer.raster.get_shader_parameter("cel_enabled"),"The raster applies the palette on the original geometry")
		var band_area := 0.0
		for packet: Dictionary in renderer.primitives:
			for triangle in packet.points.size()/3:
				var at: int=triangle*3
				var edge_ab: Vector2=packet.points[at+1]-packet.points[at]
				var edge_ac: Vector2=packet.points[at+2]-packet.points[at]
				band_area+=absf(edge_ab.cross(edge_ac))
			for vertex in packet.points.size():
				var point: Vector2=packet.points[vertex]-a;var b := point.cross(ac)/determinant;var c := ab.cross(point)/determinant;var w := 1-b-c
				check(minf(w,minf(b,c))>-.00001,"Cel band intersections stay within the snapped source triangle")
				var expected_q: float=source.inverse_depths[0]*w+source.inverse_depths[1]*b+source.inverse_depths[2]*c
				var expected_uvq: Vector2=source.uvs[0]*source.inverse_depths[0]*w+source.uvs[1]*source.inverse_depths[1]*b+source.uvs[2]*source.inverse_depths[2]*c
				var expected_uv: Vector2=source.uvs[0]*w+source.uvs[1]*b+source.uvs[2]*c
				var actual_uvq: Vector2=packet.uvs[vertex]*packet.inverse_depths[vertex]
				check(absf(packet.inverse_depths[vertex]-expected_q)<.000001 and actual_uvq.distance_to(expected_uvq)<.000001 and packet.uvs[vertex].distance_to(expected_uv)<.000001,"Cel lighting retains the original UV/depth planes")
				checked+=1
		check(is_equal_approx(band_area,absf(determinant)),"Shading bands cover the whole snapped triangle")
		await process_frame
	await RenderingServer.frame_post_draw
	var still: Image=viewport.get_texture().get_image()
	var positions: PackedVector2Array=renderer.primitives[0].points
	var depth: PackedFloat32Array=renderer.primitives[0].depth_channels
	renderer.native_geometry.set_shot_light(Vector3(0,0,1),Vector3(1,.56,.18),2.8,4.0)
	renderer.render_editor()
	check(renderer.primitives[0].points==positions and renderer.primitives[0].depth_channels==depth,
		"Muzzle lighting never changes cel geometry or depth")
	await process_frame
	await RenderingServer.frame_post_draw
	var lit: Image=viewport.get_texture().get_image()
	var lit_pixels := 0
	var darker := 0
	for y in 240:
		for x in 320:
			var delta := lit.get_pixel(x,y).get_luminance()-still.get_pixel(x,y).get_luminance()
			if delta>.025:lit_pixels+=1
			elif delta<-.025:darker+=1
	check(lit_pixels>100 and darker==0,"Warm vertex flash brightens the cel surface without creating dark facets")
	viewport.queue_free();await process_frame;await process_frame
	var result := {"ok":errors.is_empty(),"vertices_checked":checked,"errors":errors};FileAccess.open("res://docs/anime-uv-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("ANIME_UV_OK " if errors.is_empty() else "ANIME_UV_FAILED ",JSON.stringify(result));quit(0 if errors.is_empty() else 1)
