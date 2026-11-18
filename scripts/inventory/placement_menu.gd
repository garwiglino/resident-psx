extends CanvasLayer
const Slot=preload("res://scripts/inventory/placement_slot.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const MenuTheme=preload("res://scripts/ui/menu_theme.gd")
var controller: Node
var manager: Node
var canvas: Control
var grid: GridContainer
var name_label: Label
var empty_label: Label
var slot_font: Font
var text_color := MenuTheme.TEXT
var slot_highlight := MenuTheme.ACCENT
var slot_background := MenuTheme.INSET
var slot_rim := MenuTheme.LINE
var entries: Array[Dictionary]=[]
var panel: Panel
func _ready() -> void:
	layer=28;manager=get_node("/root/InventoryState")
	var game=controller.game
	canvas=Control.new();canvas.size=Vector2(320,240);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	canvas.theme=game.hud.canvas.theme
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;slot_font=canvas.theme.default_font
	panel=Panel.new();panel.position=Vector2(8,156);panel.size=Vector2(304,76);panel.mouse_filter=Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)
	var title := Label.new();title.text="OBJETS";title.theme_type_variation=&"MenuHeading";title.position=Vector2(8,3);title.size=Vector2(56,18);panel.add_child(title)
	var close := Button.new();MenuTheme.fit_button(close);close.text="X";close.theme_type_variation=&"MenuCompact";close.position=Vector2(278,3);close.pressed.connect(controller.back);panel.add_child(close);close.size=Vector2(20,18)
	var scroll := ScrollContainer.new();scroll.position=Vector2(10,22);scroll.size=Vector2(284,48);scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	grid=GridContainer.new();grid.columns=1;grid.add_theme_constant_override("h_separation",4);scroll.add_child(grid)
	empty_label=Label.new();empty_label.text="Aucun objet placable.";empty_label.position=Vector2(10,27);empty_label.size=Vector2(284,22);empty_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(empty_label)
	name_label=Label.new();name_label.position=Vector2(64,2);name_label.size=Vector2(210,18);name_label.clip_text=true;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(name_label)
	name_label.theme_type_variation=&"MenuCaption"
	manager.changed.connect(refresh);canvas.hide()
func refresh() -> void:
	entries.clear()
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	for section: StringName in [&"items",&"equipment"]:
		for index in manager.model.sections[section].size():
			var entry: Dictionary=manager.model.slot(section,index)
			if entry.is_empty() or not entry.item.can_place():continue
			entries.append(entry)
			var slot := Slot.new();slot.menu=self;slot.section=section;slot.index=index;slot.preview_entry=entry;grid.add_child(slot)
	grid.columns=maxi(entries.size(),1)
	empty_label.visible=entries.is_empty();name_label.text="" if entries.is_empty() else Text.plain(entries[0].item.display_name)
func show_choices() -> void:
	refresh();canvas.show()
	if grid.get_child_count()>0:grid.get_child(0).grab_focus()
func select_slot(section: StringName,index: int) -> void:
	var entry: Dictionary=manager.model.slot(section,index)
	name_label.text=Text.plain(entry.item.display_name) if not entry.is_empty() else ""
func choose(uid: String) -> void:controller.choose(uid)
func message(text: String) -> void:name_label.text=Text.plain(text)
