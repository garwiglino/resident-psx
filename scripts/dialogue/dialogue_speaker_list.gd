@tool
class_name DialogueSpeakerList
extends Resource
const Entry=preload("res://scripts/dialogue/dialogue_speaker.gd")
@export var entries: Array[Entry]=[]:
	set(value):
		for entry in entries:
			if entry and entry.changed.is_connected(_entry_changed):entry.changed.disconnect(_entry_changed)
		entries=value
		for entry in entries:
			if entry and not entry.changed.is_connected(_entry_changed):entry.changed.connect(_entry_changed)
		emit_changed()
func _entry_changed() -> void:emit_changed()
func top_color_for(speaker: String,fallback: Color) -> Color:
	var key := speaker.strip_edges()
	for entry in entries:
		if entry and entry.speaker_name.strip_edges().nocasecmp_to(key)==0:
			return entry.top_color if entry.use_top_color and entry.top_color is Color else fallback
	return fallback
func choices(current := "") -> Array[Dictionary]:
	var result: Array[Dictionary]=[];var seen: Dictionary={};var found := false
	for entry in entries:
		if not entry:continue
		var name := entry.speaker_name.strip_edges()
		if name.is_empty() or seen.has(name.to_upper()):continue
		seen[name.to_upper()]=true;found=found or name==current
		result.append({"name":name,"intercom":entry.intercom_by_default,"known":true})
	# Legacy and deliberately anonymous replies retain their exact stored name.
	if not found:result.append({"name":current,"intercom":false,"known":false})
	return result
func first_name() -> String:
	for entry in entries:
		if entry and not entry.speaker_name.strip_edges().is_empty():return entry.speaker_name.strip_edges()
	return ""
