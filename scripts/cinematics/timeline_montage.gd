@tool
extends RefCounted
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
const Dialogue=preload("res://scripts/dialogue/dialogue_sequence.gd")

## Interpret existing camera/dialogue cues without rewriting any animation keys.
static func from_sequence(sequence: Node) -> Array[Shot]:
	var shots: Array[Shot]=[]
	var timeline := sequence.get_node_or_null(sequence.timeline_path) as AnimationPlayer
	if not timeline or not timeline.has_animation(sequence.animation):return shots
	var clip := timeline.get_animation(sequence.animation)
	var events: Array[Dictionary]=[]
	for track in clip.get_track_count():
		if clip.track_get_type(track)!=Animation.TYPE_METHOD or not clip.track_is_enabled(track) or String(clip.track_get_path(track))!=".":continue
		for key in clip.track_get_key_count(track):
			var value: Dictionary=clip.track_get_key_value(track,key)
			var method: String=String(value.get("method",""))
			if method not in ["cut_to","blend_to","show_dialogue"]:continue
			events.append({"time":clip.track_get_key_time(track,key),"method":method,"args":value.get("args",[])})
	events.sort_custom(func(a: Dictionary,b: Dictionary):return a.time<b.time or (is_equal_approx(a.time,b.time) and a.method!="show_dialogue" and b.method=="show_dialogue"))
	var current := Shot.new();current.camera_path=sequence.entry_camera;current.animation=sequence.animation;shots.append(current)
	for event in events:
		if event.time<0 or event.time>clip.length or event.args.is_empty():continue
		if event.method in ["cut_to","blend_to"]:
			var path := NodePath(event.args[0])
			if not sequence.get_node_or_null(path) is Camera3D:continue
			if event.time>current.start_time+.00001:
				current.end_time=event.time
				current=Shot.new();current.animation=sequence.animation;current.start_time=event.time;shots.append(current)
			current.camera_path=path
		else:
			var index := int(event.args[0])
			if index<0 or index>=sequence.dialogues.size() or not sequence.dialogues[index]:continue
			if current.dialogue and event.time>current.start_time+.00001:
				current.end_time=event.time
				var next := Shot.new();next.animation=sequence.animation;next.camera_path=current.camera_path;next.start_time=event.time
				current=next;shots.append(current)
			if current.dialogue:
				var combined: Dialogue=current.dialogue.duplicate(true)
				combined.lines.append_array(sequence.dialogues[index].lines);current.dialogue=combined
			else:current.dialogue=sequence.dialogues[index]
			current.dialogue_delay=event.time-current.start_time
	for index in shots.size():
		shots[index].title="Plan %02d" % (index+1)
		if not shots[index].dialogue:shots[index].progression=Shot.Progression.CAMERA
	return shots
