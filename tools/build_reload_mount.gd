extends SceneTree
const Assets = preload("res://scripts/animation_assets.gd")
func _initialize() -> void:call_deferred("run")
func transform_from_rows(rows: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))
func run() -> void:
	var body=load("res://assets/character/animations/player_pistol_reload.glb").instantiate()
	var gun=load("res://assets/weapons/pistol.glb").instantiate()
	root.add_child(body);root.add_child(gun)
	var sk: Skeleton3D=body.get_node("rig/Skeleton3D")
	var gs: Skeleton3D=gun.find_child("Skeleton3D",true,false)
	var player: AnimationPlayer=body.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/animations/player_pistol_reload.json"))
	var time := 16.0/float(metadata.fps)
	player.play("player_pistol_reload",0);player.seek(time,true)
	for imported in gun.find_children("*","AnimationPlayer",true,false):imported.active=false
	var mechanical := AnimationPlayer.new();gun.add_child(mechanical);mechanical.root_node=NodePath("..")
	mechanical.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var animation := Animation.new()
	for source in Assets.read("res://assets/weapons/animations/pistol_reload.glb"):
		animation.length=maxf(animation.length,source.length)
		for track in source.get_track_count():source.copy_track(track,animation)
	var library := AnimationLibrary.new();library.add_animation("reload",animation);mechanical.add_animation_library("",library)
	mechanical.play("reload",0);mechanical.seek(time,true)
	var configuration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/pistol_mount.json"))
	gun.global_transform=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))*transform_from_rows(configuration.transform_rows)
	var left := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("DEF-hand.L"))
	var slot := gs.global_transform*gs.get_bone_global_pose(gs.find_bone("b_mag"))
	var mount := left.affine_inverse()*slot
	var source: MeshInstance3D=gun.find_child("mag",true,false)
	var center := source.mesh.get_aabb().get_center()
	for index in source.skin.get_bind_count():
		var bone := source.skin.get_bind_bone(index)
		if bone<0:bone=gs.find_bone(source.skin.get_bind_name(index))
		if bone==gs.find_bone("b_mag"):center=source.skin.get_bind_pose(index)*center;break
	var rows: Array=[]
	for row in 3:rows.append([mount.basis.x[row],mount.basis.y[row],mount.basis.z[row],mount.origin[row]])
	rows.append([0,0,0,1])
	var report := {"bone":"DEF-hand.L","magazine_bone":"b_mag","reference_frame":17,"drop_frame":6,"fps":metadata.fps,
	 "source":metadata.source,"source_sha256":metadata.source_sha256,"transform_rows":rows,
	 "palm_to_magazine_center_m":left.origin.distance_to(slot*center),"insertion_error_m":(left*mount).origin.distance_to(slot.origin)}
	FileAccess.open("res://assets/weapons/reload_magazine_mount.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RELOAD_MOUNT_OK ",JSON.stringify(report))
	body.queue_free();gun.queue_free();await process_frame
	quit()
