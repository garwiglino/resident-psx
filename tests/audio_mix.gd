extends SceneTree
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
const Preparation=preload("res://scripts/audio/audio_preparation.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func state(player: AudioStreamPlayer) -> Dictionary:return player.get_stream_playback().get_spu_state()
func run() -> void:
	var manager := root.get_node("PSXAudio");manager.set_process(false)
	check(ProjectSettings.get_setting("audio/driver/mix_rate")==22050,"Project requests a 22050 Hz device rate")
	check(Routing.Categories.for_path("res://assets/audio/weapons/shotgun/reload.wav")==&"Weapon Handling","Le nom du dossier d'arme ne transforme pas ses recharges en tirs")
	var voice: AudioStream=load("res://assets/audio/dialogs/1/1_Chapter_1.wav")
	var players: Array[AudioStreamPlayer]=[]
	for category: StringName in [&"Footsteps",&"Weapon Shots",&"Voices",&"Voices"]:
		var player := AudioStreamPlayer.new();player.volume_db=-8;player.stream=voice;Routing.set_category(player,category)
		if players.size()==3:Routing.set_reverb_enabled(player,false);player.stream=voice.get_meta("psx_intercom_stream")
		root.add_child(player);Routing.play(player);players.append(player)
	await create_timer(.35).timeout
	check(players[0].bus==&"Footsteps" and players[1].bus==&"Weapon Shots" and players[2].bus==&"Voices" and players[3].bus==&"Voices Dry","Pas, tirs, voix et intercom ont leurs chemins separes")
	var before: int=state(players[2]).left;var foot_before: int=state(players[0]).left
	var voice_bus := AudioServer.get_bus_index(&"Voices");AudioServer.set_bus_volume_db(voice_bus,-6)
	for player in players:Routing.sync_player(player)
	await create_timer(.06).timeout
	check(absi(state(players[2]).left-roundi(before*db_to_linear(-6)))<4 and state(players[2]).left==state(players[3]).left,"Le volume Voix s'applique aussi a l'intercom sans reverb")
	check(state(players[0]).left==foot_before,"Le volume Voix ne modifie pas les pas")
	AudioServer.set_bus_mute(voice_bus,true)
	for player in players:Routing.sync_player(player)
	await create_timer(.06).timeout
	check(state(players[2]).left==0 and state(players[3]).left==0 and state(players[0]).left>0,"Mute Voix coupe les deux routes sans toucher aux bruitages")
	AudioServer.set_bus_mute(voice_bus,false);AudioServer.set_bus_volume_db(voice_bus,0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Weapons"),-12)
	for player in players:Routing.sync_player(player)
	await create_timer(.06).timeout
	check(state(players[1]).left<state(players[0]).left*.26,"Le parent Armes controle ses tirs independamment des pas")
	for player in players:Routing.stop(player);player.queue_free()
	await create_timer(.08).timeout
	manager.mix_profile.apply()
	var capture_root := "res://exports/audio_mix_test/decoded"
	DirAccess.make_dir_recursive_absolute(capture_root);FileAccess.open(capture_root+"/.gdignore",FileAccess.WRITE).store_string("")
	var captures := [];var count := 0
	for path: String in Preparation.entries():
		var stream: AudioStream=load(path);var row: Dictionary=Preparation.entries()[path]
		check(stream.is_class("AudioStreamPSX") and stream.get("mix_rate")==22050,"Source SPU a 22050 Hz : "+path)
		check(stream.get_meta("psx_category",&"")==StringName(row.category),"Categorie preparee : "+path)
		check(absf(stream.get_length()-float(row.duration))<=1.0/22050,"Duree et synchro preservees : "+path)
		check(FileAccess.get_sha256(path)==row.sha256,"WAV original intact : "+path)
		count+=1
		if row.category!="Voices":continue
		for radio in [false,true]:
			var sample: AudioStream=stream.get_meta("psx_intercom_stream") if radio else stream
			check(sample!=null and sample.mix_rate==22050,"Intercom preencode sans travail audio au lancement de replique")
			if not sample:continue
			var playback := sample.instantiate_playback();playback.start()
			var frames := PackedVector2Array()
			# Read the true 44.1 kHz SPU clock at pitch 0x800. Changing pitch to
			# request another sampling rate would change Gaussian phase patterns.
			for start in range(0,ceili(sample.get_length()*44100),4096):frames.append_array(playback.mix_spu(mini(4096,ceili(sample.get_length()*44100)-start)))
			playback.stop()
			var destination := capture_root+"/"+String(row.signature)+("_radio" if radio else "")+".f32"
			FileAccess.open(destination,FileAccess.WRITE).store_buffer(frames.to_byte_array())
			captures.append({"source":path,"radio":radio,"data":destination,"rate":44100,"channels":2})
	var diagnostics: Dictionary=voice.get_mixer_diagnostics()
	check(diagnostics.spu_rate==44100 and diagnostics.get("output_rate",0)==22050,"Horloge SPU 44100 preservee avec une sortie reechantillonnee a 22050, meme si Windows impose un autre taux")
	var result := {"ok":failures.is_empty(),"errors":failures,"sources":count,"captures":captures,"diagnostics":diagnostics}
	FileAccess.open("res://docs/audio-mix-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("AUDIO_MIX_OK " if failures.is_empty() else "AUDIO_MIX_FAILED ",count," sources, ",captures.size()," decoded voices, ",JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
