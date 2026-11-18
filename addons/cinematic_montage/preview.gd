@tool
extends RefCounted
## Safe camera and full-body pose preview. Method/audio tracks never run.
const Actors=preload("res://scripts/cinematics/cinematic_actors.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const AutomaticPages=preload("res://scripts/dialogue/automatic_pages.gd")
var snapshots: Dictionary={}
var actors=Actors.new()
var _plan: Resource
var _sequence: Node

static func automatic_dialogue_duration(dialogue: Resource) -> float:
	if not dialogue or not dialogue.is_exploration_call():return 0
	var style=load("res://assets/dialogue/default_style.tres");var font: Font=style.font
	var settings: Resource=load("res://assets/dialogue/settings.tres")
	if style.glyph_spacing!=0:
		var variation := FontVariation.new();variation.base_font=font;variation.spacing_glyph=style.glyph_spacing;font=variation
	var seconds := 0.0;var first := true
	var lines: Array=[]
	for line in dialogue.lines:
		if line and not Text.plain(line.text).strip_edges().is_empty():lines.append(line)
	for index in lines.size():
		var line: Resource=lines[index]
		var pages := Text.paginate(line.text,font,style.font_size,maxf(style.box.size.x-30,16),style.lines_per_page)
		if pages.is_empty():continue
		var duration: float=line.audio.get_length() if line.audio else 0.0
		var policy := AutomaticPages.new();policy.configure(pages,dialogue,duration,line)
		var closing: float=style.intercom_close_sound.get_length() if line.is_intercom and duration>0 and style.intercom_close_sound else 0.0
		var reading_end := maxf(policy.deadlines[-1],duration+closing)
		var tail: float=settings.delai_disparition_apres_voix
		var end := maxf(reading_end,duration+tail) if duration>0 else reading_end+tail
		seconds+=(style.opening_delay if first else style.speaker_delay)+(reading_end+policy.reply_gap if index+1<lines.size() else end);first=false
	return seconds

func _remember(camera: Camera3D) -> void:
	if snapshots.has(camera.get_instance_id()):return
	snapshots[camera.get_instance_id()]={"node":weakref(camera),"transform":camera.transform,"fov":camera.fov,"projection":camera.projection,"size":camera.size,"near":camera.near,"far":camera.far,"keep_aspect":camera.keep_aspect}

func sample(sequence: Node,plan: Resource,time: float,follow := false) -> void:
	if _plan!=plan or _sequence!=sequence:
		actors.restore();actors.prepare(sequence,[plan],true);actors.start_plan(plan);_plan=plan;_sequence=sequence
	actors.sample(time)
	var player := sequence.get_node_or_null(sequence.timeline_path) as AnimationPlayer
	if not player or not player.has_animation(plan.animation):return
	var clip := player.get_animation(plan.animation);var root := player.get_node(player.root_node)
	var at := clampf(plan.start_time+time,plan.start_time,plan.end_position(player))
	for track in clip.get_track_count():
		if not clip.track_is_enabled(track) or clip.track_get_key_count(track)==0:continue
		var path := clip.track_get_path(track)
		var camera := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Camera3D
		if not camera:continue
		_remember(camera)
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:camera.position=clip.position_track_interpolate(track,at)
			Animation.TYPE_ROTATION_3D:camera.quaternion=clip.rotation_track_interpolate(track,at)
			Animation.TYPE_SCALE_3D:camera.scale=clip.scale_track_interpolate(track,at)
			Animation.TYPE_VALUE:
				var property := String(path.get_concatenated_subnames())
				if property in ["fov","near","far","size","projection","keep_aspect","position","rotation","rotation_degrees","transform"]:camera.set_indexed(NodePath(property),clip.value_track_interpolate(track,at))
	if follow and Engine.is_editor_hint():
		var camera := sequence.get_node_or_null(plan.camera_path) as Camera3D
		var viewport := EditorInterface.get_editor_viewport_3d(0)
		var view := viewport.get_camera_3d() if viewport else null
		if camera and view:
			_remember(view);view.global_transform=camera.get_camera_transform();view.fov=camera.fov
			view.projection=camera.projection;view.keep_aspect=camera.keep_aspect;view.size=camera.size;view.near=camera.near;view.far=camera.far

func restore() -> void:
	actors.restore();_plan=null;_sequence=null
	for data in snapshots.values():
		var camera: Camera3D=data.node.get_ref()
		if not is_instance_valid(camera):continue
		camera.transform=data.transform
		for property in ["fov","projection","size","near","far","keep_aspect"]:camera.set(property,data[property])
	snapshots.clear()
