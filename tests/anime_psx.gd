extends SceneTree
const Style=preload("res://scripts/psx_anime_style.gd")
var failures: Array[String]=[]
var checks := 0
var result := {}
var game: Node3D
var renderer: Node
var buffer: SubViewport
var style: Style
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func pixels() -> Image:
	renderer._process(0)
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	return buffer.get_texture().get_image()
func benchmark(enabled: bool,count := 180) -> Dictionary:
	style.enabled=enabled
	var cpu: Array[int]=[];var native: Array[int]=[]
	for tick in count+20:
		var start := Time.get_ticks_usec();renderer._process(0)
		if tick>=20:cpu.append(Time.get_ticks_usec()-start);native.append(int(renderer.native_geometry.get_statistics().frame_us))
		await process_frame
	cpu.sort();native.sort()
	return {"cpu_median_ms":cpu[count/2]/1000.0,"cpu_p95_ms":cpu[floori(count*.95)]/1000.0,"native_p95_ms":native[floori(count*.95)]/1000.0,"samples":count}
func run() -> void:
	create_timer(80).timeout.connect(func():push_error("Anime test timeout");quit(2))
	root.get_node("InventoryState").persist_collection=false;root.get_node("WorldEvents").reset_run()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	var hashes := {}
	for path in ["res://scenes/level_1.tscn","res://scenes/player.tscn","res://assets/rendering/anime_psx.tres"]:hashes[path]=FileAccess.get_sha256(path)
	buffer=SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	game=load("res://scenes/systemes_jeu.tscn").instantiate()
	var map: Node3D=load("res://scenes/level_1.tscn").instantiate();map.name="Map";game.add_child(map)
	for area in map.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	buffer.add_child(game);game.set_process(false);game.set_process_input(false);game.hud.hide();game.pickup_feedback.enabled=false
	renderer=game.psx_renderer;renderer.set_process(false);style=Style.new();renderer.anime_style=style
	var p: Node3D=game.player;p.process_mode=Node.PROCESS_MODE_DISABLED;p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);p.motion.set_process(false);p.camera_collision_enabled=false
	for enemy in game.enemies:enemy.set_physics_process(false)
	for frame in 12:await process_frame
	for light in get_nodes_in_group("psx_world_lights"):light.enabled=false;light.flicker=false
	map.process_mode=Node.PROCESS_MODE_DISABLED
	p.aiming=false;p.pitch=0;p.look_yaw=0;p.reset_camera_follow();p.motion.blend_time=0;p.motion.play("idle");p.motion.advance_motion(.5);p._apply_upper_body_look()
	renderer.ambient_light_color=Color(.18,.19,.24)
	var key := PSXLight3D.new();key.light_color=Color(1,.94,.84);key.light_energy=1.65;key.light_range=6;game.add_child(key);key.global_position=p.global_position+Vector3(-.8,2.2,-.9)
	var fill := PSXLight3D.new();fill.light_color=Color(.74,.82,1);fill.light_energy=.4;fill.light_range=5;game.add_child(fill);fill.global_position=p.global_position+Vector3(.8,1.8,-.5)
	var camera := Camera3D.new();game.add_child(camera);camera.fov=32;camera.near=.05;camera.global_position=p.global_position+Vector3(.5,1.5,-1.1);camera.look_at(p.global_position+Vector3.UP*1.4);renderer.set_active_camera(camera)
	check(style.enabled and style.tones==0 and style.world_strength==0 and is_equal_approx(style.outline_width,.006),"Factory preset matches approved two-tone/6 mm contour, artist edits use a separate shared profile")
	check(renderer.native_geometry.get_statistics().version>=24,"Native silhouette renderer loaded")
	var atlas: int=renderer.atlas_texture.get_instance_id();var geometry: int=renderer.geometry_revision
	style.enabled=false;var before := await pixels()
	for packet: Dictionary in renderer.primitives:
		var integral := true
		for point: Vector2 in packet.points:
			if not point.is_finite() or point!=point.floor():integral=false;break
		check(integral,"Source vertices retain finite integer PSX projection")
	style.enabled=true;var after := await pixels();var stats: Dictionary=renderer.native_geometry.get_statistics()
	check(before.get_data()!=after.get_data() and stats.anime_triangles>0 and stats.outline_triangles>0,"Cel shading and the silhouette contour remain visible on the animated character")
	var coverage: Image=renderer.native_geometry.get_depth_texture().get_image()
	var joined := Image.create(640,240,false,Image.FORMAT_RGBA8);joined.blit_rect(before,Rect2i(0,0,320,240),Vector2i.ZERO);joined.blit_rect(after,Rect2i(0,0,320,240),Vector2i(320,0));joined.resize(1280,480,Image.INTERPOLATE_NEAREST);joined.save_png("res://docs/anime-implemented-comparison.png")
	var enlarged := after.duplicate() as Image
	enlarged.resize(960,720,Image.INTERPOLATE_NEAREST);enlarged.save_png("res://docs/anime-implemented.png")
	style.outline_enabled=false;var no_outline := await pixels()
	check(renderer.native_geometry.get_statistics().outline_triangles==0 and no_outline.get_data()!=before.get_data(),"Contour can be disabled independently of cel lighting")
	var changed_pixels := 0
	var ink_inside := 0
	for y in after.get_height():
		for x in after.get_width():
			if after.get_pixel(x,y)==no_outline.get_pixel(x,y):continue
			changed_pixels+=1
			if (roundi(coverage.get_pixel(x,y).g)&2)!=0:ink_inside+=1
	check(changed_pixels>0 and ink_inside==0,"Outline changes pixels outside the solid silhouette only")
	result.outline_pixels=changed_pixels;result.ink_inside_pixels=ink_inside
	style.strength=0;check((await pixels()).get_data()==before.get_data(),"Zero cel strength and no contour exactly restore original lighting")
	style.strength=1;style.light_threshold=.25;var low := await pixels();style.light_threshold=.9
	check((await pixels()).get_data()!=low.get_data(),"Threshold live edit moves the shadow/light boundary")
	style.light_threshold=.63;style.tones=1;check((await pixels()).get_data()!=no_outline.get_data(),"Three-tone mode has a distinct result")
	style.tones=0;style.outline_enabled=true;style.outline_width=.015;var thick := await pixels();style.outline_width=.006
	check((await pixels()).get_data()!=thick.get_data(),"Geometric contour width updates without mesh/atlas rebuilding")
	style.shadow_tint=Color(.7,1,.7);var green := await pixels();style.shadow_tint=Color(.86,.9,1.1)
	check((await pixels()).get_data()!=green.get_data(),"Shadow tint is exposed and updates vertex colours")
	var visibility := {}
	for entry: Dictionary in renderer.entries:
		if entry.depth_correct and not visibility.has(entry.node):visibility[entry.node]=entry.node.visible;entry.node.visible=false
	style.enabled=false;var world_before := await pixels();style.enabled=true;var world_after := await pixels()
	check(world_before.get_data()==world_after.get_data(),"Default anime profile preserves every visible world pixel")
	style.world_strength=.7;check((await pixels()).get_data()!=world_after.get_data(),"Independent world strength can stylize the scenery")
	style.world_strength=0
	for node: Node3D in visibility:node.visible=visibility[node]
	renderer.fog_enabled=true;renderer.fog_start=0;renderer.fog_end=4;renderer.fog_color=Color(.1,.2,.35)
	var fogged := await pixels();renderer.fog_enabled=false
	check((await pixels()).get_data()!=fogged.get_data(),"Existing PSX fog still applies to cel colours and contour")
	check(renderer.atlas_texture.get_instance_id()==atlas and renderer.geometry_revision==geometry,"All style edits retain cached geometry, imported materials and texture pages")
	result.portrait_original=await benchmark(false,120);result.portrait_anime=await benchmark(true,120)
	renderer.set_active_camera(p.camera);result.gameplay_anime=await benchmark(true,180)
	check(result.gameplay_anime.cpu_p95_ms<16.67,"Anime CPU render path remains within a 60 FPS frame budget on this machine")
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Rendering does not rewrite "+path)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;buffer.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	result.merge({"ok":failures.is_empty(),"checks":checks,"errors":failures,"native_stats":stats})
	FileAccess.open("res://docs/anime-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ANIME_OK " if failures.is_empty() else "ANIME_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
