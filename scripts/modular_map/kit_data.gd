@tool
extends Resource
## Binary source geometry: triangles, original UVs and planar UV gradients.
@export var modules: Dictionary = {}:
	set(value): modules=value; emit_changed()
@export var materials: Array[Material] = []:
	set(value): materials=value; emit_changed()
@export var source_sha256 := "":
	set(value): source_sha256=value; emit_changed()
@export var cell_size := 2.0
@export var wall_height := 3.0
