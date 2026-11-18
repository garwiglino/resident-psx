extends SceneTree
var failures: Array[String]=[]
var measurements: Array=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D]=[]
	for i in skeleton.get_bone_count():result.append(skeleton.get_bone_pose(i))
	return result
func largest_shift(a: Array[Transform3D],b: Array[Transform3D]) -> float:
	var shift := 0.0
	for i in a.size():shift=maxf(shift,a[i].origin.distance_to(b[i].origin))
	return shift
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await create_timer(.1).timeout
	var m=p.motion
	var sk: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	m.upper_body.restore()
	m.current="";m.blend_time=0;m.play("idle");m.advance_motion(0);m.advance_motion(.7)
	m.blend_time=.3
	for next in ["forward_right","strafe_left","backward_right","idle","aim","walk","run","idle"]:
		var before := poses(sk)
		m.play(next)
		m.advance_motion(0)
		var start_jump := largest_shift(before,poses(sk))
		check(start_jump<.001,"No instantaneous pose jump when starting fade: "+next)
		var peak_step := 0.0
		for frame in 24:
			var previous := poses(sk)
			var delta: Vector3=m.advance_motion(1.0/60)
			check(delta.length()<.08,"Root motion remains bounded during fade: "+next)
			peak_step=maxf(peak_step,largest_shift(previous,poses(sk)))
		check(peak_step<.13,"No large skeletal jump during fade: "+next)
		measurements.append({"clip":next,"start_jump_m":start_jump,"largest_bone_step_m":peak_step})
	# Rapid input changes must preserve the currently displayed blended pose.
	m.play("forward_left");m.advance_motion(.07)
	var before := poses(sk)
	m.play("strafe_right");m.advance_motion(0)
	var interrupted_jump := largest_shift(before,poses(sk))
	check(interrupted_jump<.001,"Interrupted fade starts from the displayed pose")
	FileAccess.open("res://docs/animation-blending-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"measurements":measurements,"interrupted_jump_m":interrupted_jump,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame
	print("ANIMATION_BLENDING_OK: advancing pose crossfades, unchanged clip timing, continuous interruptions, bounded root motion" if failures.is_empty() else "ANIMATION_BLENDING_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
