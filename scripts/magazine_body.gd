extends RigidBody3D
signal floor_contact(position: Vector3)
var impact_armed := false
var floor_sound_played := false
var impact_position := Vector3.ZERO
var _generation := 0

func arm_impact() -> void:
	_generation+=1;impact_armed=true;floor_sound_played=false

func disarm_impact() -> void:
	_generation+=1;impact_armed=false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not impact_armed:return
	for index in state.get_contact_count():
		# Godot reports this body's contact normal and point in world space.
		if state.get_contact_local_normal(index).dot(Vector3.UP)<.5:continue
		impact_armed=false;floor_sound_played=true
		impact_position=state.get_contact_collider_position(index)
		_emit_contact.call_deferred(impact_position,_generation)
		break

func _emit_contact(position: Vector3,generation: int) -> void:
	if generation==_generation and not freeze:floor_contact.emit(position)
