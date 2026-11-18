@tool
extends RefCounted

static func ensure_box(area: Area3D) -> void:
	# Keep any artist-authored collision shape, including its dimensions.
	for child in area.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:return
	var volume := CollisionShape3D.new();volume.name="Volume"
	var box := BoxShape3D.new();box.resource_local_to_scene=true;box.size=Vector3(2,3,2)
	volume.shape=box;volume.position.y=1.5;area.add_child(volume)
	volume.owner=area.owner if area.owner else area
	# When a node is created from Add Node, the editor assigns its scene owner
	# after _ready. Persist the generated child with that scene as well.
	(func():
		if is_instance_valid(area) and is_instance_valid(volume) and area.owner:volume.owner=area.owner
	).call_deferred()
