extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func colors(geometry: RefCounted) -> PackedColorArray:
	var packets: Array=geometry.frame(Transform3D.IDENTITY,50,false,false,true)
	check(packets.size()==1,"Shot effects retain one ordered atlas submission")
	return packets[0].colors
func run() -> void:
	var renderer=load("res://scripts/psx_renderer.gd").new()
	renderer.torch_on=false
	var geometry: RefCounted=ClassDB.instantiate("PSXGeometry")
	check(geometry.get_statistics().version>=9,"Native shot-light and atlas-sprite implementation is loaded")
	var node := MeshInstance3D.new();root.add_child(node)
	var image := Image.create(1,1,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var vertices := PackedVector3Array([Vector3(-.4,-.3,-2),Vector3(.4,-.3,-2),Vector3(0,.4,-2)])
	var normals := PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	var uv := PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(.5,0)])
	var entry := {"node":node,"skeleton":null,"vertices":vertices,"normals":normals,"uvs":uv,"indices":PackedInt32Array([0,2,1]),
	 "bind_indices":PackedInt32Array(),"binds":[],"color":Color(.75,.75,.75),"emission":Color.BLACK,"fixed":true,"textured":false,"texture_page":0,
	 "draw_texture":texture,"logical_texture_size":Vector2.ONE,"aabb":AABB(Vector3(-.4,-.3,-2),Vector3(.8,.7,.01)),
	 "static_positions":vertices,"static_normals":normals,"static_light":PackedVector3Array([Vector3.ONE*.2,Vector3.ONE*.2,Vector3.ONE*.2])}
	geometry.set_world_lights([],Vector3.ONE*(.2/.75))
	geometry.configure([entry]);var baseline := colors(geometry)
	var position := Vector3(.2,.1,-1.4)
	var tint := Vector3(1,.56,.18)
	geometry.set_shot_light(position,tint,.6,3.2)
	var lit := colors(geometry)
	renderer.shot_light_position=position;renderer.shot_light_color=tint;renderer.shot_light_energy=.6;renderer.shot_light_range=3.2
	var indexes := [0,2,1]
	for vertex in 3:
		var point := vertices[indexes[vertex]]
		var delta := position-point
		var attenuation := pow(1.0-delta.length_squared()/(3.2*3.2),2)
		var expected := Vector3.ONE*.2+Vector3.ONE*.75*tint*.6*attenuation*Vector3.BACK.dot(delta.normalized())
		expected=(expected*255).floor()/255
		check(lit[vertex].r>baseline[vertex].r and lit[vertex].r-lit[vertex].b>.1,"Shot point light gives nearby vertices a warm diffuse contribution")
		for channel in 3:check(absf(lit[vertex][channel]-expected[channel])<.00001,"Native shot lighting matches per-vertex diffuse and distance attenuation")
		var fallback: Color=renderer.shade(point,Vector3.BACK,2,entry.color,Vector3.ONE*.2,false)
		for channel in 3:check(absf(lit[vertex][channel]-fallback[channel])<.00001,"Native and GDScript vertex lighting agree")
	check(not lit[0].is_equal_approx(lit[1]),"Different vertex distances create Gouraud lighting rather than a flat screen overlay")
	geometry.set_shot_light(position,tint,.6,.4)
	check(colors(geometry)==baseline,"Vertices outside the flash radius remain unchanged")
	geometry.set_shot_light(position,tint,0,3.2)
	check(colors(geometry)==baseline,"Ending a flash restores cached static light exactly")
	entry.static_normals=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	geometry.configure([entry]);geometry.set_shot_light(position,tint,.6,3.2)
	check(colors(geometry)==baseline,"Flash lighting respects surface orientation")
	# Verify addressing of every logical 64x64 sprite, including the bottom-right cell.
	entry.sprite=true;entry.textured=true;entry.texture_page=34;entry.logical_texture_size=Vector2(256,256)
	geometry.configure([entry])
	for frame in 16:
		node.set_meta("psx_sprite_frame",frame)
		var packets: Array=geometry.frame(Transform3D.IDENTITY,50,false,false,true)
		var rect := Rect2(Vector2((frame%4)*64,(frame/4)*64)/256.0,Vector2(64,64)/256.0)
		for texcoord: Vector2 in packets[0].uvs:check(rect.has_point(texcoord),"Sprite UVs stay inside atlas cell "+str(frame))
		for color: Color in packets[0].colors:check(absf(color.r-128.0/255)<.00001 and absf(color.a-34.0/255)<.00001,"Flash preserves its page and translucent flag through the native self-lit packet")
	var atlas_texture: Texture2D=load("res://assets/effects/muzzle_flash_atlas.png")
	var atlas := atlas_texture.get_image()
	check(atlas.get_size()==Vector2i(256,256) and atlas.detect_alpha()!=Image.ALPHA_NONE,"Flash atlas is one native-size RGBA PSX texture page")
	var hashes: Dictionary={}
	for frame in 16:
		var cell := atlas.get_region(Rect2i((frame%4)*64,(frame/4)*64,64,64))
		hashes[hash(cell.get_data())]=true
		check(cell.get_pixel(32,32).a>.5,"Every flash has an opaque bright center")
	check(hashes.size()==16,"All sixteen muzzle flash shapes have different texture data")
	FileAccess.open("res://docs/shot-lighting-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"baseline":str(baseline),"lit":str(lit),"distinct_atlas_cells":hashes.size(),"failures":failures},"\t"))
	renderer.free();node.queue_free();await process_frame
	print("SHOT_LIGHTING_OK: native/fallback diffuse vertex light, radius, normals, static restoration, 16 atlas cells and PSX packets" if failures.is_empty() else "SHOT_LIGHTING_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
