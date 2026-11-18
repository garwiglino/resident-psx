@tool
extends RefCounted
const Categories=preload("res://scripts/audio/audio_categories.gd")
## SPU reverb send (EON) is selected per voice. The master always retains the
## common signed 16-bit output stage, including for voices with EON disabled.
const WET_BUS: StringName=&"PSX Reverb"
const DRY_BUS: StringName=&"PSX Dry"

const STATE_KEY: StringName = &"psx_audio_routing_context"
static func _state() -> Dictionary:
	if not Engine.has_meta(STATE_KEY):
		Engine.set_meta(STATE_KEY,{"_configured":false,"_warned":false,"_output":null,"_send":null,"_master_sync_frame":-1,"_output_slot":-1,"_send_slot":-1})
	return Engine.get_meta(STATE_KEY)

static func release_cached_effects() -> void:
	if Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)

static func setup() -> bool:
	var state := _state()
	if not ClassDB.class_exists("AudioEffectPSXReverb"):return false
	if not ClassDB.class_has_method("AudioEffectPSXReverb","set_wet"):
		if not state._warned:push_warning("Redemarrer Godot pour charger l'audio PS1 v12 et le bypass de reverb intercom.");state._warned=true
		return false
	var existing_send := AudioServer.get_bus_index(WET_BUS)
	if state._configured and existing_send>=0 and AudioServer.get_bus_index(DRY_BUS)>=0:
		if state._output_slot>=0 and state._output_slot<AudioServer.get_bus_effect_count(0) and AudioServer.get_bus_effect(0,state._output_slot)==state._output and state._send_slot>=0 and state._send_slot<AudioServer.get_bus_effect_count(existing_send) and AudioServer.get_bus_effect(existing_send,state._send_slot)==state._send:
			if AudioServer.get_bus_index(&"Footsteps")<0:Categories.ensure_buses()
			return true
	state._master_sync_frame=-1
	if AudioServer.get_bus_index(WET_BUS)<0:
		AudioServer.add_bus(1);AudioServer.set_bus_name(1,WET_BUS)
	if AudioServer.get_bus_index(DRY_BUS)<0:
		AudioServer.add_bus(2);AudioServer.set_bus_name(2,DRY_BUS)
	AudioServer.set_bus_send(AudioServer.get_bus_index(WET_BUS),&"Master")
	AudioServer.set_bus_send(AudioServer.get_bus_index(DRY_BUS),&"Master")
	Categories.ensure_buses()
	var master_found := false;var wet_found := false;var wet_index := AudioServer.get_bus_index(WET_BUS)
	for slot in AudioServer.get_bus_effect_count(0):
		var effect := AudioServer.get_bus_effect(0,slot)
		if effect.is_class("AudioEffectPSXReverb"):effect.set("wet",0.0);master_found=true;state._output=effect;state._output_slot=slot
	if not master_found:
		var output: AudioEffect=ClassDB.instantiate("AudioEffectPSXReverb");output.set("wet",0.0);output.resource_name="PS1 - sortie 16 bits"
		state._output_slot=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,output);state._output=output
	for slot in AudioServer.get_bus_effect_count(wet_index):
		if AudioServer.get_bus_effect(wet_index,slot).is_class("AudioEffectPSXReverb"):wet_found=true;state._send=AudioServer.get_bus_effect(wet_index,slot);state._send_slot=slot
	if not wet_found:
		var reverb: AudioEffect=ClassDB.instantiate("AudioEffectPSXReverb");reverb.resource_name="PS1 SPU - Studio Medium"
		state._send_slot=AudioServer.get_bus_effect_count(wet_index);AudioServer.add_bus_effect(wet_index,reverb);state._send=reverb
	if ClassDB.class_has_method("AudioEffectPSXReverb","set_native_mixer"):
		state._output.set("native_mixer",true)
		if state._output.has_method("set_output_rate"):state._output.set("output_rate",22050)
		elif not state._warned:push_warning("Enregistrer les scenes puis rouvrir Godot pour charger le mixage audio v18 et sa sortie 22050 Hz.");state._warned=true
	elif not state._warned:
		push_warning("Redemarrer Godot pour charger le mixeur SPU v14 et les enveloppes ADSR.");state._warned=true
	state._configured=true;return true

static func sync_master() -> void:
	var state := _state()
	var frame := Engine.get_process_frames()
	if state._master_sync_frame==frame:return
	state._master_sync_frame=frame
	if not setup() or not state._output or not state._output.has_method("set_native_mixer"):return
	var index := AudioServer.get_bus_index(WET_BUS)
	var enabled := index>=0 and not AudioServer.is_bus_bypassing_effects(index)
	if enabled:
		for slot in AudioServer.get_bus_effect_count(index):
			if AudioServer.get_bus_effect(index,slot)==state._send:enabled=AudioServer.is_bus_effect_enabled(index,slot);break
	state._output.set("reverb_level",state._send.get("wet") if enabled and state._send else 0.0)

static func source_of(stream: AudioStream) -> AudioStream:
	return stream.get_meta("_psx_source",stream) if stream else null

static func play(player: Node,position := 0.0) -> void:
	# Synchronize BEFORE key-on, including one-frame UI/weapon transients.
	sync_player(player);player.play(position)

static func stop(player: Node) -> void:
	if player.stream and player.stream.has_method("key_off_all"):player.stream.key_off_all()
	player.stop()

static func sync_player(player: Node) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree() or player.is_queued_for_deletion(): return
	route(player);sync_master()
	if not ClassDB.class_has_method("AudioStreamPSX","make_voice"):return
	var stream: AudioStream=player.stream
	if not stream:return
	if not stream.is_class("AudioStreamPSX"):
		var manager := player.get_node_or_null("/root/PSXAudio")
		if manager:stream=manager.prepare(stream)
		else:
			var converted: AudioStream=ClassDB.instantiate("AudioStreamPSX")
			if not converted.configure_source(stream):return
			stream=converted
	if not stream or not stream.is_class("AudioStreamPSX"):return
	if not stream.is_managed():
		var voice: AudioStream=stream.make_voice();voice.set_meta("_psx_source",stream)
		var resume: bool=player.playing;var cursor: float=player.get_playback_position() if resume else 0.0
		player.stream=voice;stream=voice
		if resume:player.play(cursor)
	var gain: float=db_to_linear(player.volume_db)
	var bus: StringName=player.bus;var visited := {}
	while bus!=&"Master" and not visited.has(bus):
		visited[bus]=true;var index := AudioServer.get_bus_index(bus)
		if index<0:break
		gain*=0.0 if AudioServer.is_bus_mute(index) else db_to_linear(AudioServer.get_bus_volume_db(index))
		bus=AudioServer.get_bus_send(index)
	var left := gain;var right := gain
	if player is AudioStreamPlayer3D:
		var camera := player.get_viewport().get_camera_3d()
		var listener := player.get_viewport().get_audio_listener_3d()
		var transform: Transform3D=listener.global_transform if listener else camera.global_transform if camera else Transform3D.IDENTITY
		var offset: Vector3=transform.affine_inverse()*player.global_position;var distance := maxf(offset.length(),.0001)
		var attenuation := 1.0;var relative := maxf(distance/maxf(player.unit_size,.0001),.0001)
		match player.attenuation_model:
			AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE:attenuation=1.0/relative
			AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE:attenuation=1.0/(relative*relative)
			AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC:attenuation=db_to_linear(-20.0*log(relative))
		attenuation=minf(attenuation,db_to_linear(player.max_db))
		if player.max_distance>0:attenuation*=maxf(1.0-distance/player.max_distance,0.0)
		var pan := clampf(offset.x/distance*player.panning_strength,-1,1)
		left*=attenuation*sqrt((1.0-pan)*.5);right*=attenuation*sqrt((1.0+pan)*.5)
	# Signed 15-bit direct volume registers, expanded to 16 bits by the SPU.
	var lreg := clampi(roundi(left*16384.0),0,16383);var rreg := clampi(roundi(right*16384.0),0,16383)
	stream.set_spu_controls(lreg,rreg,bool(player.get_meta("psx_reverb",true)),player.stream_paused or not player.can_process())

static func set_reverb_enabled(player: Node,enabled: bool) -> void:
	player.set_meta("psx_reverb",enabled);route(player)

static func set_category(player: Node,category: StringName) -> void:
	assert(Categories.PARENTS.has(category),"Unknown audio category: "+String(category))
	player.set_meta("psx_audio_category",category);route(player)

static func route(player: Node) -> void:
	if not setup():return
	var category: StringName=player.get_meta("psx_audio_category",&"")
	if category.is_empty() and player.stream:
		var source := source_of(player.stream)
		category=StringName(source.get_meta("psx_category")) if source.has_meta("psx_category") else Categories.for_path(source.resource_path)
	if Categories.PARENTS.has(category):
		if not player.has_meta("psx_reverb"):player.set_meta("psx_reverb",category not in [&"UI",&"Radio FX"])
		Categories.sync_dry_branch(category)
		# Dry/wet is orthogonal to category. Radio speech still follows Voices,
		# and both paths retain the category and parent gains/mutes.
		player.bus=category if bool(player.get_meta("psx_reverb",category not in [&"UI",&"Radio FX"])) else Categories.dry_bus(category)
		return
	var bus: StringName=player.bus
	if not bool(player.get_meta("psx_reverb",true)):
		if bus!=DRY_BUS:player.set_meta("_psx_reverb_bus",bus);player.bus=DRY_BUS
		return
	if bus==WET_BUS:return
	if bus==DRY_BUS:
		bus=player.get_meta("_psx_reverb_bus",&"Master")
		if AudioServer.get_bus_index(bus)<0:bus=&"Master"
	if bus==&"Master":player.bus=WET_BUS;return
	player.bus=bus
	# Bus gain/mute becomes voice-register gain. Managed samples bypass Godot
	# effects; EON feeds the native reverb before the native master volume.
	var visited: Dictionary={}
	while bus not in [WET_BUS,DRY_BUS,&"Master"] and not visited.has(bus):
		visited[bus]=true
		var index := AudioServer.get_bus_index(bus)
		if index<0:player.bus=WET_BUS;return
		var send := AudioServer.get_bus_send(index)
		if send in [&"Master",&""]:AudioServer.set_bus_send(index,WET_BUS);return
		bus=send
