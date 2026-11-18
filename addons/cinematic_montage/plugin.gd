@tool
extends EditorPlugin
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
const Trigger=preload("res://scripts/cinematics/cinematic_trigger_3d.gd")
const MontagePanel=preload("res://addons/cinematic_montage/panel.gd")
var panel: VBoxContainer
var dock: EditorDock
var _installed := false
var audio_inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	if not Engine.is_editor_hint():return
	audio_inspector=preload("res://addons/cinematic_montage/audio_inspector.gd").new();audio_inspector.undo=get_undo_redo();add_inspector_plugin(audio_inspector)
	_installed=true;panel=MontagePanel.new();panel.setup(self)
	add_tool_menu_item("Reglages dialogues",_open_dialogue_settings)
	dock=EditorDock.new();dock.title="Cinematiques";dock.layout_key="cinematic_montage"
	dock.default_slot=EditorDock.DOCK_SLOT_BOTTOM;dock.available_layouts=EditorDock.DOCK_LAYOUT_HORIZONTAL|EditorDock.DOCK_LAYOUT_FLOATING
	# Keep regression runs in their own visible layout, without inheriting or
	# replacing the artist's floating dock placement on another screen.
	if "--cinematic-editor-test" in OS.get_cmdline_user_args():
		dock.layout_key="cinematic_montage_validation";dock.available_layouts=EditorDock.DOCK_LAYOUT_HORIZONTAL
	var scroll := ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(panel);dock.add_child(scroll);add_dock(dock)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	scene_changed.connect(_scene_changed);call_deferred("_selection_changed")
	if "--cinematic-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_validation")
	if "--world-events-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_world_validation")
	if "--intercom-cache-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_intercom_validation")
	if "--speaker-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_speaker_validation")
	if "--spu-import-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_spu_import_validation")

func _run_spu_import_validation() -> void:
	await load("res://tests/spu_import_editor.gd").new().run(self)

func _run_speaker_validation() -> void:
	await load("res://tests/speakers_editor.gd").new().run(self)

func _run_intercom_validation() -> void:
	await load("res://tests/intercom_cache_editor.gd").new().run(self)

func _run_world_validation() -> void:
	await load("res://tests/world_events_editor.gd").new().run(self)

func _exit_tree() -> void:
	if not _installed:return
	remove_tool_menu_item("Reglages dialogues")
	if audio_inspector:remove_inspector_plugin(audio_inspector);audio_inspector=null
	panel.stop_preview()
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	remove_dock(dock);dock.free();panel=null;dock=null

func _handles(object: Object) -> bool:return object is Sequence or object is Trigger

func _open_dialogue_settings() -> void:
	EditorInterface.inspect_object(load("res://assets/dialogue/settings.tres"))
func _edit(object: Object) -> void:
	if object is Sequence:panel.set_sequence(object)
	elif object is Trigger:
		var sequence: Node=object.get_node_or_null(object.sequence_path)
		if sequence is Sequence:panel.set_sequence(sequence)
func _make_visible(visible: bool) -> void:
	if visible and dock:dock.make_visible()
func _apply_changes() -> void:
	if is_instance_valid(panel):panel.stop_preview()
func _scene_changed(_root: Node) -> void:
	panel.stop_preview();panel.set_sequence(null);panel.refresh_scene()
func _selection_changed() -> void:
	if not is_instance_valid(panel):return
	for node in EditorInterface.get_selection().get_selected_nodes():
		var ancestor: Node=node
		while ancestor:
			if ancestor is Sequence:panel.set_sequence(ancestor);return
			if ancestor is Trigger:_edit(ancestor);return
			ancestor=ancestor.get_parent()
	panel.refresh_scene()

func make_instance_editable(undo: EditorUndoRedoManager,sequence: Node) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root and root!=sequence and not sequence.scene_file_path.is_empty():
		undo.add_do_method(root,"set_editable_instance",sequence,true)
		undo.add_undo_method(root,"set_editable_instance",sequence,root.is_editable_instance(sequence))

func _unique_name(parent: Node,base: String) -> String:
	var name := base;var index := 2
	while parent.has_node(NodePath(name)):name=base+str(index);index+=1
	return name

func _own(undo: EditorUndoRedoManager,node: Node,root: Node) -> void:
	undo.add_do_method(node,"set_owner",root)
	for child in node.get_children():_own(undo,child,root)

func create_sequence() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root is Node3D:panel.status.text="Ouvrir une carte 3D pour placer la cinematique.";return
	var sequence := Sequence.new();sequence.name=_unique_name(root,"Cinematique")
	var camera := Camera3D.new();camera.name="CameraA";camera.near=.1;camera.far=55
	var view := EditorInterface.get_editor_viewport_3d(0)
	if view and view.get_camera_3d():camera.transform=root.global_transform.affine_inverse()*view.get_camera_3d().global_transform;camera.fov=view.get_camera_3d().fov
	sequence.add_child(camera)
	var player := AnimationPlayer.new();player.name="Timeline";sequence.add_child(player)
	var clip := Animation.new();clip.length=2
	var track := clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(track,NodePath("CameraA"))
	clip.position_track_insert_key(track,0,camera.position);clip.position_track_insert_key(track,2,camera.position)
	var library := AnimationLibrary.new();library.add_animation(&"cinematic",clip);player.add_animation_library(&"",library)
	var plan := Shot.new();plan.title="Plan 01";sequence.plans.append(plan)
	var undo := get_undo_redo();undo.create_action("Creer une cinematique",UndoRedo.MERGE_DISABLE,root)
	undo.add_do_method(root,"add_child",sequence);_own(undo,sequence,root);undo.add_do_reference(sequence)
	undo.add_undo_method(root,"remove_child",sequence);undo.commit_action()
	panel.refresh_scene();panel.set_sequence(sequence);dock.make_visible();_select(sequence)

func create_camera() -> void:
	var sequence: Node=panel.sequence
	if not is_instance_valid(sequence):return
	panel.stop_preview();var root := EditorInterface.get_edited_scene_root()
	var camera := Camera3D.new();camera.name=_unique_name(sequence,"CameraPlan");camera.near=.1;camera.far=55
	var view := EditorInterface.get_editor_viewport_3d(0)
	if view and view.get_camera_3d():camera.transform=sequence.global_transform.affine_inverse()*view.get_camera_3d().global_transform;camera.fov=view.get_camera_3d().fov
	var next=panel.Operations.copy_plans(sequence)
	if not next.is_empty():next[panel.selected].camera_path=NodePath(camera.name)
	var undo := get_undo_redo();undo.create_action("Ajouter une camera au montage",UndoRedo.MERGE_DISABLE,sequence)
	make_instance_editable(undo,sequence)
	undo.add_do_method(sequence,"add_child",camera);undo.add_do_method(camera,"set_owner",root);undo.add_do_reference(camera)
	undo.add_do_property(sequence,"plans",next);undo.add_undo_property(sequence,"plans",sequence.plans)
	undo.add_undo_method(sequence,"remove_child",camera);undo.commit_action();panel.refresh();_select(camera)

func create_zone() -> void:
	var sequence: Node=panel.sequence
	if not is_instance_valid(sequence):return
	var root := EditorInterface.get_edited_scene_root();var parent := sequence.get_parent()
	if not parent:return
	var area := Trigger.new();area.name=_unique_name(parent,"ZoneCinematique")
	area.sequence_path=NodePath("../"+String(parent.get_path_to(sequence)));area.position=sequence.position
	var volume := CollisionShape3D.new();volume.name="Volume";volume.position.y=1.5;volume.shape=BoxShape3D.new();volume.shape.size=Vector3(2,3,2);area.add_child(volume)
	var undo := get_undo_redo();undo.create_action("Ajouter la zone de cinematique",UndoRedo.MERGE_DISABLE,sequence)
	undo.add_do_method(parent,"add_child",area);_own(undo,area,root);undo.add_do_reference(area);undo.add_undo_method(parent,"remove_child",area);undo.commit_action();_select(volume)

func _select(node: Node) -> void:
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(node);EditorInterface.edit_node(node)

func _run_validation() -> void:
	var script=load("res://tools/validate_montage_editor.gd")
	if not script:return
	var test=script.new();add_child(test);test.run(self)
