extends SceneTree
const Renderer=preload("res://scripts/psx_renderer.gd")
const Light=preload("res://scripts/psx_light_3d.gd")
var failures: Array[String]=[]
var observations: Dictionary={}
var fixture: Node3D
var renderer: Node2D
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: failures.append(message); push_error(message)
func capture() -> Color:
	for frame in 3: renderer.render_editor(); await process_frame
	await RenderingServer.frame_post_draw
	var at := camera.unproject_position(Vector3(1,0,0))
	return root.get_texture().get_image().get_pixel(roundi(at.x),roundi(at.y))
func run() -> void:
	root.size=Vector2i(320,240); fixture=Node3D.new(); root.add_child(fixture)
	camera=Camera3D.new(); fixture.add_child(camera); camera.position=Vector3(3,3,4); camera.look_at(Vector3(1,0,0)); camera.fov=60
	var floor := MeshInstance3D.new(); floor.mesh=PlaneMesh.new(); floor.mesh.size=Vector2(2,2); floor.position=Vector3(1,0,0); fixture.add_child(floor)
	var wall := MeshInstance3D.new(); wall.mesh=BoxMesh.new(); wall.mesh.size=Vector3(.1,3,4); wall.position=Vector3(0,1.5,0); fixture.add_child(wall); wall.visible=false
	var lamp := Light.new(); lamp.name="LampeA"; fixture.add_child(lamp); lamp.position=Vector3(-1,2,0); lamp.light_energy=4; lamp.light_range=8
	renderer=Renderer.new(); root.add_child(renderer); renderer.fog_enabled=false; renderer.dithering=false; renderer.setup_editor(fixture,camera)
	var lit := await capture(); wall.visible=true; var blocked := await capture()
	check(lit.get_luminance()>.1,"Receiver is lit without a wall")
	check(blocked.get_luminance()<.015,"Wall blocks illumination, including shared boundary vertices")
	for kind in [Light.LightType.SPOT,Light.LightType.DIRECTIONAL]:
		lamp.light_type=kind; lamp.spot_angle_degrees=120
		lamp.look_at(lamp.global_position+Vector3(1,-1,0))
		wall.visible=false; var clear := await capture()
		wall.visible=true; var shadow := await capture()
		check(clear.get_luminance()>.05 and shadow.get_luminance()<.015,"Spot and directional light are both stopped by walls")
	lamp.light_type=Light.LightType.OMNI; lamp.enabled=false
	renderer.torch_on=true
	renderer.native_geometry.set_torch_light(lamp.global_position,Vector3(1,-1,0).normalized(),Vector3.ONE,4,8,cos(deg_to_rad(70)),cos(deg_to_rad(50)))
	wall.visible=false; var torch_clear := await capture()
	wall.visible=true; var torch_shadow := await capture()
	check(torch_clear.get_luminance()>.05 and torch_shadow.get_luminance()<.015,"The player's flashlight cannot shine through a wall")
	renderer.torch_on=false; renderer.native_geometry.set_shot_light(lamp.global_position,Vector3.ONE,4,8)
	wall.visible=false; var flash_clear := await capture()
	wall.visible=true; var flash_shadow := await capture()
	check(flash_clear.get_luminance()>.05 and flash_shadow.get_luminance()<.015,"Muzzle light cannot cross a wall")
	renderer.native_geometry.set_shot_light(Vector3.ZERO,Vector3.ZERO,0,1); lamp.enabled=true
	wall.position.z=5; var restored := await capture()
	check(restored.get_luminance()>.1,"Moving the wall updates the occlusion structure")
	wall.position.z=0; wall.visible=false; lamp.position.x=1.5; var same_side_reference := await capture()
	wall.visible=true; var same_side := await capture()
	check(absf(same_side_reference.get_luminance()-same_side.get_luminance())<.04,"Wall-adjacent floor vertices remain lit from their own room")
	lamp.flicker=true; lamp.flicker_amount=.8; lamp.dropout_chance=0
	await capture()
	check(renderer.native_geometry.get_statistics().shadow_rays==0,"Static visibility cache is reused while intensity flickers")
	var clone := Light.new(); clone.name="LampeB"; fixture.add_child(clone); clone.flicker=true; clone.light_energy=lamp.light_energy
	clone.flicker_seed=123; lamp.flicker_seed=123
	var models: Array[Dictionary]=[]
	for style in 4:
		lamp.flicker_style=style; clone.flicker_style=style; clone.flicker_amount=lamp.flicker_amount; clone.dropout_chance=0
		var different := false; var low := INF; var high := -INF; var largest := 0.0; var previous := lamp.sample_energy_at(0)
		for index in 180:
			var a: float=lamp.sample_energy_at(index/60.0); var b: float=clone.sample_energy_at(index/60.0)
			different=different or absf(a-b)>.001; low=minf(low,a); high=maxf(high,a); largest=maxf(largest,absf(a-previous)); previous=a
		check(different,"Each lamp has an independent pattern, even with a copied seed")
		check(high-low>.01,"Every model varies over time")
		if style==Light.FlickerStyle.CANDLE: check(low>0 and largest<.3,"Candle varies smoothly without electric blackouts")
		models.append({"style":style,"min":low,"max":high,"largest_step":largest})
	observations={"lit":lit.to_html(),"blocked":blocked.to_html(),"restored":restored.to_html(),"same_side":same_side.to_html(),"same_side_reference":same_side_reference.to_html(),"models":models,"native":renderer.native_geometry.get_statistics()}
	fixture.queue_free(); renderer.queue_free(); await process_frame
	var result := {"ok":failures.is_empty(),"errors":failures,"observations":observations}
	FileAccess.open("res://docs/light-occlusion-flicker.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LIGHT_OCCLUSION_FLICKER_OK " if failures.is_empty() else "LIGHT_OCCLUSION_FLICKER_FAILED ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
