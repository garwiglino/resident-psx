extends CanvasLayer
## Small 2D selection mask over the existing PSX projection. No scene/atlas
## rebuild, 3D post effect, or native-library change is needed for hovering.
const Drawer=preload("res://scripts/inventory/placement_outline_draw.gd")
const Cursor=preload("res://scripts/inventory/placement_inspection_cursor.gd")
var controller: Node
var buffer: SubViewport
var drawer: Node2D
var canvas: Control
var cursor: Control
var caption: Label
var overlay: TextureRect
var selected: Node3D
var _entries: Array[Dictionary]=[]
var _entry_count := -1
func _ready() -> void:
	layer=27;process_priority=110
	buffer=SubViewport.new();buffer.size=Vector2i(320,240);buffer.transparent_bg=true;buffer.disable_3d=true;buffer.gui_disable_input=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(buffer)
	drawer=Drawer.new();drawer.material=ShaderMaterial.new();drawer.material.shader=preload("res://shaders/placement_mask.gdshader");buffer.add_child(drawer)
	canvas=Control.new();canvas.size=Vector2(320,240);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	overlay=TextureRect.new();overlay.size=Vector2(320,240);overlay.texture=buffer.get_texture();overlay.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.material=ShaderMaterial.new();overlay.material.shader=preload("res://shaders/placement_outline.gdshader");canvas.add_child(overlay)
	caption=Label.new();caption.position=Vector2(8,216);caption.size=Vector2(304,18);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.theme=controller.game.hud.canvas.theme.duplicate();caption.theme.default_font=controller.game.dialogue.style.font;caption.theme.default_font_size=controller.game.dialogue.style.font_size;canvas.add_child(caption)
	cursor=Cursor.new();cursor.style=controller.game.cursor_style;cursor.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE;cursor.size=Vector2(320,240);canvas.add_child(cursor)
	canvas.hide();set_process(false)
func show_inspection(value: bool) -> void:
	canvas.visible=value;set_process(value)
	if not value:highlight(null)
func highlight(part: Node3D) -> void:
	if part!=selected:_entry_count=-1
	selected=part;overlay.visible=is_instance_valid(part)
	cursor.hovering=is_instance_valid(part)
	buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS if part else SubViewport.UPDATE_DISABLED
	caption.text=part.get_selection_label() if part else controller.inspection_caption()
	if part:overlay.material.set_shader_parameter("outline_color",part.outline_color)
func _process(_delta: float) -> void:
	cursor.at=controller.mouse_position;cursor.queue_redraw()
	if not is_instance_valid(selected):return
	var renderer=controller.game.psx_renderer;var camera: Camera3D=controller.camera
	var depth: Texture2D=renderer.native_geometry.get_depth_texture() if renderer.native_geometry and renderer.native_geometry.has_method("get_depth_texture") else null
	drawer.material.set_shader_parameter("depth_enabled",depth!=null)
	if depth:drawer.material.set_shader_parameter("world_depth",depth)
	drawer.triangles.clear()
	if _entry_count!=renderer.entries.size():
		_entry_count=renderer.entries.size();_entries.clear();var roots: Array[Node3D]=selected.highlight_roots()
		for entry in renderer.entries:
			if is_instance_valid(entry.node) and roots.any(func(root: Node3D):return root==entry.node or root.is_ancestor_of(entry.node)):_entries.append(entry)
	var inverse := camera.get_camera_transform().affine_inverse();var rotation := inverse.basis
	for col in 3:rotation[col]=(rotation[col]*4096).round()/4096
	var ortho := camera.projection==Camera3D.PROJECTION_ORTHOGONAL
	var focal := 240.0/camera.size if ortho else 120.0/tan(deg_to_rad(camera.fov)*.5)
	for entry in _entries:
		var mesh: MeshInstance3D=entry.node
		if not is_instance_valid(mesh) or not mesh.is_visible_in_tree():continue
		var vertices: PackedVector3Array=entry.vertices;var posed := PackedVector3Array();posed.resize(vertices.size())
		var transforms: Array[Transform3D]=[]
		if is_instance_valid(entry.skeleton):
			for bind in entry.binds.size():transforms.append(entry.skeleton.global_transform*entry.skeleton.get_bone_global_pose(entry.bind_indices[bind])*entry.binds[bind])
		for index in vertices.size():
			var world := mesh.global_transform*vertices[index]
			if not transforms.is_empty():
				world=Vector3.ZERO;var stride: int=entry.bones.size()/vertices.size()
				for slot in stride:
					var bone: int=entry.bones[index*stride+slot];var weight: float=entry.weights[index*stride+slot]
					if weight>0 and bone<transforms.size():world+=(transforms[bone]*vertices[index])*weight
			world=(world*1024).round()/1024;posed[index]=(rotation*(world-camera.global_position)*1024).floor()/1024
		var indices: PackedInt32Array=entry.indices
		for face in range(0,indices.size(),3):
			var polygon: Array[Dictionary]=[]
			for corner in 3:
				var index: int=indices[face+corner];var uv: Vector2=entry.uvs[index] if entry.uvs!=null and entry.uvs.size()>index else Vector2.ZERO
				polygon.append({"point":posed[index],"uv":uv})
			polygon=_clip(polygon,camera.near)
			for fan in range(1,polygon.size()-1):_triangle([polygon[0],polygon[fan],polygon[fan+1]],focal,ortho,renderer.vertex_snapping,entry.texture)
	drawer.queue_redraw()
func _clip(input: Array[Dictionary],near: float) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for index in input.size():
		var a: Dictionary=input[index];var b: Dictionary=input[(index+1)%input.size()]
		var inside: bool=a.point.z<=-near
		if inside:result.append(a)
		if inside!=(b.point.z<=-near):
			var t: float=(-near-a.point.z)/(b.point.z-a.point.z)
			result.append({"point":a.point.lerp(b.point,t),"uv":a.uv.lerp(b.uv,t)})
	return result
func _triangle(vertices: Array,focal: float,ortho: bool,snap: bool,texture: Texture2D) -> void:
	var points := PackedVector2Array();var colors := PackedColorArray();var uvs := PackedVector2Array()
	for vertex in vertices:
		var point: Vector3=vertex.point;var divisor := 1.0 if ortho else -point.z
		var pixel := Vector2(160+point.x*focal/divisor,120-point.y*focal/divisor)
		points.append(pixel.floor() if snap else pixel);colors.append(Color(point.z if ortho else 1.0/-point.z,0,0,1));uvs.append(vertex.uv)
	if (points[1]-points[0]).cross(points[2]-points[0])<=0:return
	drawer.triangles.append({"points":points,"colors":colors,"uvs":uvs,"texture":texture})
