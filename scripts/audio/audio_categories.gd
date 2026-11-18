@tool
extends RefCounted
const PARENTS := {
	&"SFX":&"PSX Reverb",&"Footsteps":&"SFX",&"Player Foley":&"SFX",
	&"Weapons":&"SFX",&"Weapon Shots":&"Weapons",&"Weapon Handling":&"Weapons",
	&"Interactions":&"SFX",&"Voices":&"PSX Reverb",&"Radio FX":&"PSX Dry",
	&"Ambience":&"PSX Reverb",&"Music":&"PSX Reverb",&"UI":&"PSX Dry",&"Stingers":&"PSX Reverb"}

static func dry_bus(category: StringName) -> StringName:return StringName(String(category)+" Dry")
static func ensure_buses() -> void:
	# Sends point to an earlier bus, as required by Godot's bus graph.
	for category: StringName in PARENTS:
		for name: StringName in [category,dry_bus(category)]:
			if AudioServer.get_bus_index(name)<0:
				AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.bus_count-1,name)
		AudioServer.set_bus_send(AudioServer.get_bus_index(category),PARENTS[category])
		AudioServer.set_bus_send(AudioServer.get_bus_index(dry_bus(category)),dry_bus(PARENTS[category]) if PARENTS.has(PARENTS[category]) else &"PSX Dry")

static func sync_dry_branch(category: StringName) -> void:
	while PARENTS.has(category):
		var wet := AudioServer.get_bus_index(category);var dry := AudioServer.get_bus_index(dry_bus(category))
		if wet<0 or dry<0:return
		var db := AudioServer.get_bus_volume_db(wet);var mute := AudioServer.is_bus_mute(wet)
		if AudioServer.get_bus_volume_db(dry)!=db:AudioServer.set_bus_volume_db(dry,db)
		if AudioServer.is_bus_mute(dry)!=mute:AudioServer.set_bus_mute(dry,mute)
		category=PARENTS[category]

static func for_path(path: String) -> StringName:
	path=path.to_lower()
	if path.is_empty():return &""
	if path.get_file()=="intercom_end.wav":return &"Radio FX"
	if path.contains("/dialogs/"):return &"Radio FX" if path.get_file().begins_with("talkie_") else &"Voices"
	if path.contains("/footsteps/") or path.ends_with("/step.wav"):return &"Footsteps"
	if path.ends_with("/hit_marker.wav"):return &"UI"
	if path.contains("/weapons/") or path.ends_with("/shot.wav") or path.ends_with("/reload.wav"):
		var name := path.get_file().get_basename()
		for word in ["reload","aim","dry","empty","floor","casing","equip","impact"]:
			if word in name:return &"Weapon Handling"
		return &"Weapon Shots" if "shoot" in name or "shot" in name or "fire" in name else &"Weapon Handling"
	for folder in {"ambiance":"Ambience","music":"Music","stinger":"Stingers","ui":"UI","interactables":"Interactions"}:
		if path.contains("/"+folder+"/"):return StringName({"ambiance":"Ambience","music":"Music","stinger":"Stingers","ui":"UI","interactables":"Interactions"}[folder])
	if path.ends_with("/hum.wav"):return &"Ambience"
	if path.ends_with("/pickup.wav"):return &"UI"
	if path.ends_with("/hurt.wav"):return &"Player Foley"
	return &"SFX"
