@tool
extends HBoxContainer
signal speaker_selected(name: String,apply_default: bool,intercom: bool)
const Catalogue=preload("res://assets/dialogue/speakers.tres")
var choice: OptionButton
var edit_catalogue: Button
var current_speaker := "":
	set(value):current_speaker=value;_refresh()
var editable := true:
	set(value):
		editable=value
		if choice:choice.disabled=not value
		if edit_catalogue:edit_catalogue.disabled=not value
func _init() -> void:
	choice=OptionButton.new();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choice.custom_minimum_size.x=130
	choice.tooltip_text="Locuteur. La selection applique son reglage intercom par defaut.";add_child(choice)
	choice.item_selected.connect(_selected)
	edit_catalogue=Button.new();edit_catalogue.text="...";edit_catalogue.tooltip_text="Modifier les locuteurs : nom, intercom par defaut et couleur haute de la fenetre.";add_child(edit_catalogue)
	edit_catalogue.pressed.connect(func():EditorInterface.edit_resource(Catalogue))
	_refresh()
func _enter_tree() -> void:
	if not Catalogue.changed.is_connected(_refresh):Catalogue.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	if not choice:return
	choice.clear()
	for item in Catalogue.choices(current_speaker):
		var caption: String=item.name
		if not item.known:caption=(caption if not caption.is_empty() else "Sans nom")+" (actuel)"
		choice.add_item(caption);var index := choice.item_count-1;choice.set_item_metadata(index,item)
		if item.name==current_speaker:choice.select(index)
func _selected(index: int) -> void:
	if not editable or index<0 or index>=choice.item_count:return
	var item: Dictionary=choice.get_item_metadata(index)
	current_speaker=item.name
	speaker_selected.emit(item.name,item.known,item.intercom)
