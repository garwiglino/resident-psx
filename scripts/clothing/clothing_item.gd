@tool
class_name ClothingItem
extends Resource
enum Slot { OUTERWEAR, SHOES, PANTS, TOP, OUTFIT }
@export var id: StringName=&"winter_jacket"
@export var display_name := "Winter Jacket"
@export var scene: PackedScene
@export_file("*.json") var skin_metadata := ""
@export_enum("Couche 2 - doudoune", "Chaussures", "Pantalon", "Haut", "Tenue complete") var slot: int=Slot.OUTERWEAR
## Tenue complete avec chaussures dans le meme maillage.
@export var includes_shoes := false
## Calcule dans Godot les triangles couverts sur les couches inferieures.
@export var automatic_mask := true
## Autorise un coin decouvert si le centre et les milieux restent couverts.
@export var mask_allow_one_corner := false
## Masques nommes herites. Ils s'appliquent uniquement aux couches inferieures.
@export var hides_meshes: Array[StringName]=[]
@export_group("Apparence")
## Variantes partageant les UV de ce modele.
@export var texture_set: ClothingTextureSet:
	set(value):
		if texture_set==value:return
		if texture_set:texture_set.changed.disconnect(_texture_changed)
		texture_set=value
		if texture_set:texture_set.changed.connect(_texture_changed)
		emit_changed()
## Empty keeps the texture exported from Blender. This override survives reexports.
@export var texture: Texture2D:
	set(value):
		if texture==value:return
		if texture and texture.changed.is_connected(_texture_changed):texture.changed.disconnect(_texture_changed)
		texture=value
		if texture:texture.changed.connect(_texture_changed)
		emit_changed()

func _texture_changed() -> void:emit_changed()
