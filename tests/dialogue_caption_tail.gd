extends SceneTree
const Controller=preload("res://scripts/dialogue/dialogue_controller.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
var Settings: Resource=preload("res://assets/dialogue/settings.tres")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func sequence(automatic := true,two := true) -> DialogueSequence:
	var result := Sequence.new();result.mode=1 if automatic else 0;result.reply_gap=2;result.minimum_page_seconds=.5
	for index in (2 if two else 1):
		var line := Line.new();line.text="Une replique lisible.";line.audio=load("res://assets/audio/dialogs/1/1_Chapter_1.wav");result.lines.append(line)
	return result
func step(c: Node,seconds: float) -> void:
	for tick in roundi(seconds/.05):c._process(.05)
func open(c: Node,source: DialogueSequence) -> void:
	check(c.play(source),"Sequence starts");c.set_process(false);step(c,1.5)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var old_delay: float=Settings.delai_disparition_apres_voix;var old_manual: bool=Settings.masquer_conversations_manuelles
	Settings.delai_disparition_apres_voix=.35;Settings.masquer_conversations_manuelles=false
	var c := Controller.new();c.exploration_channel=true;root.add_child(c);c.style=c.style.duplicate();c.style.opening_delay=0;c.style.speaker_delay=0
	open(c,sequence());check(c.view.visible and c.line_index==0,"Caption stays visible throughout speech")
	c.voice_audio._voice_finished();step(c,.2)
	check(c.view.visible and c.line_index==0,"Post-voice display delay is respected")
	step(c,.2)
	check(not c.view.visible and c.is_active() and c.line_index==0,"Caption disappears while the response pause is still running")
	var gap: float=c._automatic.gap_elapsed;c.set_suspended(true);step(c,1)
	check(c._automatic.gap_elapsed==gap,"Suspension freezes the independent response pause")
	c.set_suspended(false);check(not c.view.visible,"Resuming does not resurrect an expired caption")
	step(c,1.2);check(c.line_index==0 and not c.view.visible,"Hiding the caption never shortens the authored response pause")
	step(c,.5);check(c.line_index==1 and c.view.visible,"Following reply opens a fresh window")
	c.cancel()
	var final := sequence(true,false);final.reply_gap=10
	open(c,final);c.voice_audio._voice_finished();step(c,.4)
	check(not c.is_active() and not c.view.visible,"Final reply closes after the global voice tail, without an unused ten-second response pause")
	# Every controller uses the one global delay, even with a different style.
	Settings.delai_disparition_apres_voix=.1;open(c,sequence());c.voice_audio._voice_finished();step(c,.1)
	check(not c.view.visible,"Changing the global delay affects the next dialogue immediately")
	c.cancel();Settings.delai_disparition_apres_voix=.35
	# A short recording must never discard pages that have not been read.
	var long := sequence(true,false);long.lines[0].text="Des mots a lire dans plusieurs pages. ".repeat(24)
	open(c,long);c.voice_audio._voice_finished();step(c,.5)
	check(c.is_active() and c.view.visible and c.page_index+1<c._pages.size(),"Unfinished long-caption pages remain visible after short audio")
	c.cancel();c.exploration_channel=false
	open(c,sequence(false));c.voice_audio._voice_finished();step(c,.6)
	check(c.view.visible and c.blocks_controls(),"Manual conversations retain validation by default")
	Settings.masquer_conversations_manuelles=true;step(c,.4)
	check(not c.view.visible and c.is_active() and c.blocks_controls(),"Optional global manual hiding keeps the manual progression mode")
	c.advance();check(c.line_index==1 and c.view.visible,"Manual confirmation still opens the next reply after hiding")
	c.cancel();c.queue_free();Settings.delai_disparition_apres_voix=old_delay;Settings.masquer_conversations_manuelles=old_manual
	await process_frame;await create_timer(.1).timeout
	FileAccess.open("res://docs/dialogue-caption-tail-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("DIALOGUE_CAPTION_TAIL_OK " if failures.is_empty() else "DIALOGUE_CAPTION_TAIL_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
