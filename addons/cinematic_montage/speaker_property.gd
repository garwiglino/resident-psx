@tool
extends EditorProperty
const Picker=preload("res://addons/cinematic_montage/speaker_picker.gd")
var picker: HBoxContainer
var undo: EditorUndoRedoManager
func _init() -> void:
	picker=Picker.new();add_child(picker);add_focusable(picker.choice)
	picker.speaker_selected.connect(_selected)
func _selected(name: String,apply_default: bool,intercom: bool) -> void:
	if is_read_only():return
	if not apply_default:emit_changed("speaker",name);return
	var object := get_edited_object()
	if not object or not undo:return
	if object.speaker==name and object.is_intercom==intercom:return
	# Godot 4.7's native multiple_properties_changed receiver expects an extra
	# argument. Keep the two fields in one explicit, non-merged editor action.
	undo.create_action("Choisir le locuteur",UndoRedo.MERGE_DISABLE,object)
	undo.add_do_property(object,"speaker",name);undo.add_do_property(object,"is_intercom",intercom)
	undo.add_undo_property(object,"speaker",object.speaker);undo.add_undo_property(object,"is_intercom",object.is_intercom)
	undo.add_do_method(object,"notify_property_list_changed");undo.add_undo_method(object,"notify_property_list_changed")
	undo.commit_action()
func _update_property() -> void:
	var object := get_edited_object()
	if object:picker.current_speaker=object.get("speaker")
	picker.editable=not is_read_only()
func _set_read_only(value: bool) -> void:
	if picker:picker.editable=not value
