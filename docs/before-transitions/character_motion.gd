extends Node3D

const Materials = preload("res://scripts/psx_materials.gd")
@export var weapon_scene: PackedScene=preload("res://scenes/pistol.tscn")
@export_file("*.json") var weapon_mount_file := "res://assets/weapons/pistol_mount.json"
var mixer: AnimationPlayer
var model: Node3D
var weapon: Node3D
var hand_attachment: BoneAttachment3D
var weapon_socket: Node3D
var current := ""
var _action := ""
var clip_metadata: Dictionary={}

func _ready() -> void:
	model=get_node_or_null("cop")
	if not model:
		model=load("res://assets/character/cop_player.glb").instantiate()
		model.name="cop"
		add_child(model)
	mixer=AnimationPlayer.new()
	mixer.name="Motion"
	model.add_child(mixer)
	mixer.root_node=NodePath("..")
	mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	mixer.root_motion_track=NodePath("rig/Skeleton3D:RootMotion")
	var library := AnimationLibrary.new()
	_add_clip(library,"idle",model,true)
	# Existing prototype clips were converted once to the game skeleton.
	for clip in ["walk","backward","strafe_left","strafe_right","run","aim","aim_walk"]:
		var path := "res://assets/character/legacy_animations/%s.res" % clip
		if ResourceLoader.exists(path):library.add_animation(clip,load(path))
	# New exports are discovered without editing the controller.
	for file in DirAccess.get_files_at("res://assets/character/animations"):
		if not file.ends_with(".glb"):continue
		var path := "res://assets/character/animations/"+file
		var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.get_basename()+".json")) if FileAccess.file_exists(path.get_basename()+".json") else {}
		var authored_name: String=metadata.get("clip",file.get_basename())
		var alias: String=authored_name.trim_prefix("player_pistol_").trim_prefix("player_")
		alias={"walk_forward_pistol":"walk","walk_backward_pistol":"backward","walk_strafe_left_pistol":"strafe_left","walk_strafe_right_pistol":"strafe_right"}.get(alias,alias)
		var source: Node=load(path).instantiate()
		var loop: bool=metadata.get("loop",alias in ["idle","walk","run","aim","aim_walk","backward","strafe_left","strafe_right"])
		_add_clip(library,authored_name,source,loop)
		if alias!=authored_name:_add_clip(library,alias,source,loop)
		clip_metadata[authored_name]=metadata
		clip_metadata[alias]=metadata
		source.free()
	mixer.add_animation_library("",library)
	mixer.animation_finished.connect(func(clip: String):
		if clip==_action:_action="";current="")
	play("idle")
	mixer.advance(0)
	_attach_weapon()
	Materials.apply_character(model)

func _add_clip(library: AnimationLibrary,name: String,source: Node,loop: bool) -> void:
	var combined := Animation.new()
	combined.length=0
	for imported in source.find_children("*","AnimationPlayer",true,false):
		if imported==mixer:continue
		for clip in imported.get_animation_list():
			if clip=="RESET":continue
			var animation: Animation=imported.get_animation(clip)
			for track in animation.get_track_count():
				var node_path := String(animation.track_get_path(track)).get_slice(":",0)
				if node_path=="rig" or node_path.begins_with("rig/"):
					animation.copy_track(track,combined)
					combined.length=maxf(combined.length,animation.length)
		imported.active=false
	combined.loop_mode=Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if library.has_animation(name):library.remove_animation(name)
	library.add_animation(name,combined)

func _attach_weapon() -> void:
	if not weapon_scene:return
	var configuration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(weapon_mount_file))
	var body_skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	hand_attachment=BoneAttachment3D.new()
	hand_attachment.name="WeaponHandAttachment"
	hand_attachment.bone_name=configuration.bone
	body_skeleton.add_child(hand_attachment)
	weapon_socket=Node3D.new()
	weapon_socket.name="WeaponSocket"
	var rows: Array=configuration.transform_rows
	weapon_socket.transform=Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))
	hand_attachment.add_child(weapon_socket)
	weapon=weapon_scene.instantiate()
	weapon_socket.add_child(weapon)
	hand_attachment.on_skeleton_update()

func _process(_delta: float) -> void:
	# The custom renderer reads bone transforms before Godot's normal 3D draw pass.
	if hand_attachment:hand_attachment.on_skeleton_update()

func play(clip: String,speed := 1.0) -> void:
	if not mixer or not _action.is_empty():return
	mixer.speed_scale=speed
	if current!=clip:
		mixer.play(clip,.18)
		current=clip

func play_action(clip: String) -> bool:
	if not mixer.has_animation(clip):return false
	_action=clip
	current=clip
	mixer.play(clip,.06)
	return true

func uses_root_motion() -> bool:
	return clip_metadata.get(current,{}).get("root_motion",false)

func advance_motion(delta: float) -> Vector3:
	mixer.advance(delta)
	return mixer.get_root_motion_position()

func root_motion_direction() -> Vector3:
	var xyz: Array=clip_metadata.get(current,{}).get("root_motion_vector",[0,0,0])
	return Vector3(xyz[0],xyz[1],xyz[2]).normalized()
