@tool
extends RefCounted
## Audio-position deadlines with independent minimum on-screen reading times.
## A slow frame or a short recording can never discard an unread page.
var minimums := PackedFloat64Array()
var durations := PackedFloat64Array()
var deadlines := PackedFloat64Array()
var audio_duration := 0.0
var clock := 0.0
var page_elapsed := 0.0
var revealed_elapsed := 0.0
var gap_elapsed := 0.0
var reply_gap := .2

func configure(pages: Array[String],sequence: Resource,seconds: float,line: Resource=null) -> void:
	minimums.clear();durations.clear();deadlines.clear();clock=0;new_page()
	audio_duration=seconds if is_finite(seconds) and seconds>0 else 0.0;reply_gap=maxf(sequence.reply_gap,0)
	if line:reply_gap=line.response_gap(sequence.reply_gap)
	var total := 0.0;var letters := 0
	for page in pages:
		var time := maxf(sequence.minimum_page_seconds,page.length()/maxf(sequence.reading_characters_per_second,1))
		minimums.append(time);total+=time;letters+=page.length()
	var extra := maxf(audio_duration-total,0);var end := 0.0
	for index in pages.size():
		var time := minimums[index]+extra*pages[index].length()/maxf(letters,1)
		durations.append(time);end+=time;deadlines.append(end)

func new_page() -> void:page_elapsed=0;revealed_elapsed=0;gap_elapsed=0

func advance(delta: float,audio_position: float,speech_complete: bool,fully_revealed: bool) -> void:
	# Time while a frame is not being drawn cannot count as reading a new page.
	var visible_delta := clampf(delta,0,.1)
	page_elapsed+=visible_delta
	if fully_revealed:revealed_elapsed+=visible_delta
	if audio_duration<=0:clock+=visible_delta
	elif speech_complete:clock=maxf(clock,audio_duration)+visible_delta
	else:clock=maxf(clock,clampf(audio_position,0,audio_duration))

func typing_speed(index: int,base: float,characters: int) -> float:
	return maxf(base,characters/maxf(durations[index]*.4,.05))

func page_ready(index: int) -> bool:
	return clock+.000001>=deadlines[index] and page_elapsed+.000001>=minimums[index] and revealed_elapsed>=.35

func reply_ready(index: int,speech_complete: bool,transmission_closed: bool,delta: float) -> bool:
	if not page_ready(index) or not speech_complete or not transmission_closed:return false
	gap_elapsed+=clampf(delta,0,.1)
	return gap_elapsed+.000001>=reply_gap
