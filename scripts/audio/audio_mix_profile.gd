@tool
extends Resource
const Categories=preload("res://scripts/audio/audio_categories.gd")
@export_group("Sortie generale")
## Marge commune pour les sons simultanes. 0 dB conserve leur niveau prepare.
@export_range(-60,0,.5,"suffix:dB") var volume_general_db := -3.0
@export_group("Bruitages")
@export_range(-60,0,.5,"suffix:dB") var bruitages_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var pas_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var joueur_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var interactions_db := -2.0
@export_group("Armes")
@export_range(-60,0,.5,"suffix:dB") var armes_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var tirs_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var mecanismes_arme_db := 0.0
@export_group("Dialogues")
## Voix normales et intercom suivent ensemble ce volume, meme sans reverb.
@export_range(-60,0,.5,"suffix:dB") var voix_db := 0.0
@export_range(-60,0,.5,"suffix:dB") var intercom_effets_db := -3.0
@export_group("Niveau et interface")
@export_range(-60,0,.5,"suffix:dB") var ambiances_db := -2.0
@export_range(-60,0,.5,"suffix:dB") var musique_db := -3.0
@export_range(-60,0,.5,"suffix:dB") var stingers_db := -4.0
@export_range(-60,0,.5,"suffix:dB") var interface_db := -2.0

func volumes() -> Dictionary:
	return {&"Master":volume_general_db,&"SFX":bruitages_db,&"Footsteps":pas_db,&"Player Foley":joueur_db,&"Interactions":interactions_db,&"Weapons":armes_db,&"Weapon Shots":tirs_db,&"Weapon Handling":mecanismes_arme_db,&"Voices":voix_db,&"Radio FX":intercom_effets_db,&"Ambience":ambiances_db,&"Music":musique_db,&"Stingers":stingers_db,&"UI":interface_db}
func apply() -> void:
	Categories.ensure_buses()
	var levels := volumes()
	for bus: StringName in levels:
		if bus!=&"Master":AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus),levels[bus])
	# Global gain belongs to the signed SPU master registers, before the final
	# 16-bit conversion. Leave Godot's floating-point output bus at unity.
	AudioServer.set_bus_volume_db(0,0)
	var volume := clampi(roundi(db_to_linear(volume_general_db)*16384),0,16383)
	for slot in AudioServer.get_bus_effect_count(0):
		var effect := AudioServer.get_bus_effect(0,slot)
		if effect.has_method("set_master_left"):effect.set("master_left",volume);effect.set("master_right",volume)
	for bus: StringName in Categories.PARENTS:Categories.sync_dry_branch(bus)
