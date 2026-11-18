extends SceneTree
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Dialogue=preload("res://scripts/dialogue/dialogue_sequence.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene := Sequence.new();scene.name="CinematicSequence"
	scene.id=&"couloir_example"
	for data in [["CameraA",Vector3(1.8,1.6,7.4),Vector3(0,1.2,5.8),52.0],["CameraB",Vector3(.1,1.4,5.1),Vector3(.1,1.4,-1),46.0]]:
		var camera := Camera3D.new();camera.name=data[0];camera.fov=data[3];camera.near=.1;camera.far=55
		camera.transform=Transform3D(Basis.IDENTITY,data[1]).looking_at(data[2],Vector3.UP)
		scene.add_child(camera);camera.owner=scene
	var line_a := Line.new();line_a.speaker="POLICIERE";line_a.text="Un bruit... Au fond du couloir."
	var line_b := Line.new();line_b.speaker="POLICIERE";line_b.text="Restons sur nos gardes."
	for line in [line_a,line_b]:
		var dialogue := Dialogue.new();dialogue.lines.append(line);scene.dialogues.append(dialogue)
	var clip := Animation.new();clip.length=3.0
	var position_track := clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(position_track,NodePath("CameraA"))
	clip.position_track_insert_key(position_track,0,Vector3(1.8,1.6,7.4));clip.position_track_insert_key(position_track,1,Vector3(1.55,1.55,7.1))
	var second_track := clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(second_track,NodePath("CameraB"))
	clip.position_track_insert_key(second_track,0,Vector3(.1,1.4,5.1));clip.position_track_insert_key(second_track,1.1,Vector3(.1,1.4,5.1));clip.position_track_insert_key(second_track,3,Vector3(.1,1.4,4.6))
	var methods := clip.add_track(Animation.TYPE_METHOD);clip.track_set_path(methods,NodePath("."))
	for cue in [[0.0,"emit_event",[&"opening"]],[.3,"show_dialogue",[0,false]],[1.0,"cut_to",[NodePath("CameraB")]],[1.1,"show_dialogue",[1,true]],[2.7,"emit_event",[&"closing"]]]:
		clip.track_insert_key(methods,cue[0],{"method":cue[1],"args":cue[2]})
	var timeline := AnimationPlayer.new();timeline.name="Timeline";scene.add_child(timeline);timeline.owner=scene
	var library := AnimationLibrary.new();library.add_animation(&"cinematic",clip);timeline.add_animation_library(&"",library)
	var packed := PackedScene.new();assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/cinematics/cinematic_sequence.tscn")==OK)
	scene.free();print("CINEMATIC_EXAMPLE_BUILT: native timeline, two cameras and two dialogue cues");quit()
