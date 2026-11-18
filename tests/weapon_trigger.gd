extends SceneTree
var failures: Array[String]=[]
var shots := 0
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func frames(count: int) -> void:
	for tick in count:await physics_frame
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player
	p.fired.connect(func(_origin: Vector3,_direction: Vector3):shots+=1)
	p.weapon_definition().shot_interval=.1;p.weapon_definition().reload_duration=.1
	p.ammo=5;p.reserve=0
	Input.action_press("aim");await frames(2)
	Input.action_press("fire");await frames(30)
	check(shots==1 and p.ammo==4,"Holding the Desert Eagle trigger fires only once")
	Input.action_release("fire");await frames(2)
	Input.action_press("fire");await frames(6)
	check(shots==2 and p.ammo==3,"Releasing and pressing again fires the next semi-auto shot")
	Input.action_release("fire");await frames(8)
	p.weapon_definition().automatic=true;p.ammo=6
	var before := shots
	Input.action_press("fire");await frames(40)
	check(shots-before==6 and p.ammo==0,"An automatic weapon keeps firing at its cadence until empty")
	await frames(20)
	check(shots-before==6 and p.reserve==0,"Holding an empty trigger creates no extra shots or negative ammo")
	Input.action_release("fire");await frames(2)
	p.weapon_definition().automatic=false;p.ammo=0;p.reserve=3
	Input.action_press("fire");await frames(20)
	check(p.ammo==0 and p.reserve==3 and p.weapon_inventory.action==p.WeaponInventory.Action.READY,"An empty trigger does not start a reload even with reserve ammo")
	var first_dry: AudioStream=p.sounds.empty.stream
	check(first_dry.is_class("AudioStreamPSX") and p._empty_sound_variants.has(first_dry),"Empty trigger plays a supplied deagle dry sound through the SPU path")
	await frames(ceili(p.motion.get_reload_duration()*60))
	check(p.ammo==0 and p.reserve==3 and shots-before==6,"Holding an empty semi-auto trigger never reloads or shoots automatically")
	Input.action_release("fire");await frames(2);Input.action_press("fire");await frames(2)
	check(p.sounds.empty.stream!=first_dry,"Successive dry clicks do not repeat the same variant")
	Input.action_release("fire");await frames(14)
	check(p.reload_weapon(),"Reload is still available explicitly with R")
	await frames(ceili(p.motion.get_reload_duration()*60)+2)
	check(p.ammo==3 and p.reserve==0 and shots-before==6,"Only explicit reload transfers ammunition; it never fires afterwards")
	Input.action_release("fire");Input.action_release("aim")
	FileAccess.open("res://docs/weapon-trigger-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"accepted_shots":shots,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.08).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("WEAPON_TRIGGER_OK: semi-auto input, automatic cadence, random SPU dry clicks without repetition, no automatic reload and explicit reload" if failures.is_empty() else "WEAPON_TRIGGER_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
