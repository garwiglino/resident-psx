@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run(plugin: EditorPlugin) -> void:
	check(Engine.is_editor_hint(),"Radio preparation runs in the actual editor")
	var source: AudioStream=load("res://assets/audio/dialogs/1/10_Chapter_1.wav")
	var line: DialogueLine=load("res://scripts/dialogue/dialogue_line.gd").new();line.text="Voix en cache.";line.audio=source;line.is_intercom=true
	var prepared: AudioStream=line.intercom_audio
	check(prepared!=null and prepared.is_class("AudioStreamPSX") and prepared.resource_path.begins_with("res://assets/audio/generated/intercom/") and prepared.resource_path.ends_with(".res"),"New WAV assignments prepare an external binary SPU sample")
	if not prepared:plugin.get_tree().quit(1);return
	var bytes: PackedByteArray=prepared.get("adpcm_left");var duration: float=prepared.get_length()
	var second: DialogueLine=load("res://scripts/dialogue/dialogue_line.gd").new();second.audio=source;second.is_intercom=true
	check(second.intercom_audio==prepared,"Replies using the same WAV share the generated file")
	var copy: DialogueLine=line.duplicate(true)
	check(copy.intercom_audio.resource_path==prepared.resource_path,"Duplicating a dialogue preserves the external sample reference")
	var sequence: DialogueSequence=load("res://scripts/dialogue/dialogue_sequence.gd").new();sequence.lines.append(line)
	var root := Node3D.new();root.name="AudioCacheFixture";plugin.add_child(root)
	var trigger=load("res://scenes/dialogue/dialogue_trigger.tscn").instantiate();trigger.sequence=sequence;root.add_child(trigger);trigger.owner=root
	await plugin.get_tree().process_frame
	var packed := PackedScene.new();check(packed.pack(root)==OK,"Fixture packs normally")
	var target := "res://exports/editor_tests/intercom_external_fixture.tscn"
	check(ResourceSaver.save(packed,target)==OK,"Text scene saves with the generated voice")
	var text := FileAccess.get_file_as_string(target)
	check(not text.contains('sub_resource type="AudioStreamPSX"') and not text.contains("PackedByteArray"),"Saving does not embed radio sample bytes")
	check(text.contains("res://assets/audio/generated/intercom/"),"Text scene references the external binary asset")
	var dependency_found := false
	for dependency in ResourceLoader.get_dependencies(target):
		if prepared.resource_path in dependency:dependency_found=true
	check(dependency_found,"Godot tracks the binary voice as an export dependency")
	var reopened: PackedScene=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var instance := reopened.instantiate();plugin.add_child(instance)
	var reopened_line: DialogueLine=instance.get_node("DialogueTrigger").sequence.lines[0]
	check(reopened_line.intercom_audio.resource_path==prepared.resource_path and reopened_line.intercom_audio.get("adpcm_left")==bytes and is_equal_approx(reopened_line.intercom_audio.get_length(),duration),"Save/reopen retains the exact voice data and timing")
	FileAccess.open("res://docs/intercom-cache-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"scene_bytes":text.to_utf8_buffer().size(),"binary_voice":prepared.resource_path,"duration":duration,"dependency_found":dependency_found},"\t"))
	root.queue_free();instance.queue_free();await plugin.get_tree().process_frame
	for step in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning():break
		await plugin.get_tree().process_frame
	print("INTERCOM_CACHE_EDITOR_OK: new radio voices externalized, reused, duplicated, exported and reopened without inline sample data" if failures.is_empty() else "INTERCOM_CACHE_EDITOR_FAILED "+str(failures))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
