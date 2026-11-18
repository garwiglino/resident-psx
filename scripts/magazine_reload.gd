extends RefCounted
const MagazineBody=preload("res://scripts/magazine_body.gd")
## The original magazine bone rides a real rigid body until it is reinserted.
## A hand-held copy and pre-registered dropped meshes keep renderer data stable.
enum Phase { IDLE, IN_GUN, IN_HAND, INSERTED }
var weapon: Node3D
var skeleton: Skeleton3D
var body_skeleton: Skeleton3D
var carrier: CharacterBody3D
var bone := -1
var hand := -1
var home_pose := Transform3D.IDENTITY
var raw_pose := Transform3D.IDENTITY
var hand_mount := Transform3D.IDENTITY
var held: MeshInstance3D
var drops: Array[Dictionary]=[]
var phase := Phase.IDLE
var pending_drop := false
var pending_insert := false
var proxy := -1
var cursor := 0
var drop_frame := 6
var insert_frame := 17
var fps := 24.0
var drop_count := 0
var insert_count := 0

func setup(owner: Node3D,target: Skeleton3D) -> void:
	weapon=owner;skeleton=target;bone=skeleton.find_bone("b_mag")
	if bone<0:return
	home_pose=skeleton.get_bone_pose(bone);raw_pose=home_pose
	var source: MeshInstance3D=weapon.get_node("Model").find_child("mag",true,false)
	if not source or not source.skin:return
	var bind := Transform3D.IDENTITY
	for index in source.skin.get_bind_count():
		var bone_index := source.skin.get_bind_bone(index)
		if bone_index<0:bone_index=skeleton.find_bone(source.skin.get_bind_name(index))
		if bone_index==bone:bind=source.skin.get_bind_pose(index);break
	var mesh := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for vertex in vertices.size():
			vertices[vertex]=bind*vertices[vertex]
			normals[vertex]=(bind.basis*normals[vertex]).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(surface,source.get_active_material(surface))
	held=MeshInstance3D.new();held.name="ReloadMagazineLeftHand";held.mesh=mesh
	weapon.add_child(held);held.top_level=true;held.visible=false
	var bounds := mesh.get_aabb()
	for index in 4:
		var body := MagazineBody.new();body.name="DroppedMagazine%d" % index
		body.freeze=true;body.collision_layer=0;body.collision_mask=1;body.mass=.12
		body.contact_monitor=true;body.max_contacts_reported=4
		body.floor_contact.connect(weapon._play_magazine_floor)
		body.continuous_cd=true;body.linear_damp=.15;body.angular_damp=.35
		var material := PhysicsMaterial.new();material.friction=.6;material.bounce=.08
		body.physics_material_override=material
		weapon.add_child(body);body.top_level=true
		var shape := BoxShape3D.new();shape.size=bounds.size.max(Vector3.ONE*.003)
		var collider := CollisionShape3D.new();collider.shape=shape;collider.position=bounds.get_center()
		body.add_child(collider)
		var visual := MeshInstance3D.new();visual.name="Magazine";visual.mesh=mesh;visual.visible=false
		body.add_child(visual)
		drops.append({"body":body,"mesh":visual,"life":0.0,"scale":Vector3.ONE})

func configure_hand(target: Skeleton3D,controller: CharacterBody3D,mount_file: String) -> void:
	body_skeleton=target;carrier=controller;hand=target.find_bone("DEF-hand.L")
	if not FileAccess.file_exists(mount_file):return
	var configuration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(mount_file))
	var rows: Array=configuration.transform_rows
	hand_mount=Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))

func restore() -> void:
	if bone>=0:skeleton.set_bone_pose(bone,raw_pose)

func capture() -> void:
	if bone>=0:raw_pose=skeleton.get_bone_pose(bone)

func _release_proxy() -> void:
	if proxy<0:return
	drops[proxy].mesh.visible=drops[proxy].life>0
	proxy=-1

func start(rate: float) -> void:
	cancel(false);fps=rate;phase=Phase.IN_GUN

func cancel(clear_drops := false) -> void:
	_release_proxy()
	phase=Phase.IDLE;pending_drop=false;pending_insert=false
	if held:held.visible=false
	if bone>=0:
		raw_pose=home_pose;skeleton.set_bone_pose(bone,home_pose)
	if clear_drops:
		for drop in drops:
			drop.life=0;drop.mesh.visible=false;drop.body.disarm_impact();drop.body.freeze=true

func advance(time: float,delta: float) -> void:
	for drop in drops:
		if drop.life<=0:continue
		drop.life=maxf(drop.life-delta,0)
		if drop.life==0:drop.mesh.visible=false;drop.body.disarm_impact();drop.body.freeze=true
	if time<0 or phase==Phase.IDLE:return
	if phase==Phase.IN_GUN and time+.00000001>=(drop_frame-1)/fps:pending_drop=true
	if phase!=Phase.INSERTED and time+.00000001>=(insert_frame-1)/fps:pending_insert=true
	if phase==Phase.INSERTED:
		raw_pose=home_pose;restore()

func sync() -> void:
	if bone<0 or not held or not body_skeleton:return
	if pending_drop:
		pending_drop=false;drop_count+=1
		var drop := drops[cursor]
		var transform := skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		drop.body.freeze=true
		drop.scale=transform.basis.get_scale();transform.basis=transform.basis.orthonormalized()
		drop.body.global_transform=transform;drop.mesh.scale=drop.scale
		drop.body.linear_velocity=Vector3.ZERO;drop.body.angular_velocity=Vector3.ZERO
		drop.body.arm_impact()
		drop.life=8.0;drop.mesh.visible=false;drop.body.freeze=false;drop.body.sleeping=false
		drop.body.linear_velocity=(carrier.velocity if carrier else Vector3.ZERO)+Vector3(0,-.25,0)
		drop.body.angular_velocity=Vector3(1.4,.6,-.8)
		proxy=cursor;cursor=(cursor+1)%drops.size();phase=Phase.IN_HAND
		held.visible=true
	if pending_insert:
		pending_insert=false;insert_count+=1
		_release_proxy();held.visible=false;phase=Phase.INSERTED
		raw_pose=home_pose;restore()
	if phase==Phase.IN_HAND:
		if proxy>=0:
			var transform: Transform3D=drops[proxy].body.global_transform
			transform.basis=transform.basis.scaled_local(drops[proxy].scale)
			skeleton.set_bone_global_pose(bone,skeleton.global_transform.affine_inverse()*transform)
		held.global_transform=body_skeleton.global_transform*body_skeleton.get_bone_global_pose(hand)*hand_mount
