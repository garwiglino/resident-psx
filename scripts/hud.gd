extends CanvasLayer
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Cursors=preload("res://scripts/ui/cursor_style.gd")
const MenuTheme=preload("res://scripts/ui/menu_theme.gd")
const Minimap=preload("res://scripts/ui/minimap.gd")
const HUD_SIZE := Vector2(320,240)
const MINIMAP_DIAMETER := 76.0
const HEALTH_SEGMENTS := 12
const HEALTH_LOW := Color8(205,82,74)
const HEALTH_CAUTION := Color8(218,169,90)
const HEALTH_NORMAL := Color8(151,184,163)
## Contextual survival-horror HUD. No branding, mission banner or debug overlay.
signal start_requested
signal restart_requested
var game: Node
var dialogue: Node
var cinematics: Node
var canvas: Control
var ammo_label: Label
var weapon_label: Label
var prompt: Label
var toast_label: Label
var menu: PanelContainer
var menu_title: Label
var start_button: Button
var restart_button: Button
var health_bar: Control
var reticle: Control
var minimap: Control
var _minimap_enabled := true
var _menu_shade: ColorRect
var _health_panel: Panel
var _weapon_panel: Panel
var _health_ratio := 1.0
var _last_health := -1
var _last_weapon: Resource
var _seen_loadout := false
var _weapon_notice := 0.0
var toast_time := 0.0
var hurt_time := 0.0
var hit_time := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	canvas=Control.new()
	canvas.size=HUD_SIZE
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.theme=MenuTheme.build()
	_build_status()
	if game.level is ModularMap3D:
		minimap=Minimap.new()
		minimap.name="Minimap"
		minimap.position=Vector2(HUD_SIZE.x-8-MINIMAP_DIAMETER,8)
		minimap.size=Vector2.ONE*MINIMAP_DIAMETER
		minimap.bind(game.level)
		canvas.add_child(minimap)
		minimap.hide()
	prompt=make_label("",Vector2(25,186),Vector2(270,12))
	prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label=make_label("",Vector2(16,169),Vector2(288,12))
	toast_label.theme_type_variation=&"MenuCaption"
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	reticle=Control.new()
	reticle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	reticle.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	reticle.draw.connect(draw_reticle)
	canvas.add_child(reticle)
	_menu_shade=ColorRect.new()
	_menu_shade.size=canvas.size
	_menu_shade.color=MenuTheme.SHADE
	_menu_shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_menu_shade)
	_menu_shade.hide()
	menu=PanelContainer.new()
	menu.custom_minimum_size.x=158
	canvas.add_child(menu)
	menu.resized.connect(_center_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	menu.add_child(column)
	menu_title=Label.new()
	menu_title.theme_type_variation=&"MenuHeading"
	menu_title.clip_text=true
	menu_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	menu_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(menu_title)
	var divider := ColorRect.new()
	divider.color=MenuTheme.LINE
	divider.custom_minimum_size.y=1
	divider.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	start_button=Button.new()
	MenuTheme.fit_button(start_button)
	start_button.text="REPRENDRE"
	start_button.custom_minimum_size.y=22
	start_button.pressed.connect(func(): start_requested.emit())
	column.add_child(start_button)
	restart_button=Button.new()
	MenuTheme.fit_button(restart_button)
	restart_button.text="RECOMMENCER"
	restart_button.custom_minimum_size.y=22
	restart_button.pressed.connect(func(): restart_requested.emit())
	column.add_child(restart_button)
	menu.visible=false

func _status_panel(rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.theme_type_variation=&"MenuInset"
	panel.position=rect.position
	panel.size=rect.size
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	panel.hide()
	return panel

func _build_status() -> void:
	_health_panel=_status_panel(Rect2(8,8,75,27))
	make_label("SANTE",Vector2(7,2),Vector2(61,13),_health_panel)
	health_bar=Control.new()
	health_bar.position=Vector2(8,16)
	health_bar.size=Vector2(59,5)
	health_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_health_panel.add_child(health_bar)
	health_bar.draw.connect(_draw_health)

	_weapon_panel=_status_panel(Rect2(204,200,108,32))
	weapon_label=make_label("",Vector2(7,2),Vector2(94,14),_weapon_panel)
	ammo_label=make_label("",Vector2(7,15),Vector2(94,14),_weapon_panel)
	ammo_label.hide()
	ammo_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var ammo_font := preload("res://assets/fonts/mgs1-ammo-hud.ttf").duplicate() as FontFile
	ammo_font.antialiasing=TextServer.FONT_ANTIALIASING_NONE
	ammo_font.hinting=TextServer.HINTING_NONE
	ammo_font.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED
	ammo_font.oversampling=1.0
	ammo_label.add_theme_font_override("font",ammo_font)

func _draw_health() -> void:
	var color := HEALTH_LOW if _health_ratio<=.25 else (HEALTH_CAUTION if _health_ratio<=.5 else HEALTH_NORMAL)
	var filled := ceili(_health_ratio*HEALTH_SEGMENTS)
	for segment in HEALTH_SEGMENTS:
		var at := Vector2(segment*5,0)
		health_bar.draw_rect(Rect2(at,Vector2(4,5)),color if segment<filled else MenuTheme.LINE.darkened(.36))
		if segment<filled:health_bar.draw_rect(Rect2(at+Vector2(0,4),Vector2(4,1)),color.darkened(.34))

func make_label(text: String,pos: Vector2,size: Vector2,parent: Control=null) -> Label:
	var node := Label.new()
	node.text=text
	node.clip_text=true
	node.max_lines_visible=1
	node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	node.position=pos
	node.add_theme_color_override("font_shadow_color",Color.BLACK)
	node.add_theme_constant_override("shadow_offset_x",1)
	node.add_theme_constant_override("shadow_offset_y",1)
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	(parent if parent else canvas).add_child(node)
	node.size=size
	return node

func _process(delta: float) -> void:
	if not get_tree().paused:
		toast_time=maxf(toast_time-delta,0)
		hurt_time=maxf(hurt_time-delta,0)
		hit_time=maxf(hit_time-delta,0)
		_weapon_notice=maxf(_weapon_notice-delta,0)
	if not game or not is_instance_valid(game.player):
		return
	var p = game.player
	var call: Node=game.exploration_dialogue
	var caption_visible: bool=is_instance_valid(call) and is_instance_valid(call.view) and call.view.visible
	var modal_open := _modal_open()
	var status_visible := not modal_open and not caption_visible
	if minimap:
		minimap.visible=_minimap_enabled and not modal_open and minimap.update_marker(p)
	toast_label.visible=toast_time>0 and status_visible
	prompt.visible=status_visible
	var definition: Resource=p.weapon_definition()
	if definition!=_last_weapon:
		_weapon_notice=1.5 if definition and _seen_loadout else 0.0
		_last_weapon=definition
	_seen_loadout=true
	var reloading: bool=p.reload_left>0
	_weapon_panel.visible=status_visible and definition!=null and (p.aiming or reloading or _weapon_notice>0.0)
	ammo_label.visible=_weapon_panel.visible
	if _weapon_panel.visible:
		weapon_label.text="RECHARGE" if reloading else plain_text(definition.display_name).to_upper()
		ammo_label.text="%02d / %02d" % [p.ammo,p.reserve]
		ammo_label.modulate=MenuTheme.ACCENT if reloading else (HEALTH_LOW if p.ammo<=0 else Color.WHITE)
	if p.health!=_last_health:
		if _last_health>=0:hurt_time=maxf(hurt_time,1.8)
		_last_health=p.health
	var ratio := clampf(float(p.health)/maxf(p.max_health,1.0),0.0,1.0)
	if not is_equal_approx(ratio,_health_ratio):
		_health_ratio=ratio
		health_bar.queue_redraw()
	_health_panel.visible=status_visible and (hurt_time>0 or _health_ratio<=.25)
	reticle.queue_redraw()

func toggle_minimap() -> bool:
	if not minimap or _modal_open():return false
	_minimap_enabled=not _minimap_enabled
	return true

func draw_reticle() -> void:
	if not game or _modal_open() or not game.player.aiming:
		return
	if hit_time>0:
		if game.cursor_style:game.cursor_style.draw(reticle,Cursors.Kind.HIT,HUD_SIZE*.5,clampf(hit_time/.05,0,1))
		return
	if game.cursor_style:game.cursor_style.draw(reticle,Cursors.Kind.AIM,HUD_SIZE*.5)

func toast(text: String) -> void:
	toast_label.text=plain_text(text)
	toast_time=2.5

func _inventory_open() -> bool:
	return is_instance_valid(game) and ((is_instance_valid(game.inventory_menu) and game.inventory_menu.opened) or (is_instance_valid(game.pickup_feedback) and game.pickup_feedback.opened) or (is_instance_valid(game.item_placement) and game.item_placement.is_active()))

func _modal_open() -> bool:
	return menu.visible or _inventory_open() or (is_instance_valid(dialogue) and dialogue.is_active()) or (is_instance_valid(cinematics) and cinematics.is_active())

func show_menu(mode: String) -> void:
	_menu_shade.show()
	menu.show()
	menu_title.text="PAUSE" if mode=="pause" else ("VOUS ETES MORTE" if mode=="dead" else "ZONE TERMINEE")
	start_button.visible=mode=="pause"
	menu.reset_size()
	_center_menu()
	(start_button if start_button.visible else restart_button).grab_focus()

func hide_menu() -> void:
	menu.hide()
	_menu_shade.hide()

func _center_menu() -> void:
	menu.position=((canvas.size-menu.size)*.5).floor()

static func plain_text(text: String) -> String:
	return Text.plain(text)
