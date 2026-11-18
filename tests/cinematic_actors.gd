extends SceneTree
const Cue=preload("res://scripts/cinematics/cinematic_actor_clip.gd")
const Actors=preload("res://scripts/cinematics/cinematic_actors.gd")
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.psx_renderer.set_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var actor := Node3D.new();actor.name="ActorFixture";game.add_child(actor)
	var sk := Skeleton3D.new();sk.name="Skeleton";actor.add_child(sk);sk.add_bone("RootMotion");sk.add_bone("Body");sk.set_bone_parent(1,0)
	var player := AnimationPlayer.new();actor.add_child(player);player.root_motion_track=NodePath("Skeleton:RootMotion")
	var clip := Animation.new();clip.length=1
	var position := clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(position,NodePath("Skeleton:RootMotion"));clip.position_track_insert_key(position,0,Vector3.ZERO);clip.position_track_insert_key(position,1,Vector3.RIGHT)
	var rotation := clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(rotation,NodePath("Skeleton:Body"));clip.rotation_track_insert_key(rotation,0,Quaternion.IDENTITY);clip.rotation_track_insert_key(rotation,1,Quaternion(Vector3.UP,PI/2))
	var library := AnimationLibrary.new();library.add_animation(&"gesture",clip);player.add_animation_library(&"",library)
	var sequence := Sequence.new();sequence.name="ActorMontage";game.add_child(sequence)
	var camera := Camera3D.new();camera.name="CameraA";sequence.add_child(camera)
	var timeline := AnimationPlayer.new();timeline.name="Timeline";sequence.add_child(timeline)
	var move := Animation.new();move.length=.5;var camera_library := AnimationLibrary.new();camera_library.add_animation(&"cinematic",move);timeline.add_animation_library(&"",camera_library)
	var shot := Shot.new();shot.progression=Shot.Progression.MANUAL
	var cue := Cue.new();cue.actor_path=sequence.get_path_to(actor);cue.animation=&"gesture";cue.start_time=.2;shot.actors.append(cue);sequence.plans.append(shot)
	check(sequence.validation_error().is_empty(),"Character and camera timing validate together: "+sequence.validation_error())
	check(is_equal_approx(shot.duration(timeline),1.2),"A character cue extends the shot beyond the camera movement")
	var helper := Actors.new();helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot)
	helper.sample(.1);check(actor.position.is_zero_approx(),"Delayed actor cues wait for their own start")
	helper.sample(.7);check(actor.position.distance_to(Vector3(.5,0,0))<.001,"Authored root displacement is applied once at the cursor")
	check(sk.get_bone_pose_rotation(1).angle_to(Quaternion(Vector3.UP,PI/4))<.002,"Animation pose uses the same cursor as the camera")
	helper.sample(.3);helper.sample(.7);check(actor.position.distance_to(Vector3(.5,0,0))<.001,"Scrubbing backwards and forwards cannot accumulate root motion")
	helper.sample(.1);check(sk.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY),"Scrubbing before a delayed cue restores its pre-cue pose")
	helper.restore();check(actor.position.is_zero_approx() and sk.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY) and player.active,"Editor preview restores transforms, skeleton poses and original players")
	var second: Resource=cue.duplicate(false);second.start_time=1.2;shot.actors.append(second)
	helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot);helper.sample(1.7)
	check(actor.position.distance_to(Vector3(1.5,0,0))<.001,"Sequential cues on one actor compose their root movement deterministically: "+str(actor.position))
	helper.restore();shot.actors.remove_at(1)
	actor.scale=Vector3.ONE*2;helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot);helper.sample(.7)
	check(actor.position.distance_to(Vector3(1,0,0))<.001,"Actor scale is retained in authored root displacement")
	helper.restore();actor.scale=Vector3.ONE
	cue.loop=true;cue.duration=2.5;helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot);helper.sample(2.7)
	check(actor.position.distance_to(Vector3(2.5,0,0))<.001,"Root motion continues coherently over animation loops: "+str(actor.position))
	helper.restore();cue.loop=false;cue.duration=-1
	var before_process := actor.is_processing();var before_physics := actor.is_physics_processing()
	check(game.play_cinematic(sequence),"Runtime starts with actor ownership");game.cinematics.set_process(false)
	check(not player.active and not actor.is_processing() and not actor.is_physics_processing(),"Actor control is temporarily owned by the montage")
	game.cinematics._process(.8)
	check(game.cinematics.is_active() and game.cinematics._camera_done and actor.position.x>.55,"Camera can hold while the character continues its cue")
	game.cinematics.cancel()
	check(player.active and actor.is_processing()==before_process and actor.is_physics_processing()==before_physics and not game.player.controls_blocked,"Cancel restores actor processing and gameplay controls")
	# Actual Rigify character and a separately exported animation GLB.
	var p=game.player;var old_transform: Transform3D=p.transform
	cue.actor_path=sequence.get_path_to(p);cue.source=load("res://assets/character/animations/player_walk_forward_pistol.glb");cue.animation=&"player_walk_forward_pistol";cue.start_time=0;cue.duration=1
	check(cue.validation_error(sequence).is_empty(),"Player accepts a separately exported Blender animation")
	helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot);helper.sample(1)
	var distance: float=p.position.distance_to(old_transform.origin)
	check(absf(distance-1.4739027)<.015,"Actual player root distance matches Blender in the cinematic: "+str(distance))
	helper.restore();check(p.transform.is_equal_approx(old_transform),"Player preview never changes the saved map placement")
	cue.source=load("res://assets/character/animations/player_turn_in_place_left.glb");cue.animation=&"player_turn_in_place_left"
	helper.prepare(sequence,sequence.plans,true);helper.start_plan(shot);helper.sample(1)
	check(absf(wrapf(p.rotation.y-old_transform.basis.get_euler().y,-PI,PI)-deg_to_rad(43.10507))<.001,"Cinematic angular root motion follows the actual Rigify rest space")
	helper.restore()
	FileAccess.open("res://docs/cinematic-actors-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"player_root_distance":distance},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	game.queue_free();await process_frame;await create_timer(.15).timeout
	print("CINEMATIC_ACTORS_OK: timed full-body cues, shared cursor, root motion, looping, sequential clips, preview restoration and runtime ownership" if failures.is_empty() else "CINEMATIC_ACTORS_FAILED "+str(failures));quit(0 if failures.is_empty() else 1)
