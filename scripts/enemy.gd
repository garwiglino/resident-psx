@tool
class_name WorldEnemy3D
extends CharacterBody3D

const Materials = preload("res://scripts/psx_materials.gd")
signal died
@export_group("Ennemi")
@export var enemy_id: StringName
@export var enabled := true
@export_range(1,1000,1) var maximum_health := 3
@export_range(0,20,.05) var movement_speed := .58
@export_range(.1,100,.1) var detection_distance := 9.0
@export_range(1,100,1) var attack_damage := 18
@export_range(.1,10,.1) var attack_cooldown := 1.7
@export_group("Evenement de mort")
## L'etat enemy.<Enemy Id>.dead est memorise automatiquement.
@export var death_event: StringName
@export var death_actions: Array[WorldAction]=[]
var target: CharacterBody3D
var health := 3
var active := false
var attack_timer := 0.0
var visual: Node3D
var legs: Array[Node3D] = []
var phase := 0.0
var dead := false
var home := Vector3.ZERO

func _enter_tree() -> void:
	add_to_group("world_enemies");add_to_group("psx_dynamic_geometry")
func world_id() -> StringName:return enemy_id if not enemy_id.is_empty() else WorldEvents.stable_id(self)
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if enemy_id.is_empty():warnings.append("Renseigner Enemy Id pour referencer cet ennemi dans les conditions du monde.")
	elif is_inside_tree() and owner:
		for other in get_tree().get_nodes_in_group("world_enemies"):
			if other!=self and other.owner==owner and other.enemy_id==enemy_id:warnings.append("Enemy Id doit etre unique : un autre ennemi utilise cet identifiant.");break
	return warnings
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	collision_layer=4
	collision_mask=1|2|4
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius=.28
	shape.height=1.62
	collision.shape=shape
	collision.position.y=.81
	add_child(collision)
	visual=Node3D.new()
	add_child(visual)
	# Original low-poly silhouette: no duplication of the officer's identity.
	var skin := Materials.make(Color(.41,.44,.30))
	var cloth := Materials.make(Color(.32,.31,.22))
	var dark := Materials.make(Color(.12,.14,.13))
	part(visual,Vector3(0,1.05,0),Vector3(.48,.65,.26),cloth)
	var head := part(visual,Vector3(0,1.56,-.12),Vector3(.26,.32,.26),skin)
	head.rotation.z=.19
	part(visual,Vector3(-.07,1.6,-.258),Vector3(.04,.028,.01),dark)
	part(visual,Vector3(.065,1.6,-.258),Vector3(.04,.028,.01),dark)
	for side in [-1,1]:
		var leg := Node3D.new()
		leg.position=Vector3(side*.13,.78,0)
		visual.add_child(leg)
		part(leg,Vector3(0,-.32,0),Vector3(.18,.68,.2),dark)
		part(leg,Vector3(0,-.7,-.06),Vector3(.20,.13,.32),dark)
		legs.append(leg)
		var limb := part(visual,Vector3(side*.31,1.14,-.23),Vector3(.15,.58,.17),cloth)
		limb.rotation.x=-.9
		part(visual,Vector3(side*.31,.96,-.46),Vector3(.13,.18,.12),skin)
	home=position
	visual.rotation.x=-.08
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():return
	health=maximum_health
	WorldEvents.state_changed.connect(_world_changed);WorldEvents.run_reset.connect(_world_reset)
	_sync_world_state()

func _world_changed(key: StringName,_value: Variant) -> void:
	if key in [StringName("enemy.%s.dead" % world_id()),&"world.restored"]:_sync_world_state()
func _world_reset() -> void:call_deferred("_sync_world_state")
func _sync_world_state() -> void:
	if WorldEvents.enemy_dead(world_id()):
		var restored := not dead
		dead=true;health=0;collision_layer=0;collision_mask=0
		if restored:visual.rotation.z=1.5;visual.position.y=-.6
	elif dead:
		dead=false;health=maximum_health;active=false;collision_layer=4;collision_mask=1|2|4
		visual.position=Vector3.ZERO;visual.rotation=Vector3(-.08,0,0)

func part(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=size
	mesh.mesh=box
	mesh.material_override=mat
	mesh.position=pos
	parent.add_child(mesh)
	return mesh

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled:return
	if dead:
		visual.rotation.z=lerpf(visual.rotation.z,1.5,delta*3)
		visual.position.y=lerpf(visual.position.y,-.60,delta*3)
		return
	if not target or not target.enabled:
		return
	attack_timer=maxf(attack_timer-delta,0)
	var to_target := target.global_position-global_position
	var distance := to_target.length()
	if distance < detection_distance and not active:
		var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.25,target.global_position+Vector3.UP*1.25,1)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			active=true
	var desired := Vector3.ZERO
	if active:
		var flat := Vector3(to_target.x,0,to_target.z).normalized()
		rotation.y=lerp_angle(rotation.y,atan2(-flat.x,-flat.z),delta*3)
		if distance>.9:
			desired=flat*movement_speed
		elif attack_timer<=0:
			target.take_damage(attack_damage)
			attack_timer=attack_cooldown
	velocity.x=desired.x
	velocity.z=desired.z
	velocity.y=-.5 if is_on_floor() else velocity.y-18*delta
	move_and_slide()
	phase+=delta*(4 if desired.length()>.1 else 1)
	for i in legs.size():
		legs[i].rotation.x=sin(phase+i*PI)*(.25 if desired.length()>.1 else .01)
	visual.rotation.z=sin(phase*.5)*.05

func take_hit(_point: Vector3,damage: int=1) -> bool:
	if dead or damage<=0:
		return false
	health-=damage
	active=true
	visual.position.z=.08
	if health<=0:
		dead=true
		collision_layer=0
		collision_mask=0
		WorldEvents.mark_enemy_dead(world_id())
		if not death_event.is_empty():WorldEvents.raise_event(death_event)
		WorldEvents.execute(death_actions,self);died.emit()
	return true
