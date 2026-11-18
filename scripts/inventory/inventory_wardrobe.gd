extends Control

const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Preview=preload("res://scripts/inventory/wardrobe_preview.gd")
const MenuTheme=preload("res://scripts/ui/menu_theme.gd")
const SLOT_NAMES := ["Chaussures","Pantalon","Haut","Tenue complete","Doudoune"]

signal edited
var game: Node
var clothing: CharacterClothing
var preview: TextureRect
var _slot_index := 0
var _categories: Array[Button]=[]
var _pieces: Array[ClothingItem]=[]
var _colors: Array[StringName]=[]
var _piece_label: Label
var _color_label: Label
var _piece_buttons: Array[Button]=[]
var _color_buttons: Array[Button]=[]

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(game):
		clothing=game.player.get_node_or_null("Tenue") as CharacterClothing
	if clothing:clothing.changed.connect(_wardrobe_changed)
	var group := ButtonGroup.new()
	for index in SLOT_NAMES.size():
		var category := _button(SLOT_NAMES[index],Rect2(10,45+index*18,172,17),_select_slot.bind(index))
		category.alignment=HORIZONTAL_ALIGNMENT_LEFT
		category.toggle_mode=true
		category.button_group=group
		_categories.append(category)
	_label("Vetement",Rect2(10,137,172,13)).theme_type_variation=&"MenuHint"
	_piece_label=_stepper(151,_piece_buttons,_cycle_piece,"Vetement")
	_label("Couleur",Rect2(10,184,172,13)).theme_type_variation=&"MenuHint"
	_color_label=_stepper(198,_color_buttons,_cycle_color,"Couleur")
	_color_label.theme_type_variation=&"MenuCaption"

	var frame := Panel.new()
	frame.theme_type_variation=&"MenuInset"
	frame.position=Vector2(192,45)
	frame.size=Vector2(118,183)
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	preview=Preview.new()
	preview.position=Vector2.ONE
	preview.size=Vector2(116,164)
	frame.add_child(preview)
	var rule := ColorRect.new()
	rule.position=Vector2(1,165)
	rule.size=Vector2(116,1)
	rule.color=MenuTheme.LINE
	rule.mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame.add_child(rule)
	var hint := _label("Clic + glisser",Rect2(197,212,108,14))
	hint.theme_type_variation=&"MenuHint"
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	hide()

func set_active(active: bool) -> void:
	visible=active
	if not active:
		preview.suspend()
		return
	_refresh()
	if clothing:preview.show_outfit(game,clothing)
	_categories[_slot_index].grab_focus()

func handle_navigation(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_UP,KEY_DOWN:
			_select_slot(posmod(_slot_index+(-1 if event.keycode==KEY_UP else 1),SLOT_NAMES.size()))
			_categories[_slot_index].grab_focus()
		KEY_LEFT,KEY_RIGHT:
			var direction := -1 if event.keycode==KEY_LEFT else 1
			if event.shift_pressed or get_viewport().gui_get_focus_owner() in _piece_buttons:
				_cycle_piece(direction)
			else:
				_cycle_color(direction)
		_:return false
	return true

func _button(text: String,rect: Rect2,action: Callable) -> Button:
	var button := Button.new()
	MenuTheme.fit_button(button)
	button.theme_type_variation=&"MenuCompact"
	button.text=Text.plain(text)
	button.position=rect.position
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	add_child(button)
	button.size=rect.size
	return button

func _label(text: String,rect: Rect2) -> Label:
	var label := Label.new()
	label.position=rect.position
	label.text=Text.plain(text)
	label.clip_text=true
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.size=rect.size
	return label

func _stepper(y: int,arrows: Array[Button],action: Callable,caption: String) -> Label:
	const HEIGHT := 28
	var frame := Panel.new()
	frame.theme_type_variation=&"MenuInset"
	frame.position=Vector2(10,y)
	frame.size=Vector2(172,HEIGHT)
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var previous := _button("<",Rect2(10,y,24,HEIGHT),action.bind(-1))
	var next := _button(">",Rect2(158,y,24,HEIGHT),action.bind(1))
	previous.tooltip_text=caption+" precedent"
	next.tooltip_text=caption+" suivant"
	arrows.append(previous)
	arrows.append(next)
	var label := _label("",Rect2(38,y,116,HEIGHT))
	label.mouse_filter=Control.MOUSE_FILTER_PASS
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing",0)
	label.max_lines_visible=2
	return label

func _select_slot(index: int) -> void:
	if _slot_index!=index:edited.emit()
	_slot_index=index
	_refresh()

func _slot() -> int:
	return CharacterClothing.SLOTS[_slot_index]

func _base_color(item: ClothingItem) -> String:
	return item.texture_set.original_label if item.texture_set and not item.texture else "Origine"

func _refresh() -> void:
	_categories[_slot_index].set_pressed_no_signal(true)
	var worn: ClothingItem
	var included_shoes := false
	_pieces=[null]
	_colors.clear()
	if clothing:
		worn=clothing.equipped_item(_slot())
		included_shoes=_slot()==ClothingItem.Slot.SHOES and clothing.outfit_includes_shoes()
		if not included_shoes:_pieces.append_array(clothing.items_for_slot(_slot()))
	_piece_label.text="Avec la tenue" if included_shoes else (Text.plain(worn.display_name) if worn else "Aucun")
	_piece_label.tooltip_text=_piece_label.text if worn or included_shoes else ""
	_color_label.text=""
	if worn:
		var original := _base_color(worn)
		_colors.append(&"")
		if worn.texture_set:
			for label in worn.texture_set.choices().slice(1):
				if label!=original:_colors.append(StringName(label))
		var variant := clothing.texture_variant(_slot())
		_color_label.text=Text.plain(String(variant) if variant in _colors and not variant.is_empty() else original)
	_color_label.tooltip_text=_color_label.text
	for button in _piece_buttons:button.disabled=_pieces.size()<2
	for button in _color_buttons:button.disabled=_colors.size()<2

func _cycle_piece(direction: int) -> void:
	if not clothing or _pieces.size()<2:return
	var current := _pieces.find(clothing.equipped_item(_slot()))
	var next := _pieces[posmod(maxi(0,current)+direction,_pieces.size())]
	if next:
		if not clothing.equip(next):return
	else:
		clothing.unequip(_slot())
	edited.emit()

func _cycle_color(direction: int) -> void:
	if not clothing or _colors.size()<2:return
	var current := _colors.find(clothing.texture_variant(_slot()))
	var next := _colors[posmod(maxi(0,current)+direction,_colors.size())]
	if clothing.set_texture_variant(_slot(),next):edited.emit()

func _wardrobe_changed(_item: Resource) -> void:
	if visible:
		_refresh()
		preview.sync_outfit(clothing)
