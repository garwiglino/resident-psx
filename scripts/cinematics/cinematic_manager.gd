class_name CinematicManager
extends Node
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
const Actors=preload("res://scripts/cinematics/cinematic_actors.gd")
enum State { IDLE, PLAYING }
signal started(sequence: Node3D)
signal finished(sequence: Node3D,reason: StringName)
signal event_reached(sequence: Node3D,id: StringName)
signal plan_started(index: int,plan: Resource)
signal plan_finished(index: int,plan: Resource)
@export var skip_action: StringName=&"cinematic_skip"
var state := State.IDLE
var sequence: Node3D
var camera: Camera3D
var waiting_for_dialogue := false
var _game: Node3D
var _dialogue: Node
var _timeline: AnimationPlayer
var _old_process_callback := 0
var _old_method_callback := 0
var _previous_camera: WeakRef
var _previous_viewport_camera: WeakRef
var _target: WeakRef
var _blend_from := Transform3D.IDENTITY
var _blend_fov := 50.0
var _blend_size := 1.0
var _blend_near := .1
var _blend_far := 50.0
var _blend_left := 0.0
var _blend_duration := 0.0
var _timeline_done := false
var _revision := 0
var _skip_held := false
var _stopping := false
var plan_index := -1
var _plans: Array[Shot]=[]
var _plan_elapsed := 0.0
var _camera_done := false
var _dialogue_started := false
var _dialogue_done := false
var _montage_done := false
var _pending_dialogues: Dictionary={}
var _delayed_dialogues: Array[Dictionary]=[]
var _advancing_plan := false
var _actors=Actors.new()
var _actor_time := 0.0
var _plan_duration := 0.0

func _enter_tree() -> void:add_to_group("cinematic_managers")
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;process_priority=50
	camera=Camera3D.new();camera.name="CinematicView";camera.cull_mask=0;add_child(camera)
	if not InputMap.has_action(skip_action):
		InputMap.add_action(skip_action)
		var key := InputEventKey.new();key.physical_keycode=KEY_BACKSPACE;InputMap.action_add_event(skip_action,key)
	set_process(false);set_process_unhandled_input(false)

func setup(game: Node3D) -> void:
	_game=game;_dialogue=game.dialogue
	_dialogue.session_finished.connect(_dialogue_finished)
	_dialogue.sequence_completed.connect(_dialogue_completed)

func is_active() -> bool:return state!=State.IDLE

func uses_montage() -> bool:return not _plans.is_empty()

func play(node: Node) -> bool:
	if not is_node_ready() or not is_instance_valid(_game) or is_active() or get_tree().paused:return false
	var candidate := node as Sequence
	if _game.state!="playing" or not is_instance_valid(candidate) or not candidate.is_inside_tree():return false
	if not is_instance_valid(_game.player) or _game.player.health<=0:return false
	if not _game.is_ancestor_of(candidate) or not candidate.validation_error().is_empty():return false
	var timeline := candidate.get_node(candidate.timeline_path) as AnimationPlayer
	if timeline.is_playing() or not _dialogue.reserve(self):return false
	var previous: Camera3D=_game.psx_renderer.camera
	_previous_camera=weakref(previous) if is_instance_valid(previous) else null
	var viewport_camera := get_viewport().get_camera_3d()
	_previous_viewport_camera=weakref(viewport_camera) if viewport_camera else null
	sequence=candidate;sequence._director=self;_timeline=timeline
	_old_process_callback=timeline.callback_mode_process;_old_method_callback=timeline.callback_mode_method
	timeline.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	timeline.callback_mode_method=AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	timeline.animation_finished.connect(_animation_finished)
	state=State.PLAYING;_timeline_done=false;waiting_for_dialogue=false;_revision+=1
	_plans.clear();_pending_dialogues.clear();_delayed_dialogues.clear();plan_index=-1;_montage_done=false;_advancing_plan=false
	if not candidate.classic_timeline:
		for plan in candidate.get_plans():_plans.append(plan.duplicate(true))
	if uses_montage():_actors.prepare(candidate,_plans)
	_skip_held=Input.is_action_pressed(skip_action)
	_copy_camera(previous);camera.make_current();_game.psx_renderer.set_active_camera(camera)
	if not change_camera(sequence.get_node(_plans[0].camera_path if uses_montage() else sequence.entry_camera),0):return false
	set_process(true);set_process_unhandled_input(true)
	var token := _revision;started.emit(sequence)
	if token!=_revision or not is_active():return true
	if uses_montage():_start_plan(0)
	else:timeline.play(sequence.animation,0);timeline.advance(0)
	if token==_revision and is_active():_update_camera(0)
	return true

func _vertical_fov(source: Camera3D) -> float:
	return source.fov if source.keep_aspect==Camera3D.KEEP_HEIGHT else rad_to_deg(2*atan(tan(deg_to_rad(source.fov)*.5)*.75))

func _vertical_size(source: Camera3D) -> float:
	return source.size if source.keep_aspect==Camera3D.KEEP_HEIGHT else source.size*.75

func _copy_camera(source: Camera3D) -> void:
	if not is_instance_valid(source):return
	camera.global_transform=source.get_camera_transform();camera.projection=source.projection
	camera.keep_aspect=Camera3D.KEEP_HEIGHT;camera.fov=_vertical_fov(source);camera.size=_vertical_size(source)
	camera.near=source.near;camera.far=source.far

func change_camera(node: Node,seconds := 0.0) -> bool:
	if not is_active():return false
	var target := node as Camera3D
	if not is_instance_valid(target) or not target.is_inside_tree() or target.get_viewport()!=get_viewport() or target.projection==Camera3D.PROJECTION_FRUSTUM:
		cancel(&"missing_camera");return false
	_target=weakref(target);_blend_from=camera.global_transform;_blend_fov=camera.fov;_blend_size=camera.size
	_blend_near=camera.near;_blend_far=camera.far
	_blend_duration=maxf(seconds,0) if camera.projection==target.projection else 0.0
	_blend_left=_blend_duration
	_update_camera(0)
	return true

func _update_camera(delta: float) -> void:
	var target: Camera3D=_target.get_ref() if _target else null
	if not is_instance_valid(target) or not target.is_inside_tree() or target.projection==Camera3D.PROJECTION_FRUSTUM:cancel(&"missing_camera");return
	_blend_left=maxf(_blend_left-delta,0)
	var weight := smoothstep(0,1,1-_blend_left/_blend_duration) if _blend_duration>0 else 1.0
	camera.global_transform=_blend_from.interpolate_with(target.get_camera_transform(),weight)
	camera.projection=target.projection
	camera.fov=lerpf(_blend_fov,_vertical_fov(target),weight);camera.size=lerpf(_blend_size,_vertical_size(target),weight)
	camera.near=lerpf(_blend_near,target.near,weight);camera.far=lerpf(_blend_far,target.far,weight)

func show_dialogue(resource: Resource,wait_for_finish := true) -> bool:
	if state!=State.PLAYING:return false
	waiting_for_dialogue=wait_for_finish
	if not _dialogue.play(resource,true,self):cancel(&"invalid_dialogue");return false
	return true

func _dialogue_finished() -> void:
	if state!=State.PLAYING or _stopping:return
	if uses_montage():_finish_montage_if_ready();return
	waiting_for_dialogue=false
	if _timeline_done:_begin_return(&"completed")

func _animation_finished(name: StringName) -> void:
	if uses_montage():return
	if state!=State.PLAYING or not is_instance_valid(sequence) or name!=sequence.animation:return
	_timeline_done=true
	# An asynchronous final conversation must finish before returning control.
	if not _dialogue.is_active():_begin_return(&"completed")

func _process(delta: float) -> void:
	if not is_active() or get_tree().paused:return
	if not is_instance_valid(_game) or not is_instance_valid(_dialogue) or not is_instance_valid(_game.psx_renderer):cancel(&"system_removed");return
	if not is_instance_valid(sequence) or not sequence.is_inside_tree() or not is_instance_valid(_timeline):cancel(&"sequence_removed");return
	if not _actors.valid():cancel(&"actor_removed");return
	if uses_montage():_process_montage(delta);return
	var token := _revision
	var remaining := delta
	if state==State.PLAYING and not waiting_for_dialogue and not _timeline_done:
		# Stop precisely on method keys so a blocking dialogue cannot consume
		# timeline time after its cue, including during a long frame.
		while remaining>.000001 and state==State.PLAYING and not waiting_for_dialogue and not _timeline_done:
			var position := _timeline.current_animation_position
			var clip := _timeline.get_animation(sequence.animation)
			if position>=clip.length-.000001:_animation_finished(sequence.animation);break
			var step := minf(remaining,clip.length-position)
			for track in clip.get_track_count():
				if clip.track_get_type(track)!=Animation.TYPE_METHOD or not clip.track_is_enabled(track):continue
				for key in clip.track_get_key_count(track):
					var time := clip.track_get_key_time(track,key)
					if time>position+.000001:step=minf(step,time-position)
			_update_camera(step)
			if token!=_revision or not is_active():return
			_timeline.advance(step);remaining=maxf(remaining-step,0)
			if token!=_revision or not is_active():return
			_update_camera(0)
			if token!=_revision or not is_active():return
	_update_camera(remaining)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active():return
	if uses_montage() and not _montage_done and _plans[plan_index].progression==Shot.Progression.MANUAL and not _dialogue.is_active() and event.is_action_pressed(_dialogue.advance_action,false):
		next_plan();get_viewport().set_input_as_handled();return
	if event.is_action_released(skip_action):_skip_held=false
	if event.is_action_pressed(skip_action,false):
		if not _skip_held:_skip_held=true;skip()
		get_viewport().set_input_as_handled()

func skip() -> bool:
	if state!=State.PLAYING or get_tree().paused or not sequence.skippable:return false
	var token := _revision
	_stopping=true
	if _dialogue.is_active():_dialogue.cancel()
	if token!=_revision or state!=State.PLAYING:_stopping=false;return true
	# Apply the final property pose, without firing skipped sounds/methods.
	if uses_montage():
		var last: Shot=_plans.back();_timeline.play(last.animation,0);_timeline.seek(last.end_position(_timeline),true,true)
		_actors.start_plan(last);_actors.sample(last.duration(_timeline))
	else:_timeline.seek(_timeline.get_animation(sequence.animation).length,true,true)
	if token!=_revision or state!=State.PLAYING:_stopping=false;return true
	_timeline.stop(true);_stopping=false;_begin_return(&"skipped")
	return true

func _return_camera() -> Camera3D:
	var previous: Camera3D=_previous_camera.get_ref() if _previous_camera else null
	if is_instance_valid(previous) and previous.is_inside_tree():return previous
	return _game.player.camera if is_instance_valid(_game) and is_instance_valid(_game.player) else null

func _begin_return(reason: StringName) -> void:
	if is_active():_finish(reason)

func _start_plan(index: int) -> void:
	if index>=_plans.size():
		_montage_done=true;waiting_for_dialogue=not _pending_dialogues.is_empty();_finish_montage_if_ready();return
	plan_index=index;_plan_elapsed=0;_actor_time=0;_camera_done=false
	var plan: Shot=_plans[index]
	var error := plan.validation_error(sequence,_timeline)
	if not error.is_empty():cancel(&"invalid_plan");return
	_plan_duration=plan.duration(_timeline)
	_dialogue_started=plan.dialogue==null;_dialogue_done=plan.dialogue==null;waiting_for_dialogue=false
	_timeline.play(plan.animation,0);_timeline.seek(plan.start_time,true,true)
	_actors.start_plan(plan)
	if plan.camera_duration(_timeline)<=.000001:_camera_done=true;_timeline.pause()
	if not change_camera(sequence.get_node_or_null(plan.camera_path),0):return
	var token := _revision;plan_started.emit(index,plan)
	if token!=_revision or not is_active() or plan_index!=index:return
	if plan.dialogue and plan.dialogue_delay<=0:_start_plan_dialogue()

func _start_plan_dialogue() -> void:
	if _dialogue_started or _montage_done:return
	_dialogue_started=true
	var resource: Resource=_plans[plan_index].dialogue.duplicate(true)
	var token := str(_revision)+":"+str(plan_index)
	resource.set_meta("cinematic_plan_token",token);_pending_dialogues[token]=plan_index
	if not _dialogue.play(resource,true,self):cancel(&"invalid_dialogue")

func _dialogue_completed(resource: Resource,cancelled: bool) -> void:
	if not uses_montage() or not is_active() or _stopping or not resource:return
	if not is_instance_valid(sequence) or not sequence.is_inside_tree() or not is_instance_valid(_timeline):cancel(&"sequence_removed");return
	var key: String=resource.get_meta("cinematic_plan_token","")
	if not _pending_dialogues.has(key):return
	var index: int=_pending_dialogues[key];_pending_dialogues.erase(key)
	if cancelled:cancel(&"dialogue_cancelled");return
	if index==plan_index and not _montage_done:
		_dialogue_done=true
		var plan: Shot=_plans[plan_index]
		if plan.progression==Shot.Progression.LINKED and plan.finish_camera_on_confirm:_complete_plan_camera(true)
		_evaluate_plan()
	_finish_montage_if_ready()

func _complete_plan_camera(finish_actors := false) -> void:
	var plan: Shot=_plans[plan_index]
	# Apply final property poses without firing skipped method/audio cues.
	_timeline.seek(plan.end_position(_timeline),true,true);_timeline.pause();_camera_done=true;_update_camera(0)
	if finish_actors:_actor_time=_plan_duration;_actors.sample(_actor_time)

func _process_montage(delta: float) -> void:
	var dispatch_token := _revision
	for job in _delayed_dialogues.duplicate():
		job.left-=delta
		if job.left<=0:
			_delayed_dialogues.erase(job)
			if not _dialogue.play(job.resource,true,self):cancel(&"invalid_dialogue");return
		if dispatch_token!=_revision or not is_active():return
	if _montage_done:_update_camera(delta);_finish_montage_if_ready();return
	var plan: Shot=_plans[plan_index]
	if not _timeline.has_animation(plan.animation):cancel(&"invalid_plan");return
	var token := _revision;var index := plan_index
	_plan_elapsed+=delta
	_actor_time=minf(_actor_time+delta*_timeline.speed_scale,_plan_duration);_actors.sample(_actor_time)
	if not _camera_done:
		var left := maxf(plan.end_position(_timeline)-_timeline.current_animation_position,0)
		_timeline.advance(minf(delta,left/_timeline.speed_scale))
		if token!=_revision or not is_active() or index!=plan_index:return
		if _timeline.current_animation_position>=plan.end_position(_timeline)-.000001:_complete_plan_camera()
	if token!=_revision or not is_active() or index!=plan_index:return
	if not _dialogue_started and _plan_elapsed>=plan.dialogue_delay:_start_plan_dialogue()
	if token!=_revision or not is_active() or index!=plan_index:return
	_update_camera(delta);_evaluate_plan()

func _evaluate_plan() -> void:
	if not is_active() or _montage_done:return
	var plan: Shot=_plans[plan_index]
	waiting_for_dialogue=_camera_done and _actor_time>=_plan_duration-.000001 and not _dialogue_done
	if plan.progression==Shot.Progression.MANUAL:return
	if _camera_done and _actor_time>=_plan_duration-.000001 and (plan.progression==Shot.Progression.CAMERA or _dialogue_done):_advance_plan()

func _advance_plan() -> void:
	if _advancing_plan:return
	_advancing_plan=true
	var token := _revision;var index := plan_index;var plan: Shot=_plans[index]
	# Camera-only/manual plans can leave before a delayed text cue. Keep that
	# cue on its own clock instead of silently losing it with the camera plan.
	if plan.dialogue and not _dialogue_started:
		var resource: Resource=plan.dialogue.duplicate(true)
		var key := str(_revision)+":"+str(index)
		resource.set_meta("cinematic_plan_token",key);_pending_dialogues[key]=index
		_delayed_dialogues.append({"left":maxf(plan.dialogue_delay-_plan_elapsed,0),"resource":resource})
		_dialogue_started=true
	plan_finished.emit(index,plan)
	if token!=_revision or not is_active():return
	if not plan.finished_event.is_empty():sequence.emit_event(plan.finished_event)
	_advancing_plan=false
	if token==_revision and is_active():_start_plan(index+1)

func next_plan() -> bool:
	if not uses_montage() or not is_active() or _montage_done or _advancing_plan or get_tree().paused:return false
	if not is_instance_valid(sequence) or not sequence.is_inside_tree() or not is_instance_valid(_timeline):cancel(&"sequence_removed");return false
	_complete_plan_camera(true);_advance_plan();return true

func _finish_montage_if_ready() -> void:
	if uses_montage() and is_active() and _montage_done and _pending_dialogues.is_empty() and not _dialogue.is_active():_finish(&"completed")

func montage_status() -> String:
	if not uses_montage() or not is_active():return "Arret"
	if _montage_done:return "Derniere image - attente de validation des dialogues"
	if _camera_done:
		if _actor_time<_plan_duration-.000001:return "Personnage en mouvement - camera maintenue"
		if _plans[plan_index].progression==Shot.Progression.MANUAL:return "Derniere image - passage manuel"
		return "Derniere image - attente du dialogue"
	return "Mouvement et dialogue independants"

func cancel(reason: StringName=&"cancelled") -> void:
	if is_active():_finish(reason)

func _finish(reason: StringName) -> void:
	_revision+=1;state=State.IDLE;waiting_for_dialogue=false;_stopping=false;set_process(false);set_process_unhandled_input(false)
	_actors.restore()
	var old_sequence := sequence;sequence=null
	if is_instance_valid(_timeline):
		if _timeline.animation_finished.is_connected(_animation_finished):_timeline.animation_finished.disconnect(_animation_finished)
		_timeline.stop(true);_timeline.callback_mode_process=_old_process_callback;_timeline.callback_mode_method=_old_method_callback
	_timeline=null
	if is_instance_valid(_dialogue):
		if _dialogue.is_active():_dialogue.cancel()
		_dialogue.release_reservation(self)
	var previous := _return_camera()
	if is_instance_valid(_game) and is_instance_valid(_game.psx_renderer) and previous:_game.psx_renderer.set_active_camera(previous)
	var viewport_camera: Camera3D=_previous_viewport_camera.get_ref() if _previous_viewport_camera else null
	if not is_instance_valid(viewport_camera) or not viewport_camera.is_inside_tree():viewport_camera=previous
	if viewport_camera:viewport_camera.make_current()
	if is_instance_valid(old_sequence):
		old_sequence._director=null
		for audio in old_sequence.find_children("*","AudioStreamPlayer",true,false):AudioRouting.stop(audio)
		for audio in old_sequence.find_children("*","AudioStreamPlayer3D",true,false):AudioRouting.stop(audio)
	_target=null;_previous_camera=null;_previous_viewport_camera=null
	_plans.clear();_pending_dialogues.clear();_delayed_dialogues.clear();plan_index=-1;_montage_done=false;_advancing_plan=false
	finished.emit(old_sequence if is_instance_valid(old_sequence) else null,reason)

func _exit_tree() -> void:
	if is_active():cancel(&"manager_removed")
