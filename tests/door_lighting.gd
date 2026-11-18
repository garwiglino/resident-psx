extends SceneTree
var Renderer: Script
var Light: Script
var PSX: Script
var failures: Array[String]=[]
var observations: Array[Dictionary]=[]
var fixture: Node3D
var renderer: Node2D
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func capture(shadows: bool) -> Color:
	renderer.native_geometry.set_render_settings({"fog_start":100.0,"fog_end":150.0,"light_occlusion":shadows})
	for frame in 2: renderer.render_editor(); await process_frame
	await RenderingServer.frame_post_draw
	var at := camera.unproject_position(Vector3(0,1.1,.03))
	return root.get_texture().get_image().get_pixel(roundi(at.x),roundi(at.y))
func run() -> void:
	Renderer=load("res://scripts/psx_renderer.gd"); Light=load("res://scripts/psx_light_3d.gd"); PSX=load("res://scripts/psx_materials.gd")
	root.size=Vector2i(320,240); fixture=Node3D.new(); root.add_child(fixture)
	var kit: Resource=load("res://assets/environment/modular_2m/default_kit.tres")
	var frame := MeshInstance3D.new(); frame.mesh=kit.mesh_for("wall_door"); fixture.add_child(frame)
	var door: Node3D=load("res://scripts/modular_map/door.gd").new(); door.name="Door"; fixture.add_child(door)
	var leaf := MeshInstance3D.new(); leaf.mesh=kit.mesh_for("door_01"); leaf.material_override=PSX.make(Color.WHITE); leaf.position.x=-.5; door.add_child(leaf)
	camera=Camera3D.new(); fixture.add_child(camera); camera.position=Vector3(0,1.1,2.6); camera.look_at(Vector3(0,1.1,0)); camera.fov=60
	var light: Node3D=Light.new(); fixture.add_child(light); light.light_energy=3; light.light_range=6
	renderer=Renderer.new(); root.add_child(renderer); renderer.fog_enabled=false; renderer.dithering=false; renderer.setup_editor(fixture,camera)
	for position in [Vector3(0,1.5,1.2),Vector3(.5,2,1),Vector3(-.5,1,1)]:
		light.position=position
		var reference := await capture(false); var lit := await capture(true)
		frame.visible=false; var without_frame := await capture(true); frame.visible=true
		observations.append({"position":str(position),"reference":reference.to_html(),"lit":lit.to_html(),"without_frame":without_frame.to_html()})
		check(lit.get_luminance()>=reference.get_luminance()*.8,"Door receives unobstructed light from its own room: "+str(position))
	root.get_texture().get_image().save_png("res://docs/door-lighting.png")
	fixture.queue_free(); renderer.queue_free(); await process_frame
	var result := {"ok":failures.is_empty(),"errors":failures,"observations":observations}
	FileAccess.open("res://docs/door-lighting-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DOOR_LIGHTING_OK " if failures.is_empty() else "DOOR_LIGHTING_FAILED ",JSON.stringify(result)); quit(0 if failures.is_empty() else 1)
