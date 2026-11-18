extends Resource
## Shared authoring data. Inventory instances duplicate it before runtime tuning.
@export var id: StringName=&"desert_eagle"
@export var display_name := "Desert Eagle"
@export var scene: PackedScene
@export_file("*.json") var mount_file := "res://assets/weapons/pistol_mount.json"
@export_group("Munitions")
@export var ammo_type: StringName=&"magnum"
@export var ammo_label := "MAGNUM"
@export_range(1,100,1) var magazine_capacity := 12
@export_range(0,100,1) var starting_ammo := 12
@export_range(0,999,1) var starting_reserve := 24
@export_group("Tir et recharge")
@export var automatic := false
@export_range(.05,2.0,.01,"suffix:s") var shot_interval := .28
## Duree de secours si aucun clip de rechargement n'est exporte.
@export_range(.1,5.0,.05,"suffix:s") var reload_duration := 1.5
@export_range(0.0,1.0,.01,"suffix:s") var equip_duration := .22
@export_range(1,100,1) var damage := 1
@export_range(1.0,100.0,1.0,"suffix:m") var shooting_distance := 45.0
@export_range(0.0,8.0,.05,"degrees") var recoil_degrees := 1.55
@export_range(0.0,2.0,.05) var shake_multiplier := 1.0
@export_group("Audio")
@export var aim_sound: AudioStream
@export var shot_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
## Variantes de clic a vide, sans repetition immediate. Empty Sound sert de secours.
@export var empty_sound_variants: Array[AudioStream]=[]
## Ajustement propre a cette arme, ajoute au volume du joueur et au mixage global.
@export_range(-24,6,.5,"suffix:dB") var shot_gain_db := 0.0
@export_range(-24,6,.5,"suffix:dB") var reload_gain_db := 0.0
## Mise en joue et clics a vide. Les impacts de douilles/chargeur se reglent sur la scene d'arme.
@export_range(-24,6,.5,"suffix:dB") var handling_gain_db := 0.0
@export_group("Animations du personnage")
@export var aim_clip := "aim_pose"
@export var fire_clip := "fire"
@export var reload_clip := "reload"
