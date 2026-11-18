extends SceneTree
var failures: Array[String]=[]
var samples := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func wall(at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();var collider := CollisionShape3D.new();var box := BoxShape3D.new()
	box.size=size;collider.shape=box;body.add_child(collider);root.add_child(body);body.position=at
	return body
func inspect_camera(p: Node,label: String) -> void:
	var frame: Transform3D=p.get_render_camera_transform()
	var query := PhysicsShapeQueryParameters3D.new();var sphere := SphereShape3D.new()
	sphere.radius=p._camera_probe_radius()-.003;query.shape=sphere;query.collision_mask=1;query.exclude=[p.get_rid()]
	query.transform=Transform3D(Basis.IDENTITY,frame.origin)
	check(p.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Camera volume outside walls: "+label)
	var ray := PhysicsRayQueryParameters3D.create(p.camera_pivot.global_position,frame.origin,1,[p.get_rid()])
	check(p.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Unobstructed line to player: "+label)
	var h: float=p.camera.near*tan(deg_to_rad(p.camera.fov)*.5)
	for x in [-1,1]:
		for y in [-1,1]:
			var corner := frame*Vector3(x*h*4/3,y*h,-p.camera.near)
			ray.from=frame.origin;ray.to=corner
			check(p.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Near-plane corner outside walls: "+label)
	samples+=1
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var p=load("res://scenes/player.tscn").instantiate();root.add_child(p);p.set_process(false);p.set_physics_process(false)
	p.camera_rotation_lag=0;p.camera_translation_lag=0;p.rotation=Vector3.ZERO;p.pitch=0;p.reset_camera_follow()
	await physics_frame;await physics_frame
	var expected: Vector3=p.camera_pivot.global_transform*Vector3(p.arm.position.x,0,p.arm.spring_length)
	check(p.camera.global_position.distance_to(expected)<.00001,"Camera uses configured boom length immediately, with no old Blender offset")
	var walls: Array[StaticBody3D]=[]
	walls.append(wall(Vector3(0,1.5,.72),Vector3(4,3,.02)))
	walls.append(wall(Vector3(.55,1.5,0),Vector3(.02,3,4)))
	walls.append(wall(Vector3(-.55,1.5,0),Vector3(.02,3,4)))
	walls.append(wall(Vector3(0,1.5,-.55),Vector3(4,3,.02)))
	walls.append(wall(Vector3(0,-.03,0),Vector3(4,.02,4)))
	walls.append(wall(Vector3(0,2.05,0),Vector3(4,.02,4)))
	await physics_frame;await physics_frame
	p.update_camera_follow(1.0/60)
	check(p.camera.global_position.z<.72-p._camera_probe_radius()-.1,"Rear wall retracts camera in the current frame")
	for aiming in [false,true]:
		p.aiming=aiming;p._camera_aim_weight=1.0 if aiming else 0.0
		for side in [-1,1]:
			p.shoulder=side
			for yaw in range(0,360,30):
				for pitch in [-65,0,65]:
					p.look_yaw=deg_to_rad(yaw);p.pitch=deg_to_rad(pitch);p.update_camera_follow(.25)
					inspect_camera(p,"yaw %d pitch %d side %d aim %s" % [yaw,pitch,side,aiming])
	# Wider frustum, lag, lateral motion and maximum weapon shake.
	p.aiming=false;p._camera_aim_weight=0;p.camera_translation_lag=.1;p.camera_rotation_lag=.08
	p.camera_max_translation_lag=.22;p.camera_max_rotation_lag_degrees=12
	p.source_fov=80;p.camera.near=.12
	p._shot_shake_left=p.shot_shake_duration;p.shot_shake_strength=2
	for tick in 50:
		p.position.x=sin(tick*.2)*.18;p.look_yaw=tick*.2;p.pitch=sin(tick*.3)*.5
		p.update_camera_follow(1.0/60);inspect_camera(p,"lag/shake tick "+str(tick))
	# A user-set forward offset must still stop on the player's side of a wall.
	p.position=Vector3.ZERO;p.pitch=0;p.look_yaw=0;p.camera_rotation_lag=0;p.camera_translation_lag=0;p.update_camera_follow(.25)
	p.flashlight_offset=Vector3(0,0,1)
	var mount: Transform3D=p.get_flashlight_transform()
	check(mount.origin.z>-.50,"Flashlight origin cannot cross the wall even with a large inspector offset")
	check(mount.basis.z.dot(Vector3.FORWARD)>.999,"Retraction does not alter beam direction")
	p.flashlight_offset=Vector3(0,0,.03)
	mount=p.get_flashlight_transform()
	var anchor: Vector3=p.motion.body_skeleton.global_transform*p.motion._flashlight_anchor
	check(mount.origin.distance_to(anchor)<.045,"Default flashlight is only 3 cm from the chest")
	for body in walls:body.queue_free()
	p.queue_free();await process_frame
	FileAccess.open("res://docs/player-obstructions-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"camera_samples":samples,"failures":failures},"\t"))
	print("PLAYER_OBSTRUCTIONS_OK "+str(samples) if failures.is_empty() else "PLAYER_OBSTRUCTIONS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
