@tool
class_name DialogueSpeaker
extends Resource
@export var speaker_name := "":
	set(value):speaker_name=value;emit_changed()
## Applique a la selection du locuteur. La replique reste modifiable ensuite.
@export var intercom_by_default := false:
	set(value):intercom_by_default=value;emit_changed()
@export_group("Fenetre de dialogue")
## Decoche : conserve Top Color du style commun.
@export var use_top_color := false:
	set(value):use_top_color=value;emit_changed()
## Remplace uniquement le haut du degrade et l'encart du nom.
## Bottom Color, bordures et texte restent ceux du style commun.
@export_color_no_alpha var top_color := Color8(81,91,130):
	set(value):top_color=value;emit_changed()
