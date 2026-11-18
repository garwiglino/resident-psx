@tool
extends EditorPlugin
var importer: EditorImportPlugin
var mix_button: Button
var _mix_profile: Resource
var _mix_signature: Dictionary={}
var _mix_menu_installed := false
func _open_mix() -> void:
	if not _mix_profile:_mix_profile=load("res://assets/audio/mixage.tres")
	EditorInterface.inspect_object(_mix_profile)
func _ensure_mix_button() -> void:
	if not _mix_menu_installed:
		add_tool_menu_item("Mixage audio",_open_mix);_mix_menu_installed=true
	if is_instance_valid(mix_button):return
	_mix_profile=load("res://assets/audio/mixage.tres")
	mix_button=Button.new();mix_button.text="Mixage audio";mix_button.tooltip_text="Volumes des pas, armes, voix, ambiances, musiques et interface."
	mix_button.pressed.connect(_open_mix)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,mix_button)
func _enter_tree() -> void:
	importer=preload("res://addons/psx_audio/importer.gd").new()
	add_import_plugin(importer)
	_ensure_mix_button()
	if "--audio-mix-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_audio_mix_test")
func _process(_delta: float) -> void:
	_ensure_mix_button()
	if _mix_profile and _mix_signature!=_mix_profile.volumes():
		load("res://scripts/audio/psx_audio_routing.gd").setup()
		_mix_signature=_mix_profile.volumes();_mix_profile.apply()
func _run_audio_mix_test() -> void:
	await load("res://tests/audio_mix_editor.gd").new().run(self)
func _exit_tree() -> void:
	if _mix_menu_installed:remove_tool_menu_item("Mixage audio");_mix_menu_installed=false
	if is_instance_valid(mix_button):remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,mix_button);mix_button.free()
	remove_import_plugin(importer)
	importer=null

func _apply_changes() -> void:
	# Older open scenes may still hold inline samples from before this update.
	# Only inspect stored script fields; native level mesh buffers stay untouched.
	var scene := EditorInterface.get_edited_scene_root()
	if not scene:return
	var visited: Dictionary={}
	for node in [scene]+scene.find_children("*","Node",true,false):
		if not node.get_script():continue
		for property in node.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0 or (int(property.usage)&PROPERTY_USAGE_STORAGE)==0:continue
			if int(property.type) in [TYPE_OBJECT,TYPE_ARRAY,TYPE_DICTIONARY]:_prepare_dialogue_resources(node.get(property.name),visited)

func _prepare_dialogue_resources(value: Variant,visited: Dictionary) -> void:
	if value is Array:
		for item in value:_prepare_dialogue_resources(item,visited)
	elif value is Dictionary:
		for item in value.values():_prepare_dialogue_resources(item,visited)
	elif value is Resource and value.get_script():
		if visited.has(value.get_instance_id()):return
		visited[value.get_instance_id()]=true
		if value is DialogueLine:value.prepare_external_audio();return
		for property in value.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0 or (int(property.usage)&PROPERTY_USAGE_STORAGE)==0:continue
			if int(property.type) in [TYPE_OBJECT,TYPE_ARRAY,TYPE_DICTIONARY]:_prepare_dialogue_resources(value.get(property.name),visited)
