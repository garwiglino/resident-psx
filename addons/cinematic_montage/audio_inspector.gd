@tool
extends EditorInspectorPlugin
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Property=preload("res://addons/cinematic_montage/audio_property.gd")
const SpeakerProperty=preload("res://addons/cinematic_montage/speaker_property.gd")
var undo: EditorUndoRedoManager

func _can_handle(object: Object) -> bool:return object is Line

func _parse_property(_object: Object,_type: int,name: String,_hint_type: int,_hint_string: String,_usage_flags: int,_wide: bool) -> bool:
	if name=="speaker":
		var editor := SpeakerProperty.new();editor.undo=undo
		add_property_editor(name,editor,false,"Locuteur");return true
	if name!="audio":return false
	add_property_editor(name,Property.new());return true
