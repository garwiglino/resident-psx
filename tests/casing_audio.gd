extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func place_case(weapon: Node,position: Vector3,velocity: Vector3) -> void:
	weapon.deactivate()
	var casing: Dictionary=weapon.casings[0]
	casing.transform=Transform3D(Basis.IDENTITY,position)
	casing.velocity=velocity;casing.spin=Vector3.ZERO
	casing.time_left=1.2;casing.attached=false;casing.bounces=0;casing.floor_sound_played=false
func run() -> void:
	seed(403)
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	var weapon=p.motion.weapon
	await physics_frame;await physics_frame
	check(weapon._floor_sounds.size()==3,"All three supplied bullet_floor sounds are available")
	for sound in weapon._floor_sounds:check(sound.is_class("AudioStreamPSX"),"Floor impacts retain automatic PS1 audio processing")
	var pool_ids: Array=[]
	for audio in weapon._floor_players:pool_ids.append(audio.get_instance_id())
	place_case(weapon,Vector3(0,1,2),Vector3.ZERO)
	var cursor: int=weapon._floor_cursor
	weapon.advance_animation(.01)
	check(weapon._floor_cursor==cursor,"Airborne casing makes no floor sound")
	var variants: Dictionary={}
	var previous := -1
	for trial in 12:
		place_case(weapon,Vector3(0,.12,2),Vector3(0,-2,0))
		cursor=weapon._floor_cursor
		for tick in 6:weapon.advance_animation(1.0/60)
		check(weapon.casings[0].floor_sound_played,"Actual floor raycast triggers the casing impact")
		check(weapon._floor_cursor==(cursor+1)%4,"One casing plays exactly one sample on its first floor contact")
		var variant: int=weapon._floor_variant
		check(variant>=0 and variant<3 and variant!=previous,"Random selection stays valid without immediate repeats")
		variants[variant]=true;previous=variant
		var audio: AudioStreamPlayer3D=weapon._floor_players[cursor]
		check(load("res://scripts/audio/psx_audio_routing.gd").source_of(audio.stream)==weapon._floor_sounds[variant],"Chosen sound is assigned to the impact voice")
		check(audio.global_position.distance_to(Vector3(0,0,2))<.005,"Sound comes from the actual ground contact")
		var audio_position := audio.global_position
		p.position.x+=.2
		check(audio.global_position.is_equal_approx(audio_position),"Impact sound stays on the floor when the character moves")
		p.position.x-=.2
		cursor=weapon._floor_cursor
		for tick in 80:weapon.advance_animation(1.0/120)
		check(weapon._floor_cursor==cursor,"Bounces and resting contact do not replay the recorded impact")
	check(variants.size()==3,"Repeated floor impacts use all three supplied variations")
	for index in weapon._floor_players.size():check(weapon._floor_players[index].get_instance_id()==pool_ids[index],"Impacts reuse the preallocated sound pool")
	var wall := StaticBody3D.new();var collider := CollisionShape3D.new();var shape := BoxShape3D.new()
	shape.size=Vector3(.1,1,1);collider.shape=shape;wall.add_child(collider);wall.position=Vector3(.3,.4,2);root.add_child(wall)
	await physics_frame;await physics_frame
	place_case(weapon,Vector3(0,.35,2),Vector3(6,0,0));cursor=weapon._floor_cursor
	weapon.advance_animation(.05)
	check(weapon.casings[0].bounces==1,"Wall collision was exercised")
	check(weapon._floor_cursor==cursor and not weapon.casings[0].floor_sound_played,"Wall hit does not use the floor sample or consume its trigger")
	for tick in 60:weapon.advance_animation(1.0/120)
	check(weapon.casings[0].floor_sound_played and weapon._floor_cursor==(cursor+1)%4,"Floor contact after a wall bounce still produces its one sound")
	weapon.deactivate();weapon.fire();weapon.advance_animation(weapon.ejection_delay+.001);weapon.sync_after_attachment()
	check(not weapon.casings[weapon._attached_case].floor_sound_played,"Reusing a casing slot resets its floor-sound trigger")
	weapon.deactivate();cursor=weapon._floor_cursor
	weapon.advance_animation(.5)
	check(weapon._floor_cursor==cursor,"Holstered or expired casings produce no new impact")
	FileAccess.open("res://docs/casing-audio-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"variants":variants.keys(),"audio_pool_size":pool_ids.size(),"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.08).timeout;wall.queue_free();game.queue_free();await process_frame;await create_timer(.08).timeout
	print("CASING_AUDIO_OK: actual floor/wall contacts, three random PS1 samples, no repeats, one sound per casing, fixed world position, bounded voice pool and reuse" if failures.is_empty() else "CASING_AUDIO_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
