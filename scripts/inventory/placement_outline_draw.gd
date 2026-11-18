extends Node2D
var triangles: Array[Dictionary]=[]
func _draw() -> void:
	for triangle in triangles:draw_polygon(triangle.points,triangle.colors,triangle.uvs,triangle.texture)
