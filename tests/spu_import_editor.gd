@tool
extends RefCounted
var paths := PackedStringArray()
var failures: Array[String]=[]
var converted := PackedStringArray()
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func scan(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):scan(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if file.get_extension().to_lower() in ["wav","ogg","mp3"]:paths.append(directory.path_join(file))
func run(plugin: EditorPlugin) -> void:
	check(Engine.is_editor_hint() and ClassDB.class_has_method("AudioStreamPSX","make_voice"),"Migration uses the isolated v14 editor")
	if not failures.is_empty():plugin.get_tree().quit(1);return
	for step in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning():break
		await plugin.get_tree().process_frame
	scan("res://assets/audio")
	var backup := "res://exports/backups/spu_import_"+Time.get_datetime_string_from_system().replace(":","").replace("-","")
	for path in paths:
		var config := ConfigFile.new();check(config.load(path+".import")==OK,"Import settings exist: "+path)
		if config.get_value("remap","importer","")=="psx.spu_audio":continue
		var copy := backup.path_join(path.trim_prefix("res://"))+".import"
		DirAccess.make_dir_recursive_absolute(copy.get_base_dir())
		FileAccess.open(copy,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(path+".import"))
		var target: String=config.get_value("remap","path","")
		check(not target.is_empty(),"Existing import destination is known: "+path)
		target=target.get_basename()+".res"
		var looping: bool=int(config.get_value("params","edit/loop_mode",0))>0
		config.set_value("remap","importer","psx.spu_audio");config.set_value("remap","type","AudioStreamPSX");config.set_value("remap","path",target)
		config.set_value("deps","dest_files",PackedStringArray([target]));config.erase_section("params")
		config.set_value("params","loop",looping);config.set_value("params","sample_rate",0)
		config.set_value("params","spu/adsr1",255);config.set_value("params","spu/adsr2",8128)
		check(config.save(path+".import")==OK,"Direct SPU importer assignment saves: "+path);converted.append(path)
	if not converted.is_empty():EditorInterface.get_resource_filesystem().reimport_files(converted)
	for step in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning():break
		await plugin.get_tree().process_frame
	for path in paths:
		# An already-open inspector can retain a WAV object with the old class.
		# Validate the newly written binary directly; a fresh runtime validates
		# all source-path remaps separately with tools/audit_psx_audio.gd.
		var settings := ConfigFile.new();settings.load(path+".import")
		var stream: AudioStream=ResourceLoader.load(settings.get_value("remap","path",""),"AudioStream",ResourceLoader.CACHE_MODE_IGNORE)
		check(stream!=null and stream.is_class("AudioStreamPSX"),"All project sources import directly as SPU ADPCM: "+path)
		if stream and stream.is_class("AudioStreamPSX"):
			check(stream.get("adpcm_left").size()>0 and stream.get("mix_rate")<=44100,"Imported source contains actual SPU blocks: "+path)
			check(stream.get("adsr1")==255 and stream.get("adsr2")==8128,"Hardware ADSR defaults remain consistent: "+path)
	FileAccess.open("res://docs/spu-import-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"source_count":paths.size(),"migrated":converted,"backup":backup},"\t"))
	print("SPU_IMPORT_EDITOR_OK: all %d audio sources use direct SPU ADPCM; %d legacy imports migrated without intermediate Godot codecs" % [paths.size(),converted.size()] if failures.is_empty() else "SPU_IMPORT_EDITOR_FAILED "+str(failures))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
