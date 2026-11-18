@tool
class_name MechanismAccess3D
extends Node
## Reusable physical opening state, independent of the placement camera and inventory.
signal transition_started(opening: bool)
signal transition_finished(opened: bool)
const Settings=preload("res://scripts/inventory/mechanism_access_settings.gd")
const Pose=preload("res://scripts/inventory/placement_pose.gd")
const TrackMask=preload("res://scripts/inventory/pose_track_mask.gd")
@export var state_id: StringName
## All NodePaths in these settings are relative to this component's parent.
@export var settings: MechanismAccessSettings=Settings.new()
var transition_allowed := Callable()
var inspecting := false:
	set(value):
		inspecting=value
		if not Engine.is_editor_hint():set_process(value or is_active())
var _open := false
var _goal := false
var _destination := false
var _moving := false
var _pending := false
var _pose: RefCounted
var _mask: RefCounted
var _revision := 0
func _enter_tree() -> void:
	if not Engine.is_editor_hint() and is_node_ready():call_deferred("restore_saved_state")
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;process_priority=90;set_process(false)
	if Engine.is_editor_hint():return
	get_parent().add_to_group("psx_dynamic_geometry")
	WorldEvents.event_raised.connect(_event);WorldEvents.run_reset.connect(_reset)
	restore_saved_state()
	var game := WorldEvents.game_for(self)
	if game and is_instance_valid(game.psx_renderer) and game.psx_renderer.native_geometry and get_parent() is Node3D:game.psx_renderer.register_dynamic_geometry(get_parent())
func get_mechanism_access() -> Node:return self
func access_configuration_error() -> String:return settings.validation_error(get_parent()) if settings else "Choisir les reglages d'ouverture."
func _id() -> StringName:return state_id if not state_id.is_empty() else WorldEvents.stable_id(get_parent())
func _key(field: String) -> StringName:return StringName("mechanism.%s.%s" % [_id(),field])
func is_open() -> bool:return _open
func is_active() -> bool:return _moving or _pending
func is_transitioning() -> bool:return _moving
func request_open() -> bool:return _request(true)
func request_close() -> bool:return _request(false)
func request_toggle() -> bool:return _request(not _goal if is_active() else not _open)
func _request(opened: bool) -> bool:
	if Engine.is_editor_hint() or not settings or not settings.enabled or not is_inside_tree():return false
	var error := access_configuration_error()
	if not error.is_empty():push_warning(error);return false
	_goal=opened;_pending=_moving or _goal!=_open
	WorldEvents.set_fact(_key("state_version"),1);WorldEvents.set_fact(_key("target_state"),"open" if opened else "closed")
	set_process(inspecting or is_active());_try_start();return true
func _try_start() -> void:
	if _moving or not _pending:return
	if transition_allowed.is_valid() and not transition_allowed.call(_goal):return
	_pending=false
	if _goal==_open:return
	_destination=_goal;_moving=true;_revision+=1
	_sample(_destination,false)
	WorldEvents.raise_event(StringName("mechanism.%s.%s" % [_id(),"opening" if _destination else "closing"]))
	transition_started.emit(_destination)
	if _moving and (not _pose or _pose.length<=0):_complete()
func _process(delta: float) -> void:
	if _moving:
		if not _pose or _pose.advance(delta):_complete()
	elif _pending:_try_start()
	else:reapply_pose()
	set_process(inspecting or is_active())
func _complete() -> void:
	_open=_destination;_moving=false;_pending=_goal!=_open
	WorldEvents.set_fact(_key("open"),_open)
	WorldEvents.raise_event(StringName("mechanism.%s.%s" % [_id(),"opened" if _open else "closed"]))
	var revision := _revision
	transition_finished.emit(_open)
	if revision==_revision:_try_start()
func reapply_pose() -> void:
	if _pose:_pose.advance(0)
func _sample(opened: bool,endpoint: bool) -> void:
	if _pose:_pose.finish(true);_pose=null
	if not settings or not settings.enabled:return
	var source := get_parent().get_node_or_null(settings.animation_player_path) as AnimationPlayer if not settings.animation_player_path.is_empty() else null
	if not source:return
	var clip: StringName=settings.opening_animation if opened else settings.closing_animation
	var backwards := clip.is_empty()
	if backwards:clip=settings.closing_animation if opened else settings.opening_animation
	if clip.is_empty() or not source.has_animation(clip):return
	_build_mask(source)
	_pose=Pose.new();_pose.begin(source,clip,self,settings.playback_speed,_track_allowed,backwards)
	if _pose.player:_pose.player.add_to_group("mechanism_pose_sampler")
	if endpoint:_pose.advance(_pose.length)
func _build_mask(source: AnimationPlayer) -> void:
	_mask=TrackMask.new();_mask.configure(get_parent(),source,[settings.opening_animation,settings.closing_animation],settings.animated_root_path,settings.bone_names)
func _track_allowed(source: AnimationPlayer,clip: Animation,track: int) -> bool:return _mask.allows(source,clip,track)
func restore_saved_state() -> void:
	if not is_inside_tree() or not get_parent():return
	_revision+=1;_moving=false;_pending=false
	if not settings:return
	var fallback := "open" if bool(WorldEvents.fact(_key("open"),settings.initially_open)) else "closed"
	var stored := String(WorldEvents.fact(_key("target_state"),fallback))
	_open=(stored if stored in ["open","closed"] else fallback)=="open";_goal=_open;_destination=_open
	if settings.enabled:
		WorldEvents.set_fact(_key("state_version"),1);WorldEvents.set_fact(_key("target_state"),"open" if _open else "closed");WorldEvents.set_fact(_key("open"),_open)
	_sample(_open,true);set_process(inspecting)
func settle_requested_state() -> void:
	# Hard interruption: retain the saved endpoint, without emitting completion events.
	restore_saved_state()
func _reset() -> void:
	_revision+=1;_moving=false;_pending=false
	if _pose:_pose.finish(true);_pose=null
	set_process(false);call_deferred("restore_saved_state")
func _event(id: StringName,_payload: Dictionary) -> void:
	if not settings or not settings.enabled:return
	if not settings.open_event.is_empty() and id==settings.open_event:request_open()
	elif not settings.close_event.is_empty() and id==settings.close_event:request_close()
func _exit_tree() -> void:
	if _pose:_pose.finish(true);_pose=null
func _get_configuration_warnings() -> PackedStringArray:
	var error := access_configuration_error() if is_inside_tree() else ""
	return PackedStringArray([error]) if not error.is_empty() else PackedStringArray()
