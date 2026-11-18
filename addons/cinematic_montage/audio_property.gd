@tool
extends EditorProperty
const Picker=preload("res://addons/cinematic_montage/audio_picker.gd")
var picker: HBoxContainer

func _init() -> void:
	picker=Picker.new();add_child(picker);add_focusable(picker.target)
	picker.resource_changed.connect(func(stream: AudioStream):emit_changed(get_edited_property(),stream))
	picker.status_message.connect(func(message: String):tooltip_text=message)

func _update_property() -> void:
	var object := get_edited_object()
	if object:picker.edited_resource=object.get(get_edited_property())
	picker.editable=not is_read_only()

func _set_read_only(value: bool) -> void:
	if picker:picker.editable=not value
