extends SceneTree
const MATRIX := [-4,0,-3,1,2,-2,3,-1,-3,1,-4,0,3,-1,2,-2]
var view: SubViewport
var canvas: Node2D
var atlas: ImageTexture
var failures: Array[String]=[]
var geometry: RefCounted
var ordering_packets: Array=[]

func _initialize() -> void:
	call_deferred("run")

func packet(rgb: Vector3i,page: int) -> Color:
	return Color(rgb.x/255.0,rgb.y/255.0,rgb.z/255.0,page/255.0)

func rect(pos: Vector2,rgb: Vector3i,page: int,uv: Vector2) -> void:
	var points := PackedVector2Array([pos,pos+Vector2(40,0),pos+Vector2(0,40),pos+Vector2(40,40)])
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),PackedInt32Array([0,1,2,1,3,2]),points,
		PackedColorArray([packet(rgb,page),packet(rgb,page),packet(rgb,page),packet(rgb,page)]),PackedVector2Array([uv,uv,uv,uv]),
		PackedInt32Array(),PackedFloat32Array(),atlas.get_rid())

func draw_packets() -> void:
	canvas.draw_rect(Rect2(0,0,320,240),packet(Vector3i(32,40,48),0))
	rect(Vector2(0,0),Vector3i(96,136,200),0,Vector2.ZERO)
	rect(Vector2(48,0),Vector3i(128,128,128),1,Vector2(.1,0))
	rect(Vector2(96,0),Vector3i(255,255,255),1,Vector2(.1,0))
	rect(Vector2(144,0),Vector3i(64,64,64),1,Vector2(.1,0))
	rect(Vector2(192,0),Vector3i(128,128,128),1,Vector2(1.1,0))
	rect(Vector2(240,0),Vector3i(128,128,128),2,Vector2(.9,0))
	rect(Vector2(0,48),Vector3i(128,128,128),33,Vector2(.1,0))
	for batch in ordering_packets:
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),batch.indices,batch.points,batch.colors,batch.uvs,
			PackedInt32Array(),PackedFloat32Array(),atlas.get_rid())

func prepare_depth_order_test() -> void:
	geometry=ClassDB.instantiate("PSXGeometry")
	var entries: Array=[]
	# Submit near green first, far red second: correct painter output must reverse them.
	for i in 2:
		var node := MeshInstance3D.new()
		root.add_child(node)
		var z := -1.5 if i==0 else -3.0
		var vertices := PackedVector3Array([Vector3(-.5,-.5,z),Vector3(.5,-.5,z),Vector3(0,.5,z)])
		var color := Vector3(0,1,0) if i==0 else Vector3(1,0,0)
		entries.append({"node":node,"skeleton":null,"vertices":vertices,"normals":PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]),
			"uvs":PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]),"indices":PackedInt32Array([0,2,1]),
			"bind_indices":PackedInt32Array(),"binds":[],"color":Color.WHITE,"emission":Color(color.x,color.y,color.z),"fixed":true,"textured":false,"texture_page":0,
			"draw_texture":atlas,"logical_texture_size":Vector2.ONE,"aabb":AABB(Vector3(-.5,-.5,z),Vector3(1,1,.01)),
			"static_positions":vertices,"static_normals":PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]),
			"static_light":PackedVector3Array([color,color,color])})
	geometry.configure(entries)
	ordering_packets=geometry.frame(Transform3D.IDENTITY,50,false,false,true)

func check_patch(image: Image,origin: Vector2i,source_rgb8: Vector3i,label: String) -> void:
	for y in 4:
		for x in 4:
			var pixel := origin+Vector2i(x,y)
			var actual := image.get_pixelv(pixel)
			var offset: int=MATRIX[(pixel.y&3)*4+(pixel.x&3)]
			for channel in 3:
				var byte: int=source_rgb8[channel]
				var expected := floorf(clampi(byte+offset,0,255)/8.0)/31.0
				if absf(actual[channel]-expected)>1.01/255.0:
					failures.append("%s at %s channel %s: %s != %s" % [label,pixel,channel,actual[channel],expected])

func run() -> void:
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.disable_3d=true
	root.add_child(view)
	var image := Image.create(4,1,false,Image.FORMAT_RGBA8)
	image.set_pixel(0,0,Color8(248,120,56))
	image.set_pixel(1,0,Color8(16,232,128))
	image.set_pixel(2,0,Color8(248,0,0))
	image.set_pixel(3,0,Color(0,0,0,0))
	atlas=ImageTexture.create_from_image(image)
	prepare_depth_order_test()
	canvas=Node2D.new()
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader=load("res://shaders/psx_raster.gdshader")
	var pages := PackedVector4Array()
	pages.resize(32)
	pages[0]=Vector4(0,0,1,1)
	pages[1]=Vector4(0,0,2,1)
	pages[2]=Vector4(2,0,2,1)
	mat.set_shader_parameter("texture_pages",pages)
	mat.set_shader_parameter("dither_enabled",true)
	canvas.material=mat
	canvas.draw.connect(draw_packets)
	view.add_child(canvas)
	for i in 4:
		await process_frame
	RenderingServer.force_draw(false)
	var result := view.get_texture().get_image()
	result.save_png("res://docs/raster-accuracy.png")
	check_patch(result,Vector2i(8,8),Vector3i(96,136,200),"Gouraud untextured + 4x4 dither")
	check_patch(result,Vector2i(56,8),Vector3i(248,120,56),"Neutral 0x80 modulation")
	check_patch(result,Vector2i(104,8),Vector3i(494,239,111),"Overbright 0xFF modulation + saturation")
	check_patch(result,Vector2i(152,8),Vector3i(124,60,28),"Half 0x40 modulation")
	check_patch(result,Vector2i(200,8),Vector3i(248,120,56),"Page wrap does not bleed into adjacent page")
	check_patch(result,Vector2i(248,8),Vector3i(32,40,48),"Transparent texels preserve background")
	for y in 4:
		for x in 4:
			var pixel := Vector2i(8+x,56+y)
			var actual := result.get_pixelv(pixel)
			var offset: int=MATRIX[(pixel.y&3)*4+(pixel.x&3)]
			for channel in 3:
				var foreground := floorf(clampi(Vector3i(248,120,56)[channel]+offset,0,255)/8.0)/31.0
				var background := floorf(clampi(Vector3i(32,40,48)[channel]+offset,0,255)/8.0)/31.0
				if absf(actual[channel]-(foreground+background)*.5)>1.5/255.0:failures.append("Translucent sprite must blend at half opacity over the already ordered scene")
	var center := result.get_pixel(160,120)
	if center.g<.99 or center.r>.01 or center.b>.01:
		failures.append("Ordering table must draw near green over far red in the single atlas batch")
	for failure in failures.slice(0,8):
		push_error(failure)
	print("RASTER_ACCURACY_OK: GPU pixels match RGB555, modulation, saturation, hardware dither, texture window, cutout and depth ordering" if failures.is_empty() else "RASTER_ACCURACY_FAILED "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
