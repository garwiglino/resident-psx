@tool
extends RefCounted
const Catalogue=preload("res://assets/dialogue/speakers.tres")
const Property=preload("res://addons/cinematic_montage/speaker_property.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 8) -> void:
	for step in count:await plugin.get_tree().process_frame
func find_property(node: Node,script: Script=null,property := "") -> EditorProperty:
	if node is EditorProperty:
		if script and node.get_script()==script:return node
		if not property.is_empty() and node.get_edited_property()==property:return node
	for child in node.get_children():
		var found := find_property(child,script,property)
		if found:return found
	return null
func select(picker: Control,name: String) -> void:
	for index in picker.choice.item_count:
		if picker.choice.get_item_metadata(index).name==name:
			picker.choice.item_selected.emit(index);return
	check(false,"Dropdown contains "+name)
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,30)
	var line := DialogueLine.new();line.speaker="POLICIERE";line.text="Test de locuteur."
	var inspector := EditorInspector.new();plugin.add_child(inspector);inspector.edit(line)
	await settle(plugin)
	var editor := find_property(inspector,Property)
	check(editor!=null,"Native inspector uses the speaker dropdown")
	check(find_property(inspector,null,"is_intercom")!=null,"Manual Is Intercom checkbox remains available")
	for property in ["end_intercom","end_event_id","override_reply_gap","reply_gap"]:
		check(find_property(inspector,null,property)!=null,"Line inspector exposes "+property)
	if not editor:plugin.get_tree().quit(1);return
	check(line.speaker=="POLICIERE" and not line.is_intercom,"Opening a legacy reply preserves its name and settings")
	select(editor.picker,"LE CONCIERGE");await settle(plugin)
	check(line.speaker=="LE CONCIERGE" and line.is_intercom,"Concierge selection enables intercom in the native inspector")
	var undo := plugin.get_undo_redo()
	var history := undo.get_history_undo_redo(undo.get_object_history_id(line))
	history.undo();await settle(plugin)
	check(line.speaker=="POLICIERE" and not line.is_intercom,"One native Undo restores both properties")
	history.redo();await settle(plugin)
	check(line.speaker=="LE CONCIERGE" and line.is_intercom,"One native Redo restores both properties")
	var checkbox := find_property(inspector,null,"is_intercom")
	checkbox.emit_changed("is_intercom",false);await settle(plugin)
	check(not line.is_intercom,"Intercom can be overridden after choosing a speaker")
	inspector.edit(null);inspector.edit(line);await settle(plugin)
	editor=find_property(inspector,Property)
	check(not line.is_intercom,"Refreshing the inspector keeps a manual override")
	select(editor.picker,"LE CONCIERGE");await settle(plugin)
	editor=find_property(inspector,Property)
	select(editor.picker,"HITOMI");await settle(plugin)
	check(line.speaker=="HITOMI" and not line.is_intercom,"Hitomi selection restores the normal voice default")
	var catalogue: DialogueSpeakerList=Catalogue
	var original := catalogue.entries.duplicate()
	var extra := DialogueSpeaker.new();extra.speaker_name="TEST LOCUTEUR";extra.intercom_by_default=true
	var extended := catalogue.entries.duplicate();extended.append(extra);catalogue.entries=extended
	editor=find_property(inspector,Property)
	select(editor.picker,"TEST LOCUTEUR");await settle(plugin)
	check(line.speaker=="TEST LOCUTEUR" and line.is_intercom,"Adding a catalogue entry updates existing dropdowns and its voice default")
	# The same catalogue entry inspector owns the new window palette controls.
	var entry_inspector := EditorInspector.new();plugin.add_child(entry_inspector);entry_inspector.edit(extra);await settle(plugin)
	var enabled_property := find_property(entry_inspector,null,"use_top_color")
	var color_property := find_property(entry_inspector,null,"top_color")
	check(enabled_property!=null and color_property!=null,"The existing speaker management inspector exposes the top-color override and picker")
	if enabled_property and color_property:
		enabled_property.emit_changed("use_top_color",true);color_property.emit_changed("top_color",Color(.6,.15,.3));await settle(plugin)
		check(extra.use_top_color and extra.top_color==Color(.6,.15,.3),"Native inspector changes the speaker color without modifying dialogue lines")
		var entry_history := undo.get_history_undo_redo(undo.get_object_history_id(extra))
		entry_history.undo();await settle(plugin)
		check(extra.top_color!=Color(.6,.15,.3),"Speaker color supports native Undo")
		entry_history.redo();await settle(plugin)
		check(extra.top_color==Color(.6,.15,.3),"Speaker color supports native Redo")
	entry_inspector.edit(null);entry_inspector.queue_free()
	catalogue.entries=original
	editor=find_property(inspector,Property)
	check(editor.picker.choice.get_item_text(editor.picker.choice.selected).contains("actuel"),"Removing an entry preserves already assigned replies")
	line.speaker="LE CONCIERGE";line.is_intercom=false
	var path := "res://exports/editor_tests/speaker_override.tres"
	check(ResourceSaver.save(line,path)==OK,"Speaker and manual override save normally")
	var restored: DialogueLine=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.speaker=="LE CONCIERGE" and not restored.is_intercom,"Reloading does not reapply a speaker default over a saved override")
	# Exercise the same visible selector inside the dedicated montage.
	var sequence=load("res://scenes/cinematics/cinematic_sequence.tscn").instantiate();plugin.add_child(sequence)
	var panel=plugin.panel;panel.set_sequence(sequence);panel.new_dialogue()
	check(panel.current().dialogue.lines[0].speaker=="HITOMI","New montage replies use the first catalogue entry")
	select(panel.speaker_edit,"LE CONCIERGE");await settle(plugin)
	check(panel.current().dialogue.lines[0].speaker=="LE CONCIERGE" and panel.intercom_edit.button_pressed,"Montage selection enables its visible intercom checkbox")
	var montage_history := undo.get_history_undo_redo(undo.get_object_history_id(sequence))
	montage_history.undo();await settle(plugin)
	check(panel.current().dialogue.lines[0].speaker=="HITOMI" and not panel.intercom_edit.button_pressed,"Montage Undo restores both values together")
	montage_history.redo();await settle(plugin)
	check(panel.current().dialogue.lines[0].speaker=="LE CONCIERGE" and panel.intercom_edit.button_pressed,"Montage Redo restores both values together")
	panel.intercom_edit.toggled.emit(false);await settle(plugin)
	check(not panel.current().dialogue.lines[0].is_intercom,"Montage permits a manual intercom override")
	select(panel.speaker_edit,"HITOMI");await settle(plugin)
	check(panel.current().dialogue.lines[0].speaker=="HITOMI" and not panel.intercom_edit.button_pressed,"Montage applies Hitomi's normal voice default")
	panel.hangup_edit.toggled.emit(true);await settle(plugin)
	check(panel.current().dialogue.lines[0].end_intercom,"Montage hangup checkbox edits the selected reply")
	montage_history.undo();await settle(plugin)
	check(not panel.current().dialogue.lines[0].end_intercom,"Hangup edit supports Undo")
	montage_history.redo();await settle(plugin)
	check(panel.current().dialogue.lines[0].end_intercom,"Hangup edit supports Redo")
	panel.end_event_edit.text_submitted.emit("test.montage.reply_end");await settle(plugin)
	panel.reply_gap_override_edit.toggled.emit(true);await settle(plugin)
	panel.reply_gap_edit.value=1.25;await settle(plugin)
	check(panel.current().dialogue.lines[0].end_event_id==&"test.montage.reply_end","Montage exposes custom world events at reply end")
	check(panel.current().dialogue.lines[0].override_reply_gap and panel.current().dialogue.lines[0].reply_gap==1.25,"Montage applies a per-reply response delay")
	plugin._open_dialogue_settings();await settle(plugin)
	var common: Resource=load("res://assets/dialogue/settings.tres")
	check(EditorInterface.get_inspector().get_edited_object()==common,"Reglages dialogues opens the one shared resource")
	for property in ["delai_disparition_apres_voix","volume_raccroche_db","masquer_conversations_manuelles"]:
		check(find_property(EditorInterface.get_inspector(),null,property)!=null,"Global dialogue inspector exposes "+property)
	FileAccess.open("res://docs/speakers-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"catalogue":Catalogue.resource_path},"\t"))
	panel.set_sequence(null);inspector.edit(null);inspector.queue_free();sequence.queue_free();await settle(plugin)
	for step in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning():break
		await settle(plugin,1)
	print("SPEAKERS_EDITOR_OK: native and montage dropdowns, automatic intercom, manual overrides, Undo/Redo, extensible catalogue and persistence" if failures.is_empty() else "SPEAKERS_EDITOR_FAILED "+str(failures))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
