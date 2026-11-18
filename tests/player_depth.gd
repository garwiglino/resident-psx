extends SceneTree
const Renderer=preload("res://scripts/psx_renderer.gd")
var failures: Array[String]=[]
var cases: Array[Dictionary]=[]
var fixture: Node3D
var actor: Node3D
var camera: Camera3D
var renderer: Node2D
var sheet: Image
var captures := 0
const SCREEN := [Vector2(24,24),Vector2(296,24),Vector2(160,220)]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func begin(orthographic := false) -> void:
	fixture=Node3D.new();root.add_child(fixture)
	actor=Node3D.new();fixture.add_child(actor);actor.add_to_group("player")
	camera=Camera3D.new();fixture.add_child(camera);camera.fov=90;camera.near=.1;camera.far=100
	if orthographic:camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2
	renderer=Renderer.new();root.add_child(renderer)
	# Exact swatch checks isolate visibility from the shared anime color grade.
	renderer.anime_style=null
	renderer.ambient_light_color=Color.WHITE;renderer.dithering=false;renderer.fog_start=90;renderer.fog_end=99
	renderer.ordering_table_size=16
func triangle(owner: Node,color: Color,depths: Array,texture: Texture2D=null,sprite := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new();owner.add_child(mesh)
	var points := PackedVector3Array()
	for i in 3:
		var scale: float=1.0 if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else depths[i]
		points.append(Vector3((SCREEN[i].x-160)*scale/120,(120-SCREEN[i].y)*scale/120,-depths[i]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2(.5,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var resource := ArrayMesh.new();resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new();material.albedo_color=color;material.albedo_texture=texture
	resource.surface_set_material(0,material);mesh.mesh=resource
	if sprite:mesh.add_to_group("psx_sprite")
	return mesh
func capture(label: String,left: Color,right: Color) -> void:
	renderer.setup_editor(fixture,camera)
	renderer._process(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var a := image.get_pixel(70,55);var b := image.get_pixel(250,55)
	check(Vector3(a.r,a.g,a.b).distance_to(Vector3(left.r,left.g,left.b))<.075,label+": correct left pixel")
	check(Vector3(b.r,b.g,b.b).distance_to(Vector3(right.r,right.g,right.b))<.075,label+": correct right pixel")
	var native: Dictionary=renderer.native_geometry.get_statistics()
	check(native.version>=13 and native.batches==1,label+": native v13 and one draw batch")
	cases.append({"case":label,"left":a.to_html(),"right":b.to_html(),"triangles":native.triangles,"corrected":native.player_depth_triangles,"pixels":native.player_depth_pixels})
	if captures<8:sheet.blit_rect(image,Rect2i(0,0,320,240),Vector2i((captures%4)*320,(captures/4)*240));captures+=1
	renderer.queue_free();fixture.queue_free();await process_frame
func run() -> void:
	root.size=Vector2i(320,240);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	sheet=Image.create(1280,480,false,Image.FORMAT_RGBA8)
	# Same projected triangle, crossing depth planes: no average sort can solve it.
	begin();triangle(actor,Color.RED,[2,6,6]);triangle(actor,Color.BLUE,[4,4,4])
	await capture("player_weapon_crossing",Color.RED,Color.BLUE)
	begin();triangle(actor,Color.RED,[4,4,4]);triangle(actor,Color.BLUE,[2,6,6])
	await capture("reversed_submission",Color.BLUE,Color.RED)
	begin();triangle(actor,Color.RED,[2,2,2]);triangle(fixture,Color.GREEN,[1,6,6])
	await capture("world_nearer_than_player",Color.GREEN,Color.RED)
	begin();triangle(actor,Color.RED,[1,6,6]);triangle(fixture,Color.GREEN,[3,3,3])
	await capture("player_nearer_than_late_world",Color.RED,Color.GREEN)
	begin();triangle(fixture,Color.RED,[1,6,6]);triangle(fixture,Color.GREEN,[3,3,3])
	await capture("world_crossing_depth_corrected",Color.RED,Color.GREEN)
	check(cases[-1].corrected>0 and cases[-1].pixels>0,"World-only scenes use full-scene depth correction")
	var cutout := Image.create(32,32,false,Image.FORMAT_RGBA8);cutout.fill(Color(1,1,1,0));cutout.fill_rect(Rect2i(0,0,16,32),Color.WHITE)
	var texture := ImageTexture.create_from_image(cutout)
	begin();triangle(actor,Color.RED,[4,4,4]);triangle(actor,Color.GREEN,[2,2,2],texture)
	await capture("player_alpha_cutout",Color.GREEN,Color.RED)
	begin();renderer.affine_texture_strength=0;renderer.vertex_snapping=false
	triangle(actor,Color.RED,[4,4,4]);triangle(fixture,Color.GREEN,[2,2,2],texture)
	await capture("world_alpha_cutout_perspective",Color.GREEN,Color.RED)
	begin(true);triangle(actor,Color.RED,[2,6,6]);triangle(actor,Color.BLUE,[4,4,4])
	await capture("orthographic_visibility",Color.RED,Color.BLUE)
	# The muzzle flash is translucent and must not become a solid occluder.
	begin();triangle(actor,Color.RED,[2,2,2]);triangle(actor,Color.WHITE,[1,1,1],null,true)
	renderer.setup_editor(fixture,camera);renderer._process(0)
	var mask: Image=renderer.native_geometry.get_player_depth_texture().get_image()
	check(absf(mask.get_pixel(160,100).r-.5)<.001 and mask.get_pixel(160,100).g>.5,"Flash never writes depth or hides the opaque player")
	renderer.queue_free();fixture.queue_free();await process_frame
	sheet.save_png("res://docs/player-depth-cases.png")
	FileAccess.open("res://docs/player-depth-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":cases},"\t"))
	print("PLAYER_DEPTH_OK: crossing player/weapon/world surfaces, global depth, alpha cutouts, perspective/orthographic projection and translucent flash" if failures.is_empty() else "PLAYER_DEPTH_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
