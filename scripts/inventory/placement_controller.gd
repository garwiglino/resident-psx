extends Node
const Menu=preload("res://scripts/inventory/placement_menu.gd")
const Pose=preload("res://scripts/inventory/placement_pose.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Audio=preload("res://scripts/audio/psx_audio_routing.gd")
const Inspection=preload("res://scripts/inventory/placement_highlight.gd")
const AccessSettings=preload("res://scripts/inventory/mechanism_access_settings.gd")
enum Phase { IDLE, CHOOSING, PLACING, ANIMATING, INSPECTING, OPENING, CLOSING, ACTION_ANIMATING, ACTIONS, ACTION_CYCLE }
signal opened(target: Node3D)
signal closed(target: Node3D,installed: bool)
signal wrong_item_selected(item: Resource,line: Resource)
var game: Node
var phase := Phase.IDLE
var target: Node3D
var station: Node3D
var hovered: Node3D
var parts: Array[Node3D]=[]
var mouse_position := Vector2(160,120)
var inspection: CanvasLayer
var _click_pending := false
var _publications: Array[WeakRef]=[]
var menu: CanvasLayer
var camera: Camera3D
var _audio: AudioStreamPlayer3D
var _ui_audio: AudioStreamPlayer
var _inventory: Node
var _piece: Node3D
var _pose: RefCounted
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _elapsed := 0.0
var _selected_uid := ""
var _previous_camera: WeakRef
var _previous_viewport_camera: WeakRef
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _old_player_visible := true
var _suspended := false
var _closing := false
var _wrong_pending := false
var _last_wrong: Dictionary={}
var _access: Node
var _exit_requested := false
var _exit_installed := false
var _stay_closed := false
var _action_data: Dictionary={}
var _action_job := 0
var _action_dialogues: Array[WeakRef]=[]
var _action_publications: Array[Dictionary]=[]
var _action_cycle: Node
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;_inventory=get_node("/root/InventoryState")
	camera=Camera3D.new();camera.name="VueInteraction";camera.cull_mask=0;add_child(camera)
	menu=Menu.new();menu.controller=self;add_child(menu)
	inspection=Inspection.new();inspection.controller=self;add_child(inspection)
	_audio=AudioStreamPlayer3D.new();_audio.name="SonMecanisme";_audio.max_distance=9;add_child(_audio);Audio.set_category(_audio,&"Interactions")
	_ui_audio=AudioStreamPlayer.new();_ui_audio.name="ChoixObjet";add_child(_ui_audio);Audio.set_category(_ui_audio,&"UI");Audio.set_reverb_enabled(_ui_audio,false)
	game.dialogue.session_finished.connect(_reply_finished)
	WorldEvents.run_reset.connect(_world_reset);set_process(false);set_physics_process(false)
func is_active() -> bool:return phase!=Phase.IDLE
func begin(candidate: Node3D,player: Node3D=null) -> bool:
	if is_active() or not candidate or not is_inside_tree() or get_tree().paused or game.state!="playing":return false
	if not is_instance_valid(game.player) or game.player.health<=0 or (player and player!=game.player):return false
	if not candidate.can_interact() or not game.is_ancestor_of(candidate):return false
	var error: String=candidate.configuration_error()
	if not error.is_empty():push_warning(error);return false
	if not game.dialogue.reserve(self):return false
	parts=candidate.placement_targets()
	if parts.is_empty():game.dialogue.release_reservation(self);return false
	station=candidate;station._busy=true;station.tree_exiting.connect(_target_exiting)
	target=null;_piece=null;hovered=null;_publications.clear();_click_pending=false;_exit_requested=false;_exit_installed=false;_stay_closed=false
	_action_data.clear();_action_job=0;_action_dialogues.clear();_action_publications.clear()
	for part in parts:
		if part.has_method("set_inspection_active"):part.set_inspection_active(true)
	_previous_camera=weakref(game.psx_renderer.camera) if is_instance_valid(game.psx_renderer.camera) else null
	var current := get_viewport().get_camera_3d();_previous_viewport_camera=weakref(current) if current else null
	_old_mouse=Input.mouse_mode;phase=Phase.INSPECTING;_wrong_pending=false;_suspended=false
	_old_player_visible=game.player.visual.visible
	if station.hide_player_in_view:game.player.visual.hide()
	_copy_camera();camera.make_current();game.psx_renderer.set_active_camera(camera);game._acquire_controls(&"item_placement")
	mouse_position=get_viewport().get_mouse_position().clamp(Vector2.ZERO,Vector2(319,239));set_process(true);set_physics_process(true)
	_access=station.get_mechanism_access()
	if _access:
		_access.transition_allowed=_access_allowed;_access.inspecting=true
		_access.transition_started.connect(_access_started);_access.transition_finished.connect(_access_finished)
		if _access.is_active():_access_started(_access._destination)
		elif _access.settings.open_on_interaction and not _access.is_open():_access.request_open()
		else:_show_selection()
	else:_show_selection()
	opened.emit(station);return true
func _show_selection() -> void:
	_inspect()
	if (not _access or _access.is_open()) and not station.has_method("is_placement_scene") and not station.select_part_first and not station.all_installed():select_part(station)
func can_pick_parts() -> bool:return parts.any(func(part: Node3D):return is_instance_valid(part) and _can_pick_part(part))
func _can_pick_part(part: Node3D) -> bool:return not is_instance_valid(_access) or (not _access.is_active() and (_access.is_open() or not part.requires_open))
func inspection_caption() -> String:
	if _access and not _access.is_open() and not can_pick_parts():return "FERME"
	return "MECANISME COMPLET" if station and station.all_installed() and not parts.any(func(part: Node3D):return not part.is_item_socket() and part.can_select_part(true)) else ""
func _access_allowed(_opening: bool) -> bool:
	if not is_active():return true
	if phase in [Phase.PLACING,Phase.ANIMATING,Phase.ACTION_ANIMATING,Phase.ACTION_CYCLE]:return false
	if _wrong_pending:
		_wrong_pending=false
		if game.dialogue.is_active():game.dialogue.cancel()
	if target:_release_part(false);station._busy=true
	return true
func _access_started(opening: bool) -> void:
	if not is_active():return
	if not opening and not _stay_closed:_exit_requested=true
	phase=Phase.OPENING if opening else Phase.CLOSING
	hovered=null;_click_pending=false;menu.canvas.hide();inspection.show_inspection(false);Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
func _access_finished(_opened: bool) -> void:
	if not is_active() or not _access or _access.is_active():return
	if _exit_requested:request_exit(_exit_installed);return
	if WorldEvents.job_active(_action_job) or _part_dialogue_active():phase=Phase.ACTIONS;return
	_stay_closed=false;_show_selection()
func request_exit(installed := false,force_close := false) -> void:
	if not is_active() or _closing:return
	_exit_requested=true;_exit_installed=_exit_installed or installed;_stay_closed=false
	var close_lid: bool=_access!=null and (force_close or _access.settings.close_policy==AccessSettings.ClosePolicy.ON_EXIT or (_access.settings.close_policy==AccessSettings.ClosePolicy.WHEN_COMPLETE and station.all_installed()))
	if close_lid:
		_access.request_close()
		if not is_active() or not _access or _access.is_active():return
	elif _access and _access.is_active():return
	_finish(_exit_installed)
func _copy_camera() -> void:
	var source := station.get_node_or_null(station.camera_path) as Camera3D if not station.camera_path.is_empty() else null
	if source:
		camera.global_transform=source.get_camera_transform();camera.projection=source.projection;camera.keep_aspect=Camera3D.KEEP_HEIGHT
		camera.fov=source.fov if source.keep_aspect==Camera3D.KEEP_HEIGHT else rad_to_deg(2*atan(tan(deg_to_rad(source.fov)*.5)*.75))
		camera.size=source.size if source.keep_aspect==Camera3D.KEEP_HEIGHT else source.size*.75;camera.near=source.near;camera.far=source.far
	else:
		var point: Vector3=station.get_interaction_position();camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=45;camera.near=.05;camera.far=55
		camera.global_position=point+station.global_basis.orthonormalized()*Vector3(0,.2,1.5);camera.look_at(point-Vector3.UP*.3)
func _inspect() -> void:
	phase=Phase.INSPECTING;menu.canvas.hide();hovered=null;_click_pending=false
	mouse_position=get_viewport().get_mouse_position().clamp(Vector2.ZERO,Vector2(319,239))
	inspection.show_inspection(not _suspended);inspection.highlight(null);Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
func select_part(part: Node3D) -> bool:
	if phase!=Phase.INSPECTING or _suspended or not is_instance_valid(part) or part not in parts or not _can_pick_part(part) or not part.can_select_part(true):return false
	var error: String=part.configuration_error()
	if not error.is_empty():push_warning("%s : %s" % [part.name,error]);return false
	if not part.is_item_socket():return _activate_part(part)
	target=part;_piece=part.prepare_piece()
	if not _piece:target=null;return false
	target._busy=true
	if target!=station:target.tree_exiting.connect(_target_exiting)
	phase=Phase.CHOOSING;hovered=null;inspection.show_inspection(false);menu.show_choices();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;_menu_sound(true);return true
func _activate_part(part: Node3D) -> bool:
	target=part;target._busy=true;_piece=null;_action_data=part.intent();_action_dialogues.clear()
	if target!=station:target.tree_exiting.connect(_target_exiting)
	phase=Phase.ACTION_ANIMATING;hovered=null;_click_pending=false;inspection.show_inspection(false);menu.canvas.hide();Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	_pose=Pose.new();_pose.capture(station);part.sample_animation(_pose,self,bool(_action_data.active))
	_play_sound(part.activation_sound if bool(_action_data.active) else part.deactivation_sound)
	if _pose.length<=0:_commit_action()
	return true
func _commit_action() -> void:
	if not is_instance_valid(target):cancel();return
	_action_cycle=target.create_action_cycle(_action_data)
	if _action_cycle:
		phase=Phase.ACTION_CYCLE;_action_cycle.finished.connect(_action_cycle_finished,CONNECT_ONE_SHOT);add_child(_action_cycle);_action_cycle.start();return
	_publish_part_action()
func _action_cycle_finished() -> void:
	if not is_active() or phase!=Phase.ACTION_CYCLE:return
	_dispose_action_cycle();_publish_part_action()
func _dispose_action_cycle() -> void:
	if not is_instance_valid(_action_cycle):_action_cycle=null;return
	var cycle := _action_cycle;_action_cycle=null
	if cycle.finished.is_connected(_action_cycle_finished):cycle.finished.disconnect(_action_cycle_finished)
	cycle.cancel();cycle.queue_free()
func _publish_part_action() -> void:
	if not is_instance_valid(target) or not target.commit_action(_action_data):cancel();return
	if _pose:_pose.finish(true);_pose=null
	if target.must_exit(_action_data):
		_action_publications.append({"source":weakref(target),"data":_action_data.duplicate(true)})
		_release_part(true);_action_data.clear();phase=Phase.INSPECTING;request_exit(true);return
	phase=Phase.ACTIONS;var token: int=target.publish_action(_action_data.duplicate(),game.player,self)
	if not is_active():WorldEvents.release_job_owner(token);return
	_action_job=token
	if _action_job<=0:_finish_part_actions()
func world_dialogue_started(receiver: Node) -> void:
	if phase==Phase.ACTIONS and not _action_dialogues.any(func(reference: WeakRef):return reference.get_ref()==receiver):_action_dialogues.append(weakref(receiver))
func world_dialogue_controller(_sequence: Resource) -> Node:return game.dialogue
func _part_dialogue_active() -> bool:
	return _action_dialogues.any(func(reference: WeakRef):return is_instance_valid(reference.get_ref()) and reference.get_ref().is_active())
func _finish_part_actions() -> void:
	_action_job=0;_action_dialogues.clear();_action_data.clear();_release_part(true);station._busy=true
	if _exit_requested:request_exit(true)
	else:_inspect()
func back() -> void:
	if phase!=Phase.CHOOSING or _wrong_pending or _suspended:return
	if not station.has_method("is_placement_scene") and not station.select_part_first:request_exit();return
	_menu_sound(false);_release_part(false);station._busy=true;_inspect()
func _physics_process(_delta: float) -> void:
	if phase!=Phase.INSPECTING or _suspended or get_tree().paused:return
	if not is_instance_valid(station):cancel();return
	hovered=pick_part(mouse_position);inspection.highlight(hovered)
	if _click_pending:
		_click_pending=false
		if hovered:select_part(hovered)
func pick_part(at: Vector2) -> Node3D:
	if not can_pick_parts() or not is_instance_valid(station) or not Rect2(0,0,320,240).has_point(at):return null
	var from := camera.project_ray_origin(at);var end := from+camera.project_ray_normal(at)*camera.far
	var query := PhysicsRayQueryParameters3D.create(from,end,1<<19);query.collide_with_areas=true;query.collide_with_bodies=false;query.hit_from_inside=true
	var space := station.get_world_3d().direct_space_state
	for attempt in 32:
		var hit := space.intersect_ray(query)
		if hit.is_empty():return null
		for part in parts:
			if is_instance_valid(part) and _can_pick_part(part) and part.can_select_part(true) and part.selection_area()==hit.collider:
				var blocker := space.intersect_ray(PhysicsRayQueryParameters3D.create(from,hit.position,1))
				if blocker.is_empty() or from.distance_to(blocker.position)+.01>=from.distance_to(hit.position):return part
				return null
		var excluded := query.exclude;excluded.append(hit.collider.get_rid());query.exclude=excluded
	return null
func choose(uid: String) -> bool:
	if phase!=Phase.CHOOSING or _wrong_pending or _suspended or get_tree().paused:return false
	var location: Dictionary=_inventory.model.locate(uid)
	if location.is_empty() or not location.entry.item.can_place():return false
	if location.entry.item.id!=target.required_id():_wrong_item(location.entry.item);return false
	if _inventory.count(target.required_id())<target.required_quantity:menu.message("Quantite insuffisante.");return false
	if not target.configuration_error().is_empty() or not WorldCondition.all_match(target.requirements):cancel();return false
	_selected_uid=uid;_pose=Pose.new();_pose.capture(station)
	_to=_piece.transform
	var start := target.get_node_or_null(target.placement_start_path) as Node3D if not target.placement_start_path.is_empty() else null
	var world: Transform3D=_piece.global_transform
	if start:world=Transform3D(start.global_basis.orthonormalized().scaled_local(world.basis.get_scale()),start.global_position)
	else:world.origin+=target.global_basis.orthonormalized()*Vector3(0,.15,.7)
	_from=_piece.get_parent_node_3d().global_transform.affine_inverse()*world
	_piece.transform=_from;_piece.visible=true;_elapsed=0;phase=Phase.PLACING;menu.canvas.hide();_menu_sound(false)
	_play_sound(target.insertion_sound);return true
func _wrong_item(item: Resource) -> void:
	var source: Resource=target.wrong_item_dialogue
	if not source:menu.message("Ca ne convient pas.");wrong_item_selected.emit(item,null);return
	var valid: Array=[]
	for index in source.lines.size():
		if source.lines[index] and not Text.plain(source.lines[index].text).strip_edges().is_empty():valid.append(index)
	if valid.is_empty():menu.message("Ca ne convient pas.");wrong_item_selected.emit(item,null);return
	var key := source.resource_path if not source.resource_path.is_empty() else String.num_int64(source.get_instance_id())
	if valid.size()>1:valid.erase(int(_last_wrong.get(key,-1)))
	var index: int=valid[randi_range(0,valid.size()-1)];_last_wrong[key]=index
	var reply: Resource=source.duplicate(false);var lines: Array[DialogueLine]=[source.lines[index].duplicate(true)];reply.lines=lines;reply.mode=Sequence.Mode.EXPLORATION_CALL
	_wrong_pending=true;menu.canvas.hide()
	if not game.dialogue.play(reply,false,self):_wrong_pending=false;menu.show_choices()
	wrong_item_selected.emit(item,source.lines[index])
func _reply_finished() -> void:
	if not is_active() or not _wrong_pending or _closing:return
	_wrong_pending=false
	if not _suspended:menu.show_choices()
func _process(delta: float) -> void:
	if not is_active() or _suspended:return
	if not is_instance_valid(station) or game.player.health<=0:cancel();return
	if phase in [Phase.INSPECTING,Phase.OPENING,Phase.CLOSING]:return
	if phase==Phase.ACTION_CYCLE:
		if not is_instance_valid(target) or not is_instance_valid(_action_cycle):cancel()
		return
	if phase==Phase.ACTIONS:
		if not WorldEvents.job_active(_action_job) and not _part_dialogue_active():_finish_part_actions()
		return
	if phase==Phase.ACTION_ANIMATING:
		if not is_instance_valid(target):cancel();return
		if _pose.advance(delta):_commit_action()
		return
	if not is_instance_valid(target) or not is_instance_valid(_piece):cancel();return
	if phase==Phase.PLACING:
		_elapsed+=delta;var t := clampf(_elapsed/maxf(target.placement_duration,.001),0,1)
		_piece.transform=_from.interpolate_with(_to,smoothstep(0,1,t))
		if t>=1:
			_piece.transform=_to;_pose.begin(target.animation_source(),target.installation_animation,self,target.installation_animation_speed);phase=Phase.ANIMATING
			if _pose.length<=0:_complete()
	elif phase==Phase.ANIMATING:
		var finished: bool=_pose.advance(delta);target.sync_socket()
		if finished:_complete()
func _complete() -> void:
	if not target.commit_piece(_selected_uid):cancel();return
	_play_sound(target.installed_sound);_publications.append(weakref(target));_release_part(true);phase=Phase.INSPECTING
	if station.has_method("is_placement_scene"):
		if station.all_installed():
			if not WorldEvents.interaction_used(station._id()):WorldEvents.mark_interaction(station._id());_publications.append(weakref(station))
			if station.close_when_complete:request_exit(true);return
			if _access and _access.settings.close_policy==AccessSettings.ClosePolicy.WHEN_COMPLETE:
				_stay_closed=true;phase=Phase.INSPECTING;_access.request_close()
				if _access.is_active():return
		if _exit_requested:request_exit(_exit_installed);return
		_inspect()
	else:request_exit(true)
func _release_part(installed: bool) -> void:
	_dispose_action_cycle()
	if _pose:_pose.finish(installed);_pose=null
	if is_instance_valid(target):
		if target!=station:
			target._busy=false
			if target.tree_exiting.is_connected(_target_exiting):target.tree_exiting.disconnect(_target_exiting)
		if installed and target.is_item_socket():target._show_installed(true)
		else:target._busy=false;target._sync()
	target=null;_piece=null
	if is_instance_valid(_access):_access.reapply_pose()
func _play_sound(stream: AudioStream) -> void:
	if not stream:return
	_audio.global_position=target.get_interaction_position();_audio.stream=get_node("/root/PSXAudio").prepare(stream);_audio.volume_db=target.mechanism_volume_db;Audio.play(_audio)
func _menu_sound(open: bool) -> void:
	var style=game.dialogue.style;_ui_audio.stream=get_node("/root/PSXAudio").prepare(style.opening_sound if open else style.closing_sound);_ui_audio.volume_db=style.window_volume_db
	if _ui_audio.stream:Audio.play(_ui_audio)
func set_suspended(value: bool) -> void:
	_suspended=value
	if is_instance_valid(_action_cycle):_action_cycle.set_suspended(value)
	if not is_active():return
	menu.canvas.visible=not value and phase==Phase.CHOOSING and not _wrong_pending
	inspection.show_inspection(not value and phase==Phase.INSPECTING)
	if not value:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if phase==Phase.CHOOSING else Input.MOUSE_MODE_HIDDEN
func handle_input(event: InputEvent) -> bool:
	if not is_active() or get_tree().paused:return false
	if event.is_action_pressed("inventory"):return true
	if phase==Phase.ACTIONS and _part_dialogue_active():return false
	if event is InputEventMouseMotion and phase==Phase.INSPECTING:mouse_position=event.position;return true
	if event is InputEventMouseButton and phase==Phase.INSPECTING:
		mouse_position=event.position
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:_click_pending=true
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:request_exit()
		return true
	if event.is_action_pressed("pause") and not _wrong_pending:
		if phase in [Phase.INSPECTING,Phase.OPENING,Phase.CLOSING,Phase.ACTIONS]:request_exit();return true
		if phase==Phase.CHOOSING:back();return true
	return false
func _world_reset() -> void:_publications.clear();_action_publications.clear();cancel()
func cancel() -> void:
	if is_active():_finish(false,true)
func _target_exiting() -> void:cancel()
func _finish(installed: bool,hard := false) -> void:
	if _closing:return
	_closing=true
	var completed := station
	if hard:
		WorldEvents.cancel_job(_action_job)
		for reference in _action_dialogues:
			var receiver: Node=reference.get_ref()
			if is_instance_valid(receiver) and receiver.is_active():receiver.cancel()
	else:WorldEvents.release_job_owner(_action_job)
	_action_job=0;_action_dialogues.clear();_action_data.clear()
	for part in parts:
		if is_instance_valid(part) and part.has_method("set_inspection_active"):part.set_inspection_active(false)
	if is_instance_valid(_access):
		_access.transition_allowed=Callable();_access.inspecting=false
		if _access.transition_started.is_connected(_access_started):_access.transition_started.disconnect(_access_started)
		if _access.transition_finished.is_connected(_access_finished):_access.transition_finished.disconnect(_access_finished)
	_release_part(false)
	if is_instance_valid(_access):_access.settle_requested_state()
	_access=null
	if is_instance_valid(completed):
		completed._busy=false
		if completed.tree_exiting.is_connected(_target_exiting):completed.tree_exiting.disconnect(_target_exiting)
	if not installed:Audio.stop(_audio)
	if menu.canvas.visible:_menu_sound(false)
	menu.canvas.hide();inspection.show_inspection(false);phase=Phase.IDLE;set_process(false);set_physics_process(false)
	if is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion():
		if _wrong_pending and game.dialogue.is_active():game.dialogue.cancel()
		game.dialogue.release_reservation(self)
		game.player.visual.visible=_old_player_visible
		var previous: Node=_previous_camera.get_ref() if _previous_camera else null
		if not is_instance_valid(previous) or not previous.is_inside_tree():previous=game.player.camera
		if is_instance_valid(previous) and previous.is_inside_tree():game.psx_renderer.set_active_camera(previous)
		var viewport_previous: Node=_previous_viewport_camera.get_ref() if _previous_viewport_camera else null
		if is_instance_valid(viewport_previous) and viewport_previous.is_inside_tree():viewport_previous.make_current()
		game._release_controls(&"item_placement");Input.mouse_mode=_old_mouse
	var publications := _publications.duplicate();_publications.clear()
	var action_publications := _action_publications.duplicate();_action_publications.clear()
	_wrong_pending=false;target=null;station=null;hovered=null;_piece=null;parts.clear();_closing=false
	if is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion():
		for reference in publications:
			var source=reference.get_ref()
			if is_instance_valid(source) and source.is_inside_tree() and WorldEvents.interaction_used(source._id()):source.publish_installation(game.player)
		if not hard:
			for publication in action_publications:
				var source: Node=publication.source.get_ref()
				if is_instance_valid(source) and source.is_inside_tree():source.publish_action(publication.data,game.player)
	closed.emit(completed,installed)
func _exit_tree() -> void:
	if is_active():_finish(false,true)
