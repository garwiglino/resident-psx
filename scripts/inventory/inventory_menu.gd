extends CanvasLayer
const Slot=preload("res://scripts/inventory/inventory_slot.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Audio=preload("res://scripts/audio/psx_audio_routing.gd")
const Wardrobe=preload("res://scripts/inventory/inventory_wardrobe.gd")
const MenuTheme=preload("res://scripts/ui/menu_theme.gd")
# Interface sounds follow dialogues; visuals follow the real pause menu.
var style: Resource=preload("res://assets/dialogue/default_style.tres")
@export var pause_world := true
var game: Node
var manager: Node
var canvas: Control
var modal: Panel
var slot_font: Font
var slot_background := MenuTheme.INSET
var slot_rim := MenuTheme.LINE
var slot_highlight := MenuTheme.ACCENT
var text_color := MenuTheme.TEXT
var opened := false
var selected_uid := ""
var _old_pause := false
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _slots: Array[Control]=[]
var _cards: Array[Control]=[]
var _inventory: Control
var _collection: Control
var _wardrobe: Control
var _sections: Dictionary={}
var _category_label: Label
var _category := 0
var _category_selection: Dictionary={}
var _name: Label
var _description: Label
var _progress: Label
var _card_image: TextureRect
var _card_name: Label
var _card_text: Label
var _context: PanelContainer
var _quantity: PanelContainer
var _warning: PanelContainer
var _reader: PanelContainer
var _reader_title: Label
var _reader_text: Label
var _blocker: ColorRect
var _tabs: Array[Button]=[]
var _slider: HSlider
var _quantity_label: Label
var _pending_uid := ""
var _pending_amount := 1
var _notice_left := 0.0
var _audio: AudioStreamPlayer

func _ready() -> void:
	layer=40; process_mode=Node.PROCESS_MODE_ALWAYS
	manager=get_node("/root/InventoryState")
	if is_instance_valid(game) and game.dialogue: style=game.dialogue.style
	canvas=Control.new(); canvas.size=Vector2(320,240); canvas.mouse_filter=Control.MOUSE_FILTER_STOP; canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(canvas)
	canvas.theme=game.hud.canvas.theme if is_instance_valid(game) and game.hud else MenuTheme.build()
	slot_font=canvas.get_theme_default_font()
	var shade := ColorRect.new(); shade.size=canvas.size; shade.color=MenuTheme.INSET; shade.mouse_filter=Control.MOUSE_FILTER_IGNORE; canvas.add_child(shade)
	modal=Panel.new(); modal.size=canvas.size; canvas.add_child(modal)
	_build_tabs()
	var divider := ColorRect.new()
	divider.position=Vector2(10,37);divider.size=Vector2(300,1);divider.color=MenuTheme.LINE
	divider.mouse_filter=Control.MOUSE_FILTER_IGNORE;modal.add_child(divider)
	_inventory=Control.new(); _inventory.size=modal.size; _inventory.mouse_filter=Control.MOUSE_FILTER_IGNORE; modal.add_child(_inventory)
	# Header arrows cycle the two sections in the same modal and keep slot order.
	var previous := _button(_inventory,"<",Rect2(10,43,24,20),_cycle_category.bind(-1)); previous.tooltip_text="Categorie precedente"
	var next := _button(_inventory,">",Rect2(286,43,24,20),_cycle_category.bind(1)); next.tooltip_text="Categorie suivante"
	_category_label=_label(_inventory,"OBJETS",Rect2(40,43,240,20)); _category_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_category_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_category_label.theme_type_variation=&"MenuHeading"
	_inset(_inventory,Rect2(178,69,132,159))
	_name=_label(_inventory,"",Rect2(187,77,114,33)); _name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible=2
	_name.mouse_filter=Control.MOUSE_FILTER_PASS
	_name.theme_type_variation=&"MenuCaption"
	var details := ScrollContainer.new(); details.position=Vector2(187,115); details.size=Vector2(114,104); details.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _inventory.add_child(details)
	_description=Label.new(); _description.text="Survoler un objet."; _description.custom_minimum_size.x=104; _description.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; details.add_child(_description)
	for section: StringName in [&"items",&"equipment"]:
		var scroll := ScrollContainer.new(); scroll.position=Vector2(10,69); scroll.size=Vector2(162,159); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _inventory.add_child(scroll); _sections[section]=scroll
		var grid := GridContainer.new(); grid.columns=4; grid.add_theme_constant_override("h_separation",3); grid.add_theme_constant_override("v_separation",3); scroll.add_child(grid)
		for index in manager.model.sections[section].size():
			var slot := Slot.new(); slot.menu=self; slot.section=section; slot.index=index; slot.slot_size=Vector2(36,36); grid.add_child(slot); _slots.append(slot)
	_build_collection()
	_wardrobe=Wardrobe.new()
	_wardrobe.name="Hitomi"
	_wardrobe.size=modal.size
	_wardrobe.game=game
	_wardrobe.edited.connect(_sound.bind(style.letter_sound))
	modal.add_child(_wardrobe)
	_blocker=ColorRect.new(); _blocker.color=Color(0,0,0,.4); _blocker.size=Vector2(320,240); _blocker.z_index=8; canvas.add_child(_blocker); _blocker.hide()
	_audio=AudioStreamPlayer.new(); _audio.process_mode=Node.PROCESS_MODE_ALWAYS; _audio.volume_db=-28; add_child(_audio)
	Audio.set_category(_audio,&"UI");Audio.set_reverb_enabled(_audio,false)
	manager.changed.connect(_refresh); manager.notice.connect(_notice)
	canvas.hide(); set_process(false)

func _label(parent: Control,text: String,rect: Rect2,bold := false) -> Label:
	var label := Label.new(); label.text=Text.plain(text); label.position=rect.position; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.clip_text=true;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if bold:label.theme_type_variation=&"MenuHeading"
	parent.add_child(label);label.size=rect.size;return label
func _button(parent: Control,text: String,rect: Rect2,action: Callable) -> Button:
	var button := Button.new(); MenuTheme.fit_button(button); button.text=Text.plain(text); button.position=rect.position; button.pressed.connect(action); parent.add_child(button)
	button.size=rect.size;return button

func _inset(parent: Control,rect: Rect2) -> void:
	var panel := Panel.new()
	panel.theme_type_variation=&"MenuInset"
	panel.position=rect.position
	panel.size=rect.size
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)

func _build_tabs() -> void:
	var bar := HBoxContainer.new()
	bar.position=Vector2(10,9)
	bar.size=Vector2(300,22)
	bar.add_theme_constant_override("separation",4)
	modal.add_child(bar)
	var group := ButtonGroup.new()
	var titles := ["INVENTAIRE","COLLECTION","HITOMI"]
	for index in titles.size():
		var tab := _button(bar,titles[index],Rect2(),_set_tab.bind(index))
		tab.theme_type_variation=&"MenuTab"
		tab.toggle_mode=true
		tab.button_group=group
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y=22
		tab.size_flags_stretch_ratio=1.3 if index<2 else .85
		_tabs.append(tab)
	var close_button := _button(bar,"X",Rect2(),close)
	close_button.theme_type_variation=&"MenuCompact"
	close_button.custom_minimum_size=Vector2(22,22)

func _build_collection() -> void:
	_collection=Control.new(); _collection.size=modal.size; _collection.mouse_filter=Control.MOUSE_FILTER_IGNORE; modal.add_child(_collection)
	var scroll := ScrollContainer.new(); scroll.position=Vector2(10,45); scroll.size=Vector2(181,164); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _collection.add_child(scroll)
	var grid := GridContainer.new(); grid.columns=5; grid.add_theme_constant_override("h_separation",3); grid.add_theme_constant_override("v_separation",3); scroll.add_child(grid)
	for card: Resource in manager.catalogue.cards:
		var slot := Slot.new(); slot.menu=self; slot.card=card; slot.slot_size=Vector2(32,46); grid.add_child(slot); _cards.append(slot)
	_progress=_label(_collection,"",Rect2(10,213,181,15))
	_progress.theme_type_variation=&"MenuHint"
	_inset(_collection,Rect2(196,45,114,183))
	_card_image=TextureRect.new(); _card_image.position=Vector2(204,51); _card_image.size=Vector2(98,104); _card_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; _card_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; _card_image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; _collection.add_child(_card_image)
	_card_name=_label(_collection,"",Rect2(204,159,98,25)); _card_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_card_name.max_lines_visible=2
	_card_name.mouse_filter=Control.MOUSE_FILTER_PASS
	_card_name.theme_type_variation=&"MenuCaption"
	var description := ScrollContainer.new(); description.position=Vector2(204,188); description.size=Vector2(98,33); description.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _collection.add_child(description)
	_card_text=Label.new(); _card_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _card_text.custom_minimum_size.x=88; _card_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; description.add_child(_card_text)
	_collection.hide()

func _cycle_category(direction: int) -> void:
	_show_category(posmod(_category+direction,2)); _sound(style.letter_sound)
func _show_category(index: int) -> void:
	_category=index
	var current: StringName=&"items" if index==0 else &"equipment"
	for section in _sections: _sections[section].visible=section==current
	_category_label.text="OBJETS" if index==0 else "ARMES / MUNITIONS"
	selected_uid=String(_category_selection.get(current,""))
	if manager.model.locate(selected_uid).is_empty():
		selected_uid=""
		for entry: Dictionary in manager.model.sections[current]:
			if not entry.is_empty(): selected_uid=entry.uid; break
	_notice_left=0; _show_selection()

func open() -> bool:
	if opened or not is_instance_valid(game) or game.state!="playing" or not game._control_owners.is_empty() or game.player.health<=0: return false
	_old_pause=get_tree().paused; _old_mouse=Input.mouse_mode
	game._acquire_controls(&"inventory"); opened=true; canvas.show(); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if pause_world: get_tree().paused=true
	_set_tab(0); _refresh(); _sound(style.opening_sound); set_process(true); return true
func close() -> void:
	if not opened: return
	opened=false; _wardrobe.set_active(false); canvas.hide(); _hide_popups(); get_tree().paused=_old_pause
	if is_instance_valid(game): game._release_controls(&"inventory")
	Input.mouse_mode=_old_mouse; _sound(style.closing_sound); set_process(false)
func _exit_tree() -> void:
	if opened:
		get_tree().paused=_old_pause
		if is_instance_valid(game) and not game.is_queued_for_deletion(): game._release_controls(&"inventory")
func back() -> void:
	if is_instance_valid(_reader) and _reader.visible: _reader.hide()
	elif is_instance_valid(_warning) and _warning.visible: _warning.hide(); _quantity.show()
	elif is_instance_valid(_quantity) and _quantity.visible: _quantity.hide()
	elif is_instance_valid(_context) and _context.visible: _context.hide()
	else: close()
	_sync_blocker()
func _input(event: InputEvent) -> void:
	if not opened: return
	if event is InputEventKey and event.pressed and not event.echo and _wardrobe.visible and _wardrobe.handle_navigation(event):
		get_viewport().set_input_as_handled(); return
	if event is InputEventKey and event.pressed and not event.echo and _inventory.visible and event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
		_cycle_category(-1 if event.keycode==KEY_PAGEUP else 1); get_viewport().set_input_as_handled(); return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and is_instance_valid(_context) and _context.visible and not _context.get_global_rect().has_point(canvas.get_global_mouse_position()):
		_context.hide(); get_viewport().set_input_as_handled()
func _process(delta: float) -> void:
	_notice_left=maxf(_notice_left-delta,0)
	if _notice_left==0: _show_selection()
func _set_tab(index: int) -> void:
	_hide_popups(); _inventory.visible=index==0; _collection.visible=index==1
	_wardrobe.set_active(index==2)
	if not _tabs.is_empty(): _tabs[index].button_pressed=true
	if index==0: _show_category(_category)
	if index==1 and not manager.catalogue.cards.is_empty():
		var chosen: Resource=manager.catalogue.cards[0]
		for card: Resource in manager.catalogue.cards:
			if manager.owns_card(card.id): chosen=card; break
		select_card(chosen)
func _hide_popups() -> void:
	for node in [_context,_quantity,_warning,_reader]:
		if is_instance_valid(node): node.hide()
	if is_instance_valid(_blocker): _blocker.hide()
func _sync_blocker() -> void:
	if _blocker: _blocker.visible=(is_instance_valid(_reader) and _reader.visible) or (is_instance_valid(_quantity) and _quantity.visible) or (is_instance_valid(_warning) and _warning.visible)
func _sound(stream: AudioStream) -> void:
	if _audio and stream: _audio.stream=stream; Audio.play(_audio)
func _refresh() -> void:
	for slot: Control in _slots: slot.queue_redraw()
	for slot: Control in _cards: slot.queue_redraw()
	if _progress: _progress.text="%02d / %02d TROUVEES" % [manager.collection.size(),manager.catalogue.cards.size()]
	_show_selection()
func select_slot(section: StringName,index: int) -> void:
	var entry: Dictionary=manager.model.slot(section,index); selected_uid=String(entry.get("uid","")); _notice_left=0; _show_selection()
	_category_selection[section]=selected_uid
func _show_selection() -> void:
	if not _name or _notice_left>0: return
	var location: Dictionary=manager.model.locate(selected_uid)
	if location.is_empty(): _name.text=""; _name.tooltip_text=""; _description.text="Survoler un objet."; return
	var item: Resource=location.entry.item; _name.text=Text.plain(item.display_name)
	if item.kind==6:
		var index: int=manager.weapon_index(selected_uid)
		if index>=0: _name.text+="  %d / %d" % [manager.backend.weapons[index].ammo,item.weapon.magazine_capacity]
	_name.tooltip_text=_name.text
	_description.text=Text.plain(item.description)
func select_card(card: Resource) -> void:
	var owned: bool=manager.owns_card(card.id)
	_card_image.texture=card.image if owned else manager.catalogue.card_mystery
	_card_name.text=Text.plain(card.display_name if owned else "INCONNUE")
	_card_name.tooltip_text=_card_name.text
	_card_text.text=Text.plain(card.description+"\n\n"+card.lore if owned else "Explorez le monde pour trouver cette carte.")
func move_slot(uid: String,section: StringName,index: int) -> void:
	if manager.move(uid,section,index): selected_uid=uid if not manager.model.locate(uid).is_empty() else String(manager.model.slot(section,index).get("uid","")); _sound(style.letter_sound); _refresh()
func _notice(text: String) -> void:
	if not opened:
		if is_instance_valid(game): game.hud.toast(text)
		return
	_notice_left=3; _description.text=Text.plain(text)

func _popup(rect: Rect2) -> PanelContainer:
	var panel := PanelContainer.new(); panel.position=rect.position; panel.size=rect.size; panel.z_index=10
	var box: StyleBox=modal.get_theme_stylebox("panel").duplicate(); box.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel",box); canvas.add_child(panel); _fit_popup(panel); return panel
func _fit_popup(panel: Control) -> void:
	var bounds := modal.get_global_rect().grow(-4)
	panel.position=Vector2(clampf(panel.position.x,bounds.position.x,bounds.end.x-panel.size.x),clampf(panel.position.y,bounds.position.y,bounds.end.y-panel.size.y))
func show_context(uid: String,at: Vector2) -> void:
	_hide_popups(); _pending_uid=uid
	var location: Dictionary=manager.model.locate(uid)
	if location.is_empty(): return
	if is_instance_valid(_context): _context.free()
	_context=_popup(Rect2(at,Vector2(112,12)))
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation",1); _context.add_child(list)
	var item: Resource=location.entry.item; var label: String=item.action_label()
	if item.kind==InventoryItemDefinition.Kind.WEAPON and uid==manager.active_weapon_uid():label="RANGER"
	if not label.is_empty():
		var use := Button.new(); MenuTheme.fit_button(use); use.text=label; use.tooltip_text=label; use.pressed.connect(_use.bind(uid)); list.add_child(use)
	var discard := Button.new(); MenuTheme.fit_button(discard); discard.text="JETER"; discard.disabled=not item.can_discard(); discard.pressed.connect(_ask_drop.bind(uid)); list.add_child(discard)
	for button in list.get_children(): button.custom_minimum_size.y=20
	if discard.disabled: discard.tooltip_text="Objet essentiel : il ne peut pas etre jete."
	_context.reset_size(); _context.position=at; _fit_popup(_context)
	call_deferred("_fit_context")
	_sound(style.letter_sound)
func _fit_context() -> void:
	if is_instance_valid(_context): _fit_popup(_context)
func _use(uid: String) -> void:
	if is_instance_valid(_context): _context.hide()
	var result: Dictionary=manager.use(uid)
	if result.has("read"): _read(result.read)
	elif result.get("close",false): close()
	else: _notice(result.get("message",""))
	_sound(style.letter_sound)
func _ask_drop(uid: String) -> void:
	_context.hide(); _pending_uid=uid
	var location: Dictionary=manager.model.locate(uid)
	if location.is_empty(): return
	if int(location.entry.quantity)==1: _perform_drop(1); return
	if is_instance_valid(_quantity): _quantity.free()
	_quantity=_popup(Rect2(32,66,256,112))
	_blocker.show()
	var body := Control.new(); body.custom_minimum_size=Vector2(246,102); _quantity.add_child(body)
	_label(body,"QUANTITE A JETER",Rect2(4,0,238,18),true)
	_quantity_label=_label(body,"1 / %d" % int(location.entry.quantity),Rect2(82,22,82,18),true); _quantity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_slider=HSlider.new(); _slider.position=Vector2(8,43); _slider.size=Vector2(230,15); _slider.min_value=1; _slider.max_value=int(location.entry.quantity); _slider.step=1; _slider.value=1; body.add_child(_slider)
	var bar := StyleBoxFlat.new(); bar.bg_color=slot_rim.darkened(.4); bar.content_margin_top=1; bar.content_margin_bottom=1; _slider.add_theme_stylebox_override("slider",bar)
	var fill := bar.duplicate(); fill.bg_color=text_color; _slider.add_theme_stylebox_override("grabber_area",fill); _slider.add_theme_stylebox_override("grabber_area_highlight",fill)
	var gradient := Gradient.new(); gradient.set_color(0,MenuTheme.ACCENT.lightened(.12)); gradient.set_color(1,MenuTheme.ACCENT.darkened(.28))
	var handle := GradientTexture2D.new(); handle.gradient=gradient; handle.width=7; handle.height=11; handle.fill_to=Vector2(0,1)
	_slider.add_theme_icon_override("grabber",handle); _slider.add_theme_icon_override("grabber_highlight",handle)
	_slider.value_changed.connect(func(value: float): _quantity_label.text="%d / %d" % [roundi(value),roundi(_slider.max_value)])
	_button(body,"JETER",Rect2(3,66,64,20),func(): _perform_drop(roundi(_slider.value)))
	_button(body,"TOUT JETER",Rect2(71,66,100,20),_ask_all)
	_button(body,"ANNULER",Rect2(175,66,68,20),func(): _quantity.hide(); _sync_blocker())
func _ask_all() -> void:
	var location: Dictionary=manager.model.locate(_pending_uid)
	if location.is_empty(): return
	_pending_amount=int(location.entry.quantity); _quantity.hide()
	if is_instance_valid(_warning): _warning.free()
	_warning=_popup(Rect2(42,65,236,114))
	var body := Control.new(); body.custom_minimum_size=Vector2(226,104); _warning.add_child(body)
	_label(body,"TOUT JETER ?",Rect2(4,0,218,18),true)
	var text := _label(body,"Deposer les %d objets au sol ?" % _pending_amount,Rect2(4,24,218,37)); text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_button(body,"ANNULER",Rect2(4,76,100,20),func(): _warning.hide(); _quantity.show()).grab_focus()
	_button(body,"CONFIRMER",Rect2(112,76,110,20),func(): _perform_drop(_pending_amount))
func _perform_drop(quantity: int) -> void:
	if manager.drop(_pending_uid,quantity): _hide_popups(); _notice("Objet depose au sol."); _sound(style.letter_sound)
	else: _hide_popups(); _notice("Impossible de jeter cet objet.")
func _read(item: Resource) -> void:
	if is_instance_valid(_reader): _reader.free()
	_reader=_popup(modal.get_global_rect().grow(-8))
	_blocker.show()
	var body := Control.new(); body.custom_minimum_size=Vector2(296,216); _reader.add_child(body)
	_reader_title=_label(body,item.display_name,Rect2(7,5,282,22),true)
	var scroll := ScrollContainer.new(); scroll.position=Vector2(7,34); scroll.size=Vector2(282,148); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	_reader_text=Label.new(); _reader_text.text=Text.plain(item.document_text); _reader_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _reader_text.custom_minimum_size.x=270; _reader_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(_reader_text)
	_button(body,"RETOUR",Rect2(195,189,94,21),func(): _reader.hide(); _sync_blocker())
