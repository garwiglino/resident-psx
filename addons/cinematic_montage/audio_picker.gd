@tool
extends HBoxContainer
const DropButton=preload("res://addons/cinematic_montage/audio_drop_button.gd")
## Accept actual audio resources, including files imported as AudioStreamPSX.
## Both the field and its buttons route drops through the same validation.
signal resource_changed(resource: AudioStream)
signal status_message(message: String)
var edited_resource: AudioStream:
	set(value):edited_resource=value;_refresh()
var editable := true:
	set(value):editable=value;_refresh()
var target: Button
var clear_button: Button
var dialog: EditorFileDialog
var _candidate_path := ""
var _candidate: AudioStream

func _init() -> void:
	target=DropButton.new();target.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	target.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;target.alignment=HORIZONTAL_ALIGNMENT_LEFT
	target.custom_minimum_size=Vector2(180,30);target.pressed.connect(_choose_file);add_child(target)
	clear_button=DropButton.new();clear_button.text="X";clear_button.tooltip_text="Retirer l'audio de cette replique."
	clear_button.pressed.connect(func():_assign(null));add_child(clear_button)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(target):return
	target.disabled=not editable;clear_button.disabled=not editable or edited_resource==null
	if edited_resource:
		var path := edited_resource.resource_path
		target.text=path.get_file() if not path.is_empty() else edited_resource.resource_name
		if target.text.is_empty():target.text="Audio de la replique"
		target.tooltip_text=path+"\nCliquer pour choisir un autre son, ou deposer un WAV / OGG / MP3."
	else:
		target.text="Deposer un son ou cliquer pour choisir"
		target.tooltip_text="Glisser un WAV / OGG / MP3 depuis le systeme de fichiers Godot, ou cliquer pour le choisir."

func _from_data(data: Variant) -> AudioStream:
	if not data is Dictionary:return null
	if data.get("type")=="resource":return data.get("resource") as AudioStream
	if data.get("type") not in ["files","files_and_dirs"]:return null
	var files: Variant=data.get("files",PackedStringArray())
	if files.size()!=1:return null
	var path := String(files[0])
	if path.get_extension().to_lower() not in ["wav","ogg","mp3","res","tres"]:return null
	if path==_candidate_path and _candidate:return _candidate
	if not ResourceLoader.exists(path):return null
	_candidate=ResourceLoader.load(path) as AudioStream;_candidate_path=path
	return _candidate

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	return editable and _from_data(data)!=null

func _drop_data(_position: Vector2,data: Variant) -> void:
	if not editable:return
	var stream := _from_data(data)
	if stream:_assign(stream)
	else:status_message.emit("Deposer un seul fichier audio WAV, OGG ou MP3 importe dans le projet.")

func _assign(stream: AudioStream) -> void:
	edited_resource=stream;resource_changed.emit(stream)

func _choose_file() -> void:
	if not editable:return
	if not is_instance_valid(dialog):
		dialog=EditorFileDialog.new();dialog.file_mode=EditorFileDialog.FILE_MODE_OPEN_FILE
		dialog.access=EditorFileDialog.ACCESS_RESOURCES;dialog.title="Audio de la replique"
		dialog.filters=PackedStringArray(["*.wav,*.ogg,*.mp3 ; Audio (WAV, OGG, MP3)","*.tres,*.res ; Ressource audio"])
		dialog.file_selected.connect(_file_selected);add_child(dialog)
	dialog.current_dir=edited_resource.resource_path.get_base_dir() if edited_resource and not edited_resource.resource_path.is_empty() else "res://assets/audio"
	dialog.popup_centered_ratio(.65)

func _file_selected(path: String) -> void:
	var stream := ResourceLoader.load(path) as AudioStream
	if stream:_assign(stream)
	else:status_message.emit("Ce fichier ne contient pas de son utilisable.")
