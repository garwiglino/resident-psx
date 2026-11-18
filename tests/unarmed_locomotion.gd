extends SceneTree

const TICK := 1.0/60.0
const ROOT_TRACK := NodePath("rig/Skeleton3D:RootMotion")
var errors: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func drive(player: Node,frames: int) -> void:
	for _frame in frames:
		player._physics_process(TICK)

func forearm_step(player: Node,frames: int) -> float:
	var skeleton: Skeleton3D=player.motion.body_skeleton
	var forearm := skeleton.find_bone("DEF-forearm.R")
	var previous := skeleton.get_bone_pose_rotation(forearm)
	var peak := 0.0
	for _frame in frames:
		drive(player,1)
		var current := skeleton.get_bone_pose_rotation(forearm)
		peak=maxf(peak,rad_to_deg(previous.angle_to(current)))
		previous=current
	return peak

func run() -> void:
	root.size=Vector2i(960,720)
	var inventory := root.get_node("InventoryState")
	inventory.persist_collection=false
	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.psx_renderer.set_process(false)
	var p: Node=game.player
	p.free_orbit_enabled=false
	p.set_process(false)
	p.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	game.start_game()
	await process_frame
	var start_transform: Transform3D=p.global_transform
	var m: Node=p.motion
	var lib: AnimationLibrary=m.mixer.get_animation_library("")
	var uid: String=inventory.active_weapon_uid()
	check(not uid.is_empty() and m.current=="idle","Authored armed loadout starts in the armed idle")
	check(root.get_visible_rect().size==Vector2(320,240),"The enlarged window keeps the 320x240 game canvas")

	for clip: String in m.WALK_DIRECTIONS+["run","idle","turn_in_place_left","turn_in_place_left_long"]:
		var animation: Animation=lib.get_animation("unarmed_"+clip)
		check(animation!=null and animation.find_track(ROOT_TRACK,Animation.TYPE_ROTATION_3D)>=0,"Exported root track exists: "+clip)
		check(animation.get_track_count()==m.body_skeleton.get_bone_count()*3,"All runtime joints have pose tracks: "+clip)
	var hand_path := NodePath("rig/Skeleton3D:DEF-hand.R")
	var unarmed_walk := lib.get_animation("unarmed_walk")
	var rotation_track := unarmed_walk.find_track(hand_path,Animation.TYPE_ROTATION_3D)
	check(unarmed_walk.rotation_track_interpolate(rotation_track,.1).angle_to(unarmed_walk.rotation_track_interpolate(rotation_track,.5))>.10,
		"Export preserves the unarmed arm movement")

	Input.action_press("forward")
	drive(p,27)
	var walk_time: float=m.mixer.current_animation_position
	var right_hand: int=m.body_skeleton.find_bone("DEF-hand.R")
	var before: Transform3D=m.body_skeleton.get_bone_pose(right_hand)
	var old_weapon: Node3D=m.weapon
	check(p.unequip_weapon(),"A live player can holster the equipped weapon")
	check(m.weapon==null and not old_weapon.is_visible_in_tree(),"Holster clears the active weapon and hides its visual")
	check(before.is_equal_approx(m.body_skeleton.get_bone_pose(right_hand)),"Holster does not snap the displayed hand pose")
	drive(p,1)
	check(m.current=="unarmed_walk" and m.current_clip_has_root_motion(),"The controller enters the unarmed forward walk with root motion")
	check(absf(m.mixer.current_animation_position-walk_time-TICK)<.001,"Holstering during a stride keeps its phase")
	check(absf(m.root_sampler.get_root_motion_position().length()-5.893679/240.0)<.002,"The stance blend keeps the new root displacement")
	check(forearm_step(p,15)<28.0,"Holstering blends the arm without a sudden twist")
	walk_time=m.mixer.current_animation_position
	check(p.equip_weapon(0),"The held weapon stays in inventory")
	drive(p,1)
	check(m.current=="walk" and absf(m.mixer.current_animation_position-walk_time-TICK)<.001,"Equipping blends back at the same stride phase")
	check(forearm_step(p,15)<28.0,"Equipping blends the arm without a sudden twist")
	Input.action_release("forward")
	drive(p,20)

	check(game.inventory_menu.open(),"The normal inventory opens")
	game.inventory_menu.show_context(uid,Vector2(180,80))
	var first_action: Button=game.inventory_menu._context.get_child(0).get_child(0)
	check(first_action.text=="RANGER","The equipped weapon exposes the holster action")
	first_action.pressed.emit()
	check(inventory.active_weapon_uid().is_empty(),"RANGER holsters through the inventory")
	game.inventory_menu.close()
	drive(p,16)
	check(m.current=="unarmed_idle" and m.turn_in_place.available(),"Unarmed idle and short turn use the authored stance")
	p.unarmed_turn_variant=1
	drive(p,1)
	check(is_equal_approx(m.turn_in_place.length,1.5),"The long unarmed turn is selectable in the inspector")
	var saved: Dictionary=inventory.snapshot()
	inventory.add_ammo(&"magnum",1)
	check(inventory.active_weapon_uid().is_empty(),"Changing ammo does not re-equip the holstered weapon")
	check(inventory.restore(saved) and inventory.active_weapon_uid().is_empty(),"A snapshot restores an empty active slot")

	Input.action_press("aim")
	drive(p,4)
	game.hud._process(0)
	check(not p.aiming and not game.hud.ammo_label.is_visible_in_tree(),"Unarmed aim does not show a weapon or crosshair")
	Input.action_release("aim")
	Input.action_press("forward")
	Input.action_press("sprint")
	drive(p,22)
	check(m.current=="unarmed_run" and m.current_clip_has_root_motion(),"Shift uses the exported unarmed run")
	check(m.root_sampler.get_root_motion_position().length()>.045,"Unarmed run advances its own stride")
	Input.action_release("sprint")
	Input.action_release("forward")
	Input.action_press("left")
	check(forearm_step(p,22)<28.0 and m.current=="unarmed_strafe_left","Run to strafe uses the same continuous unarmed blend")
	Input.action_press("back")
	check(forearm_step(p,22)<28.0 and m.current=="unarmed_backward_left","Strafe to a diagonal keeps a smooth arm transition")
	Input.action_release("back")
	Input.action_release("left")
	drive(p,18)

	p.health=23
	p.global_transform=start_transform
	p.reset_camera_follow()
	check(inventory.use(uid).ok,"The same inventory slot equips the gun again")
	Input.action_press("aim")
	drive(p,32)
	p.reset_camera_follow(false)
	game.hud._process(0)
	check(p.aiming and game.hud.ammo_label.is_visible_in_tree() and game.hud.weapon_label.text=="DESERT EAGLE","Aiming shows the equipped weapon and ammunition")
	check(game.hud.health_bar.is_visible_in_tree(),"Critical health remains visible with the weapon HUD")
	check(game.hud.ammo_label.text=="%02d / %02d" % [p.ammo,p.reserve],"HUD shows live magazine and reserve counts")
	game.psx_renderer.ambient_light_color=Color(.22,.22,.24)
	game.psx_renderer._process(0)
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(frame.get_size()==Vector2i(320,240),"The captured world, text, reticle and gauges share one 320x240 render target")
	frame.save_png("res://docs/unarmed-gameplay-hud.png")

	p.ammo=p.magazine_capacity-2
	check(p.reload_weapon(),"A partial magazine can reload")
	drive(p,14)
	game.hud._process(0)
	check(game.hud.weapon_label.text=="RECHARGE","Reload status keeps the ammunition panel visible")
	before=m.body_skeleton.get_bone_pose(right_hand)
	check(p.unequip_weapon() and p.reload_left==0,"Holstering cancels the reload timer")
	check(before.is_equal_approx(m.body_skeleton.get_bone_pose(right_hand)),"Holstering mid-reload keeps the displayed hand pose")
	drive(p,ceili(p.animation_blend_time/TICK)+2)
	check(m.aim_pose.reload_time<0.0 and m.aim_pose.weight==0.0,"Holstering fades the upper action all the way out")
	Input.action_release("aim")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free()
	await process_frame
	await create_timer(.08).timeout
	print("UNARMED_LOCOMOTION_OK" if errors.is_empty() else "UNARMED_LOCOMOTION_FAILED "+str(errors))
	quit(0 if errors.is_empty() else 1)
