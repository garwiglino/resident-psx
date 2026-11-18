extends Node2D
## PSX-like render path: CPU geometry, integer projection, Gouraud colours,
## affine 2D triangles and ordering table. No 3D depth buffer is used.
const WIDTH := 320
const HEIGHT := 240
const UNITS := 1024.0
const FAR := 42.0
const NEAR := 0.08
const LAMPS := [Vector3(-2.8,2.8,5),Vector3(2.7,2.8,-3),Vector3(-2.8,2.8,-11),Vector3(2.7,2.8,-20),Vector3(0,2.7,-28)]
const LAMP_COLORS := [Vector3(1.05,.71,.40),Vector3(.40,.85,.79),Vector3(.94,.32,.21),Vector3(.60,.83,.72),Vector3(.9,.12,.06)]
@export_group("Rendu PSX")
@export var vertex_snapping := true
@export var dithering := true
@export_range(10.0,100.0,1.0,"suffix:m") var draw_distance := 42.0
@export_range(0.0,80.0,.5,"suffix:m") var fog_start := 9.0
@export_range(1.0,100.0,.5,"suffix:m") var fog_end := 33.0
@export_enum("256:256","512:512","1024:1024","2048:2048") var ordering_table_size := 1024
@export_group("Performances")
## 0 = sans limite. Le tick physique reste à 60 Hz.
@export_range(0,240,1,"suffix:FPS") var target_fps := 60
var native_geometry_enabled := true
var game: Node3D
var camera: Camera3D
var entries: Array[Dictionary] = []
var primitives: Array[Dictionary] = []
var blank: ImageTexture
var triangle_count := 0
var vertex_count := 0
var raster: ShaderMaterial
var inverse_camera := Transform3D.IDENTITY
var camera_matrix := Basis.IDENTITY
var focal := 200.0
var torch_pos := Vector3.ZERO
var torch_dir := Vector3.FORWARD
var torch_on := true
var powered := false
var effects: Array[Dictionary]=[]
var last_process_us := 0
var last_draw_us := 0
var native_geometry: RefCounted
var batch_count := 0
var _render_settings: Array=[]

func _ready() -> void:
	set_process(false)

func setup(game_root: Node3D,active_camera: Camera3D) -> void:
	game=game_root
	camera=active_camera
	z_index=-100
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	var image := Image.create(1,1,false,Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	blank=ImageTexture.create_from_image(image)
	raster=ShaderMaterial.new()
	raster.shader=load("res://shaders/psx_raster.gdshader")
	material=raster
	cache_branch(game.level)
	cache_branch(game.player.motion.model)
	for enemy in game.enemies:
		cache_branch(enemy)
	for item in game.interactables:
		if item.node:
			cache_branch(item.node)
	camera.cull_mask=0
	if native_geometry_enabled and ClassDB.class_exists("PSXGeometry"):
		native_geometry=ClassDB.instantiate("PSXGeometry")
		native_geometry.configure(entries)
	apply_render_settings()
	set_process(true)

func apply_render_settings() -> void:
	Engine.max_fps=target_fps
	raster.set_shader_parameter("dither_enabled",dithering)
	game.materials.snap_enabled=vertex_snapping
	if native_geometry:
		native_geometry.set_render_settings({"far_clip":minf(draw_distance,camera.far),"near_clip":camera.near,
			"fog_start":fog_start,"fog_end":fog_end,"ordering_buckets":ordering_table_size})
	_render_settings=[vertex_snapping,dithering,draw_distance,fog_start,fog_end,ordering_table_size,target_fps,camera.near,camera.far]

func cache_branch(node: Node) -> void:
	if node is MeshInstance3D:
		cache_mesh(node)
	elif node is Label3D:
		node.visible=false
	for child in node.get_children():
		cache_branch(child)

func cache_mesh(node: MeshInstance3D) -> void:
	if not node.mesh or node.mesh is ImmediateMesh:
		return
	for surface in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var mat: Material=node.get_active_material(surface)
		var tint := Color.WHITE
		var emission := Color.BLACK
		var texture: Texture2D=blank
		if mat is ShaderMaterial:
			tint=mat.get_shader_parameter("tint")
			var e = mat.get_shader_parameter("emission_color")
			if e is Vector3:
				emission=Color(e.x,e.y,e.z)
			elif e is Color:
				emission=e
			if mat.get_shader_parameter("has_texture"):
				texture=mat.get_shader_parameter("albedo_texture")
		elif mat is StandardMaterial3D:
			tint=mat.albedo_color
			if mat.emission_enabled:
				emission=mat.emission
			if mat.albedo_texture:
				texture=mat.albedo_texture
		var skeleton: Skeleton3D=null
		var bind_indices := PackedInt32Array()
		var binds: Array[Transform3D]=[]
		if node.skin and not node.skeleton.is_empty():
			skeleton=node.get_node_or_null(node.skeleton)
			if skeleton:
				for b in node.skin.get_bind_count():
					var bone := node.skin.get_bind_bone(b)
					if bone<0:
						bone=skeleton.find_bone(node.skin.get_bind_name(b))
					bind_indices.append(bone)
					binds.append(node.skin.get_bind_pose(b))
		var static_positions := PackedVector3Array()
		var static_normals := PackedVector3Array()
		var static_light := PackedVector3Array()
		var fixed: bool=game.level.is_ancestor_of(node)
		if fixed:
			var normal_matrix := node.global_basis.inverse().transposed()
			var ns: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				var p: Vector3=(node.global_transform*vertices[i]*UNITS).round()/UNITS
				var n: Vector3=(normal_matrix*ns[i]).normalized()
				static_positions.append(p)
				static_normals.append(n)
				static_light.append(bake_light(p,n,tint,emission))
		entries.append({"node":node,"vertices":vertices,"normals":arrays[Mesh.ARRAY_NORMAL],"uvs":arrays[Mesh.ARRAY_TEX_UV],"indices":indices,
			"color":tint,"emission":emission,"texture":texture,"skeleton":skeleton,"bind_indices":bind_indices,"binds":binds,
			"bones":arrays[Mesh.ARRAY_BONES],"weights":arrays[Mesh.ARRAY_WEIGHTS],"aabb":node.mesh.get_aabb(),
			"fixed":fixed,"static_positions":static_positions,"static_normals":static_normals,"static_light":static_light})

func _process(_delta: float) -> void:
	var start_us := Time.get_ticks_usec()
	if not is_instance_valid(camera):
		return
	if [vertex_snapping,dithering,draw_distance,fog_start,fog_end,ordering_table_size,target_fps,camera.near,camera.far]!=_render_settings:
		apply_render_settings()
	inverse_camera=camera.global_transform.affine_inverse()
	camera_matrix=inverse_camera.basis
	for col in 3:
		camera_matrix[col]=(camera_matrix[col]*4096.0).round()/4096.0
	focal=120.0/tan(deg_to_rad(camera.fov)*.5)
	torch_pos=camera.global_position
	torch_dir=-camera.global_basis.z
	torch_on=game.player.flashlight
	powered=game.power
	primitives.clear()
	vertex_count=0
	if native_geometry:
		primitives.assign(native_geometry.frame(camera.global_transform,camera.fov,torch_on,powered,game.materials.snap_enabled))
		var statistics: Dictionary=native_geometry.get_statistics()
		triangle_count=statistics.triangles
		vertex_count=statistics.vertices
		batch_count=statistics.batches
		last_process_us=Time.get_ticks_usec()-start_us
		queue_redraw()
		return
	for entry in entries:
		if is_instance_valid(entry.node) and entry.node.is_visible_in_tree():
			transform_entry(entry)
	primitives.sort_custom(func(a: Dictionary,b: Dictionary): return a.bucket>b.bucket if a.bucket!=b.bucket else a.order>b.order)
	triangle_count=primitives.size()
	last_process_us=Time.get_ticks_usec()-start_us
	queue_redraw()

func transform_entry(entry: Dictionary) -> void:
	var node: MeshInstance3D=entry.node
	var transform := node.global_transform
	var center: Vector3=transform*entry.aabb.get_center()
	var scale_factor: float=transform.basis.get_scale().max_axis_index()
	var radius: float=entry.aabb.size.length()*.5*transform.basis.get_scale()[int(scale_factor)]
	var c: Vector3=inverse_camera*center
	var depth := -c.z
	if depth+radius<camera.near or depth-radius>minf(draw_distance,camera.far) or absf(c.x)>depth*(160.0/focal)+radius or absf(c.y)>depth*(120.0/focal)+radius:
		return
	var skin_transforms: Array[Transform3D]=[]
	var skeleton: Skeleton3D=entry.skeleton
	if skeleton:
		for b in entry.binds.size():
			skin_transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(entry.bind_indices[b])*entry.binds[b])
	var vertices: PackedVector3Array=entry.vertices
	var normals: PackedVector3Array=entry.normals if entry.normals!=null else PackedVector3Array()
	var uvs: PackedVector2Array=entry.uvs if entry.uvs!=null else PackedVector2Array()
	var view_positions := PackedVector3Array()
	var lighting := PackedColorArray()
	var texcoords := PackedVector2Array()
	view_positions.resize(vertices.size())
	lighting.resize(vertices.size())
	texcoords.resize(vertices.size())
	var normal_matrix := transform.basis.inverse().transposed()
	var texture_size: Vector2=entry.texture.get_size()
	for v in vertices.size():
		var p: Vector3=vertices[v]
		var n: Vector3=normals[v] if not normals.is_empty() else Vector3.UP
		var world_pos := Vector3.ZERO
		var world_normal := Vector3.ZERO
		if entry.fixed:
			world_pos=entry.static_positions[v]
			world_normal=entry.static_normals[v]
		elif skeleton:
			for weight_index in 4:
				var bone: int=entry.bones[v*4+weight_index]
				var weight: float=entry.weights[v*4+weight_index]
				if weight>0 and bone<skin_transforms.size():
					world_pos+=(skin_transforms[bone]*p)*weight
					world_normal+=(skin_transforms[bone].basis*n)*weight
		else:
			world_pos=transform*p
			world_normal=normal_matrix*n
		world_pos=(world_pos*UNITS).round()/UNITS
		world_normal=world_normal.normalized()
		var view_pos := camera_matrix*(world_pos-camera.global_position)
		view_pos=(view_pos*UNITS).floor()/UNITS
		view_positions[v]=view_pos
		var base_light: Vector3=entry.static_light[v] if entry.fixed else bake_light(world_pos,world_normal,entry.color,entry.emission)
		lighting[v]=shade(world_pos,world_normal,-view_pos.z,entry.color,base_light)
		var uv: Vector2=uvs[v] if not uvs.is_empty() else Vector2.ZERO
		texcoords[v]=(uv*texture_size).floor()/texture_size
	vertex_count+=vertices.size()
	var indices: PackedInt32Array=entry.indices
	for triangle in range(0,indices.size(),3):
		var a := indices[triangle]
		var b := indices[triangle+1]
		var d := indices[triangle+2]
		if view_positions[a].z>=-camera.near and view_positions[b].z>=-camera.near and view_positions[d].z>=-camera.near:
			continue
		var polygon: Array=[{"p":view_positions[a],"c":lighting[a],"uv":texcoords[a]},
			{"p":view_positions[b],"c":lighting[b],"uv":texcoords[b]},
			{"p":view_positions[d],"c":lighting[d],"uv":texcoords[d]}]
		if view_positions[a].z>=-camera.near or view_positions[b].z>=-camera.near or view_positions[d].z>=-camera.near:
			polygon=clip_near(polygon)
		for j in range(1,polygon.size()-1):
			submit_triangle(polygon[0],polygon[j],polygon[j+1],entry.texture)

func bake_light(p: Vector3,n: Vector3,tint: Color,emission: Color) -> Vector3:
	var light := Vector3(.19,.22,.24)+Vector3(.09,.10,.11)*maxf(n.y,0)
	for i in LAMPS.size():
		var delta: Vector3=LAMPS[i]-p
		var distance := delta.length()
		var falloff := maxf(1-distance/8.0,0)
		var color: Vector3=LAMP_COLORS[i]
		if i==4 and powered:
			color=Vector3(.45,.9,.63)
		if falloff>0:
			light+=color*maxf(n.dot(delta/maxf(distance,.001)),0)*falloff*falloff
	return Vector3(tint.r,tint.g,tint.b)*light+Vector3(emission.r,emission.g,emission.b)

func shade(p: Vector3,n: Vector3,depth: float,tint: Color,base: Vector3) -> Color:
	var rgb := base
	if torch_on:
		var delta := p-torch_pos
		var distance := delta.length()
		var cone := smoothstep(.78,.94,delta.normalized().dot(torch_dir))
		var attenuation := maxf(1-distance/16,0)
		rgb+=Vector3(tint.r,tint.g,tint.b)*Vector3(1,.93,.77)*cone*attenuation*maxf(n.dot(-delta.normalized()),.12)*2
	var fog := clampf((depth-fog_start)/maxf(fog_end-fog_start,.001),0,.88)
	rgb=rgb.lerp(Vector3(.027,.044,.046),fog)
	rgb=(rgb*128).floor().clamp(Vector3.ZERO,Vector3.ONE*255)/128.0
	return Color(rgb.x,rgb.y,rgb.z,1)

func clip_near(polygon: Array) -> Array:
	var clipped: Array=[]
	var previous: Dictionary=polygon[-1]
	for current: Dictionary in polygon:
		var inside: bool=current.p.z < -camera.near
		var previous_inside: bool=previous.p.z < -camera.near
		if inside!=previous_inside:
			var ratio: float=(-camera.near-previous.p.z)/(current.p.z-previous.p.z)
			clipped.append({"p":previous.p.lerp(current.p,ratio),"c":previous.c.lerp(current.c,ratio),"uv":previous.uv.lerp(current.uv,ratio)})
		if inside:
			clipped.append(current)
		previous=current
	return clipped

func submit_triangle(a: Dictionary,b: Dictionary,c: Dictionary,texture: Texture2D) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray([a.c,b.c,c.c])
	var texcoords := PackedVector2Array([a.uv,b.uv,c.uv])
	var average_z := 0.0
	for vertex: Dictionary in [a,b,c]:
		var p: Vector3=vertex.p
		var screen := Vector2(160+p.x*focal/-p.z,120-p.y*focal/-p.z)
		if game.materials.snap_enabled:
			screen=screen.floor()
		points.append(screen)
		average_z-=p.z/3
	var cross := (points[1]-points[0]).cross(points[2]-points[0])
	if cross<=0:
		return
	var rect := Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2])
	if not rect.intersects(Rect2(0,0,WIDTH,HEIGHT)):
		return
	primitives.append({"points":points,"colors":colors,"uvs":texcoords,"texture":texture,
		"bucket":clampi(int(average_z/minf(draw_distance,camera.far)*(ordering_table_size-1)),0,ordering_table_size-1),"order":primitives.size()})

func _draw() -> void:
	var start_us := Time.get_ticks_usec()
	draw_rect(Rect2(0,0,WIDTH,HEIGHT),Color(1.0/31,1.0/31,1.0/31))
	for primitive in primitives:
		if primitive.has("indices"):
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),primitive.indices,primitive.points,primitive.colors,primitive.uvs,
				PackedInt32Array(),PackedFloat32Array(),primitive.texture.get_rid())
		else:
			draw_polygon(primitive.points,primitive.colors,primitive.uvs,primitive.texture)
	for effect in effects:
		if Time.get_ticks_msec()>effect.until:
			continue
		var pos: Vector3=inverse_camera*effect.position
		if pos.z>=-NEAR:
			continue
		var p := Vector2(160+pos.x*focal/-pos.z,120-pos.y*focal/-pos.z).floor()
		var radius: float=effect.radius
		draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,0),p+Vector2(0,-radius),p+Vector2(radius,0),p+Vector2(0,radius)]),effect.color)
	last_draw_us=Time.get_ticks_usec()-start_us

func add_shot(muzzle: Vector3,impact: Vector3,hit: bool) -> void:
	var time := Time.get_ticks_msec()
	effects=effects.filter(func(effect: Dictionary): return effect.until>time)
	effects.append({"position":muzzle,"radius":3.0,"color":Color(1,.75,.3),"until":time+70})
	if hit:
		effects.append({"position":impact,"radius":1.0,"color":Color(.7,.62,.44),"until":time+130})
