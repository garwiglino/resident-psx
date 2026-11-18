extends SceneTree
const Light=preload("res://scripts/psx_light_3d.gd")
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func colors(geometry: RefCounted,power := false) -> PackedColorArray:
	var packets: Array=geometry.frame(Transform3D.IDENTITY,50,false,power,true)
	check(packets.size()==1,"Manual lighting keeps the single ordered atlas submission")
	return packets[0].colors
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.player.set_process(false);game.player.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var renderer=game.psx_renderer
	# Isolate this test without changing lights the artist has since placed.
	for source in get_nodes_in_group("psx_world_lights"):
		if game.is_ancestor_of(source):source.enabled=false
	renderer._sync_world_lights()
	renderer.torch_on=false;renderer.shot_light_energy=0
	renderer.fog_start=9;renderer.fog_end=33
	check(renderer.world_lights.is_empty() and renderer.native_geometry.get_statistics().world_lights==0,"Level has no default or hidden point lights")
	check(renderer.ambient_light_color==Color.BLACK,"Old ambient wash is removed by default")
	check(game.level.has_node("Lumieres"),"Map has an empty editable lighting container")
	check(game.level.find_children("*","Light3D",true,false).is_empty(),"Map has no standard pixel lights")
	var lamp := Light.new();lamp.name="TestManualLight"
	game.level.get_node("Lumieres").add_child(lamp)
	lamp.global_position=Vector3(.125,.25,-1.25);lamp.light_color=Color(1,.4,.1);lamp.light_energy=1.6;lamp.light_range=4
	renderer._sync_world_lights()
	check(renderer.world_lights.size()==1 and renderer.native_geometry.get_statistics().world_lights==1,"A manually placed PSXLight3D reaches the native renderer")
	var revision: int=renderer.native_geometry.get_statistics().light_revision
	for frame in 20:renderer._sync_world_lights()
	check(renderer.native_geometry.get_statistics().light_revision==revision,"Unchanged lights do not invalidate the static lighting cache")
	var node := MeshInstance3D.new();root.add_child(node)
	var vertices := PackedVector3Array([Vector3(-.5,-.25,-2),Vector3(.5,-.25,-2),Vector3(0,.5,-2)])
	var normals := PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	var entry := {"node":node,"skeleton":null,"vertices":vertices,"normals":normals,
	 "uvs":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE]),"indices":PackedInt32Array([0,2,1]),
	 "bind_indices":PackedInt32Array(),"binds":[],"color":Color(.4,.4,.4),"emission":Color.BLACK,"fixed":true,"textured":false,"texture_page":0,
	 "draw_texture":renderer.blank,"logical_texture_size":Vector2.ONE,"aabb":AABB(Vector3(-.5,-.25,-2),Vector3(1,.75,.01)),
	 "static_positions":vertices,"static_normals":normals,"static_light":PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])}
	var geometry: RefCounted=ClassDB.instantiate("PSXGeometry")
	var order := [0,2,1]
	var lit: PackedColorArray
	for fixed in [true,false]:
		entry.fixed=fixed;geometry.configure([entry]);geometry.set_world_lights(renderer.world_lights,Vector3.ZERO)
		lit=colors(geometry)
		for vertex in 3:
			var point: Vector3=vertices[order[vertex]]
			var base: Vector3=renderer.bake_light(point,Vector3.BACK,entry.color,Color.BLACK)
			var expected: Color=renderer.shade(point,Vector3.BACK,2,entry.color,base,false)
			for channel in 3:check(absf(lit[vertex][channel]-expected[channel])<.00001,"Native and fallback point lighting agree on static and dynamic geometry")
		check(lit[0].r>lit[0].b and not lit[0].is_equal_approx(lit[1]),"Manual source gives a colored Gouraud gradient across vertices")
	lamp.position.z=8;renderer._sync_world_lights();geometry.set_world_lights(renderer.world_lights,Vector3.ZERO)
	var dark := colors(geometry)
	for color in dark:check(color.r==0 and color.g==0 and color.b==0,"Moving the light outside its radius removes its contribution")
	check(colors(geometry,true)==dark,"Restoring level power cannot resurrect any removed hardcoded lamps")
	lamp.position.z=-1.25;lamp.light_color=Color(.1,.6,1);renderer._sync_world_lights();geometry.set_world_lights(renderer.world_lights,Vector3.ZERO)
	var blue := colors(geometry)
	check(blue[0].b>blue[0].r,"Color and transform edits reach active geometry")
	entry.fixed=true;entry.static_light=PackedVector3Array([Vector3.ONE,Vector3.ONE,Vector3.ONE]);geometry.configure([entry])
	check(colors(geometry)==blue,"Registering more geometry cannot restore stale baked colors")
	lamp.enabled=false;renderer._sync_world_lights();geometry.set_world_lights(renderer.world_lights,Vector3.ZERO)
	check(colors(geometry)==dark,"Disabling a source invalidates the static lighting cache")
	lamp.enabled=true;lamp.visible=false;renderer._sync_world_lights()
	check(renderer.world_lights.is_empty(),"Hiding the source disables it")
	lamp.visible=true;renderer._sync_world_lights()
	check(renderer.world_lights.size()==1,"Showing the source enables it again")
	lamp.queue_free();await process_frame;renderer._sync_world_lights()
	check(renderer.world_lights.is_empty(),"Deleting a source removes it from rendering")
	renderer.ambient_light_color=Color(.1,.05,.02);renderer._sync_world_lights()
	geometry.set_world_lights([],Vector3(.1,.05,.02))
	var ambient := colors(geometry)
	for vertex in 3:
		var expected: Color=renderer.shade(vertices[order[vertex]],Vector3.BACK,2,entry.color,renderer.bake_light(vertices[order[vertex]],Vector3.BACK,entry.color,Color.BLACK),false)
		for channel in 3:check(absf(ambient[vertex][channel]-expected[channel])<.00001,"Editable ambient light matches in both paths")
	report.lit=str(lit);report.blue=str(blue);report.dark=str(dark);report.failures=failures
	FileAccess.open("res://docs/manual-lights-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	geometry=null;node.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("MANUAL_LIGHTS_OK: empty level, manual class, static/dynamic Gouraud parity, range/color/visibility edits, cache invalidation and no hidden lamps" if failures.is_empty() else "MANUAL_LIGHTS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
