extends CanvasLayer
const Audio=preload("res://scripts/audio/psx_audio_routing.gd")
const Visuals=preload("res://scripts/inventory/item_visuals.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const MenuTheme=preload("res://scripts/ui/menu_theme.gd")
signal sound_started(kind: StringName,player: AudioStreamPlayer)
signal discovery_opened(item: Resource)
signal discovery_closed(item: Resource)
@export var enabled := true
@export_group("Sons de ramassage")
@export var pickup_sound: AudioStream=preload("res://assets/audio/ui/item_pickup.wav")
@export var essential_sound: AudioStream=preload("res://assets/audio/ui/essential_item_found.wav")
@export var secret_card_sound: AudioStream=preload("res://assets/audio/ui/secret_card_found.wav")
@export_range(-40,0,.5,"suffix:dB") var pickup_volume_db := -12.0
@export_range(-40,0,.5,"suffix:dB") var discovery_volume_db := -10.0
@export_group("Decouverte")
@export_range(1,90,1,"suffix:deg/s") var rotation_speed := 40.0
@export var preview_tilt_degrees := Vector3(-10,0,-4)
@export_range(.1,.5,.01,"suffix:s") var confirm_delay := .18
@export_range(.2,1,.05) var background_brightness := .65
var game: Node
var opened := false
var current_item: Resource
var canvas: Control
var modal: Panel
var backdrop: TextureRect
var item_name: Label
var confirm_button: Button
var buffer: SubViewport
var preview_renderer: Node
var preview_root: Node3D
var rotator: Node3D
var _model: Node3D
var _sound_jobs: Array[Dictionary]=[]
var _queue: Array[Resource]=[]
var _old_pause := false
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _old_hud_visible := true
var _old_dialogue_suspended := false
var _ready_to_confirm := false
var _confirm_elapsed := 0.0
var _confirm_held := true
var _generation := 0

func _ready() -> void:
	layer=50; process_mode=Node.PROCESS_MODE_ALWAYS
	if not is_instance_valid(game): set_process(false); return
	var inventory := get_node("/root/InventoryState")
	inventory.item_acquired.connect(_item_acquired); inventory.card_acquired.connect(_card_acquired)
	get_node("/root/WorldEvents").run_reset.connect(cancel)
	canvas=Control.new(); canvas.size=Vector2(320,240); canvas.mouse_filter=Control.MOUSE_FILTER_STOP; canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; add_child(canvas)
	canvas.theme=game.hud.canvas.theme
	backdrop=TextureRect.new(); backdrop.size=canvas.size; backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE; canvas.add_child(backdrop)
	modal=Panel.new(); modal.position=Vector2(88,50); modal.size=Vector2(144,140); canvas.add_child(modal)
	_label("TROUVE",Rect2(8,6,128,18)).theme_type_variation=&"MenuHeading"
	var frame := Panel.new(); frame.position=Vector2(20,28); frame.size=Vector2(104,58)
	frame.theme_type_variation=&"MenuInset"; modal.add_child(frame)
	var picture := TextureRect.new(); picture.position=Vector2(16,2); picture.size=Vector2(72,54); picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter=Control.MOUSE_FILTER_IGNORE; frame.add_child(picture)
	item_name=_label("",Rect2(8,90,128,26))
	item_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item_name.max_lines_visible=2
	item_name.theme_type_variation=&"MenuCaption"
	confirm_button=Button.new(); MenuTheme.fit_button(confirm_button); confirm_button.text="OK"; confirm_button.position=Vector2(50,118); confirm_button.size=Vector2(44,18); confirm_button.pressed.connect(confirm); modal.add_child(confirm_button)
	confirm_button.theme_type_variation=&"MenuCompact"
	confirm_button.size=Vector2(44,18)
	buffer=SubViewport.new(); buffer.name="ApercuObjetPSX"; buffer.size=Vector2i(320,240); buffer.own_world_3d=true; buffer.world_2d=World2D.new(); buffer.disable_3d=true; buffer.transparent_bg=true; buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED; add_child(buffer)
	preview_root=Node3D.new(); buffer.add_child(preview_root)
	rotator=Node3D.new(); rotator.add_to_group("psx_dynamic_geometry"); rotator.add_to_group("psx_no_light_occluder"); preview_root.add_child(rotator)
	var camera := Camera3D.new(); buffer.add_child(camera); camera.position=Vector3(0,.12,10); camera.look_at(Vector3.ZERO); camera.fov=35; camera.near=.03
	preview_renderer=load("res://scripts/psx_renderer.gd").new(); buffer.add_child(preview_renderer)
	for property in ["vertex_snapping","affine_texture_strength","dithering","ordering_table_size"]: preview_renderer.set(property,game.psx_renderer.get(property))
	preview_renderer.ambient_light_color=Color(.5,.5,.5); preview_renderer.fog_enabled=false; preview_renderer.draw_background=false
	preview_renderer.setup_editor(preview_root,camera)
	# Crop the native buffer at 1:1 so the small preview retains PSX pixel snapping.
	var crop := AtlasTexture.new(); crop.atlas=buffer.get_texture(); crop.region=Rect2(124,93,72,54); picture.texture=crop
	canvas.hide(); set_process(true)

func _label(text: String,rect: Rect2) -> Label:
	var label := Label.new(); label.text=Text.plain(text); label.position=rect.position; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.clip_text=true;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	modal.add_child(label);label.size=rect.size;return label
func _belongs_to_game() -> bool:
	return enabled and is_instance_valid(game) and get_node("/root/InventoryState").game==game and game.state not in ["dead","won"]
func _item_acquired(item: Resource,_quantity: int,discovery: bool) -> void:
	if not _belongs_to_game(): return
	var essential: bool=discovery and item.is_essential()
	_play_pickup(&"essential_item_found" if essential else &"",essential_sound if essential else null)
	if essential:
		_queue.append(item); call_deferred("_try_open")
func _card_acquired(_card: Resource,_fresh: bool) -> void:
	if not _belongs_to_game(): return
	_play_pickup(&"secret_card_found",secret_card_sound)
func _play_pickup(variant_kind: StringName,variant: AudioStream) -> void:
	var player := AudioStreamPlayer.new(); player.name="SonRamassage"; player.process_mode=Node.PROCESS_MODE_ALWAYS; add_child(player); Audio.set_reverb_enabled(player,false)
	Audio.set_category(player,&"UI")
	var job := {"player":player,"kind":&"item_pickup","stream":pickup_sound,"variant_kind":variant_kind,"variant":variant,"stage":0,"elapsed":0.0}
	_sound_jobs.append(job); player.finished.connect(_finish_sound.bind(job))
	if pickup_sound: _start_sound(job,&"item_pickup",pickup_sound)
	else: _finish_sound(job)
func _start_sound(job: Dictionary,kind: StringName,stream: AudioStream) -> void:
	job.kind=kind; job.stream=stream; job.elapsed=0.0; job.player.stream=stream
	_balance_sounds(); Audio.play(job.player); sound_started.emit(kind,job.player)
func _balance_sounds() -> void:
	var ordinary := 0; var discovery := 0
	for job in _sound_jobs:
		if job.kind==&"item_pickup": ordinary+=1
		else: discovery+=1
	for job in _sound_jobs:
		var common: bool=job.kind==&"item_pickup"; var count := ordinary if common else discovery
		job.player.volume_db=(pickup_volume_db if common else discovery_volume_db)-linear_to_db(maxi(count,1))
		Audio.sync_player(job.player)
func _finish_sound(job: Dictionary) -> void:
	if not _sound_jobs.has(job): return
	if job.stage==0 and job.variant:
		job.stage=1; _start_sound(job,job.variant_kind,job.variant)
	else:
		_sound_jobs.erase(job); Audio.stop(job.player); job.player.queue_free(); _balance_sounds()
func is_active() -> bool: return opened or not _queue.is_empty()

func _try_open() -> void:
	if opened or _queue.is_empty() or not _belongs_to_game() or game.state=="pause": return
	if is_instance_valid(game.inventory_menu) and game.inventory_menu.opened: return
	_generation+=1; var generation := _generation
	_old_pause=get_tree().paused; _old_mouse=Input.mouse_mode; _old_hud_visible=game.hud.canvas.visible
	_old_dialogue_suspended=game.dialogue.suspended
	opened=true; _ready_to_confirm=false; _confirm_elapsed=0; _confirm_held=true; confirm_button.disabled=true
	game._acquire_controls(&"item_discovery"); game.dialogue.set_suspended(true)
	game.hud.canvas.hide(); get_tree().paused=true; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.psx_renderer._process(0)
	_present(_queue.pop_front())
	# Capture the last PSX frame after hiding the HUD and dialogue, then freeze it.
	await RenderingServer.frame_post_draw
	if not opened or generation!=_generation or not is_inside_tree(): return
	var image := get_viewport().get_texture().get_image(); image.adjust_bcs(1.0,1.0,0.0)
	backdrop.texture=ImageTexture.create_from_image(image); backdrop.modulate=Color(background_brightness,background_brightness,background_brightness)
	canvas.show(); _ready_to_confirm=true; discovery_opened.emit(current_item)
func _present(item: Resource) -> void:
	current_item=item; item_name.text=Text.plain(item.display_name)
	if is_instance_valid(_model): _model.get_parent().remove_child(_model); _model.free()
	_model=Visuals.inspection(item); preview_root.rotation_degrees=preview_tilt_degrees; rotator.rotation=Vector3(0,.35,0); rotator.add_child(_model)
	var bounds := Visuals.bounds(_model); var longest := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)); var scale := 1.0/maxf(longest,.01)
	_model.scale=Vector3.ONE*scale; _model.position=-bounds.get_center()*scale
	preview_renderer.rebuild_editor_geometry()
	# Private preview lights never join the level's PSXLight3D group.
	preview_renderer.native_geometry.set_world_lights([{"position":Vector3(-1.5,2,3),"color":Vector3(1,.95,.84),"energy":2.0,"range":7.0,"type":0}],Vector3(.5,.5,.5))
	buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS; preview_renderer.render_editor()
func _process(delta: float) -> void:
	for job in _sound_jobs.duplicate():
		job.elapsed+=delta
		if job.elapsed>job.stream.get_length()+.2:
			Audio.stop(job.player); _finish_sound(job)
	if not opened:
		if not _queue.is_empty(): _try_open()
		return
	_confirm_elapsed+=delta
	var held := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not held: _confirm_held=false
	confirm_button.disabled=not _ready_to_confirm or _confirm_elapsed<confirm_delay or _confirm_held
	rotator.rotation.y+=deg_to_rad(rotation_speed)*delta; preview_renderer.render_editor()
func _input(event: InputEvent) -> void:
	if not opened: return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		if not (event is InputEventKey and event.echo): confirm()
		get_viewport().set_input_as_handled()
func confirm() -> void:
	if not opened or not _ready_to_confirm or _confirm_elapsed<confirm_delay or _confirm_held: return
	var previous := current_item
	if not _queue.is_empty():
		_present(_queue.pop_front()); _confirm_elapsed=0; _confirm_held=true; confirm_button.disabled=true
		discovery_closed.emit(previous); discovery_opened.emit(current_item)
	else:
		_close(); discovery_closed.emit(previous)
func _close() -> void:
	_generation+=1; opened=false; _ready_to_confirm=false; canvas.hide(); buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED; current_item=null
	get_tree().paused=_old_pause; Input.mouse_mode=_old_mouse
	if is_instance_valid(game) and not game.is_queued_for_deletion():
		game.hud.canvas.visible=_old_hud_visible; game._release_controls(&"item_discovery"); game.dialogue.set_suspended(_old_dialogue_suspended)
func cancel() -> void:
	_queue.clear()
	for job in _sound_jobs: Audio.stop(job.player); job.player.queue_free()
	_sound_jobs.clear()
	if opened: _close()
func _exit_tree() -> void:
	cancel()
