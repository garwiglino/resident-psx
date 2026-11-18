extends SceneTree
const Light=preload("res://scripts/psx_light_3d.gd")
var failures: Array[String]=[]
var report: Dictionary={"types":[]}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func frame(geometry: RefCounted) -> PackedColorArray:
	return geometry.frame(Transform3D.IDENTITY,50,false,false,true)[0].colors
func editor_property(node: Node,name: String) -> bool:
	for property in node.get_property_list():
		if property.name==name:return (property.usage&PROPERTY_USAGE_EDITOR)!=0
	return false
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.player.set_process(false);game.player.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var r=game.psx_renderer;r.torch_on=false;r.shot_light_energy=0;r.fog_start=9;r.fog_end=33
	for source in get_nodes_in_group("psx_world_lights"):
		if game.is_ancestor_of(source):source.enabled=false
	r._sync_world_lights()
	var lamp := Light.new();game.level.get_node("Lumieres").add_child(lamp)
	lamp.global_position=Vector3(.125,.25,-1.25);lamp.light_color=Color(1,.4,.1);lamp.light_energy=1.6;lamp.light_range=4
	var node := MeshInstance3D.new();root.add_child(node)
	var vertices := PackedVector3Array([Vector3(-.5,-.25,-2),Vector3(.5,-.25,-2),Vector3(0,.5,-2)])
	var normals := PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	var entry := {"node":node,"skeleton":null,"vertices":vertices,"normals":normals,
	 "uvs":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE]),"indices":PackedInt32Array([0,2,1]),
	 "bind_indices":PackedInt32Array(),"binds":[],"color":Color(.4,.4,.4),"emission":Color.BLACK,"fixed":true,"textured":false,"texture_page":0,
	 "draw_texture":r.blank,"logical_texture_size":Vector2.ONE,"aabb":AABB(Vector3(-.5,-.25,-2),Vector3(1,.75,.01)),
	 "static_positions":vertices,"static_normals":normals,"static_light":PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])}
	var geometry: RefCounted=ClassDB.instantiate("PSXGeometry")
	check(geometry.get_statistics().version>=9,"Light type and fog backend is loaded")
	var order := [0,2,1];var results: Array=[]
	for kind in [Light.LightType.OMNI,Light.LightType.SPOT,Light.LightType.DIRECTIONAL]:
		lamp.light_type=kind;r._sync_world_lights()
		check(editor_property(lamp,"light_range")==(kind!=Light.LightType.DIRECTIONAL),"Inspector shows range only for local lights")
		check(editor_property(lamp,"spot_angle_degrees")==(kind==Light.LightType.SPOT),"Inspector shows cone controls only for spotlights")
		for fixed in [true,false]:
			entry.fixed=fixed;geometry.configure([entry]);geometry.set_world_lights(r.world_lights,Vector3.ZERO)
			var colors := frame(geometry)
			for vertex in 3:
				var point: Vector3=vertices[order[vertex]]
				var expected: Color=r.shade(point,Vector3.BACK,2,entry.color,r.bake_light(point,Vector3.BACK,entry.color,Color.BLACK),false)
				for channel in 3:check(absf(colors[vertex][channel]-expected[channel])<.00001,"Native/fallback parity for every light type and cache mode")
		results.append(frame(geometry));report.types.append({"type":kind,"colors":str(frame(geometry))})
	check(results[1][0].r<results[0][0].r and results[1][1].r>0,"Spot cone excludes outside vertices and fades its edge")
	check(results[2][0].is_equal_approx(results[2][1]),"Directional light is independent of vertex distance")
	var revision: int=r.native_geometry.get_statistics().light_revision
	lamp.position+=Vector3(20,20,20);r._sync_world_lights()
	check(r.native_geometry.get_statistics().light_revision==revision,"Moving a directional source does not rebuild static lighting")
	lamp.rotation.y=PI;r._sync_world_lights();geometry.set_world_lights(r.world_lights,Vector3.ZERO)
	for color in frame(geometry):check(color.r==0 and color.g==0 and color.b==0,"Directional rotation changes the direction of illumination")
	lamp.light_type=Light.LightType.SPOT;lamp.position=Vector3(.125,.25,-1.25);r._sync_world_lights();geometry.set_world_lights(r.world_lights,Vector3.ZERO)
	for color in frame(geometry):check(color.r==0 and color.g==0 and color.b==0,"A rotated spot does not light vertices behind its cone")
	lamp.spot_softness=0;lamp.rotation=Vector3.ZERO;r._sync_world_lights();geometry.set_world_lights(r.world_lights,Vector3.ZERO)
	for color in frame(geometry):check(is_finite(color.r) and is_finite(color.g) and is_finite(color.b),"A hard spotlight edge remains numerically stable")
	var packed := PackedScene.new();packed.pack(lamp)
	var restored: Node=packed.instantiate()
	check(restored.light_type==Light.LightType.SPOT and restored.spot_angle_degrees==45,"Light type and cone settings survive scene serialization")
	restored.free()
	lamp.enabled=false;r._sync_world_lights();geometry.set_world_lights([],Vector3.ZERO)
	var original: RefCounted=r.native_geometry;r.native_geometry=geometry
	r.fog_start=0;r.fog_end=4;r.fog_color=Color(.4,.3,.2);r.apply_render_settings()
	var fogged := frame(geometry)
	for vertex in 3:
		var expected: Color=r.shade(vertices[order[vertex]],Vector3.BACK,2,entry.color,Vector3.ZERO,false)
		for channel in 3:check(absf(fogged[vertex][channel]-expected[channel])<.00001,"Fog color and distance controls reach the actual native rendering settings")
	check(fogged[0].r>.1,"Depth cue remains visible on an unlit surface")
	r.fog_color=Color(.1,.2,.5);r.apply_render_settings()
	var blue := frame(geometry)
	check(blue[0].b>blue[0].r and blue!=fogged,"Changing fog color updates rendering without rebuilding geometry")
	r.fog_start=3;r.fog_end=7;r.apply_render_settings()
	for color in frame(geometry):check(color.r==0 and color.g==0 and color.b==0,"Fog starts only after the configured near distance")
	r.native_geometry=original;report.fogged=str(fogged);report.blue_fog=str(blue);report.failures=failures
	FileAccess.open("res://docs/light-types-fog-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	geometry=null;node.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("LIGHT_TYPES_FOG_OK: Omni/Spot/Directional vertex lighting, direction/cone/softness, inspector fields, serialization, cache behavior and editable depth cue" if failures.is_empty() else "LIGHT_TYPES_FOG_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
