class_name DialogueController
extends CanvasLayer
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Style=preload("res://scripts/dialogue/dialogue_style.gd")
const View=preload("res://scripts/dialogue/dialogue_view.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
const AutomaticPages=preload("res://scripts/dialogue/automatic_pages.gd")
var settings: Resource=preload("res://assets/dialogue/settings.tres")
enum State { IDLE, OPENING, TYPING, WAITING }
signal session_started
signal session_finished
signal sequence_started(sequence: Resource)
signal sequence_finished(id: StringName,cancelled: bool)
signal sequence_completed(sequence: Resource,cancelled: bool)
signal line_started(line: Resource,index: int)
signal line_finished(line: Resource,index: int)
signal page_revealed(line: Resource,page: int)
signal letter_revealed(character: String)
signal control_lock_changed(locked: bool)
## Internal channel role. The gameplay mode is selected on DialogueSequence.
@export_storage var exploration_channel := false
@export var style: Style=preload("res://assets/dialogue/default_style.tres")
@export var advance_action: StringName=&"dialogue_advance"
@export_range(1,32,1) var maximum_queue := 8
var state := State.IDLE
var suspended := false
var view: Control
var letter_audio: AudioStreamPlayer
var window_audio: AudioStreamPlayer
var voice_audio: Node
var _voice_pending := false
var _line_completion_sent := false
var _finishing_line := false
var _caption_tail_elapsed := 0.0
var _line_view_hidden := false
var _opening_stream: AudioStream
var _closing_stream: AudioStream
var current_sequence: Sequence
var current_line: Line
var page_index := 0
var line_index := 0
var _pages: Array[String]=[]
var _queue: Array[Sequence]=[]
var _session := false
var _revision := 0
var _opening_left := 0.0
var _budget := 0.0
var _next_delay := 0.0
var _visible_count := 0
var _indicator_clock := 0.0
var _confirm_held := false
var _reservation: WeakRef
var _controls_locked := false
var _automatic=AutomaticPages.new()

func _enter_tree() -> void:add_to_group("dialogue_controllers")

func _exit_tree() -> void:
	if _session:
		_session=false;_queue.clear();session_finished.emit()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;layer=19 if exploration_channel else 20
	if not style:style=Style.new()
	view=View.new();add_child(view);view.configure(style)
	letter_audio=AudioStreamPlayer.new();letter_audio.name="LetterTick";letter_audio.max_polyphony=1
	AudioRouting.set_category(letter_audio,&"UI");AudioRouting.set_reverb_enabled(letter_audio,false)
	letter_audio.process_mode=Node.PROCESS_MODE_ALWAYS
	letter_audio.stream=get_node("/root/PSXAudio").prepare(style.letter_sound)
	letter_audio.volume_db=style.letter_volume_db;add_child(letter_audio)
	window_audio=AudioStreamPlayer.new();window_audio.name="WindowSound";window_audio.max_polyphony=1
	AudioRouting.set_category(window_audio,&"UI");AudioRouting.set_reverb_enabled(window_audio,false)
	window_audio.process_mode=Node.PROCESS_MODE_PAUSABLE;add_child(window_audio)
	voice_audio=Voice.new();voice_audio.name="ReplyAudio";add_child(voice_audio)
	_prepare_window_sounds()
	if not InputMap.has_action(advance_action):
		InputMap.add_action(advance_action)
		for code in [KEY_E,KEY_SPACE,KEY_ENTER]:
			var key := InputEventKey.new();key.physical_keycode=code;InputMap.action_add_event(advance_action,key)
		var pad := InputEventJoypadButton.new();pad.button_index=JOY_BUTTON_A;InputMap.action_add_event(advance_action,pad)
	set_process(false)

static func find_for(node: Node,resource: Sequence=null) -> Node:
	var controllers := node.get_tree().get_nodes_in_group("dialogue_controllers")
	var want_call := resource!=null and resource.is_exploration_call()
	var ancestor: Node=node
	while ancestor:
		for controller in controllers:
			if controller.exploration_channel!=want_call:continue
			if ancestor==controller or ancestor.is_ancestor_of(controller):return controller
		ancestor=ancestor.get_parent()
	if want_call:return find_for(node)
	return null

func is_active() -> bool:return _session
func is_automatic() -> bool:return current_sequence!=null and current_sequence.is_exploration_call()
func blocks_controls() -> bool:return _session and _controls_locked

func _set_control_lock(value: bool) -> void:
	if _controls_locked==value:return
	_controls_locked=value;control_lock_changed.emit(value)

func reservation_owner() -> Node:
	return _reservation.get_ref() if _reservation else null

func reserve(owner: Node) -> bool:
	if not is_instance_valid(owner) or _session or (reservation_owner()!=null and reservation_owner()!=owner):return false
	_reservation=weakref(owner);return true

func release_reservation(owner: Node) -> void:
	if reservation_owner()==owner:_reservation=null

func _prepare_window_sounds() -> void:
	var spu := get_node("/root/PSXAudio")
	_opening_stream=spu.prepare(style.opening_sound);_closing_stream=spu.prepare(style.closing_sound)

func _play_window_sound(opening: bool) -> void:
	window_audio.stream=_opening_stream if opening else _closing_stream
	window_audio.volume_db=style.window_volume_db
	if window_audio.stream:AudioRouting.play(window_audio)

func play(sequence: Sequence,enqueue_if_busy := true,owner: Node=null) -> bool:
	if not is_node_ready() or not sequence or get_tree().paused:return false
	# Cinematic-owned text stays on the reserved channel, even if automatic.
	if owner==null and sequence.is_exploration_call()!=exploration_channel:
		var channel := find_for(self,sequence)
		if channel and channel!=self:return channel.play(sequence,enqueue_if_busy,owner)
	if suspended and not exploration_channel:return false
	if reservation_owner()!=null and reservation_owner()!=owner:return false
	if not _session:view.configure(style)
	var snapshot: Sequence=sequence.duplicate(true)
	var valid: Array[Line]=[]
	for line in snapshot.lines:
		if line and not Text.plain(line.text).strip_edges().is_empty():valid.append(line)
	if valid.is_empty():return false
	# Validate every line before taking control. No partial conversation is
	# opened if a single unbreakable word is wider than the configured box.
	for line in valid:
		if Text.paginate(line.text,view.text_font,style.font_size,view.text_rect().size.x,style.lines_per_page).is_empty():return false
		if line.audio:line.voice_stream()
	snapshot.lines=valid
	if suspended:
		if ((_session or not _queue.is_empty()) and not enqueue_if_busy) or _queue.size()>=maximum_queue:return false
		_queue.append(snapshot);return true
	if _session:
		if not enqueue_if_busy or _queue.size()>=maximum_queue:return false
		_queue.append(snapshot);_update_indicator();return true
	return _open_session(snapshot)

func _open_session(snapshot: Sequence) -> bool:
	_session=true;_revision+=1
	var token := _revision
	_confirm_held=Input.is_action_pressed(advance_action)
	session_started.emit()
	if token!=_revision or not _session:return true
	_prepare_window_sounds();_play_window_sound(true)
	_begin_sequence(snapshot)
	return true

func _begin_sequence(sequence: Sequence) -> void:
	_revision+=1;current_sequence=sequence;line_index=0
	var token := _revision
	_set_control_lock(not sequence.is_exploration_call())
	if token!=_revision or not _session:return
	view.configure(style);view.visible=not suspended
	letter_audio.stream=get_node("/root/PSXAudio").prepare(style.letter_sound);letter_audio.volume_db=style.letter_volume_db
	set_process(true)
	sequence_started.emit(sequence)
	if token==_revision and _session:_begin_line(true)

func _begin_line(first := false) -> void:
	_revision+=1;current_line=current_sequence.lines[line_index];page_index=0
	_line_completion_sent=false
	_caption_tail_elapsed=0.0
	if _line_view_hidden:_play_window_sound(true)
	_line_view_hidden=false;view.visible=not suspended
	_pages=Text.paginate(current_line.text,view.text_font,style.font_size,view.text_rect().size.x,style.lines_per_page)
	if _pages.is_empty():cancel();return
	var source: AudioStream=current_line.voice_stream() if current_line.audio else null
	if is_automatic():_automatic.configure(_pages,current_sequence,source.get_length() if source else 0.0,current_line)
	view.set_speaker(current_line.speaker);_show_page(true,first)
	_voice_pending=true
	var token := _revision
	line_started.emit(current_line,line_index)
	if token==_revision and _session:_raise_line_event(current_line.event_id,&"start")

func _raise_line_event(id: StringName,phase: StringName) -> void:
	if id.is_empty():return
	var world := get_node_or_null("/root/WorldEvents")
	if world:world.raise_event(id,{"sequence_id":current_sequence.id,"line_index":line_index,"speaker":current_line.speaker,"phase":phase})

func _start_line_audio() -> void:
	if _voice_pending:_voice_pending=false;voice_audio.play_line(current_line,style)

func _show_page(new_speaker: bool,first := false) -> void:
	view.show_page(_pages[page_index]);_visible_count=0;_budget=0;_next_delay=0;_indicator_clock=0
	if is_automatic():_automatic.new_page()
	_opening_left=(style.opening_delay if first else style.speaker_delay) if new_speaker else 0.0
	state=State.OPENING if _opening_left>0 else State.TYPING

func advance() -> void:
	if not _session or suspended or get_tree().paused or is_automatic():return
	if state==State.OPENING or state==State.TYPING:
		_start_line_audio()
		_visible_count=_pages[page_index].length();view.body.visible_characters=-1;AudioRouting.stop(letter_audio);_page_complete();return
	if state!=State.WAITING:return
	_advance_page_or_line()

func _advance_page_or_line() -> void:
	if _finishing_line:return
	_revision+=1
	if page_index+1<_pages.size():page_index+=1;_show_page(false);return
	var token := _revision
	if not _finish_line():return
	if token!=_revision or not _session:return
	if line_index+1<current_sequence.lines.size():line_index+=1;_begin_line();return
	var id := current_sequence.id
	var completed := current_sequence
	state=State.IDLE;current_sequence=null;current_line=null;view.visible=false;AudioRouting.stop(letter_audio)
	sequence_completed.emit(completed,false)
	if token!=_revision or not _session:return
	sequence_finished.emit(id,false)
	if token!=_revision or not _session:return
	if not _queue.is_empty():_begin_sequence(_queue.pop_front())
	else:_end_session()

func _finish_line() -> bool:
	if _line_completion_sent:return true
	_line_completion_sent=true
	_finishing_line=true
	var token := _revision
	voice_audio.stop_line(not current_line.hangs_up_intercom());_voice_pending=false
	_raise_line_event(current_line.end_event_id,&"end")
	if current_line.end_intercom and current_line.end_event_id!=&"end_intercom":_raise_line_event(&"end_intercom",&"end")
	line_finished.emit(current_line,line_index)
	_finishing_line=false
	return token==_revision and _session

func cancel() -> void:
	if not _session:_queue.clear();return
	_revision+=1
	voice_audio.stop_line();_voice_pending=false
	var id: StringName=current_sequence.id if current_sequence else &""
	var completed := current_sequence
	_queue.clear();state=State.IDLE;current_sequence=null;current_line=null;view.visible=false;AudioRouting.stop(letter_audio)
	# Close the modal session before callbacks can start another dialogue.
	_end_session();sequence_completed.emit(completed,true);sequence_finished.emit(id,true)

func _end_session() -> void:
	_session=false;state=State.IDLE;set_process(false);_set_control_lock(false)
	if not _line_view_hidden:_play_window_sound(false)
	_line_view_hidden=false;session_finished.emit()

func set_suspended(value: bool) -> void:
	suspended=value;view.visible=_session and not suspended and not _line_view_hidden
	voice_audio.set_suspended(value)
	if value:AudioRouting.stop(letter_audio)
	_confirm_held=Input.is_action_pressed(advance_action)
	if not value and not _session and not _queue.is_empty():_open_session(_queue.pop_front())

func _input(event: InputEvent) -> void:
	if not _session or suspended or get_tree().paused or is_automatic():return
	if event.is_action_released(advance_action):_confirm_held=false
	if event.is_action_pressed(advance_action,false):
		if not _confirm_held:_confirm_held=true;advance()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _session or suspended or get_tree().paused:return
	if state==State.OPENING:
		_opening_left-=delta
		if _opening_left>0:return
		delta=-_opening_left
		state=State.TYPING
	if is_automatic():_process_automatic(delta);return
	if state==State.WAITING:
		_update_caption_visibility(delta)
		_indicator_clock+=delta;_update_indicator();return
	if state!=State.TYPING:return
	var token := _revision
	_start_line_audio()
	if token!=_revision or not _session:return
	var speed: float=current_line.characters_per_second if current_line.characters_per_second>0 else style.characters_per_second
	_type_text(delta,speed)
	if token==_revision and _session:_update_caption_visibility(delta)

func _update_caption_visibility(delta: float) -> void:
	if _line_view_hidden or _voice_pending:return
	if not is_automatic() and not settings.masquer_conversations_manuelles:return
	# The voice tail and the response pause have separate clocks. Finishing
	# a page, pausing, or hiding the box never advances/skips the reply.
	if current_line.audio:
		if not voice_audio.speech_complete:return
	elif not is_automatic() or not _line_completion_sent:return
	_caption_tail_elapsed+=maxf(delta,0)
	if _caption_tail_elapsed+.000001<settings.delai_disparition_apres_voix:return
	if state!=State.WAITING or page_index+1<_pages.size():return
	if is_automatic() and not _automatic.page_ready(page_index):return
	_line_view_hidden=true;view.visible=false;AudioRouting.stop(letter_audio)
	_play_window_sound(false)

func _type_text(delta: float,speed: float) -> void:
	_budget+=delta
	var text := _pages[page_index]
	var count := 0
	while _budget>=_next_delay and count<3 and state==State.TYPING:
		_budget-=_next_delay
		if _visible_count>=text.length():_page_complete();return
		var character := text[_visible_count];_visible_count+=1;count+=1
		view.body.visible_characters=_visible_count
		_next_delay=1.0/maxf(speed,1)
		if character in [",",";",":"]:_next_delay+=style.punctuation_pause*.5
		if character in [".","!","?"] and (_visible_count>=text.length() or text[_visible_count]!="."):_next_delay+=style.punctuation_pause
		var token := _revision
		if Text.is_letter(character):
			if letter_audio.stream:letter_audio.volume_db=style.letter_volume_db;AudioRouting.play(letter_audio)
			letter_revealed.emit(character)
		if token!=_revision or not _session or state!=State.TYPING:return
		if _visible_count>=text.length():_page_complete();return
	# A delayed frame cannot accumulate an unbounded audio/reveal burst.
	if count==3:_budget=minf(_budget,_next_delay)

func _process_automatic(delta: float) -> void:
	var token := _revision
	_start_line_audio()
	if token!=_revision or not _session:return
	_automatic.advance(delta,voice_audio.speech_position(),voice_audio.speech_complete,state==State.WAITING)
	if state==State.TYPING:
		var base: float=current_line.characters_per_second if current_line.characters_per_second>0 else style.characters_per_second
		_type_text(delta,_automatic.typing_speed(page_index,base,_pages[page_index].length()))
	if token!=_revision or not _session:return
	_update_caption_visibility(delta)
	if state!=State.WAITING:return
	if page_index+1<_pages.size():
		if _automatic.page_ready(page_index):_advance_page_or_line()
	else:
		# Completion events happen before the optional pause for the next reply.
		if _automatic.page_ready(page_index) and voice_audio.speech_complete and voice_audio.phase==Voice.Phase.SILENT:
			if not _finish_line():return
		if token!=_revision or not _session:return
		_update_caption_visibility(0)
		var has_response := line_index+1<current_sequence.lines.size() or not _queue.is_empty()
		if not has_response:
			if _line_completion_sent and _line_view_hidden:_advance_page_or_line()
		elif _automatic.reply_ready(page_index,voice_audio.speech_complete,voice_audio.phase==Voice.Phase.SILENT,delta):_advance_page_or_line()

func _page_complete() -> void:
	state=State.WAITING;_indicator_clock=0;view.body.visible_characters=-1;_update_indicator()
	page_revealed.emit(current_line,page_index)

func _update_indicator() -> void:
	if state!=State.WAITING:return
	if is_automatic():view.set_indicator(View.Indicator.NONE);return
	var more := page_index+1<_pages.size() or line_index+1<current_sequence.lines.size() or not _queue.is_empty()
	view.set_indicator(View.Indicator.NEXT if more else View.Indicator.END,_indicator_clock)
