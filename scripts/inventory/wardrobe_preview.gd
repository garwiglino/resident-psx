extends TextureRect

const Renderer=preload("res://scripts/psx_renderer.gd")
const AnimationAssets=preload("res://scripts/animation_assets.gd")
const MODEL=preload("res://assets/character/cop_player.glb")
const FRAME_TIME := 1.0/30.0
const TURN_PER_PIXEL := TAU/180.0

var buffer: SubViewport
var outfit: CharacterClothing
var mixer: AnimationPlayer
var renderer: Node2D
var _elapsed := 0.0
var _model: Node3D
var _dragging := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape=Control.CURSOR_DRAG
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode=EXPAND_IGNORE_SIZE
	set_process(false)

func show_outfit(game: Node, clothing: CharacterClothing) -> void:
	if not buffer:_build(game,clothing)
	# Native pixels in the portrait, centered on the full-size PSX buffer.
	var crop := AtlasTexture.new()
	crop.atlas=buffer.get_texture()
	crop.region=Rect2((Vector2(buffer.size)-size)*.5,size)
	texture=crop
	sync_outfit(clothing)
	_elapsed=0
	set_process(true)

func suspend() -> void:
	set_process(false)
	_dragging=false
	if buffer:buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
	texture=null

func _exit_tree() -> void:
	suspend()

func game_cursor_shape() -> int:
	return Input.CURSOR_CAN_DROP if _dragging else Input.CURSOR_DRAG

func _gui_input(event: InputEvent) -> void:
	if not _model:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging=event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if (event.button_mask&MOUSE_BUTTON_MASK_LEFT)==0:
			_dragging=false
			return
		_model.rotation.y=fposmod(_model.rotation.y+event.relative.x*TURN_PER_PIXEL,TAU)
		accept_event()

func sync_outfit(clothing: CharacterClothing) -> void:
	if not outfit:return
	for slot in CharacterClothing.SLOTS:
		for item in clothing.items_for_slot(slot):
			if item not in outfit.available_items:outfit.add_available_item(item)
	outfit.restore_wardrobe(clothing.wardrobe_state())
	_render_frame()

func _build(game: Node, clothing: CharacterClothing) -> void:
	buffer=SubViewport.new()
	buffer.name="ApercuHitomiPSX"
	buffer.size=Vector2i(320,240)
	buffer.own_world_3d=true
	buffer.world_2d=World2D.new()
	buffer.transparent_bg=true
	buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(buffer)
	var stage := Node3D.new()
	buffer.add_child(stage)
	var model := MODEL.instantiate() as Node3D
	_model=model
	model.name="cop"
	model.add_to_group("psx_anime_character")
	stage.add_child(model)

	var live_face := game.player.get_node_or_null("Visage") as FaceExpressions
	var face := FaceExpressions.new()
	face.model_path=NodePath("../cop")
	if live_face:
		face.enabled=live_face.enabled
		face.set_expression(live_face.top_frame,live_face.bottom_frame)
	stage.add_child(face)
	var live_appearance := game.player.get_node_or_null("Apparence") as CharacterAppearance
	var appearance := CharacterAppearance.new()
	appearance.model_path=NodePath("../cop")
	if live_appearance:appearance.texture_corps=live_appearance.texture_corps
	stage.add_child(appearance)

	outfit=CharacterClothing.new()
	outfit.model_path=NodePath("../cop")
	outfit.available_items=[]
	for slot in CharacterClothing.SLOTS:
		outfit.available_items.append_array(clothing.items_for_slot(slot))
	outfit.outerwear=null
	stage.add_child(outfit)
	outfit.restore_wardrobe(clothing.wardrobe_state())

	mixer=AnimationPlayer.new()
	mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.add_child(mixer)
	var skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	var idle: Animation=load("res://assets/character/poses/cloth_idle.res").duplicate()
	for track in range(idle.get_track_count()-1,-1,-1):
		var bone := idle.track_get_path(track).get_subname(0)
		if skeleton.find_bone(bone)<0:idle.remove_track(track)
	AnimationAssets.complete_upper_arm_segments(idle,skeleton)
	var library := AnimationLibrary.new()
	library.add_animation(&"cloth_idle",idle)
	mixer.add_animation_library(&"",library)
	mixer.play(&"cloth_idle")
	mixer.advance(0)

	var camera := Camera3D.new()
	buffer.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.69
	camera.near=.03
	camera.position=Vector3(.88,1.0,4.0)
	camera.look_at(Vector3(0,.83,0))
	var key := PSXLight3D.new()
	stage.add_child(key)
	key.position=Vector3(-1.45,2.4,2.6)
	key.light_range=6
	key.light_energy=1.45
	key.light_color=Color(1,.96,.9)

	renderer=Renderer.new()
	renderer.name="PSXRenderer"
	stage.add_child(renderer)
	for property in ["vertex_snapping","affine_texture_strength","dithering","ordering_table_size","anime_style"]:
		renderer.set(property,game.psx_renderer.get(property))
	renderer.ambient_light_color=Color(.43,.45,.5)
	renderer.fog_enabled=false
	renderer.draw_background=false
	renderer.setup_editor(stage,camera)

func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed<FRAME_TIME:return
	var interval := floorf(_elapsed/FRAME_TIME)*FRAME_TIME
	mixer.advance(interval)
	_elapsed-=interval
	_render_frame()

func _render_frame() -> void:
	renderer.render_editor()
	buffer.render_target_update_mode=SubViewport.UPDATE_ONCE
