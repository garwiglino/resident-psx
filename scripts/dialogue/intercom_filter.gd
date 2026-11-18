@tool
extends RefCounted
## Radio coloration is baked into the sample before SPU ADPCM encoding.
## It is a production effect, not an imaginary hardware-wide PS1 radio filter.
const RATE := 22050
const CACHE_DIRECTORY := "res://assets/audio/generated/intercom"
const CACHE_VERSION := "radio_v2_mix_22050_300_3000_lufs18"
const STATE_KEY: StringName = &"psx_intercom_cache"
static func _cache() -> Dictionary:
	if not Engine.has_meta(STATE_KEY): Engine.set_meta(STATE_KEY,{})
	return Engine.get_meta(STATE_KEY)
static func clear_cache() -> void:
	if Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)

static func prepared_path(source_path: String) -> String:
	if source_path.get_extension().to_lower() not in ["wav","ogg","mp3"] or not FileAccess.file_exists(source_path):return ""
	var digest := (CACHE_VERSION+":"+FileAccess.get_sha256(source_path)).sha256_text().left(24)
	return CACHE_DIRECTORY+"/"+source_path.get_file().get_basename().validate_filename()+"_"+digest+".res"

## External resources retain their SPU bytes and are included by Godot's exporter.
## Procedural/in-memory sources have no original file and remain transient.
static func store_prepared(source: AudioStream,prepared: AudioStream) -> AudioStream:
	if not source or not prepared:return prepared
	var path := prepared_path(source.resource_path)
	if path.is_empty() or prepared.resource_path==path:return prepared
	if ResourceLoader.exists(path,"AudioStream"):
		var saved: AudioStream=load(path)
		if saved and saved.is_class("AudioStreamPSX"):return saved
	var error := DirAccess.make_dir_recursive_absolute(CACHE_DIRECTORY)
	if error!=OK:push_error("Impossible de creer le cache intercom : "+error_string(error));return prepared
	error=ResourceSaver.save(prepared,path,ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_CHANGE_PATH)
	if error!=OK:push_error("Impossible de sauvegarder la voix intercom : "+error_string(error))
	else:prepared.take_over_path(path)
	return prepared

static func invalidate(source: AudioStream) -> void:
	if not source:return
	_cache().erase(str(source.get_instance_id()))

static func _coefficients(frequency: float,high_pass: bool) -> PackedFloat64Array:
	var w := TAU*frequency/RATE;var c := cos(w);var alpha := sin(w)/sqrt(2.0);var a := 1+alpha
	return PackedFloat64Array([((1+c) if high_pass else (1-c))*.5/a,(-(1+c) if high_pass else (1-c))/a,((1+c) if high_pass else (1-c))*.5/a,-2*c/a,(1-alpha)/a])

static func build(source: AudioStream) -> AudioStream:
	if not source or source.get_length()<=0 or source.get_length()>600:return null
	if source.has_meta("psx_intercom_stream"):return source.get_meta("psx_intercom_stream")
	if not ClassDB.class_exists("AudioStreamPSX"):return null
	var key := str(source.get_instance_id())
	if _cache().has(key):
		var existing: AudioStream=_cache()[key].get_ref()
		if existing:return existing
	if _cache().size()>128:
		for entry in _cache().keys():
			if not _cache()[entry].get_ref():_cache().erase(entry)
	if Engine.is_editor_hint():
		var path := prepared_path(source.resource_path)
		if not path.is_empty() and ResourceLoader.exists(path,"AudioStream"):
			var saved: AudioStream=load(path)
			if saved and saved.is_class("AudioStreamPSX"):_cache()[key]=weakref(saved);return saved
	var original: AudioStream=source
	# In the editor read the original file to avoid encoding an ADPCM voice twice.
	if Engine.is_editor_hint() and FileAccess.file_exists(source.resource_path):
		match source.resource_path.get_extension().to_lower():
			"wav":original=AudioStreamWAV.load_from_file(source.resource_path,{"compress/mode":0})
			"ogg":original=AudioStreamOggVorbis.load_from_file(source.resource_path)
			"mp3":original=AudioStreamMP3.load_from_file(source.resource_path)
	if not original:return null
	var playback := original.instantiate_playback()
	if not playback:return null
	var frames := ceili(original.get_length()*RATE);var pcm := PackedByteArray();pcm.resize(frames*2)
	var hp := _coefficients(300,true);var lp := _coefficients(3000,false)
	var hx1 := 0.0;var hx2 := 0.0;var hy1 := 0.0;var hy2 := 0.0
	var lx1 := 0.0;var lx2 := 0.0;var ly1 := 0.0;var ly2 := 0.0
	playback.start()
	for first in range(0,frames,4096):
		var samples := playback.mix_audio(AudioServer.get_mix_rate()/float(RATE),mini(4096,frames-first))
		for index in samples.size():
			var x: float=(samples[index].x+samples[index].y)*.5
			var high: float=hp[0]*x+hp[1]*hx1+hp[2]*hx2-hp[3]*hy1-hp[4]*hy2
			hx2=hx1;hx1=x;hy2=hy1;hy1=high
			var low: float=lp[0]*high+lp[1]*lx1+lp[2]*lx2-lp[3]*ly1-lp[4]*ly2
			lx2=lx1;lx1=high;ly2=ly1;ly1=low
			# Mild transmitter limiting, with no artificial bit crusher or hiss bed.
			var limited := tanh(low*1.35)/1.35
			var frame := first+index
			var fade := minf(1,minf(frame/66.0,(frames-1-frame)/66.0))
			pcm.encode_s16(frame*2,roundi(clampf(limited*fade,-1,1)*32767))
	playback.stop()
	var wave := AudioStreamWAV.new();wave.format=AudioStreamWAV.FORMAT_16_BITS;wave.mix_rate=RATE;wave.stereo=false;wave.data=pcm
	var converted: AudioStream=ClassDB.instantiate("AudioStreamPSX")
	if not converted.configure_source(wave,RATE):return null
	converted.resource_name="Intercom - "+source.resource_name;converted.set("loop",false)
	if Engine.is_editor_hint():converted=store_prepared(source,converted)
	_cache()[key]=weakref(converted)
	return converted
