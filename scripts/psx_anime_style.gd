@tool
class_name PSXAnimeStyle
extends Resource
## Palette de lumiere et contour geometrique des personnages. Aucun filtre ecran.
@export var enabled := true:
	set(value):enabled=value;emit_changed()
## 0 retrouve l'eclairage Gouraud d'origine. 1 utilise les aplats de l'apercu valide.
@export_range(0,1,.01) var strength := 1.0:
	set(value):strength=value;emit_changed()
@export_enum("Deux tons","Trois tons") var tones := 0:
	set(value):tones=value;emit_changed();notify_property_list_changed()
## Applique aussi le style aux ennemis et personnages. Le decor reste independant.
@export var other_characters := true:
	set(value):other_characters=value;emit_changed()
## 0 conserve le decor valide dans l'apercu. Doser son style separement.
@export_range(0,1,.01) var world_strength := 0.0:
	set(value):world_strength=value;emit_changed()
@export_group("Ombre et lumiere")
## Seuil de passage de l'ombre a la lumiere, avant le fog.
@export_range(.01,2,.01) var light_threshold := .63:
	set(value):light_threshold=value;emit_changed()
@export_range(0,2,.01) var shadow_level := .36:
	set(value):shadow_level=value;emit_changed()
@export var shadow_tint := Color(.86,.9,1.1):
	set(value):shadow_tint=value;emit_changed()
@export_range(0,2,.01) var light_level := 1.14:
	set(value):light_level=value;emit_changed()
@export var light_tint := Color(1.04,1.02,.96):
	set(value):light_tint=value;emit_changed()
@export_group("Troisieme ton")
@export_range(.01,2,.01) var middle_threshold := .46:
	set(value):middle_threshold=value;emit_changed()
@export_range(.01,2,.01) var highlight_threshold := .94:
	set(value):highlight_threshold=value;emit_changed()
@export_range(0,2,.01) var middle_level := .77:
	set(value):middle_level=value;emit_changed()
@export_group("Contour geometrique")
@export var outline_enabled := true:
	set(value):outline_enabled=value;emit_changed()
## Epaisseur dans le monde, pas un contour plein ecran. 0.006 = 6 mm.
@export_range(0,.03,.0005,"suffix:m") var outline_width := .006:
	set(value):outline_width=value;emit_changed()
@export var outline_color := Color(.025,.02,.04):
	set(value):outline_color=value;emit_changed()
@export_group("Eclairage sombre")
## Sous ce seuil, conserver les zones presque noires au lieu de les eclaircir.
@export_range(0,1,.005) var darkness_threshold := .09:
	set(value):darkness_threshold=value;emit_changed()
@export_range(0,1,.01) var darkness_multiplier := .9:
	set(value):darkness_multiplier=value;emit_changed()
## Part des couleurs des lampes conservee dans les aplats.
@export_range(0,1,.01) var light_color_retention := .35:
	set(value):light_color_retention=value;emit_changed()

func is_active() -> bool:
	return enabled and (strength>0 or world_strength>0 or (outline_enabled and outline_width>0))

func signature() -> Array:
	return [enabled,strength,tones,other_characters,world_strength,light_threshold,shadow_level,shadow_tint,light_level,light_tint,middle_threshold,highlight_threshold,middle_level,outline_enabled,outline_width,outline_color,darkness_threshold,darkness_multiplier,light_color_retention]

func native_settings() -> Dictionary:
	return {"enabled":enabled,"strength":strength,"tones":tones,"other_characters":other_characters,"world_strength":world_strength,"light_threshold":light_threshold,"shadow_level":shadow_level,"shadow_tint":Vector3(shadow_tint.r,shadow_tint.g,shadow_tint.b),"light_level":light_level,"light_tint":Vector3(light_tint.r,light_tint.g,light_tint.b),"middle_threshold":middle_threshold,"highlight_threshold":highlight_threshold,"middle_level":middle_level,"outline_enabled":outline_enabled,"outline_width":outline_width,"outline_color":Vector3(outline_color.r,outline_color.g,outline_color.b),"darkness_threshold":darkness_threshold,"darkness_multiplier":darkness_multiplier,"light_color_retention":light_color_retention}

func _validate_property(property: Dictionary) -> void:
	if property.name in ["middle_threshold","highlight_threshold","middle_level"] and tones==0:property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="light_threshold" and tones==1:property.usage&=~PROPERTY_USAGE_EDITOR
