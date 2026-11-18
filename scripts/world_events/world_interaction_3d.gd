@tool
class_name WorldInteraction3D
extends Marker3D
signal interacted(player: Node3D)
signal refused
@export var interaction_id: StringName
@export var interaction_label := "EXAMINER"
@export var interaction_offset := Vector3.ZERO
@export var enabled := true
@export var once := false
@export var requirements: Array[WorldCondition]=[]
@export var interaction_event: StringName
@export var actions: Array[WorldAction]=[]
func _enter_tree() -> void:add_to_group("world_interactions")
func _id() -> StringName:return interaction_id if not interaction_id.is_empty() else WorldEvents.stable_id(self)
func can_interact() -> bool:return enabled and is_visible_in_tree() and (not once or not WorldEvents.interaction_used(_id()))
func get_interaction_label() -> String:return interaction_label
func get_interaction_position() -> Vector3:return global_transform*interaction_offset
func interact(player: Node3D=null) -> bool:
	if Engine.is_editor_hint() or not can_interact():return false
	if not WorldCondition.all_match(requirements):refused.emit();return false
	if not _perform():refused.emit();return false
	WorldEvents.mark_interaction(_id())
	if not interaction_event.is_empty():WorldEvents.raise_event(interaction_event)
	WorldEvents.execute(actions,self);interacted.emit(player);return true
func trigger() -> bool:return interact()
func _perform() -> bool:return true

func refresh_render_geometry(branch: Node3D=null) -> void:
	if Engine.is_editor_hint() or not is_inside_tree(): return
	if not branch: branch=self
	var game := WorldEvents.game_for(self)
	if game and is_instance_valid(game.psx_renderer) and game.psx_renderer.native_geometry:
		game.psx_renderer.register_dynamic_geometry(branch)
