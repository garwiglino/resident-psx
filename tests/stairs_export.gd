extends SceneTree
var failures: Array[String]=[]
var body: CharacterBody3D
var largest_up_step := 0.0
var largest_down_step := 0.0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func ground(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var solid := StaticBody3D.new();solid.position=at;parent.add_child(solid)
	var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=size;collision.shape=shape;solid.add_child(collision)
func step(direction: float) -> void:
	await physics_frame
	var before := body.position.y
	body.velocity=Vector3(0,-.1 if body.is_on_floor() else body.velocity.y-20.0/60.0,direction*2.5)
	body.move_and_slide()
	largest_up_step=maxf(largest_up_step,body.position.y-before)
	largest_down_step=maxf(largest_down_step,before-body.position.y)
func run() -> void:
	var stage := Node3D.new();root.add_child(stage)
	var scene: PackedScene=load("res://assets/props/stairs_01/stairs_01.tscn");var stairs: Node3D=scene.instantiate();stage.add_child(stairs)
	check(stairs.get_meta("psx_asset_type")=="stairs","Staircase exports as a freely placeable scene")
	check(stairs.find_children("*","MeshInstance3D",true,false).size()==1,"Only the visible staircase is rendered")
	var collision: CollisionShape3D=stairs.get_node("Collision/CollisionShape3D")
	check(collision.shape is ConcavePolygonShape3D and collision.shape.get_faces().size()==60,"Physics uses the actual 20-triangle stairs_collision ramp")
	check(stairs.get_node("Collision").get_meta("source_mesh")=="stairs_collision","The collision source remains identifiable in Godot")
	var visual: MeshInstance3D=stairs.get_node("Modele");var bounds := visual.mesh.get_aabb()
	check(absf(bounds.end.y-3)<.001 and bounds.position.y<-.29,"Automatic pivot keeps the original stair/collider alignment with the entry at ground height")
	# Use the actual player's capsule and floor settings without animation or input.
	var prototype: CharacterBody3D=load("res://scenes/player.tscn").instantiate()
	body=CharacterBody3D.new();body.collision_layer=2;body.collision_mask=1;body.floor_snap_length=prototype.floor_snap_length;body.floor_max_angle=prototype.floor_max_angle
	var capsule: CollisionShape3D=prototype.get_node("CollisionShape3D").duplicate();body.add_child(capsule);prototype.free()
	stage.add_child(body);body.position=Vector3(0,.12,1.2)
	ground(stage,Vector3(0,-.1,2),Vector3(8,.2,4))
	ground(stage,Vector3(0,2.9,-5),Vector3(8,.2,2))
	for frame in 30:await step(0)
	check(body.is_on_floor(),"Player capsule settles on the lower floor")
	largest_up_step=0;largest_down_step=0
	for frame in 420:
		await step(-1)
		if body.position.z< -4.8:break
	check(body.position.z< -4.8 and body.position.y>2.95 and body.is_on_floor(),"Player climbs the entire ramp and reaches the upper landing")
	check(largest_up_step<.08,"Climbing follows a smooth slope instead of jumping up the rendered treads")
	for frame in 420:
		await step(1)
		if body.position.z>1:break
	check(body.position.z>1 and body.position.y<.05 and body.is_on_floor(),"Player descends the ramp and returns to the lower floor")
	check(largest_down_step<.08,"Floor snap keeps the descent smooth")
	stage.queue_free();await process_frame;await process_frame
	var result := {"ok":failures.is_empty(),"errors":failures,"largest_up_step_m":largest_up_step,"largest_down_step_m":largest_down_step}
	FileAccess.open("res://docs/stairs-game-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("STAIRS_GAME_OK " if failures.is_empty() else "STAIRS_GAME_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
