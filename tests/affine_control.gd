extends SceneTree
var failures: Array[String]=[]
var view: SubViewport
var canvas: Node2D
var mesh: ArrayMesh
var atlas: ImageTexture
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func draw_triangle() -> void:canvas.draw_mesh(mesh,atlas)

func run() -> void:
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.disable_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	canvas=Node2D.new()
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(canvas)
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:image.set_pixel(x,y,Color8((x/2)*8,(y/2)*8,32))
	atlas=ImageTexture.create_from_image(image)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector2Array([Vector2(20,20),Vector2(300,20),Vector2(20,220)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2(63.0/64,0),Vector2(0,63.0/64)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color(128.0/255,128.0/255,128.0/255,1.0/255),Color(128.0/255,128.0/255,128.0/255,1.0/255),Color(128.0/255,128.0/255,128.0/255,1.0/255)])
	arrays[Mesh.ARRAY_CUSTOM0]=PackedFloat32Array([1,.25,.5])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	mesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES|(Mesh.ARRAY_CUSTOM_R_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/psx_raster.gdshader")
	material.set_shader_parameter("dither_enabled",false)
	var pages := PackedVector4Array()
	pages.resize(32)
	pages[1]=Vector4(0,0,64,64)
	material.set_shader_parameter("texture_pages",pages)
	canvas.material=material
	canvas.draw.connect(draw_triangle)
	var measurements: Array=[]
	for strength in [1.0,.5,0.0]:
		material.set_shader_parameter("affine_texture_strength",strength)
		canvas.queue_redraw()
		for frame in 3:await process_frame
		RenderingServer.force_draw(false)
		var result := view.get_texture().get_image()
		result.save_png("res://docs/affine-control-%d.png" % roundi(strength*100))
		var largest_error := 0.0
		for pixel in [Vector2i(100,80),Vector2i(150,60),Vector2i(70,130)]:
			var b := (float(pixel.x)+.5-20)/280
			var c := (float(pixel.y)+.5-20)/200
			var a := 1-b-c
			var affine_uv := Vector2(b,c)*(63.0/64)
			var correct_uv := Vector2(b*.25,c*.5)*(63.0/64)/(a+b*.25+c*.5)
			var uv := correct_uv.lerp(affine_uv,strength)
			var expected := Vector3(floorf(floorf(uv.x*64)/2)/31,floorf(floorf(uv.y*64)/2)/31,4.0/31)
			var actual := result.get_pixelv(pixel)
			var error := Vector3(actual.r,actual.g,actual.b).distance_to(expected)
			largest_error=maxf(largest_error,error)
			check(error<.008,"GPU affine strength %.2f at %s: %s expected %s" % [strength,pixel,actual,expected])
		measurements.append({"strength":strength,"largest_color_error":largest_error})
	FileAccess.open("res://docs/affine-control-validation.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t"))
	print("AFFINE_CONTROL_OK: GPU pixels match affine, perspective-correct and intermediate UV interpolation" if failures.is_empty() else "AFFINE_CONTROL_FAILED "+str(failures))
	view.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
