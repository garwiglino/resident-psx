@tool
class_name ClothingTextureSet
extends Resource

## Nom affiche pour la texture integree au modele dans le menu Hitomi.
@export var original_label := "Origine"

## Vide pour un atlas commun. Avec plusieurs atlas, indiquer le nom du materiau importe.
@export var material_name: StringName:
	set(value):
		material_name=value
		emit_changed()
## Chaque cle est le nom affiche dans Tenue. Glisser le PNG dans la valeur.
@export var variants: Dictionary[StringName,Texture2D]={}:
	set(value):
		variants=value
		emit_changed()

func choices() -> PackedStringArray:
	var labels := PackedStringArray(["Origine"])
	for label in variants:
		var name := String(label)
		if not name.is_empty() and not name.contains(",") and not name.contains(":") and name!="Origine" and variants[label]:
			labels.append(name)
	return labels
