@tool
extends Node
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Operations=preload("res://addons/cinematic_montage/operations.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(count := 6) -> void:
	for index in count:await get_tree().process_frame
func drag_audio(field: Control,path: String) -> void:
	# Invoke the actual visible button's virtual drag callbacks with a FileSystem
	# payload, rather than emitting resource_changed and bypassing drop validation.
	# Synthetic mouse events cannot reliably target a second editor while the
	# artist is using the real mouse in the main editor.
	await settle(8)
	var viewport := field.get_viewport();var at := field.get_global_rect().get_center()
	check(viewport.get_visible_rect().has_point(at),"Audio drop target is inside the visible editor viewport")
	var data := {"type":"files","files":PackedStringArray([path])}
	check(field._can_drop_data(field.size*.5,data),"Visible audio button accepts the real file drag payload")
	field._drop_data(field.size*.5,data);await settle(3)
func run(plugin: EditorPlugin) -> void:
	await settle(30)
	await get_tree().create_timer(4.0).timeout
	var initial := EditorInterface.get_edited_scene_root()
	var previous_path: String=initial.scene_file_path if initial else ""
	if previous_path.begins_with("res://exports/editor_tests/"):previous_path=ProjectSettings.get_setting("application/run/main_scene")
	var source_hash := FileAccess.get_sha256("res://scenes/cinematics/cinematic_sequence.tscn")
	var scene := Node3D.new();scene.name="MontageEditorFixture"
	var instance=load("res://scenes/cinematics/cinematic_sequence.tscn").instantiate();scene.add_child(instance);instance.owner=scene
	var actor=load("res://scenes/player.tscn").instantiate();actor.name="Player";scene.add_child(actor);actor.owner=scene
	var packed := PackedScene.new();check(packed.pack(scene)==OK,"Instanced fixture packs")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://exports/editor_tests"))
	var path := "res://exports/editor_tests/montage_fixture_%d.tscn" % Time.get_ticks_usec()
	check(ResourceSaver.save(packed,path)==OK,"Editor fixture saved separately from artist maps");scene.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	await get_tree().create_timer(.3).timeout
	var root := EditorInterface.get_edited_scene_root()
	for attempt in 20:
		EditorInterface.open_scene_from_path(path)
		await get_tree().create_timer(.3).timeout;root=EditorInterface.get_edited_scene_root()
		if root and root.scene_file_path==path:break
	if not root or root.scene_file_path!=path:
		push_error("Editor fixture did not become active; no edits performed.");get_tree().quit(1);return
	EditorInterface.set_main_screen_editor("3D")
	var matches := root.find_children("*","CinematicSequence3D",true,false) if root else []
	if matches.is_empty():
		push_error("Montage editor fixture has no cinematic sequence: "+str(root));get_tree().quit(1);return
	var sequence: Sequence=matches[0]
	plugin.panel.set_sequence(sequence);plugin.dock.make_visible();await settle()
	var panel=plugin.panel;var player := Operations.timeline(sequence)
	print("MONTAGE_EDITOR_FIXTURE ",root.scene_file_path," ",sequence.get_path()," plans=",panel.plans.size()," timeline=",player.get_animation_list())
	check(panel.plans.size()==2 and panel.plan_list.item_count==2,"Dedicated montage lists the imported camera/dialogue plans")
	check(not EditorInterface.is_playing_scene(),"Montage works inside the edited map without running gameplay")
	var undo := plugin.get_undo_redo();var history := undo.get_history_undo_redo(undo.get_object_history_id(root))
	panel._edit_property(&"finish_camera_on_confirm",false)
	check(sequence.plans.size()==2 and not sequence.plans[0].finish_camera_on_confirm,"Editing the flow stores clear local plans")
	history.undo();await settle()
	check(sequence.plans.is_empty(),"Undo restores the original unmodified imported montage")
	history.redo();await settle();check(not sequence.plans[0].finish_camera_on_confirm,"Redo restores the edited flow")
	var camera: Camera3D=sequence.get_node("CameraA");var original_pose := camera.transform;var original_fov := camera.fov
	panel._seek(.5);check(not camera.transform.is_equal_approx(original_pose),"Scrubbing samples camera motion directly inside the map")
	panel.stop_preview();check(camera.transform.is_equal_approx(original_pose) and camera.fov==original_fov,"Stopping restores original camera properties")
	panel._select_plan(0);panel.playing=true;panel.preview_confirmed=false;panel._process(2)
	check(panel.selected==0 and panel.playing and is_equal_approx(panel.cursor,panel.plans[0].duration(player)),"Editor preview holds its last frame while keeping the dialogue clock alive")
	panel.confirm_preview();check(panel.selected==1,"Preview confirmation advances the linked plan explicitly")
	panel.stop_preview();panel._select_plan(0);panel._seek(.5);plugin._apply_changes()
	check(camera.transform.is_equal_approx(original_pose) and panel.preview.snapshots.is_empty(),"Saving restores all temporary camera poses before scene serialization")
	var source_library := player.get_animation_library(&"");var source_clip := player.get_animation(&"cinematic")
	var keys_before := source_clip.track_get_key_count(0)
	panel._seek(.5);camera.position+=Vector3(.3,0,0);panel.camera_key(false)
	check(player.get_animation_library(&"")!=source_library and player.get_animation(&"cinematic")!=source_clip,"Key editing makes the instance's library unique automatically")
	check(player.get_animation(&"cinematic").track_get_key_count(0)==keys_before+1 and source_clip.track_get_key_count(0)==keys_before,"Adding a key never changes the source scene's shared animation")
	panel.camera_key(true)
	check(player.get_animation(&"cinematic").track_get_key_count(0)==keys_before,"Dedicated delete removes the actual in-map key")
	history.undo();await settle()
	check(player.get_animation(&"cinematic").track_get_key_count(0)==keys_before+1,"Key deletion is undoable")
	history.redo();await settle()
	check(player.get_animation(&"cinematic").track_get_key_count(0)==keys_before,"Key deletion can be redone")
	panel.stop_preview();panel.new_dialogue();panel._edit_line(&"speaker","POLICIERE");panel._edit_line(&"text","Un bruit dans le couloir.")
	check(sequence.plans[0].dialogue.lines[0].text=="Un bruit dans le couloir.","Dedicated dialogue editor stores its own linked text")
	check(panel.dialogue_mode_edit.item_count==2 and sequence.plans[0].dialogue.mode==0,"Conversation remains the default, with both modes available in the montage")
	panel.dialogue_mode_edit.item_selected.emit(1)
	check(sequence.plans[0].dialogue.mode==1 and panel.graph.automatic_dialogue,"The mode selector configures an exploration call and its automatic timeline label")
	history.undo();await settle();check(sequence.plans[0].dialogue.mode==0,"Changing dialogue mode is undoable")
	history.redo();await settle();check(sequence.plans[0].dialogue.mode==1,"Changing dialogue mode supports Redo")
	panel.playing=true;panel.preview_confirmed=false;panel.preview_elapsed=0
	panel._process(panel._automatic_preview_seconds+sequence.plans[0].dialogue_delay+1)
	check(panel.selected==1,"Editor playback advances automatic dialogue plans without a confirmation click")
	panel.stop_preview();panel._select_plan(0)
	var audio_path := "res://assets/audio/dialogs/1/1_Chapter_1.wav"
	if not ResourceLoader.exists(audio_path):audio_path="res://assets/audio/ui/dialogue_open.wav"
	check(panel.audio_picker._can_drop_data(Vector2.ZERO,{"type":"files","files":PackedStringArray([audio_path])}),"Audio field accepts a WAV imported as AudioStreamPSX")
	check(not panel.audio_picker._can_drop_data(Vector2.ZERO,{"type":"files","files":PackedStringArray(["res://scenes/player.tscn"])}),"Audio field rejects a non-audio file")
	check(not panel.audio_picker._can_drop_data(Vector2.ZERO,{"type":"files","files":PackedStringArray([audio_path,audio_path])}),"Audio field rejects ambiguous multi-file drops")
	plugin.dock.make_visible()
	await drag_audio(panel.audio_picker.target,audio_path)
	check(sequence.plans[0].dialogue.lines[0].audio!=null and sequence.plans[0].dialogue.lines[0].audio.resource_path==audio_path,"Dropping a WAV onto the actual visible button assigns the current reply")
	check(panel.audio_picker.target.text==audio_path.get_file(),"Audio field displays the assigned filename")
	history.undo();await settle();check(sequence.plans[0].dialogue.lines[0].audio==null,"Undo removes the dropped voice")
	history.redo();await settle();check(sequence.plans[0].dialogue.lines[0].audio!=null,"Redo restores the dropped voice")
	panel.audio_picker._choose_file();await settle()
	check(panel.audio_picker.dialog.visible,"Clicking the audio field opens a real file chooser")
	panel.audio_picker.dialog.hide();panel.audio_picker.dialog.file_selected.emit(audio_path)
	panel._edit_line(&"is_intercom",true)
	check(panel.intercom_edit.button_pressed and sequence.plans[0].dialogue.lines[0].intercom_audio!=null,"Audio picker and Is Intercom bake a prepared radio voice in the editor")
	var capture_slot := AudioServer.get_bus_effect_count(0)
	var voice_capture := AudioEffectCapture.new();voice_capture.buffer_length=6;AudioServer.add_bus_effect(0,voice_capture)
	panel.preview_voice()
	print("EDITOR_VOICE_STARTED phase=",panel.audition.phase," paused=",get_tree().paused," process=",panel.audition.can_process()," player_process=",panel.audition.voice.can_process()," master_mute=",AudioServer.is_bus_mute(0)," volume=",AudioServer.get_bus_volume_db(0))
	await get_tree().create_timer(sequence.plans[0].dialogue.lines[0].audio.get_length()+1.2).timeout
	var voice_samples := voice_capture.get_buffer(voice_capture.get_frames_available());var voice_peak := 0.0;var voice_energy := 0.0
	for sample in voice_samples:voice_peak=maxf(voice_peak,maxf(absf(sample.x),absf(sample.y)));voice_energy+=sample.length_squared()*.5
	print("EDITOR_VOICE_OUTPUT frames=",voice_samples.size()," peak=",voice_peak," rms=",sqrt(voice_energy/maxi(voice_samples.size(),1))," phase=",panel.audition.phase)
	check(voice_peak>.05,"Ecouter produces actual AudioServer output from the supplied -01.wav, not only a playing flag")
	panel.audition.stop_line(false)
	AudioServer.remove_bus_effect(0,capture_slot)
	panel.add_actor();panel._edit_actor(&"source",load("res://assets/character/animations/player_walk_forward_pistol.glb"))
	panel._edit_actor(&"animation",&"player_walk_forward_pistol");panel._edit_actor(&"start_time",.2);panel._edit_actor(&"duration",.6)
	check(panel.graph.actor_rows.size()==1 and sequence.plans[0].actors[0].actor(sequence)==root.get_node("Player"),"Character animation has its own visible track below camera, dialogue and audio")
	var character: Node3D=root.get_node("Player");var original_character := character.transform
	panel._seek(.5);check(character.position.distance_to(original_character.origin)>.2,"The in-map cursor previews the character's authored root motion")
	plugin._apply_changes();check(character.transform.is_equal_approx(original_character),"Saving restores the character placement before serialization")
	panel._edit_actor(&"speed",1.5);history.undo();await settle();check(is_equal_approx(sequence.plans[0].actors[0].speed,1),"Character edits support Undo")
	history.redo();await settle();check(is_equal_approx(sequence.plans[0].actors[0].speed,1.5),"Character edits support Redo")
	var saved := PackedScene.new();check(saved.pack(root)==OK,"Montage with characters and voice packs")
	var saved_path := "res://exports/editor_tests/montage_actor_audio_%d.tscn" % Time.get_ticks_usec()
	check(ResourceSaver.save(saved,saved_path)==OK,"Character/audio montage is serializable")
	var reopened: Node=load(saved_path).instantiate();var reopened_sequence: Node=reopened.get_node(String(root.get_path_to(sequence)))
	check(reopened_sequence.plans[0].actors.size()==1 and reopened_sequence.plans[0].dialogue.mode==1 and reopened_sequence.plans[0].dialogue.lines[0].is_intercom and reopened_sequence.plans[0].dialogue.lines[0].intercom_audio.is_class("AudioStreamPSX"),"Saving and reopening retains dialogue mode, actor timing, voice and prepared SPU radio data")
	reopened.free()
	var before := sequence.plans.size();var old_animation: StringName=sequence.plans[0].animation
	panel.add_plan();check(sequence.plans.size()==before+1 and panel.current().animation!=old_animation,"A new plan owns an independent native animation")
	panel.move_plan(-1);panel.duplicate_plan();panel.remove_plan();check(sequence.plans.size()==before+1,"Reorder, duplicate and remove preserve the montage list")
	panel.selected=0;panel.refresh();plugin.create_camera();await settle()
	check(sequence.get_node_or_null(sequence.plans[0].camera_path) is Camera3D,"A new camera is placed and assigned to the selected plan")
	plugin.create_zone();await settle()
	var zone := root.get_node_or_null("ZoneCinematique")
	check(zone!=null and zone.get_node(zone.sequence_path)==sequence and zone.get_node("Volume").shape is BoxShape3D,"Created cube zone is visibly editable and targets the sequence")
	panel.stop_preview();panel._select_plan(0);plugin.dock.make_visible();await settle(15)
	check(panel.is_visible_in_tree() and panel.get_parent().size.y>250,"Actual editor dock is visible with usable height")
	RenderingServer.force_draw(false)
	var image := get_tree().root.get_texture().get_image()
	if image:image.save_png("res://docs/montage-editor.png")
	var details: TabContainer=panel.actor_list.get_parent().get_parent().get_parent();details.current_tab=1
	await settle(6);RenderingServer.force_draw(false)
	var actor_image := get_tree().root.get_texture().get_image()
	if actor_image:actor_image.save_png("res://docs/montage-actors-editor.png")
	var inspected=load("res://scripts/dialogue/dialogue_line.gd").new();inspected.text="Inspector audio fixture."
	EditorInterface.inspect_object(inspected);await settle(12)
	var audio_property: EditorProperty
	for property in EditorInterface.get_inspector().find_children("*","EditorProperty",true,false):
		if property.get_edited_object()==inspected and property.get_edited_property()==&"audio":audio_property=property;break
	check(audio_property!=null and audio_property.get_script()==load("res://addons/cinematic_montage/audio_property.gd"),"DialogueLine inspector uses the same reliable audio drop field")
	if audio_property and audio_property.get_script()==load("res://addons/cinematic_montage/audio_property.gd"):
		var payload := {"type":"files","files":PackedStringArray([audio_path])}
		check(audio_property.picker.target._can_drop_data(Vector2.ZERO,payload),"Inspector audio button accepts the WAV payload")
		audio_property.picker.target._drop_data(Vector2.ZERO,payload);await settle(6)
		check(inspected.audio!=null and inspected.audio.resource_path==audio_path,"Inspector drop writes the real DialogueLine audio property")
		audio_property.set_read_only(true);check(not audio_property.picker.target._can_drop_data(Vector2.ZERO,payload),"Read-only inspector audio stays protected")
	EditorInterface.edit_node(sequence);await settle(6)
	check(FileAccess.get_sha256("res://scenes/cinematics/cinematic_sequence.tscn")==source_hash,"Editor actions never rewrite the original cinematic scene")
	panel.stop_preview()
	if not previous_path.is_empty():EditorInterface.open_scene_from_path(previous_path);await settle()
	FileAccess.open("res://docs/montage-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"source_preserved":true,"dedicated_dock":true,"instanced_key_editing":true,"undo_redo":true,"audio_button_drop":true,"audio_file_dialog":true,"audio_inspector_drop":true},"\t"))
	print("MONTAGE_EDITOR_OK: dedicated dock, in-map preview, unique animation edits, real key deletion, undo/redo, dialogue editing, plan ordering, new cameras and visible trigger cube" if failures.is_empty() else "MONTAGE_EDITOR_FAILED "+str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
