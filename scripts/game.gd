extends Node3D
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")

const Player = preload("res://scripts/player.gd")
const World = preload("res://scripts/world.gd")
const Enemy = preload("res://scripts/enemy.gd")
const HUD = preload("res://scripts/hud.gd")
const PSX = preload("res://scripts/psx_materials.gd")
const Rasterizer = preload("res://scripts/psx_renderer.gd")
const DialogueScene=preload("res://scenes/dialogue/dialogue_system.tscn")
const CinematicScene=preload("res://scenes/cinematics/cinematic_system.tscn")
const InventoryMenuScene=preload("res://scenes/inventory/inventory_menu.tscn")
const PickupFeedbackScene=preload("res://scenes/inventory/pickup_feedback.tscn")
const PlacementController=preload("res://scripts/inventory/placement_controller.gd")
const CursorStyle=preload("res://scripts/ui/cursor_style.gd")
const GameCursor=preload("res://scripts/ui/game_cursor.gd")
## Only the original main scene enables the prototype's authored couloir items.
@export var legacy_couloir_content := false
@export_group("Interactions")
@export_range(.5,4.0,.1,"suffix:m") var interaction_distance := 1.8
@export_range(0,10,1) var starting_medkits := 1
@export_group("Confirmation des impacts")
@export var hit_marker_sound: AudioStream=preload("res://assets/audio/weapons/hit_marker.wav")
@export_range(-60.0,0.0,.5,"suffix:dB") var hit_marker_volume_db := -22.0
@export_range(.05,.3,.01,"suffix:s") var hit_marker_duration := .12
@export_group("Curseurs et visee")
@export var cursor_style: CursorStyle=preload("res://assets/ui/cursors/default_cursors.tres")
var materials = PSX
var player: CharacterBody3D
var level: Node3D
var hud: CanvasLayer
var enemies: Array[CharacterBody3D] = []
var interactables: Array[Dictionary] = []
var nearest: Dictionary = {}
var has_fuse := false
var power := false
var medkits := 1
var state := "intro"
var elapsed := 0.0
var psx_renderer: Node2D
var level_audio: Node
var hit_audio: AudioStreamPlayer
var dialogue: Node
var exploration_dialogue: Node
var cinematics: Node
var inventory_menu: CanvasLayer
var pickup_feedback: CanvasLayer
var item_placement: Node
var game_cursor: CanvasLayer
var _control_owners: Dictionary={}
var _controls_before_modal := false
var _pause_player_enabled := true

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	PSX.initialize()
	setup_input()
	level=get_node_or_null("Map")
	if not level:level=get_node_or_null("Annexe09")
	if level:
		pass
	elif ResourceLoader.exists("res://scenes/annexe.tscn"):
		level=load("res://scenes/annexe.tscn").instantiate()
		add_child(level)
	else:
		level=World.new()
		add_child(level)
		level.build()
	var session := get_node_or_null("/root/LevelRuntime")
	if session: session.configure_game(self)
	if level.process_mode==Node.PROCESS_MODE_INHERIT: level.process_mode=Node.PROCESS_MODE_PAUSABLE
	player=get_node("Player")
	var map_spawn: Marker3D=level.get_node_or_null("Gameplay/PlayerSpawn")
	if map_spawn:
		player.global_position=map_spawn.global_position
		player.global_rotation.y=map_spawn.global_rotation.y
		player.reset_camera_follow()
	player.process_mode=Node.PROCESS_MODE_PAUSABLE
	medkits=starting_medkits
	get_node("/root/InventoryState").bind_game(self)
	has_fuse=legacy_couloir_content and WorldEvents.interaction_used(&"couloir.fuse");power=legacy_couloir_content and WorldEvents.flag(&"couloir.power")
	WorldEvents.state_changed.connect(_world_state_changed);WorldEvents.run_reset.connect(_world_flags_restored)
	player.fired.connect(shoot_ray)
	player.hurt.connect(func(): hud.hurt_time=.6)
	hud=HUD.new()
	hud.game=self
	add_child(hud)
	hud.start_requested.connect(start_game)
	hud.restart_requested.connect(restart)
	dialogue=get_node_or_null("Dialogue")
	if not dialogue:dialogue=DialogueScene.instantiate();add_child(dialogue)
	dialogue.session_started.connect(_dialogue_started);dialogue.session_finished.connect(_dialogue_finished)
	dialogue.control_lock_changed.connect(_dialogue_controls_changed)
	dialogue.sequence_completed.connect(_world_dialogue_completed)
	exploration_dialogue=get_node_or_null("ExplorationDialogue")
	if not exploration_dialogue:
		exploration_dialogue=DialogueScene.instantiate();exploration_dialogue.name="ExplorationDialogue"
		exploration_dialogue.exploration_channel=true;exploration_dialogue.style=dialogue.style;add_child(exploration_dialogue)
	exploration_dialogue.sequence_completed.connect(_world_dialogue_completed)
	hud.dialogue=dialogue
	hit_audio=AudioStreamPlayer.new();hit_audio.name="HitMarker"
	AudioRouting.set_category(hit_audio,&"UI");AudioRouting.set_reverb_enabled(hit_audio,false)
	hit_audio.process_mode=Node.PROCESS_MODE_PAUSABLE
	hit_audio.stream=get_node("/root/PSXAudio").prepare(hit_marker_sound)
	hit_audio.volume_db=hit_marker_volume_db;add_child(hit_audio)
	for enemy in get_tree().get_nodes_in_group("world_enemies"):_register_enemy(enemy)
	get_tree().node_added.connect(_world_node_added)
	if legacy_couloir_content: _add_legacy_content()
	psx_renderer=get_node("PSXRenderer")
	psx_renderer.setup(self,player.camera)
	cinematics=get_node_or_null("Cinematics")
	if not cinematics:cinematics=CinematicScene.instantiate();add_child(cinematics)
	cinematics.setup(self);cinematics.started.connect(_cinematic_started);cinematics.finished.connect(_cinematic_finished)
	cinematics.event_reached.connect(func(_sequence: Node3D,id: StringName):WorldEvents.raise_event(id))
	hud.cinematics=cinematics
	inventory_menu=InventoryMenuScene.instantiate(); inventory_menu.game=self; add_child(inventory_menu)
	pickup_feedback=PickupFeedbackScene.instantiate(); pickup_feedback.game=self; add_child(pickup_feedback)
	item_placement=PlacementController.new();item_placement.name="PlacementObjet";item_placement.game=self;add_child(item_placement)
	game_cursor=GameCursor.new();game_cursor.name="CurseurJeu";game_cursor.game=self;add_child(game_cursor)
	player.weapon_added.connect(psx_renderer.register_weapon_geometry)
	for manager in get_tree().get_nodes_in_group("level_audio_managers"):
		if level.is_ancestor_of(manager):level_audio=manager;break
	if is_instance_valid(level_audio) and level_audio.autoplay: level_audio.start_level()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	start_game()
	if "--play" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		start_game()
	if "--capture" in OS.get_cmdline_user_args():
		capture.call_deferred()

func setup_input() -> void:
	var actions := {
		"forward":[KEY_W,KEY_Z,KEY_UP],"back":[KEY_S,KEY_DOWN],
		"left":[KEY_A,KEY_Q,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],
		"sprint":[KEY_SHIFT],"reload":[KEY_R],"interact":[KEY_E],"torch":[KEY_F],
		"heal":[KEY_H],"shoulder":[KEY_TAB],"pause":[KEY_ESCAPE],
		"inventory":[KEY_I],"minimap":[KEY_M],
		"weapon_next":[KEY_BRACKETRIGHT],"weapon_previous":[KEY_BRACKETLEFT],
		"weapon_slot_1":[KEY_1],"weapon_slot_2":[KEY_2],"weapon_slot_3":[KEY_3],"weapon_slot_4":[KEY_4],
		}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in actions[action]:
			var event := InputEventKey.new()
			event.keycode=code
			InputMap.action_add_event(action,event)
	for action in ["aim","fire"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_RIGHT if action=="aim" else MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action,event)
	for action in ["weapon_next","weapon_previous"]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN if action=="weapon_next" else MOUSE_BUTTON_WHEEL_UP
		InputMap.action_add_event(action,wheel)

func _add_legacy_content() -> void:
	add_item("fuse","FUSIBLE 16 A",_map_position("Fuse",Vector3(-4.5,.99,-12)),Color(.76,.41,.12),&"magnum",12,&"couloir.fuse")
	add_item("ammo","MUNITIONS / 12",_map_position("AmmoA",Vector3(4.25,.99,-4)),Color(.28,.43,.30),&"magnum",12,&"couloir.ammo_a")
	add_item("medkit","TROUSSE DE SOIN",_map_position("Medkit",Vector3(-4.2,1.26,4)),Color(.72,.73,.63),&"magnum",12,&"couloir.medkit")
	add_item("ammo","MUNITIONS / 12",_map_position("AmmoB",Vector3(-3.6,.25,-26.8)),Color(.28,.43,.30),&"magnum",12,&"couloir.ammo_b")
	interactables.append({"kind":"power","label":"INSÉRER LE FUSIBLE","pos":_map_position("Power",Vector3(5.3,1,-20)),"node":null})
	interactables.append({"kind":"exit","label":"OUVRIR L'ISSUE DE SECOURS","pos":_map_position("Exit",Vector3(0,1,-29)),"node":null})

func _map_position(marker_name: String,fallback: Vector3) -> Vector3:
	var marker: Marker3D=level.get_node_or_null("Gameplay/"+marker_name)
	return to_local(marker.global_position) if marker else fallback

func _world_node_added(node: Node) -> void:
	if node is WorldEnemy3D:call_deferred("_register_enemy",node)
func _register_enemy(enemy: Node) -> void:
	if not is_instance_valid(enemy) or not enemy is WorldEnemy3D or not is_ancestor_of(enemy) or enemy in enemies:return
	enemy.target=player;enemies.append(enemy)
	enemy.tree_exiting.connect(func():enemies.erase(enemy))
	if is_instance_valid(psx_renderer):psx_renderer.register_dynamic_geometry(enemy)
func _world_dialogue_completed(sequence: Resource,cancelled: bool) -> void:
	if not sequence:return
	WorldEvents.raise_event(StringName("dialogue.%s.%s" % [sequence.id,"cancelled" if cancelled else "completed"]))

func _world_state_changed(key: StringName,_value: Variant) -> void:
	if key in [&"interaction.couloir.fuse.used",&"flag.couloir.power",&"world.restored"]:_world_flags_restored()
func _world_flags_restored() -> void:
	has_fuse=legacy_couloir_content and WorldEvents.interaction_used(&"couloir.fuse");power=legacy_couloir_content and WorldEvents.flag(&"couloir.power")

func start_game() -> void:
	var resuming := state=="pause"
	state="playing";_sync_modal_state()
	player.enabled=(_pause_player_enabled if resuming else true) and player.health>0
	hud.hide_menu()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	get_tree().paused=false
	if is_instance_valid(dialogue):dialogue.set_suspended(false)
	if is_instance_valid(item_placement):item_placement.set_suspended(false)
	_sync_exploration_dialogue()

func pause_game() -> void:
	if is_instance_valid(pickup_feedback) and pickup_feedback.opened: return
	if is_instance_valid(inventory_menu) and inventory_menu.opened: inventory_menu.close()
	_pause_player_enabled=player.enabled
	state="pause"
	player.enabled=false
	hud.show_menu("pause")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_tree().paused=true
	if is_instance_valid(dialogue):dialogue.set_suspended(true)
	if is_instance_valid(exploration_dialogue):exploration_dialogue.set_suspended(true)
	if is_instance_valid(item_placement):item_placement.set_suspended(true)

func play_dialogue(sequence: Resource,enqueue_if_busy := true) -> bool:
	if state not in ["playing","dialogue","cinematic"] or not is_instance_valid(dialogue):return false
	return dialogue.play(sequence,enqueue_if_busy)

func _dialogue_started() -> void:
	if state not in ["playing","cinematic"]:dialogue.cancel();return
	_sync_exploration_dialogue()

func _dialogue_controls_changed(locked: bool) -> void:
	if locked:_acquire_controls(&"dialogue")
	else:_release_controls(&"dialogue")

func _dialogue_finished() -> void:
	_release_controls(&"dialogue")
	_sync_exploration_dialogue()

func _sync_exploration_dialogue() -> void:
	if not is_instance_valid(exploration_dialogue):return
	var hidden: bool=state not in ["playing","dialogue","cinematic"] or get_tree().paused or not _control_owners.is_empty() or (is_instance_valid(dialogue) and dialogue.is_active())
	exploration_dialogue.set_suspended(hidden)

func play_cinematic(sequence: Node3D) -> bool:
	return is_instance_valid(cinematics) and cinematics.play(sequence)

func _cinematic_started(sequence: Node3D) -> void:
	_acquire_controls(&"cinematic");WorldEvents.raise_event(StringName("cinematic.%s.started" % sequence.id))
func _cinematic_finished(sequence: Node3D,reason: StringName) -> void:
	_release_controls(&"cinematic")
	if is_instance_valid(sequence):WorldEvents.raise_event(StringName("cinematic.%s.%s" % [sequence.id,reason]))

func _acquire_controls(owner: StringName) -> void:
	if _control_owners.is_empty():_controls_before_modal=player.controls_blocked
	_control_owners[owner]=true;player.controls_blocked=true;_sync_modal_state()
	hud.reticle.queue_redraw()

func _release_controls(owner: StringName) -> void:
	if not _control_owners.has(owner):return
	_control_owners.erase(owner)
	if is_instance_valid(player):
		player.controls_blocked=_controls_before_modal if _control_owners.is_empty() else true
		if _control_owners.is_empty():player.suppress_action_inputs_until_release()
	_sync_modal_state()

func _sync_modal_state() -> void:
	if state not in ["playing","dialogue","cinematic"]:return
	state="cinematic" if _control_owners.has(&"cinematic") or _control_owners.has(&"item_placement") else ("dialogue" if _control_owners.has(&"dialogue") else "playing")
	_sync_exploration_dialogue()

func restart() -> void:
	if is_instance_valid(item_placement):item_placement.cancel()
	if is_instance_valid(pickup_feedback): pickup_feedback.cancel()
	if is_instance_valid(inventory_menu) and inventory_menu.opened: inventory_menu.close()
	get_tree().paused=false
	WorldEvents.reset_run()
	get_tree().reload_current_scene()

func _input(event: InputEvent) -> void:
	if is_instance_valid(pickup_feedback) and pickup_feedback.opened: return
	if is_instance_valid(item_placement) and item_placement.handle_input(event):get_viewport().set_input_as_handled();return
	if is_instance_valid(inventory_menu):
		if event.is_action_pressed("inventory"):
			if event is InputEventKey and event.echo: return
			if inventory_menu.opened: inventory_menu.close()
			else: inventory_menu.open()
			get_viewport().set_input_as_handled(); return
		if inventory_menu.opened:
			if event.is_action_pressed("pause"): inventory_menu.back(); get_viewport().set_input_as_handled()
			return
	# This node also receives pause input while the rest of the game is suspended.
	if event.is_action_pressed("pause"):
		if state in ["playing","dialogue","cinematic"]:
			pause_game()
		elif state=="pause":
			start_game()
	if state!="playing":
		return
	if event.is_action_pressed("minimap") and hud.toggle_minimap():
		get_viewport().set_input_as_handled()
		return
	if player.action_input_blocked():return
	if event.is_action_pressed("interact"):
		interact()
	if event.is_action_pressed("heal"):
		if get_node("/root/InventoryState").quick_heal():
			AudioRouting.play(player.sounds.pickup)
			hud.toast("Soin utilisé / +50 santé")
		else:
			hud.toast("Aucun soin disponible" if medkits==0 else "Santé déjà au maximum")

func _process(delta: float) -> void:
	if is_instance_valid(pickup_feedback) and pickup_feedback.opened: return
	if is_instance_valid(inventory_menu) and inventory_menu.opened: return
	if state not in ["playing","dialogue","cinematic"]:
		return
	elapsed+=delta
	_update_level_audio()
	nearest={}
	var best := interaction_distance
	for item in interactables:
		var horizontal := Vector2(player.position.x-item.pos.x,player.position.z-item.pos.z).length()
		if horizontal<best and not item.get("taken",false):
			var from: Vector3 = player.position+Vector3.UP*1.1
			var ray := PhysicsRayQueryParameters3D.create(from,item.pos,1)
			var obstruction := get_world_3d().direct_space_state.intersect_ray(ray)
			if not obstruction.is_empty() and obstruction.position.distance_to(item.pos)>.5:
				continue
			best=horizontal
			nearest=item
		if item.node and is_instance_valid(item.node):
			item.node.rotation.y=sin(elapsed*.8)*.12
	for source in get_tree().get_nodes_in_group("world_interactions"):
		if not is_ancestor_of(source) or not source.can_interact():continue
		var point: Vector3=source.get_interaction_position()
		var horizontal := Vector2(player.global_position.x-point.x,player.global_position.z-point.z).length()
		if horizontal>=best:continue
		var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*1.1,point,1)
		var obstruction := get_world_3d().direct_space_state.intersect_ray(ray)
		if not obstruction.is_empty() and not source.is_ancestor_of(obstruction.collider) and obstruction.position.distance_to(point)>.5:continue
		best=horizontal;nearest={"kind":"world","node":source,"label":source.get_interaction_label(),"pos":to_local(point)}
	hud.prompt.text=HUD.plain_text("[ E ]  %s" % nearest.label) if not nearest.is_empty() else ""
	if player.health<=0:
		finish("dead")

func _update_level_audio() -> void:
	if not is_instance_valid(level_audio):return
	var distance: float=level_audio.combat_exit_distance if level_audio.in_combat else level_audio.combat_enter_distance
	distance=maxf(distance,level_audio.combat_enter_distance)
	var threat := false
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.active and enemy.target==player and enemy.global_position.distance_squared_to(player.global_position)<=distance*distance:
			threat=true;break
	level_audio.report_combat(threat and player.health>0)

func add_item(kind: String, label: String, pos: Vector3, color: Color,ammo_type: StringName=&"magnum",amount: int=12,world_id: StringName=&"") -> void:
	if not world_id.is_empty() and WorldEvents.interaction_used(world_id):return
	var item := Node3D.new()
	item.position=pos
	item.name=kind.capitalize()
	add_child(item)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=Vector3(.23,.12,.15) if kind!="medkit" else Vector3(.3,.14,.23)
	mesh.mesh=box
	mesh.material_override=PSX.make(color,null,Vector2.ONE,color*.17)
	item.add_child(mesh)
	var tag := Label3D.new()
	tag.text="+" if kind=="medkit" else ("16A" if kind=="fuse" else String(ammo_type).to_upper())
	tag.font_size=32
	tag.pixel_size=.0025
	tag.position=Vector3(0,.085,.081)
	tag.rotation.x=-.4
	tag.outline_size=0
	item.add_child(tag)
	interactables.append({"kind":kind,"label":label,"pos":pos,"node":item,"taken":false,"ammo_type":ammo_type,"amount":amount,"world_id":world_id})

func interact() -> void:
	if nearest.is_empty() or nearest.get("taken",false):
		return
	var pickup: bool=nearest.kind in ["fuse","ammo","medkit"]
	match nearest.kind:
		"world":
			if is_instance_valid(nearest.node):nearest.node.interact(player)
			nearest={};return
		"fuse":
			if not get_node("/root/InventoryState").give(get_node("/root/InventoryState").resolve_item(&"fuse_16a")):return
			has_fuse=true
			hud.toast("Fusible 16 A")
		"ammo":
			var count: int=player.add_ammo(nearest.get("ammo_type",&"magnum"),int(nearest.get("amount",12)))
			if count<=0:return
			hud.toast("%d cartouches récupérées" % count)
		"medkit":
			if not get_node("/root/InventoryState").give(get_node("/root/InventoryState").resolve_item(&"medkit")):return
			hud.toast("Trousse de soin")
		"power":
			if not has_fuse:
				hud.toast("Il manque un fusible 16 A.")
				return
			power=true
			get_node("/root/InventoryState").remove_item(&"fuse_16a")
			WorldEvents.set_flag(&"couloir.power",true);WorldEvents.mark_interaction(&"couloir.power_panel")
			hud.toast("Courant rétabli")
		"exit":
			if not power:
				hud.toast("Verrou électrique hors tension")
				return
			WorldEvents.set_door_open(&"couloir.exit",true);WorldEvents.mark_interaction(&"couloir.exit")
			finish("won")
			return
	nearest["taken"]=true
	var world_id: StringName=nearest.get("world_id",&"")
	if not world_id.is_empty():WorldEvents.mark_interaction(world_id)
	if nearest.node:
		nearest.node.queue_free()
	if not pickup: AudioRouting.play(player.sounds.pickup)
	nearest={}

func shoot_ray(origin: Vector3, direction: Vector3) -> void:
	var definition=player.weapon_definition()
	var distance: float=definition.shooting_distance if definition else 45.0
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*distance,1|4)
	query.exclude=[player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = hit.position if not hit.is_empty() else origin+direction*distance
	# A second ray from the barrel prevents shots passing through nearby walls.
	var muzzle: Vector3 = player.global_position+Vector3.UP*1.35-player.global_basis.z*.55+player.global_basis.x*.10
	if player.motion.weapon:
		player.motion.hand_attachment.on_skeleton_update()
		muzzle=player.motion.weapon.get_muzzle_transform().origin
	var barrel_query := PhysicsRayQueryParameters3D.create(muzzle,end,1|4)
	barrel_query.exclude=[player.get_rid()]
	var barrel_hit := get_world_3d().direct_space_state.intersect_ray(barrel_query)
	if not barrel_hit.is_empty():
		hit=barrel_hit
		end=hit.position
	if not hit.is_empty() and hit.collider.has_method("break_on_impact"):
		hit.collider.break_on_impact(end,direction)
	elif not hit.is_empty() and hit.collider.has_method("take_hit"):
		if hit.collider.take_hit(end,definition.damage if definition else 1):
			hud.hit_time=hit_marker_duration
			hit_audio.stream=get_node("/root/PSXAudio").prepare(hit_marker_sound)
			hit_audio.volume_db=hit_marker_volume_db
			if hit_audio.stream:AudioRouting.play(hit_audio)
	psx_renderer.add_shot(muzzle,end,not hit.is_empty())

func finish(result: String) -> void:
	if is_instance_valid(pickup_feedback): pickup_feedback.cancel()
	if is_instance_valid(inventory_menu) and inventory_menu.opened: inventory_menu.close()
	state=result
	if is_instance_valid(item_placement):item_placement.cancel()
	if is_instance_valid(cinematics) and cinematics.is_active():cinematics.cancel(&"level_finished")
	if is_instance_valid(dialogue) and dialogue.is_active():dialogue.cancel()
	if is_instance_valid(exploration_dialogue):exploration_dialogue.cancel()
	player.enabled=false
	if is_instance_valid(level_audio):level_audio.stop_level()
	hud.show_menu(result)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_tree().paused=true

func capture() -> void:
	await get_tree().create_timer(2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/gameplay.png")
	Input.action_press("aim")
	await get_tree().create_timer(1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/aim.png")
	Input.action_release("aim")
	get_tree().quit()
