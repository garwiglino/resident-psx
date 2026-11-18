@tool
extends EditorPlugin
const Map = preload("res://scripts/modular_map/map_3d.gd")
const Layout = preload("res://scripts/modular_map/layout.gd")
const PlanView = preload("res://addons/modular_map/plan_view.gd")
const LevelSettings = preload("res://scripts/levels/psx_level_settings.gd")
const Dialogue = preload("res://scripts/dialogue/dialogue_sequence.gd")
const MODES := ["Piece","Sol","Mur","Porte","Fenetre","Passage","Effacer","Regler","Plafond","Tremie"]
var map: Node3D
var dock: EditorDock
var panel: VBoxContainer
var plan: Control
var status: Label
var rooms: OptionButton
var variants: OptionButton
var paint_3d: CheckBox
var options: VBoxContainer
var fields: Dictionary = {}
var reply_picker: EditorResourcePicker
var storeys: OptionButton
var other_storeys: CheckBox
var ceiling_visibility: CheckBox
var lock_modes: OptionButton
var tool_help: Label
var stair_opening: Button
var _stroke_point := Vector3.ZERO
var _stroke_edges: Dictionary={}
var _ui_rebuild_pending := false
var mode := 0
var room_id := 0
var painting := false
var erasing := false
var first := Vector2i.ZERO
var last := Vector2i.ZERO
var hover := Vector3.ZERO
var before: Dictionary = {}
var selected_edge := ""
var notice := ""
var _stroke_room := 0
var _buttons: Array[Button] = []
var _updating := false
var _dialog: EditorFileDialog
var _gizmo: EditorNode3DGizmoPlugin

func _enter_tree() -> void:
	_gizmo=preload("res://addons/modular_map/gizmo.gd").new(); add_node_3d_gizmo_plugin(_gizmo)
	_build_ui()
	EditorInterface.get_selection().selection_changed.connect(_selection)
	scene_changed.connect(_scene_changed)
	set_input_event_forwarding_always_enabled()
	call_deferred("_selection")
	if "--modular-map-editor-test" in OS.get_cmdline_user_args(): call_deferred("_validate")

func _exit_tree() -> void:
	cancel_stroke()
	if EditorInterface.get_selection().selection_changed.is_connected(_selection):
		EditorInterface.get_selection().selection_changed.disconnect(_selection)
	_set_map(null)
	remove_node_3d_gizmo_plugin(_gizmo)
	remove_dock(dock); dock.free()
	if is_instance_valid(_dialog): _dialog.queue_free()

func _handles(object: Object) -> bool: return object is Map
func _edit(object: Object) -> void:
	if object is Map: _set_map(object)
func _make_visible(value: bool) -> void:
	if value and dock: dock.make_visible()
func _apply_changes() -> void: end_stroke()

func _build_ui() -> void:
	panel=VBoxContainer.new(); panel.custom_minimum_size.x=285
	var row := HBoxContainer.new(); panel.add_child(row)
	var create := Button.new(); create.text="Nouvelle carte"; create.pressed.connect(_new_map); row.add_child(create)
	var fit := Button.new(); fit.text="Cadrer"; fit.pressed.connect(func(): plan.fit()); row.add_child(fit)
	var hint := Label.new(); hint.text="Cases 2 m / murs 3 m"; panel.add_child(hint)
	var levels := HBoxContainer.new();panel.add_child(levels)
	storeys=OptionButton.new();storeys.size_flags_horizontal=Control.SIZE_EXPAND_FILL;storeys.item_selected.connect(func(index: int):select_storey(int(storeys.get_item_metadata(index))));levels.add_child(storeys)
	for direction in [1,-1]:
		var add := Button.new();add.text="+ etage" if direction>0 else "- sous-sol";add.pressed.connect(add_storey.bind(direction));levels.add_child(add)
	var visibility := HBoxContainer.new();panel.add_child(visibility)
	other_storeys=CheckBox.new();other_storeys.text="Autres etages";other_storeys.toggled.connect(func(value: bool):
		if is_instance_valid(map):map.show_other_storeys_in_editor=value);visibility.add_child(other_storeys)
	ceiling_visibility=CheckBox.new();ceiling_visibility.text="Plafonds";ceiling_visibility.toggled.connect(func(value: bool):
		if is_instance_valid(map):map.show_ceilings_in_editor=value);visibility.add_child(ceiling_visibility)
	rooms=OptionButton.new(); rooms.item_selected.connect(func(index: int): room_id=rooms.get_item_id(index)); panel.add_child(rooms)
	var grid := GridContainer.new(); grid.columns=4; panel.add_child(grid)
	var group := ButtonGroup.new()
	for index in MODES.size():
		var button := Button.new(); button.text=MODES[index]; button.toggle_mode=true; button.button_group=group
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_mode.bind(index)); grid.add_child(button); _buttons.append(button)
	_buttons[0].button_pressed=true
	tool_help=Label.new();tool_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(tool_help)
	variants=OptionButton.new(); panel.add_child(variants)
	paint_3d=CheckBox.new(); paint_3d.text="Peindre dans la vue 3D"; panel.add_child(paint_3d)
	plan=PlanView.new(); plan.controller=self; panel.add_child(plan)
	stair_opening=Button.new();stair_opening.text="Ouvrir tremie sur escalier";stair_opening.pressed.connect(open_selected_stairwell);panel.add_child(stair_opening)
	var footer := Label.new(); footer.text="Glisser : peindre | Maj : effacer\nMolette : zoom | Milieu : deplacer | Ctrl+Z : annuler"
	footer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size",12); panel.add_child(footer)
	options=VBoxContainer.new(); panel.add_child(options)
	for field in ["id","required_item_id","opened_event","closed_event"]:
		var edit := LineEdit.new(); edit.placeholder_text={"id":"Identifiant porte (auto si vide)","required_item_id":"ID de la cle / carte d'acces requise","opened_event":"Evenement a l'ouverture (facultatif)","closed_event":"Evenement a la fermeture (facultatif)"}[field]
		edit.text_submitted.connect(func(_text: String): _portal_field(field,edit.text))
		edit.focus_exited.connect(func(): _portal_field(field,edit.text))
		options.add_child(edit); fields[field]=edit
	lock_modes=OptionButton.new();lock_modes.add_item("Libre",0);lock_modes.add_item("A cle / carte d'acces",1);lock_modes.add_item("Verrouillee sans cle",2);lock_modes.item_selected.connect(func(index: int):_portal_field("lock_mode",index));options.add_child(lock_modes)
	for field in ["open","consume_key","locked_dialogue_enabled"]:
		var check := CheckBox.new(); check.text={"open":"Ouverte au depart","consume_key":"Consommer la cle au deverrouillage","locked_dialogue_enabled":"Repliques si verrouillee"}[field]
		check.toggled.connect(func(value: bool): _portal_field(field,value)); options.add_child(check); fields[field]=check
	var reply_label := Label.new(); reply_label.text="Repliques de la porte (vide = celles de la carte)"; reply_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; options.add_child(reply_label)
	reply_picker=EditorResourcePicker.new(); reply_picker.base_type="DialogueSequence"; reply_picker.resource_changed.connect(_door_replies_changed); options.add_child(reply_picker)
	reply_picker.resource_selected.connect(func(resource: Resource,_inspect: bool):EditorInterface.edit_resource(resource))
	var edit_replies := Button.new(); edit_replies.text="Modifier les repliques communes de la carte"
	edit_replies.pressed.connect(func():
		if is_instance_valid(map):
			var source: Resource=map.permanent_door_dialogues if _door_lock_mode()==2 else map.locked_door_dialogues
			if source:EditorInterface.edit_resource(source))
	options.add_child(edit_replies)
	var reset := Button.new(); reset.text="Retablir le bord automatique"; reset.pressed.connect(_reset_edge); options.add_child(reset)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; panel.add_child(status)
	dock=EditorDock.new(); dock.title="Cartes 2m"; dock.layout_key="modular_map_2m"
	dock.default_slot=EditorDock.DOCK_SLOT_LEFT_BR
	dock.available_layouts=EditorDock.DOCK_LAYOUT_VERTICAL|EditorDock.DOCK_LAYOUT_FLOATING
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(panel); dock.add_child(scroll); add_dock(dock)
	_set_mode(0); _refresh()

func _set_mode(value: int) -> void:
	end_stroke(); mode=value; notice=""; variants.clear()
	var names: Array = []
	var ids: Array = []
	match mode:
		2: names=["Mur detaille","Mur simple"]; ids=["wall_loop","wall_loop_simple"]
		3:
			names=["Porte 01","Porte 02","Porte 03","Porte double 01 (4 m)","Porte double 02 (4 m)","Porte double 03 (4 m)"]
			ids=["solid","glass","door_03","double","double_02","double_03"]
		4: names=["Fenetre vitree","Fenetre condamnee","Ouverture vide"]; ids=["glass","boarded","empty"]
	for index in names.size(): variants.add_item(names[index]); variants.set_item_metadata(index,ids[index])
	variants.visible=not names.is_empty()
	if mode==8 and is_instance_valid(map):map.show_ceilings_in_editor=true
	if is_instance_valid(tool_help):tool_help.text=["Piece : sol et cloisons automatiques.","Sol seul, sans ajouter de murs. Maj : retirer le sol.","Mur seul, meme sans sol. Maj : ouvrir le bord.","Porte : remplacer un bord par un cadre et son vantail.","Fenetre : cadre et panneau au choix.","Passage : enlever le mur et sa collision.","Effacer : retirer la case et ses bords.","Regler : cliquer sur une porte.","Plafond seul a 3 m au-dessus de cet etage.","Tremie : ouvrir le sol et le plafond de l'etage inferieur. Maj : reboucher."][mode]
	_refresh(); update_overlays()

func _set_map(value: Node3D) -> void:
	if map==value:_refresh();return
	cancel_stroke()
	if is_instance_valid(map) and map.plan_changed.is_connected(_refresh): map.plan_changed.disconnect(_refresh)
	map=value; selected_edge=""; room_id=0; notice=""
	if is_instance_valid(map):
		if not map.layout: map.layout=Layout.new()
		if not map.plan_changed.is_connected(_refresh): map.plan_changed.connect(_refresh)
	_refresh(); call_deferred("_fit")

func _fit() -> void:
	if is_instance_valid(plan): plan.fit()

func _scene_changed(_root: Node) -> void: _set_map(null); call_deferred("_selection")
func _selection() -> void:
	for selected: Node in EditorInterface.get_selection().get_selected_nodes():
		var current := selected
		while current:
			if current is Map: _set_map(current); return
			current=current.get_parent()
	var root := EditorInterface.get_edited_scene_root()
	if root is Map: _set_map(root); return
	if root:
		for child in root.find_children("*","Node3D",true,false):
			if child is Map: _set_map(child); return
	_set_map(null)

func _refresh() -> void:
	if not is_instance_valid(panel): return
	if not is_instance_valid(storeys) or _buttons.size()!=MODES.size():
		if not _ui_rebuild_pending:_ui_rebuild_pending=true;call_deferred("_rebuild_ui_after_reload")
		return
	_updating=true; rooms.clear(); rooms.add_item("Nouvelle piece",0)
	storeys.clear()
	if is_instance_valid(map) and map.layout:
		for level: int in map.layout.level_ids():
			storeys.add_item("%s  Y=%d m" % [Layout.level_name(level),level*3]);storeys.set_item_metadata(storeys.item_count-1,level)
			if level==current_level():storeys.select(storeys.item_count-1)
		other_storeys.set_pressed_no_signal(map.show_other_storeys_in_editor);ceiling_visibility.set_pressed_no_signal(map.show_ceilings_in_editor)
		for id: int in map.layout.rooms: rooms.add_item(map.layout.rooms[id],id)
		var index := rooms.get_item_index(room_id); rooms.select(maxi(index,0))
		status.text="%s / %s : %d cases, %d bords" % [map.name,Layout.level_name(current_level()),map.layout.cells_at(current_level()).size(),map.layout.effective_edges(current_level()).size()]
	else: status.text="Ouvrir une carte 2m, ou cliquer sur Nouvelle carte."
	if not notice.is_empty(): status.text=notice
	var config: Dictionary = map.layout.edges_at(current_level()).get(selected_edge,{}) if is_instance_valid(map) and map.layout else {}
	options.visible=config.get("kind",-1)==Layout.Kind.DOOR
	if options.visible:
		var lock: int=_door_lock_mode(config);lock_modes.select(lock)
		for field: String in fields:
			if fields[field] is LineEdit:
				if not fields[field].has_focus(): fields[field].text=config.get(field,"")
			else: fields[field].set_pressed_no_signal(config.get(field,field=="locked_dialogue_enabled"))
		fields["required_item_id"].visible=lock==1;fields["consume_key"].visible=lock==1;fields["open"].visible=lock!=2
		reply_picker.edited_resource=config.get("permanent_dialogue_pool" if lock==2 else "locked_dialogue_pool")
	stair_opening.visible=_selected_stair()!=null
	_updating=false; plan.queue_redraw(); update_overlays()

func _rebuild_ui_after_reload() -> void:
	_ui_rebuild_pending=false;cancel_stroke()
	if is_instance_valid(dock):remove_dock(dock);dock.queue_free()
	fields={};_buttons=[];_stroke_edges={};_build_ui()
func current_level() -> int:return int(map.editor_storey) if is_instance_valid(map) else 0
func select_storey(level: int) -> void:
	end_stroke()
	if not is_instance_valid(map):return
	map.set_editor_storey(level);selected_edge="";_refresh();call_deferred("_fit")
func add_storey(direction: int) -> void:
	if not is_instance_valid(map) or not map.layout:return
	end_stroke();var old: Dictionary=map.layout.snapshot();var ids: Array[int]=map.layout.level_ids();var level: int=ids[-1]+1 if direction>0 else ids[0]-1
	map.layout.add_level(level);_commit(old,map.layout.snapshot(),"Ajouter "+Layout.level_name(level));select_storey(level)
func _selected_stair() -> Node3D:
	if not is_instance_valid(map):return null
	for selected: Node in EditorInterface.get_selection().get_selected_nodes():
		var node := selected
		while node and node!=map:
			if node is Node3D and node.get_meta("psx_asset_type","")=="stairs" and map.is_ancestor_of(node):return node
			node=node.get_parent()
	return null
func open_selected_stairwell() -> void:
	var stairs := _selected_stair()
	if not stairs:return
	end_stroke();var bounds := AABB();var found := false
	for visual: MeshInstance3D in stairs.find_children("*","MeshInstance3D",true,false):
		if not visual.mesh:continue
		var box: AABB=map.global_transform.affine_inverse()*visual.global_transform*visual.mesh.get_aabb()
		bounds=bounds.merge(box) if found else box;found=true
	if not found:return
	var level := roundi(map.to_local(stairs.global_position).y/3)+1
	var low := Vector2i(floori((bounds.position.x+.001)/2),floori((bounds.position.z+.001)/2));var high := Vector2i(floori((bounds.end.x-.001)/2),floori((bounds.end.z-.001)/2))
	if (high.x-low.x+1)*(high.y-low.y+1)>4096:notice="Empreinte d'escalier trop grande.";_refresh();return
	var old: Dictionary=map.layout.snapshot();map.layout.add_level(level)
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):map.layout.paint_opening(Vector2i(x,z),level)
	_commit(old,map.layout.snapshot(),"Ouvrir la tremie de l'escalier");select_storey(level)
func _door_lock_mode(config: Dictionary={}) -> int:
	if config.is_empty() and is_instance_valid(map) and map.layout:config=map.layout.edges_at(current_level()).get(selected_edge,{})
	return int(config.get("lock_mode",1 if not String(config.get("required_item_id","")).is_empty() else (2 if config.get("locked",false) else 0)))

func begin_stroke(point: Vector3, erase := false) -> void:
	if not is_instance_valid(map) or not map.layout: return
	end_stroke(); notice=""; hover=point; erasing=erase or mode==6
	first=Vector2i(floori(point.x/2),floori(point.z/2)); last=first
	selected_edge=Layout.nearest_edge(point)
	if mode==7: _refresh(); return
	before=map.layout.snapshot(); painting=true; _stroke_room=room_id;_stroke_point=point;_stroke_edges={}
	if mode==0 and not erasing and _stroke_room==0: _stroke_room=map.layout.add_room()
	if mode!=0: _paint(point)
	map.layout.emit_changed()
	plan.queue_redraw(); update_overlays()

func move_stroke(point: Vector3) -> void:
	hover=point
	var cell := Vector2i(floori(point.x/2),floori(point.z/2))
	if painting:
		if mode in [1,6,8,9]:
			var delta := cell-last; var steps := maxi(absi(delta.x),absi(delta.y))
			for step in range(1,mini(steps,128)+1):
				var between := Vector2(last).lerp(Vector2(cell),float(step)/maxi(steps,1)).round()
				_paint(Vector3(between.x*2+1,0,between.y*2+1))
		elif mode in [2,3,4,5]:
			var samples := clampi(ceili(_stroke_point.distance_to(point)/.5),1,256)
			for sample in range(1,samples+1):_paint(_stroke_point.lerp(point,float(sample)/samples))
		last=cell
		_stroke_point=point;map.layout.emit_changed()
	plan.queue_redraw(); update_overlays()

func _paint(point: Vector3) -> void:
	var level := current_level();var cell := Vector2i(floori(point.x/2),floori(point.z/2))
	if mode in [1,6,8,9]:
		if map.layout.cells_at(level).size()>=4096 and not map.layout.cells_at(level).has(cell):notice="Limite de 4096 cases par etage.";return
		match mode:
			1:map.layout.paint_floor(cell,_stroke_room,level,erasing)
			6:map.layout.erase_cell(cell,level)
			8:map.layout.paint_ceiling(cell,level,erasing)
			9:map.layout.paint_opening(cell,level,erasing)
	elif mode in [2,3,4,5]:
		var kind: int = Layout.Kind.PASSAGE if erasing else {2:Layout.Kind.WALL,3:Layout.Kind.DOOR,4:Layout.Kind.WINDOW,5:Layout.Kind.PASSAGE}[mode]
		var variant := String(variants.get_item_metadata(variants.selected)) if variants.item_count else ""
		if erasing:variant=""
		selected_edge=Layout.nearest_edge(point)
		if _stroke_edges.has(selected_edge):return
		_stroke_edges[selected_edge]=true
		var error: String = map.layout.paint_edge(selected_edge,kind,variant,level)
		if not error.is_empty(): notice=error; status.text=error; return
		notice=""

func end_stroke() -> void:
	if not painting: return
	painting=false
	if not is_instance_valid(map): return
	if mode==0:
		var low := first.min(last); var high := first.max(last)
		if (high.x-low.x+1)*(high.y-low.y+1)>4096:
			map.layout.restore(before); status.text="Piece trop grande : maximum 4096 cases."; return
		for x in range(low.x,high.x+1):
			for z in range(low.y,high.y+1): map.layout.paint_cell(Vector2i(x,z),0 if erasing else _stroke_room,current_level())
	var after: Dictionary = map.layout.snapshot()
	if after!=before:
		_commit(before,after,"Peindre "+MODES[mode].to_lower())
		if _stroke_room>0 and not erasing: room_id=_stroke_room
	map.layout.emit_changed(); _refresh()
	if mode==0: call_deferred("_fit")

func cancel_stroke() -> void:
	if not painting: return
	painting=false
	if is_instance_valid(map) and map.layout: map.layout.restore(before)
	if is_instance_valid(plan): plan.queue_redraw()
	update_overlays()

func _commit(old: Dictionary, state: Dictionary, title: String) -> void:
	var undo := get_undo_redo()
	undo.create_action(title,UndoRedo.MERGE_DISABLE,map)
	undo.add_do_method(map,"apply_plan",state); undo.add_undo_method(map,"apply_plan",old)
	undo.commit_action(false)
	map.apply_plan(state)
	EditorInterface.mark_scene_as_unsaved()

func _portal_field(field: String, value: Variant) -> void:
	if _updating or not is_instance_valid(map) or not map.layout.edges_at(current_level()).has(selected_edge): return
	var config: Dictionary=map.layout.edges_at(current_level())[selected_edge]
	var fallback: Variant=true if field=="locked_dialogue_enabled" else (null if field in ["locked_dialogue_pool","permanent_dialogue_pool"] else ("" if value is String else false))
	if field=="lock_mode":fallback=_door_lock_mode(config)
	if config.get(field,fallback)==value: return
	var old: Dictionary = map.layout.snapshot()
	config[field]=value
	if field=="required_item_id" and not String(value).is_empty() and _door_lock_mode(config)==0:config.lock_mode=1
	if field=="lock_mode":
		config.locked=int(value)!=0
		if int(value)==2:config.open=false
	_commit(old,map.layout.snapshot(),"Regler la porte"); map.layout.emit_changed()

func _door_replies_changed(value: Resource) -> void:
	if value and not value is Dialogue:
		notice="Choisir un DialogueSequence contenant les repliques possibles."; _refresh(); return
	_portal_field("permanent_dialogue_pool" if _door_lock_mode()==2 else "locked_dialogue_pool",value)

func _reset_edge() -> void:
	if not is_instance_valid(map): return
	var old: Dictionary = map.layout.snapshot(); map.layout.reset_edge(selected_edge,current_level())
	_commit(old,map.layout.snapshot(),"Retablir le bord"); map.layout.emit_changed()

func _new_map() -> void:
	end_stroke()
	if not _dialog:
		_dialog=EditorFileDialog.new(); _dialog.file_mode=EditorFileDialog.FILE_MODE_SAVE_FILE
		_dialog.access=EditorFileDialog.ACCESS_RESOURCES; _dialog.add_filter("*.tscn","Scene Godot")
		_dialog.file_selected.connect(create_map_at); EditorInterface.get_base_control().add_child(_dialog)
	_dialog.current_path="res://scenes/nouvelle_carte.tscn"; _dialog.popup_centered_ratio(.65)

func create_map_at(path: String) -> void:
	var root := Map.new(); root.name="Map"; root.layout=Layout.new()
	root.kit=load("res://assets/environment/modular_2m/default_kit.tres")
	root.event_namespace=path.get_file().get_basename().validate_node_name()
	var settings := LevelSettings.new(); settings.name="ReglagesNiveau"
	settings.profile=load("res://scripts/audio/level_audio_profile.gd").new()
	root.add_child(settings); settings.owner=root
	var gameplay := Node3D.new(); gameplay.name="Gameplay"; root.add_child(gameplay); gameplay.owner=root
	# No imposed spawn: the launcher uses the first painted cell until the artist
	# places a Gameplay/PlayerSpawn marker explicitly.
	var packed := PackedScene.new(); packed.pack(root)
	var error := ResourceSaver.save(packed,path); root.free()
	if error!=OK: status.text="Impossible d'enregistrer la carte : "+error_string(error); return
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)

func _point(camera: Camera3D, at: Vector2) -> Variant:
	var plane := Plane(map.global_basis.y.normalized(),map.to_global(Vector3(0,_paint_height(),0)))
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(at),camera.project_ray_normal(at))
	return map.to_local(hit) if hit is Vector3 else null
func _paint_height() -> float:return current_level()*3+(3 if mode==8 else 0)

func _can_paint_3d() -> bool:
	if not is_instance_valid(map) or not paint_3d.button_pressed:return false
	var selected := EditorInterface.get_selection().get_selected_nodes()
	return selected.is_empty() or (selected.size()==1 and selected[0]==map)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _can_paint_3d():
		if painting:cancel_stroke()
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and painting:
		cancel_stroke(); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE) or event.alt_pressed: return AFTER_GUI_INPUT_PASS
		var point: Variant = _point(camera,event.position)
		if point is Vector3: move_stroke(point)
		return AFTER_GUI_INPUT_STOP if painting else AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.alt_pressed:
		var point: Variant = _point(camera,event.position)
		if not point is Vector3: return AFTER_GUI_INPUT_PASS
		if event.pressed: begin_stroke(point,event.shift_pressed)
		else: end_stroke()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _can_paint_3d(): return
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if not camera: return
	var cell := Vector2i(floori(hover.x/2),floori(hover.z/2))
	var a := first.min(last) if painting and mode==0 else cell
	var b := first.max(last)+Vector2i.ONE if painting and mode==0 else cell+Vector2i.ONE
	var y := _paint_height()+.02
	var corners: Array[Vector3] = [Vector3(a.x*2,y,a.y*2),Vector3(b.x*2,y,a.y*2),Vector3(b.x*2,y,b.y*2),Vector3(a.x*2,y,b.y*2)]
	for i in 4:
		var start := map.to_global(corners[i]); var finish := map.to_global(corners[(i+1)%4])
		if not camera.is_position_behind(start) and not camera.is_position_behind(finish):
			overlay.draw_line(camera.unproject_position(start),camera.unproject_position(finish),Color(.4,.9,.75),2)

func _validate() -> void:
	await load("res://tests/modular_map_editor.gd").new().run(self)
