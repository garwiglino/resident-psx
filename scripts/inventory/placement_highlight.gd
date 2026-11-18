extends CanvasLayer
## Inspection HUD; hover changes the real PSX surface lighting, not a 2D outline.
const Cursor=preload("res://scripts/inventory/placement_inspection_cursor.gd")
var controller: Node
var canvas: Control
var cursor: Control
var caption: Label
var selected: Node3D
var _renderer: Node
var _geometry_revision := -1
func _ready() -> void:
	layer=27;process_priority=110;_renderer=controller.game.psx_renderer
	canvas=Control.new();canvas.size=Vector2(320,240);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	caption=Label.new();caption.position=Vector2(8,216);caption.size=Vector2(304,18);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.clip_text=true;caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.theme=controller.game.hud.canvas.theme
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",1)
	caption.add_theme_constant_override("shadow_offset_y",1)
	canvas.add_child(caption)
	cursor=Cursor.new();cursor.style=controller.game.cursor_style;cursor.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE;cursor.size=Vector2(320,240);canvas.add_child(cursor)
	canvas.hide();set_process(false)
func show_inspection(value: bool) -> void:
	canvas.visible=value;set_process(value)
	if not value:highlight(null)
func highlight(part: Node3D) -> void:
	if not is_instance_valid(part):part=null
	cursor.hovering=part!=null
	caption.text=part.get_selection_label() if part else controller.inspection_caption()
	if part==selected:return
	selected=part;_sync_highlight()
func _sync_highlight() -> void:
	if not is_instance_valid(_renderer):return
	_geometry_revision=_renderer.geometry_revision
	var meshes: Array=[]
	if is_instance_valid(selected):
		for branch in selected.highlight_roots():
			if branch is MeshInstance3D:meshes.append(branch)
			for mesh in branch.find_children("*","MeshInstance3D",true,false):meshes.append(mesh)
	_renderer.set_hover_unlit(meshes)
func _process(_delta: float) -> void:
	cursor.at=controller.mouse_position;cursor.queue_redraw()
	if selected and (not is_instance_valid(selected) or not selected.is_visible_in_tree()):highlight(null)
	elif is_instance_valid(_renderer) and _geometry_revision!=_renderer.geometry_revision:_sync_highlight()
func _exit_tree() -> void:
	if is_instance_valid(_renderer) and is_instance_valid(controller.game) and not controller.game.is_queued_for_deletion():_renderer.set_hover_unlit([])
