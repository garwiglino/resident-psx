extends Node3D

const Materials = preload("res://scripts/psx_materials.gd")
var mixer: AnimationPlayer
var model: Node3D
var current := ""

func _ready() -> void:
	model=get_node_or_null("cop")
	if not model:
		model = load("res://assets/character/cop.glb").instantiate()
		add_child(model)
	Materials.apply_character(model)
	mixer = AnimationPlayer.new()
	mixer.name = "Motion"
	model.add_child(mixer)
	mixer.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	for clip in ["idle", "walk", "backward", "strafe_left", "strafe_right", "run", "aim", "aim_walk"]:
		var source: Node = model if clip == "idle" else load("res://assets/character/%s.glb" % clip).instantiate()
		var combined := Animation.new()
		combined.length = 0.0
		for imported in source.find_children("*", "AnimationPlayer", true, false):
			if imported==mixer:
				continue
			for anim_name in imported.get_animation_list():
				if anim_name == "RESET":
					continue
				var anim: Animation = imported.get_animation(anim_name)
				combined.length = maxf(combined.length, anim.length)
				for track in anim.get_track_count():
					anim.copy_track(track,combined)
			imported.active = false
		combined.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip,combined)
		if source != model:
			source.free()
	mixer.add_animation_library("",library)
	play("idle")
	mixer.advance(0)

func play(clip: String, speed := 1.0) -> void:
	if not mixer:
		return
	if current != clip:
		mixer.play(clip,0.18,speed)
		current = clip
	else:
		mixer.speed_scale = speed
