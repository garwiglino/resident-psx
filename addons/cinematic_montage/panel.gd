@tool
extends VBoxContainer
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
const Dialogue=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Operations=preload("res://addons/cinematic_montage/operations.gd")
const Preview=preload("res://addons/cinematic_montage/preview.gd")
const Timeline=preload("res://addons/cinematic_montage/timeline.gd")
const ActorClip=preload("res://scripts/cinematics/cinematic_actor_clip.gd")
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
const AudioPicker=preload("res://addons/cinematic_montage/audio_picker.gd")
var host: EditorPlugin
var sequence: Node
var selected := 0
var line_index := 0
var plans: Array[Shot]=[]
var cursor := 0.0
var playing := false
var preview_confirmed := false
var preview_elapsed := 0.0
var _automatic_preview_seconds := 0.0
var preview=Preview.new()
var _syncing := false
var _changing := false
var chooser: OptionButton
var plan_list: ItemList
var title_edit: LineEdit
var camera_edit: OptionButton
var animation_edit: OptionButton
var start_edit: SpinBox
var end_edit: SpinBox
var end_clip: CheckBox
var delay_edit: SpinBox
var mode_edit: OptionButton
var finish_edit: CheckBox
var dialogue_picker: EditorResourcePicker
var dialogue_bank: OptionButton
var dialogue_mode_edit: OptionButton
var line_edit: OptionButton
var speaker_edit: HBoxContainer
var text_edit: TextEdit
var graph: Control
var time_edit: SpinBox
var status: Label
var rule: Label
var play_button: Button
var follow_camera: CheckBox
var save_plans_button: Button
var _sequences: Array[Node]=[]
var actor_index := 0
var actor_list: OptionButton
var actor_path_edit: LineEdit
var actor_source: EditorResourcePicker
var actor_animation: OptionButton
var actor_start: SpinBox
var actor_offset: SpinBox
var actor_duration: SpinBox
var actor_speed: SpinBox
var actor_loop: CheckBox
var actor_root: CheckBox
var audio_picker: HBoxContainer
var audio_volume: SpinBox
var intercom_edit: CheckBox
var hangup_edit: CheckBox
var end_event_edit: LineEdit
var reply_gap_override_edit: CheckBox
var reply_gap_edit: SpinBox
var audition: Node

func _button(parent: Node,text: String,callback: Callable,tip := "") -> Button:
	var button := Button.new();button.text=text;button.tooltip_text=tip;button.pressed.connect(callback);parent.add_child(button);return button
func _label(parent: Node,text: String) -> Label:
	var label := Label.new();label.text=text;parent.add_child(label);return label
func _spin(parent: Node,text: String,callback: Callable) -> SpinBox:
	_label(parent,text)
	var spin := SpinBox.new();spin.min_value=0;spin.max_value=3600;spin.step=.01;spin.custom_minimum_size.x=88;spin.value_changed.connect(callback);parent.add_child(spin);return spin

func setup(plugin: EditorPlugin) -> void:
	host=plugin;custom_minimum_size=Vector2(730,350)
	var header := HBoxContainer.new();add_child(header)
	_label(header,"Cinematique")
	chooser=OptionButton.new();chooser.fit_to_longest_item=false;chooser.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;chooser.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(chooser);chooser.item_selected.connect(func(i: int):if i>=0 and i<_sequences.size():set_sequence(_sequences[i]))
	_button(header,"Nouvelle",host.create_sequence)
	_button(header,"Ajouter zone",host.create_zone,"Creer une vraie zone cube liee a cette cinematique.")
	save_plans_button=_button(header,"Conserver les plans",_materialize,"Enregistrer ces plans dans la scene sans changer les cles de l'ancienne timeline.")
	var split := HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(split)
	var left := VBoxContainer.new();left.custom_minimum_size.x=180;split.add_child(left)
	plan_list=ItemList.new();plan_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(plan_list);plan_list.item_selected.connect(_select_plan)
	var tools := HBoxContainer.new();left.add_child(tools)
	_button(tools,"+ Plan",add_plan);_button(tools,"Copier",duplicate_plan);_button(tools,"Retirer",remove_plan)
	tools=HBoxContainer.new();left.add_child(tools)
	_button(tools,"Monter",func():move_plan(-1));_button(tools,"Descendre",func():move_plan(1))
	var right := VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(right)
	var row := HBoxContainer.new();right.add_child(row)
	title_edit=LineEdit.new();title_edit.placeholder_text="Nom du plan";title_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(title_edit)
	title_edit.text_changed.connect(func(value: String):_edit_property(&"title",value,UndoRedo.MERGE_ENDS))
	camera_edit=OptionButton.new();camera_edit.custom_minimum_size.x=130;row.add_child(camera_edit);camera_edit.item_selected.connect(func(i: int):if not _syncing:_edit_property(&"camera_path",camera_edit.get_item_metadata(i)))
	_button(row,"+ Camera",host.create_camera)
	animation_edit=OptionButton.new();animation_edit.custom_minimum_size.x=130;row.add_child(animation_edit);animation_edit.item_selected.connect(func(i: int):if not _syncing:_edit_property(&"animation",StringName(animation_edit.get_item_text(i))))
	row=HBoxContainer.new();right.add_child(row)
	start_edit=_spin(row,"Debut",func(v: float):_edit_property(&"start_time",v))
	end_edit=_spin(row,"Fin",func(v: float):_edit_property(&"end_time",v))
	end_clip=CheckBox.new();end_clip.text="Fin du clip";row.add_child(end_clip);end_clip.toggled.connect(func(v: bool):if not _syncing:_edit_property(&"end_time",-1.0 if v else end_edit.value))
	delay_edit=_spin(row,"Texte apres",func(v: float):_edit_property(&"dialogue_delay",v))
	row=HBoxContainer.new();right.add_child(row)
	_label(row,"Passage")
	mode_edit=OptionButton.new();row.add_child(mode_edit)
	for text in ["Camera + dialogue valides","Camera seule / texte libre","Commande manuelle"]:mode_edit.add_item(text)
	mode_edit.item_selected.connect(func(i: int):_edit_property(&"progression",i))
	finish_edit=CheckBox.new();finish_edit.text="Valider le texte termine le mouvement";row.add_child(finish_edit);finish_edit.toggled.connect(func(v: bool):_edit_property(&"finish_camera_on_confirm",v))
	rule=Label.new();rule.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(rule)
	graph=Timeline.new();right.add_child(graph);graph.seek_requested.connect(_seek);graph.delete_requested.connect(func():camera_key(true));graph.play_requested.connect(toggle_play)
	graph.actor_selected.connect(func(index: int):actor_index=index;_refresh_fields())
	graph.actor_delete_requested.connect(func(index: int):actor_index=index;remove_actor())
	row=HBoxContainer.new();right.add_child(row)
	play_button=_button(row,"Lire",toggle_play);_button(row,"Arreter",stop_preview)
	time_edit=_spin(row,"Temps",_seek)
	_button(row,"Cle camera",func():camera_key(false),"Ajouter ou remplacer position, rotation et FOV au curseur.")
	_button(row,"Suppr. cle",func():camera_key(true),"Supprime vraiment les cles camera au curseur, meme dans une cinematique instanciee.")
	_button(row,"Animation Godot",open_animation,"Editer les autres pistes et les courbes dans la carte.")
	follow_camera=CheckBox.new();follow_camera.text="Voir camera";follow_camera.button_pressed=true;row.add_child(follow_camera)
	var tabs := TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(tabs)
	var dialogue_fields := VBoxContainer.new();dialogue_fields.name="Dialogue et voix";tabs.add_child(dialogue_fields)
	row=HBoxContainer.new();dialogue_fields.add_child(row)
	_label(row,"Dialogue du plan")
	dialogue_bank=OptionButton.new();dialogue_bank.custom_minimum_size.x=130;row.add_child(dialogue_bank)
	dialogue_bank.fit_to_longest_item=false;dialogue_bank.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	dialogue_bank.item_selected.connect(func(i: int):if not _syncing and i>0 and sequence:_edit_property(&"dialogue",sequence.dialogues[i-1]))
	dialogue_picker=EditorResourcePicker.new();dialogue_picker.base_type="DialogueSequence";dialogue_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(dialogue_picker)
	dialogue_picker.resource_changed.connect(func(resource: Resource):_edit_property(&"dialogue",resource))
	dialogue_picker.resource_selected.connect(func(resource: Resource,_inspect: bool):if resource:EditorInterface.inspect_object(resource))
	_button(row,"Nouveau texte",new_dialogue)
	_button(row,"Confirmer (simulation)",confirm_preview,"Simule la validation de tout le dialogue du plan. En jeu, la premiere pression revele le texte.")
	row=HBoxContainer.new();dialogue_fields.add_child(row);_label(row,"Mode du dialogue")
	dialogue_mode_edit=OptionButton.new();dialogue_mode_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(dialogue_mode_edit)
	dialogue_mode_edit.add_item("Conversation - validation manuelle");dialogue_mode_edit.add_item("Appel en exploration - automatique")
	dialogue_mode_edit.tooltip_text="En dehors d'une cinematique, Appel laisse toutes les commandes libres. Une cinematique garde la main sur sa camera et ses acteurs."
	dialogue_mode_edit.item_selected.connect(func(index: int):_edit_dialogue_property(&"mode",index))
	row=HBoxContainer.new();dialogue_fields.add_child(row)
	line_edit=OptionButton.new();row.add_child(line_edit);line_edit.item_selected.connect(func(i: int):line_index=i;_refresh_fields())
	speaker_edit=preload("res://addons/cinematic_montage/speaker_picker.gd").new();speaker_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(speaker_edit);speaker_edit.speaker_selected.connect(_select_speaker)
	_button(row,"+ Replique",func():_change_lines(false));_button(row,"- Replique",func():_change_lines(true))
	text_edit=TextEdit.new();text_edit.custom_minimum_size.y=65;text_edit.size_flags_vertical=Control.SIZE_EXPAND_FILL;text_edit.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;dialogue_fields.add_child(text_edit)
	text_edit.text_changed.connect(func():_edit_line(&"text",text_edit.text))
	row=HBoxContainer.new();dialogue_fields.add_child(row);_label(row,"Audio")
	audio_picker=AudioPicker.new();audio_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(audio_picker)
	audio_picker.resource_changed.connect(func(value: Resource):_edit_line(&"audio",value))
	audio_picker.status_message.connect(func(message: String):status.text=message)
	intercom_edit=CheckBox.new();intercom_edit.text="Is Intercom";row.add_child(intercom_edit);intercom_edit.toggled.connect(func(value: bool):_edit_line(&"is_intercom",value))
	audio_volume=_spin(row,"dB",func(value: float):_edit_line(&"audio_volume_db",value));audio_volume.min_value=-40;audio_volume.max_value=0;audio_volume.step=.5
	_button(row,"Ecouter",preview_voice);_button(row,"Couper",func():audition.stop_line(false))
	row=HBoxContainer.new();dialogue_fields.add_child(row);_label(row,"Fin de replique")
	hangup_edit=CheckBox.new();hangup_edit.text="Raccrocher intercom";row.add_child(hangup_edit)
	hangup_edit.toggled.connect(func(value: bool):_edit_line(&"end_intercom",value))
	end_event_edit=LineEdit.new();end_event_edit.placeholder_text="Evenement monde (facultatif)";end_event_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(end_event_edit)
	end_event_edit.tooltip_text="Identifiant WorldEvents emis une seule fois apres toute la replique. Laisser vide si aucun."
	end_event_edit.text_submitted.connect(func(value: String):_edit_line(&"end_event_id",StringName(value.strip_edges())))
	end_event_edit.focus_exited.connect(func():_edit_line(&"end_event_id",StringName(end_event_edit.text.strip_edges())))
	row=HBoxContainer.new();dialogue_fields.add_child(row);_label(row,"Delai de reponse")
	reply_gap_override_edit=CheckBox.new();reply_gap_override_edit.text="Personnaliser pour cette replique";row.add_child(reply_gap_override_edit)
	reply_gap_override_edit.tooltip_text="Appel automatique : pause apres cette replique, avant la suivante. Decoche = delai general du dialogue."
	reply_gap_override_edit.toggled.connect(func(value: bool):_edit_line(&"override_reply_gap",value))
	reply_gap_edit=_spin(row,"secondes",func(value: float):_edit_line(&"reply_gap",value));reply_gap_edit.max_value=30;reply_gap_edit.step=.05
	audition=Voice.new();audition.name="AuditionDialogue";add_child(audition)
	var actors_fields := VBoxContainer.new();actors_fields.name="Personnages";tabs.add_child(actors_fields)
	row=HBoxContainer.new();actors_fields.add_child(row)
	actor_list=OptionButton.new();actor_list.fit_to_longest_item=false;actor_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(actor_list);actor_list.item_selected.connect(func(index: int):actor_index=index;_refresh_fields())
	_button(row,"+ Personnage / animation",add_actor);_button(row,"Retirer",remove_actor)
	row=HBoxContainer.new();actors_fields.add_child(row);_label(row,"Personnage")
	actor_path_edit=LineEdit.new();actor_path_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(actor_path_edit);actor_path_edit.text_submitted.connect(func(value: String):_edit_actor(&"actor_path",NodePath(value)))
	_button(row,"Utiliser la selection",assign_selected_actor,"Selectionner le personnage dans l'arbre de la carte, puis cliquer ici.")
	row=HBoxContainer.new();actors_fields.add_child(row);_label(row,"Animation GLB (facultatif)")
	actor_source=EditorResourcePicker.new();actor_source.base_type="PackedScene";actor_source.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(actor_source);actor_source.resource_changed.connect(func(value: Resource):_edit_actor(&"source",value))
	actor_animation=OptionButton.new();actor_animation.custom_minimum_size.x=180;row.add_child(actor_animation);actor_animation.item_selected.connect(func(index: int):_edit_actor(&"animation",StringName(actor_animation.get_item_text(index))))
	row=HBoxContainer.new();actors_fields.add_child(row)
	actor_start=_spin(row,"Debut",func(value: float):_edit_actor(&"start_time",value))
	actor_offset=_spin(row,"Dans le clip",func(value: float):_edit_actor(&"source_offset",value))
	actor_duration=_spin(row,"Duree (-1 = clip)",func(value: float):_edit_actor(&"duration",value));actor_duration.min_value=-1
	actor_speed=_spin(row,"Vitesse",func(value: float):_edit_actor(&"speed",value));actor_speed.min_value=.05;actor_speed.max_value=4;actor_speed.step=.05
	row=HBoxContainer.new();actors_fields.add_child(row)
	actor_loop=CheckBox.new();actor_loop.text="Boucler";row.add_child(actor_loop);actor_loop.toggled.connect(func(value: bool):_edit_actor(&"loop",value))
	actor_root=CheckBox.new();actor_root.text="Appliquer le root motion";row.add_child(actor_root);actor_root.toggled.connect(func(value: bool):_edit_actor(&"apply_root_motion",value))
	_label(actors_fields,"Le curseur anime aussi les personnages. Arreter ou enregistrer restaure les poses de l'editeur.")
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
	refresh_scene()

func refresh_scene() -> void:
	chooser.clear();_sequences.clear()
	var root := EditorInterface.get_edited_scene_root()
	if root:
		if root is Sequence:_sequences.append(root)
		for node in root.find_children("*","CinematicSequence3D",true,false):_sequences.append(node)
	for node in _sequences:chooser.add_item(String(root.get_path_to(node)) if node!=root else node.name)
	if not is_instance_valid(sequence) or sequence not in _sequences:set_sequence(_sequences[0] if not _sequences.is_empty() else null)
	elif sequence:chooser.select(_sequences.find(sequence))
	if not sequence:status.text="Selectionner une cinematique dans la carte, ou cliquer sur Nouvelle."

func set_sequence(value: Node) -> void:
	if value==sequence and is_instance_valid(sequence):refresh();return
	stop_preview()
	if is_instance_valid(sequence) and sequence.montage_changed.is_connected(_sequence_changed):sequence.montage_changed.disconnect(_sequence_changed)
	sequence=value;selected=0;line_index=0;cursor=0
	if sequence:
		sequence.montage_changed.connect(_sequence_changed)
		if sequence not in _sequences:
			_sequences.append(sequence)
			var root := EditorInterface.get_edited_scene_root()
			chooser.add_item(String(root.get_path_to(sequence)) if root and root!=sequence else String(sequence.name))
		chooser.select(_sequences.find(sequence))
	refresh()

func _sequence_changed() -> void:
	if not _changing:stop_preview();refresh()

func refresh() -> void:
	var refreshed: Array[Shot]=[]
	if is_instance_valid(sequence):refreshed.assign(sequence.get_plans())
	plans=refreshed
	selected=clampi(selected,0,maxi(plans.size()-1,0));plan_list.clear()
	for index in plans.size():plan_list.add_item("%02d  %s" % [index+1,plans[index].title]);plan_list.set_item_tooltip(index,String(plans[index].camera_path))
	if not plans.is_empty():plan_list.select(selected)
	save_plans_button.disabled=not sequence or not sequence.plans.is_empty()
	_refresh_fields()

func current() -> Resource:return plans[selected] if selected>=0 and selected<plans.size() else null

func _select_plan(index: int) -> void:
	stop_preview();selected=index;line_index=0;cursor=0;preview_elapsed=0;preview_confirmed=false;_refresh_fields()

func _refresh_fields() -> void:
	_syncing=true
	var plan := current();var player := Operations.timeline(sequence) if sequence else null
	camera_edit.clear();animation_edit.clear();line_edit.clear();dialogue_bank.clear();dialogue_bank.add_item("Texte existant...")
	if sequence:
		for resource in sequence.dialogues:
			var text: String=resource.lines[0].text if resource and not resource.lines.is_empty() else "Dialogue vide"
			dialogue_bank.add_item(text.left(28));dialogue_bank.set_item_tooltip(dialogue_bank.item_count-1,text)
		for camera in sequence.find_children("*","Camera3D",true,false):
			camera_edit.add_item(String(sequence.get_path_to(camera)));camera_edit.set_item_metadata(camera_edit.item_count-1,sequence.get_path_to(camera))
			if plan and sequence.get_path_to(camera)==plan.camera_path:camera_edit.select(camera_edit.item_count-1)
	if player:
		for animation in player.get_animation_list():
			animation_edit.add_item(animation)
			if plan and animation==plan.animation:animation_edit.select(animation_edit.item_count-1)
	if plan:
		title_edit.text=plan.title;start_edit.value=plan.start_time;end_clip.button_pressed=plan.end_time<0
		end_edit.value=maxf(plan.end_position(player),0);end_edit.editable=plan.end_time>=0
		delay_edit.value=plan.dialogue_delay;mode_edit.select(plan.progression);finish_edit.button_pressed=plan.finish_camera_on_confirm
		finish_edit.disabled=plan.progression!=Shot.Progression.LINKED or plan.dialogue==null
		dialogue_picker.edited_resource=plan.dialogue
		dialogue_mode_edit.disabled=plan.dialogue==null;dialogue_mode_edit.select(plan.dialogue.mode if plan.dialogue else 0)
		if plan.dialogue:
			line_index=clampi(line_index,0,maxi(plan.dialogue.lines.size()-1,0))
			for index in plan.dialogue.lines.size():line_edit.add_item("Replique %d" % (index+1))
			if not plan.dialogue.lines.is_empty():line_edit.select(line_index)
		var line=plan.dialogue.lines[line_index] if plan.dialogue and not plan.dialogue.lines.is_empty() else null
		speaker_edit.current_speaker=line.speaker if line else "";text_edit.text=line.text if line else ""
		text_edit.editable=line!=null;speaker_edit.editable=line!=null
		audio_picker.edited_resource=line.audio if line else null;intercom_edit.button_pressed=line.is_intercom if line else false
		intercom_edit.disabled=line==null;audio_volume.editable=line!=null;audio_volume.value=line.audio_volume_db if line else -8.0
		hangup_edit.disabled=line==null;hangup_edit.button_pressed=line.end_intercom if line else false
		end_event_edit.editable=line!=null;end_event_edit.text=String(line.end_event_id) if line else ""
		reply_gap_override_edit.disabled=line==null;reply_gap_override_edit.button_pressed=line.override_reply_gap if line else false
		reply_gap_edit.editable=line!=null and line.override_reply_gap
		reply_gap_edit.value=line.reply_gap if line else .2
		audio_picker.editable=line!=null
		if not line:audio_picker.target.tooltip_text="Creer d'abord un dialogue avec Nouveau texte, puis choisir sa replique."
	_refresh_actor_fields()
	_automatic_preview_seconds=Preview.automatic_dialogue_duration(plan.dialogue) if plan else 0.0
	_update_summary();_syncing=false

func _refresh_actor_fields() -> void:
	actor_list.clear();actor_animation.clear()
	var plan := current();var cue: Resource
	if plan:
		actor_index=clampi(actor_index,0,maxi(plan.actors.size()-1,0))
		for item in plan.actors:actor_list.add_item(String(item.actor_path).get_file()+" / "+String(item.animation))
		if not plan.actors.is_empty():actor_list.select(actor_index);cue=plan.actors[actor_index]
	actor_path_edit.text=String(cue.actor_path) if cue else "";actor_path_edit.editable=cue!=null
	actor_source.edited_resource=cue.source if cue else null
	if cue:
		for key in cue.animations(sequence):
			actor_animation.add_item(key)
			if key==cue.animation:actor_animation.select(actor_animation.item_count-1)
	actor_start.value=cue.start_time if cue else 0;actor_offset.value=cue.source_offset if cue else 0
	actor_duration.value=cue.duration if cue else -1;actor_speed.value=cue.speed if cue else 1
	actor_loop.button_pressed=cue.loop if cue else false;actor_root.button_pressed=cue.apply_root_motion if cue else true

func _update_summary() -> void:
	var plan := current();var player := Operations.timeline(sequence) if sequence else null
	if not plan or not player:rule.text="Aucun plan selectionne.";graph.visible=false;return
	graph.visible=true;graph.duration=plan.duration(player);graph.cursor=cursor;graph.dialogue_delay=plan.dialogue_delay;graph.has_dialogue=plan.dialogue!=null;graph.keys=Operations.key_times(sequence,plan);graph.queue_redraw()
	graph.automatic_dialogue=plan.dialogue!=null and plan.dialogue.is_exploration_call()
	graph.camera_duration=plan.camera_duration(player);graph.actor_rows=[];graph.selected_actor=actor_index
	for cue in plan.actors:graph.actor_rows.append({"label":String(cue.actor_path).get_file(),"animation":String(cue.animation),"start":cue.start_time,"duration":cue.length(sequence)})
	var line: Resource=plan.dialogue.lines[line_index] if plan.dialogue and line_index<plan.dialogue.lines.size() else null
	graph.audio_duration=line.audio.get_length() if line and line.audio else 0;graph.is_intercom=line.is_intercom if line else false;graph.resize_rows()
	_syncing=true;time_edit.max_value=graph.duration;time_edit.value=cursor;_syncing=false
	if plan.progression==Shot.Progression.MANUAL:rule.text="Fin du mouvement : image maintenue. Passage par commande manuelle."
	elif plan.progression==Shot.Progression.CAMERA:rule.text="La camera passe au plan suivant a la fin. Le texte ouvert continue librement."
	elif not plan.dialogue:rule.text="Sans dialogue : passage automatique a la fin du mouvement."
	elif graph.automatic_dialogue:rule.text="Le texte avance avec les WAV. Le plan attend la fin automatique des repliques."+(" La fin du texte termine le mouvement." if plan.finish_camera_on_confirm else " Le mouvement termine naturellement.")
	elif plan.finish_camera_on_confirm:rule.text="Camera finie : attend le texte. Texte valide : termine le mouvement puis passe au plan suivant."
	else:rule.text="Attend les deux : fin naturelle du mouvement ET validation du dialogue."
	var error: String=plan.validation_error(sequence,player)
	status.text=error if not error.is_empty() else "Entree et sortie en cut. Les animations et dialogues continuent separement."
	if selected<plan_list.item_count:plan_list.set_item_text(selected,"%02d  %s" % [selected+1,plan.title])

func change_plans(next: Array[Shot],description: String,merge := UndoRedo.MERGE_DISABLE) -> void:
	if not is_instance_valid(sequence):return
	_changing=true
	var undo := host.get_undo_redo();undo.create_action(description,merge,sequence)
	undo.add_do_property(sequence,"plans",next);undo.add_undo_property(sequence,"plans",sequence.plans);undo.commit_action()
	plans=sequence.get_plans();_changing=false;_update_summary()

func _edit_property(property: StringName,value: Variant,merge := UndoRedo.MERGE_DISABLE) -> void:
	if _syncing or not current() or current().get(property)==value:return
	if property!=&"title":stop_preview()
	var next := Operations.copy_plans(sequence);next[selected].set(property,value)
	change_plans(next,"Regler le plan : "+String(property),merge)
	if property not in [&"title"]:_refresh_fields()

func _materialize() -> void:
	if not sequence:return
	change_plans(Operations.copy_plans(sequence),"Conserver le montage par plans");refresh()

func add_plan() -> void:
	if not sequence:host.create_sequence();return
	stop_preview();var next := Operations.copy_plans(sequence);var plan := Shot.new()
	plan.title="Plan %02d" % (next.size()+1)
	if current():plan.camera_path=current().camera_path;plan.animation=current().animation
	elif not sequence.entry_camera.is_empty():plan.camera_path=sequence.entry_camera;plan.animation=sequence.animation
	var library := Operations.new_animation(sequence,plan)
	if library.is_empty():return
	plan.animation=library.animation;next.append(plan);selected=next.size()-1;_plans_and_library(next,library,"Ajouter un plan");refresh()
func duplicate_plan() -> void:
	if not current():return
	stop_preview();var next := Operations.copy_plans(sequence);var library := Operations.new_animation(sequence,next[selected],true)
	if library.is_empty():return
	next.insert(selected+1,next[selected].duplicate(true));selected+=1;next[selected].title+=" copie";next[selected].animation=library.animation
	_plans_and_library(next,library,"Dupliquer un plan");refresh()

func _plans_and_library(next: Array[Shot],library: Dictionary,description: String) -> void:
	_changing=true;var undo := host.get_undo_redo();undo.create_action(description,UndoRedo.MERGE_DISABLE,sequence)
	host.make_instance_editable(undo,sequence)
	undo.add_do_method(sequence,"set_montage_library",library.name,library.after);undo.add_do_property(sequence,"plans",next)
	undo.add_undo_property(sequence,"plans",sequence.plans);undo.add_undo_method(sequence,"set_montage_library",library.name,library.before)
	undo.commit_action();_changing=false;plans=sequence.get_plans()
func remove_plan() -> void:
	if not current() or plans.size()<=1:status.text="Garder au moins un plan. Retirer la cinematique pour supprimer le montage.";return
	stop_preview();var next := Operations.copy_plans(sequence);next.remove_at(selected);selected=maxi(selected-1,0);change_plans(next,"Retirer un plan");refresh()
func move_plan(direction: int) -> void:
	if not current() or selected+direction<0 or selected+direction>=plans.size():return
	stop_preview();var next := Operations.copy_plans(sequence);var value=next[selected];next[selected]=next[selected+direction];next[selected+direction]=value;selected+=direction
	change_plans(next,"Deplacer un plan");refresh()

func new_dialogue() -> void:
	var resource := Dialogue.new();resource.lines.append(Line.new());resource.lines[0].text="Nouveau dialogue."
	resource.lines[0].speaker=preload("res://assets/dialogue/speakers.tres").first_name()
	_edit_property(&"dialogue",resource)

func _edit_dialogue_property(property: StringName,value: Variant) -> void:
	if _syncing or not current() or not current().dialogue or current().dialogue.get(property)==value:return
	stop_preview();var next := Operations.copy_plans(sequence);next[selected].dialogue=next[selected].dialogue.duplicate(false)
	next[selected].dialogue.set(property,value);change_plans(next,"Regler le dialogue : "+String(property));_refresh_fields()
func _edit_line(property: StringName,value: Variant) -> void:
	if _syncing or not current() or not current().dialogue or line_index>=current().dialogue.lines.size():return
	if current().dialogue.lines[line_index].get(property)==value:return
	stop_preview()
	var next := Operations.copy_plans(sequence);next[selected].dialogue=next[selected].dialogue.duplicate(false);next[selected].dialogue.lines=next[selected].dialogue.lines.duplicate()
	next[selected].dialogue.lines[line_index]=next[selected].dialogue.lines[line_index].duplicate(false)
	next[selected].dialogue.lines[line_index].set(property,value);change_plans(next,"Texte du plan : "+String(property),UndoRedo.MERGE_ENDS)
	if property not in [&"text",&"speaker"]:_refresh_fields()

func _select_speaker(name: String,apply_default: bool,intercom: bool) -> void:
	if _syncing or not current() or not current().dialogue or line_index>=current().dialogue.lines.size():return
	var line: Resource=current().dialogue.lines[line_index]
	if line.speaker==name and (not apply_default or line.is_intercom==intercom):return
	stop_preview()
	var next := Operations.copy_plans(sequence);next[selected].dialogue=next[selected].dialogue.duplicate(false);next[selected].dialogue.lines=next[selected].dialogue.lines.duplicate()
	var changed: Resource=line.duplicate(false);changed.speaker=name
	if apply_default:changed.is_intercom=intercom
	next[selected].dialogue.lines[line_index]=changed
	change_plans(next,"Choisir le locuteur");_refresh_fields()

func preview_voice() -> void:
	if current() and current().dialogue and line_index<current().dialogue.lines.size():audition.play_line(current().dialogue.lines[line_index],load("res://assets/dialogue/default_style.tres"))

func _selected_actor() -> Node3D:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Node3D and node!=sequence and (node is CharacterBody3D or not node.find_children("*","AnimationPlayer",true,false).is_empty() or not node.find_children("*","Skeleton3D",true,false).is_empty()):return node
	return null

func add_actor() -> void:
	if not current():return
	stop_preview();var next := Operations.copy_plans(sequence);next[selected].actors=next[selected].actors.duplicate()
	var cue := ActorClip.new();var target := _selected_actor()
	if target:cue.actor_path=sequence.get_path_to(target)
	elif EditorInterface.get_edited_scene_root().get_node_or_null("Player"):cue.actor_path=sequence.get_path_to(EditorInterface.get_edited_scene_root().get_node("Player"))
	var clips := cue.animations(sequence)
	if not clips.is_empty():cue.animation=clips.keys()[0]
	next[selected].actors.append(cue);actor_index=next[selected].actors.size()-1;change_plans(next,"Ajouter une piste de personnage");_refresh_fields()

func remove_actor() -> void:
	if not current() or current().actors.is_empty():return
	stop_preview();var next := Operations.copy_plans(sequence);next[selected].actors=next[selected].actors.duplicate();next[selected].actors.remove_at(actor_index)
	actor_index=maxi(actor_index-1,0);change_plans(next,"Retirer une animation de personnage");_refresh_fields()

func assign_selected_actor() -> void:
	var target := _selected_actor()
	if target:_edit_actor(&"actor_path",sequence.get_path_to(target))
	else:status.text="Selectionner un personnage dans l'arbre de la carte."

func _edit_actor(property: StringName,value: Variant) -> void:
	if _syncing or not current() or actor_index>=current().actors.size():return
	stop_preview();var next := Operations.copy_plans(sequence);next[selected].actors=next[selected].actors.duplicate()
	var cue: Resource=next[selected].actors[actor_index].duplicate(false);next[selected].actors[actor_index]=cue;cue.set(property,value)
	if property in [&"actor_path",&"source"]:
		var clips: Dictionary=cue.animations(sequence)
		if not clips.has(cue.animation) and not clips.is_empty():cue.animation=clips.keys()[0]
	change_plans(next,"Animation de personnage : "+String(property));_refresh_fields()
func _change_lines(remove: bool) -> void:
	if not current():return
	if not current().dialogue:new_dialogue();return
	stop_preview()
	var next := Operations.copy_plans(sequence);next[selected].dialogue=next[selected].dialogue.duplicate(true)
	if remove:
		if next[selected].dialogue.lines.size()<=1:return
		next[selected].dialogue.lines.remove_at(line_index);line_index=maxi(line_index-1,0)
	else:
		next[selected].dialogue.lines.append(Line.new());line_index=next[selected].dialogue.lines.size()-1;next[selected].dialogue.lines[line_index].text="Nouvelle replique."
		next[selected].dialogue.lines[line_index].speaker=preload("res://assets/dialogue/speakers.tres").first_name()
	change_plans(next,"Modifier les repliques du plan");_refresh_fields()

func _seek(time: float) -> void:
	if _syncing or not current():return
	cursor=clampf(time,0,current().duration(Operations.timeline(sequence)));preview.sample(sequence,current(),cursor,follow_camera.button_pressed);_update_summary()
func toggle_play() -> void:
	if not current():return
	if cursor>=current().duration(Operations.timeline(sequence))-.00001:cursor=0;preview_elapsed=0;preview_confirmed=false
	playing=not playing;play_button.text="Pause" if playing else "Lire"
	if playing:_seek(cursor)
func stop_preview() -> void:
	playing=false;preview.restore()
	if is_instance_valid(audition):audition.stop_line(false)
	if play_button:play_button.text="Lire"
func confirm_preview() -> void:
	if not current():return
	if current().progression==Shot.Progression.MANUAL:
		_seek(current().duration(Operations.timeline(sequence)));_next_preview();return
	if current().dialogue and preview_elapsed<current().dialogue_delay:
		status.text="Le dialogue commence a %.2f s. Lancer la lecture avant de le confirmer." % current().dialogue_delay;return
	preview_confirmed=true
	if current().progression==Shot.Progression.LINKED and current().finish_camera_on_confirm:_seek(current().duration(Operations.timeline(sequence)))
	_preview_gate()
func _preview_gate() -> void:
	if not current():return
	if cursor<current().duration(Operations.timeline(sequence))-.00001:return
	if current().progression==Shot.Progression.MANUAL:status.text="Image maintenue. Selectionner le plan suivant pour continuer.";return
	if current().dialogue and current().progression==Shot.Progression.LINKED and not preview_confirmed:
		status.text="Image maintenue : fin automatique des repliques en attente." if current().dialogue.is_exploration_call() else "Image maintenue : confirmer le dialogue du plan pour continuer."
		return
	_next_preview()

func _next_preview() -> void:
	if selected+1<plans.size():
		selected+=1;line_index=0;cursor=0;preview_elapsed=0;preview_confirmed=false;playing=true;plan_list.select(selected);_refresh_fields();_seek(0)
	else:playing=false;play_button.text="Lire";status.text="Fin du montage. Arreter restaure la vue et les cameras."
func _process(delta: float) -> void:
	if EditorInterface.is_playing_scene():
		if playing or (is_instance_valid(audition) and audition.phase!=audition.Phase.SILENT):stop_preview()
		return
	if not playing or not current() or not is_instance_valid(sequence):return
	preview_elapsed+=delta
	_seek(cursor+delta*Operations.timeline(sequence).speed_scale)
	if current().dialogue and current().dialogue.is_exploration_call() and not preview_confirmed and preview_elapsed>=current().dialogue_delay+_automatic_preview_seconds:
		preview_confirmed=true
		if current().progression==Shot.Progression.LINKED and current().finish_camera_on_confirm:_seek(current().duration(Operations.timeline(sequence)))
		_preview_gate();return
	if cursor>=current().duration(Operations.timeline(sequence))-.00001:
		_preview_gate()

func camera_key(remove: bool) -> void:
	if not current():return
	var result := Operations.camera_keys(sequence,current(),cursor,remove)
	if result.is_empty() or result.changed==0:status.text="Aucune cle camera a ce temps. Cliquer sur un losange pour la choisir.";return
	stop_preview();var undo := host.get_undo_redo();undo.create_action("Supprimer une cle camera" if remove else "Poser une cle camera",UndoRedo.MERGE_DISABLE,sequence)
	host.make_instance_editable(undo,sequence)
	undo.add_do_method(sequence,"set_montage_library",result.name,result.after);undo.add_undo_method(sequence,"set_montage_library",result.name,result.before);undo.commit_action()
	_refresh_fields();_seek(cursor)
func open_animation() -> void:
	if not current():return
	stop_preview();var player := Operations.timeline(sequence);player.assigned_animation=current().animation
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(player);EditorInterface.edit_node(player)
