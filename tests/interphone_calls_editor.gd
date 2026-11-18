@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 12) -> void:
	for frame in count:await plugin.get_tree().process_frame
func fields(object: Object) -> Array[String]:
	var result: Array[String]=[]
	for property in object.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR:result.append(property.name)
	return result
func run(plugin: EditorPlugin) -> void:
	plugin.get_tree().create_timer(40).timeout.connect(func():push_error("Interphone editor timeout");plugin.get_tree().quit(2));await settle(plugin,80)
	var path := "res://scenes/interactions/interphone_interact.tscn";var scene_hash := FileAccess.get_sha256(path)
	while EditorInterface.get_resource_filesystem().is_scanning():await plugin.get_tree().process_frame
	EditorInterface.open_scene_from_path(path)
	var phone: Node3D
	for frame in 180:
		await plugin.get_tree().process_frame
		var candidate := EditorInterface.get_edited_scene_root()
		if candidate and candidate.scene_file_path==path:phone=candidate;break
		if frame==60:EditorInterface.open_scene_from_path(path)
	check(phone!=null,"Authored interphone opens in its own editor tab")
	if not phone:plugin.get_tree().quit(1);return
	await settle(plugin,12)
	var buttons: Array=phone.placement_targets();var first: Node3D=buttons[0];var second: Node3D=buttons[1]
	var camera_pose: Transform3D=phone.get_node("CameraFixe").transform;var button_pose: Transform3D=first.transform
	var root_fields := fields(phone);var button_fields := fields(first)
	check(phone.configuration_error().is_empty() and buttons.size()==12,"Authored interphone opens with its 12 original buttons")
	for property in ["ringing_sound","ringing_volume_db","hangup_sound","hangup_volume_db"]:check(property in root_fields,"Root inspector exposes "+property)
	for property in ["ringing_seconds","response","ringing_sound_override","dialogue","activation_sound","mechanism_volume_db"]:check(property in button_fields,"Button inspector exposes "+property)
	check("behaviour" not in button_fields and "after_interaction" not in button_fields,"Phone inspector hides incompatible generic switch/camera modes")
	var second_duration: float=second.ringing_seconds;first.ringing_seconds=7.3;first.response=1
	check(second.ringing_seconds==second_duration and "dialogue" not in fields(first),"Each button owns its duration and no-answer mode hides the unused dialogue")
	check(phone.get_node("CameraFixe").transform.is_equal_approx(camera_pose) and first.transform.is_equal_approx(button_pose),"Inspector edits leave model, camera and hit-zone transforms intact")
	check(phone.find_children("*","AudioStreamPlayer3D",true,false).is_empty(),"Editor inspection never starts a ringing cycle or creates an audio player")
	EditorInterface.inspect_object(first,"",true);await settle(plugin)
	check(EditorInterface.get_inspector().get_edited_object()==first,"Phone button settings open in the regular inspector")
	check(FileAccess.get_sha256(path)==scene_hash,"Editor validation does not save the artist's scene")
	var result := {"ok":failures.is_empty(),"errors":failures};FileAccess.open("res://docs/interphone-calls-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("INTERPHONE_EDITOR_OK " if failures.is_empty() else "INTERPHONE_EDITOR_FAILED ",JSON.stringify(result));plugin.get_tree().quit(0 if failures.is_empty() else 1)
