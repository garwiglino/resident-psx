extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run(plugin: EditorPlugin) -> void:
	for frame in 35:await plugin.get_tree().process_frame
	check(is_instance_valid(plugin.mix_button) and plugin.mix_button.is_inside_tree(),"Mixage audio est accessible dans la barre de la vue 3D")
	# The permanent Project/Tools entry remains available in the Script screen,
	# even if the 3D toolbar overflows on a narrow editor window.
	EditorInterface.set_main_screen_editor("Script")
	var entries := 0
	var pending: Array[Node]=[plugin.get_tree().root]
	while not pending.is_empty():
		var popup: Node=pending.pop_back()
		pending.append_array(popup.get_children(true))
		if not popup is PopupMenu:continue
		for index in popup.item_count:
			if popup.get_item_text(index)!="Mixage audio":continue
			entries+=1
			if not popup.get_signal_connection_list("index_pressed").is_empty():popup.index_pressed.emit(index)
			else:popup.id_pressed.emit(popup.get_item_id(index))
	if entries!=1:print("MIX_MENU_DIAGNOSTIC entries=",entries," installed=",plugin._mix_menu_installed)
	check(entries==1 and EditorInterface.get_inspector().get_edited_object()==plugin._mix_profile,"Projet > Outils > Mixage audio ouvre le profil depuis tous les ecrans")
	EditorInterface.set_main_screen_editor("3D")
	plugin.mix_button.pressed.emit()
	check(EditorInterface.get_inspector().get_edited_object()==plugin._mix_profile,"Le bouton ouvre le profil de mixage commun")
	var before: float=plugin._mix_profile.pas_db
	plugin._mix_profile.pas_db=-9
	for frame in 8:await plugin.get_tree().process_frame
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Footsteps"))+9)<.001,"Le reglage Pas agit sur son bus")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Footsteps Dry"))+9)<.001,"Sa route seche suit le meme volume")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Voices"))==plugin._mix_profile.voix_db,"Les autres categories restent independantes")
	plugin._mix_profile.pas_db=before
	for frame in 8:await plugin.get_tree().process_frame
	var importer: EditorImportPlugin=plugin.importer
	var options := importer._get_import_options("res://assets/audio/dialogs/new_voice.wav",0)
	check(options[1].default_value==22050,"Les prochains imports choisissent 22050 Hz")
	check(not options[1].hint_string.contains("44100"),"L'import ne propose plus de sources haute definition par defaut")
	check(AudioServer.get_bus_volume_db(0)==0,"Le Master Godot reste a gain unite apres le reglage global")
	var native_master: AudioEffect=AudioServer.get_bus_effect(0,0)
	check(native_master.get("master_left")==roundi(db_to_linear(plugin._mix_profile.volume_general_db)*16384),"Le volume general agit dans les registres SPU")
	FileAccess.open("res://docs/audio-mix-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("AUDIO_MIX_EDITOR_OK " if failures.is_empty() else "AUDIO_MIX_EDITOR_FAILED ",JSON.stringify(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
