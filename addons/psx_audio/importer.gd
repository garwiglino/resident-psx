@tool
extends EditorImportPlugin
const Preparation=preload("res://scripts/audio/audio_preparation.gd")
const Categories=preload("res://scripts/audio/audio_categories.gd")
func _get_importer_name() -> String:return "psx.spu_audio"
func _get_visible_name() -> String:return "Audio PS1 (automatique)"
func _get_recognized_extensions() -> PackedStringArray:return PackedStringArray(["wav","ogg","mp3"])
func _get_save_extension() -> String:return "res"
func _get_resource_type() -> String:return "AudioStreamPSX"
func _get_priority() -> float:return 2.0
func _get_import_order() -> int:return 0
func _can_import_threaded() -> bool:return false
func _get_preset_count() -> int:return 1
func _get_preset_name(_preset_index: int) -> String:return "PS1 automatique"
func _get_import_options(_path: String,_preset_index: int) -> Array[Dictionary]:
	return [{"name":"loop","default_value":false},{"name":"sample_rate","default_value":22050,"property_hint":PROPERTY_HINT_ENUM,"hint_string":"22050 Hz:22050,11025 Hz:11025"},{"name":"spu/adsr1","default_value":255,"property_hint":PROPERTY_HINT_RANGE,"hint_string":"0,65535,1"},{"name":"spu/adsr2","default_value":8128,"property_hint":PROPERTY_HINT_RANGE,"hint_string":"0,65535,1"}]
func _get_option_visibility(_path: String,_option_name: StringName,_options: Dictionary) -> bool:return true
func _import(source_file: String,save_path: String,options: Dictionary,_platform_variants: Array[String],_gen_files: Array[String]) -> Error:
	var converted := Preparation.import_stream(source_file,options)
	if not converted:return ERR_INVALID_DATA
	return ResourceSaver.save(converted,save_path+"."+_get_save_extension())
