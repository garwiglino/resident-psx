extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func ray(game: Node3D, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_ray(query)

func run() -> void:
	root.get_node("InventoryState").persist_collection = false
	var world := root.get_node("WorldEvents")
	world.reset_run()
	change_scene_to_file("res://scenes/level_1.tscn")
	for frame in 10:await process_frame
	var game := current_scene as Node3D
	var renderer: Node = game.psx_renderer
	var map: Node3D = game.level
	game.player.set_physics_process(false)
	game.player.set_process(false)
	renderer.set_process(false)
	var panes := map.find_children("VitreCassable", "StaticBody3D", true, false)
	var double_panes := panes.filter(func(p: StaticBody3D): return p.get_parent().get_parent().has_node("RightPivot"))
	var narrow_panes := panes.filter(func(p: StaticBody3D): return p.intact.mesh.get_aabb().size.x < .5)
	check(double_panes.size() >= 2 and narrow_panes.size() >= 1, "The real level builds both the double door and its narrower glazed variant")
	if double_panes.size() < 2 or narrow_panes.is_empty():quit(1);return
	var pane = double_panes[0]
	var other = double_panes[1]
	for door_pane in panes:
		var opening: AABB = door_pane.intact.mesh.get_aabb()
		var border: AABB = door_pane.rim.mesh.get_aabb()
		check(opening.position.distance_to(border.position) < .002 and opening.size.distance_to(border.size) < .002, "The fitted broken rim meets all edges of the actual pane")
	for narrow in narrow_panes:
		var intact_material: StandardMaterial3D = narrow.intact.get_active_material(0)
		var broken_material: StandardMaterial3D = narrow.rim.get_active_material(0)
		check(intact_material.albedo_texture == broken_material.albedo_texture, "Adapted fractures use their own glass texture")
	var clip := AudioStreamWAV.new()
	clip.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(2205)
	clip.data = samples
	map.glass_break_sound = clip
	var center: Vector3 = pane.to_global(pane.pane_shape.position)
	var normal: Vector3 = pane.global_basis.z.normalized()
	var from := center + normal * .45
	var to := center - normal * .45
	await physics_frame
	check(ray(game, from, to).get("collider") == pane, "An intact pane blocks the shot")
	check(pane.shards.size() == 8 and pane.intact.visible and not pane.rim.visible, "All eight Blender pieces start in the pool")
	var material := pane.rim.get_active_material(0) as PSXReflectiveMaterial
	var fragment := pane.shards[0].get_child(0) as MeshInstance3D
	var shard_material := fragment.get_active_material(0) as PSXReflectiveMaterial
	check(material != null and material.reflection_texture != null and shard_material.reflection_projection == PSXReflectiveMaterial.ReflectionProjection.ENVIRONMENT, "The rim retains the glass reflection and rotating shards use the environment projection")
	var atlas: Texture2D = renderer.atlas_texture
	# With the held visual parked, the normal camera-and-barrel ray path uses
	# the fallback muzzle at the test position on the same side of the pane.
	game.player.unequip_weapon()
	game.player.global_position = from + normal * .8 - Vector3.UP * 1.35
	game.player.look_at(game.player.global_position - normal)
	game.shoot_ray(from, -normal)
	check(world.fact(pane.state_key) and not pane.intact.visible and pane.rim.visible, "A real game shot swaps the pane for the attached rim")
	check(other.intact.visible and not world.fact(other.state_key), "The other leaf has its own saved state")
	check(pane.shards.all(func(body: RigidBody3D): return body.visible and not body.freeze and body.linear_velocity.length() > .1), "All pieces start as moving rigid bodies")
	check(pane.dust.visible and pane.dust.get_meta("psx_sprite_frame") == 0, "Glass dust starts on the impact frame")
	check(pane.sound != null and pane.sound.bus == &"Interactions" and pane.sound.playing, "Assigned spatial SFX uses the Interactions bus")
	check(not pane.break_on_impact(center, normal), "A second impact cannot replay the break")
	var first_position: Vector3 = pane.shards[0].global_position
	for frame in 5:await physics_frame
	check(ray(game, from, to).is_empty(), "The broken opening lets subsequent shots through")
	check(pane.shards[0].global_position.distance_to(first_position) > .015, "Glass fragments move under physics")
	renderer._process(0)
	check(renderer.atlas_texture == atlas and int(pane.dust.get_meta("psx_sprite_frame")) > 0, "The PSX sheet advances inside the existing atlas")
	pane.set_process(false)
	pane._age = 0.0
	for frame in 5:
		pane.update_glass_dust(Basis.IDENTITY)
		check(pane.dust.get_meta("psx_sprite_frame") == frame, "Dust advances through the five retained poses")
		pane._process(.042)
	check(not pane.dust.visible, "The five-pose dust burst ends after about 210 ms")
	var opposite_center: Vector3 = other.to_global(other.pane_shape.position)
	var opposite_normal: Vector3 = other.global_basis.z.normalized()
	var opposite_origin := opposite_center - opposite_normal * .45
	check(ray(game, opposite_origin, opposite_center + opposite_normal * .45).get("collider") == other, "The mirrored leaf is hittable from the opposite side")
	check(other.break_on_impact(opposite_center, opposite_normal) and other.rim.visible, "The second leaf fractures on its own hinge")
	for body: RigidBody3D in other.shards:
		check(absf((body.global_position - opposite_center).dot(other.global_basis.x)) < .35, "The mirrored shards originate inside their own pane")
	var narrow = narrow_panes[0]
	var narrow_center: Vector3 = narrow.to_global(narrow.pane_shape.position)
	var narrow_normal: Vector3 = narrow.global_basis.z.normalized()
	check(narrow.break_on_impact(narrow_center, narrow_normal) and narrow.rim.visible, "The narrow pane uses the same break and saved state")
	for body: RigidBody3D in narrow.shards:
		check(absf((body.global_position - narrow_center).dot(narrow.global_basis.x)) < .2, "Shard origins fit the narrow pane")
	var saved: Dictionary = world.snapshot()
	pane._process(5.0)
	check(not pane.dust.visible and pane.shards.all(func(body: RigidBody3D): return not body.visible and body.freeze), "Expired debris returns to its preallocated pool")
	world.reset_run()
	check(pane.intact.visible and not pane.rim.visible, "Reset restores the unbroken pane")
	check(world.restore(saved) and pane.rim.visible and other.rim.visible and not pane.dust.visible and not other.dust.visible, "Loading restores the broken rims without replaying effects")
	for sound in game.find_children("*", "AudioStreamPlayer3D", true, false):sound.stop()
	game.queue_free()
	await process_frame
	print("DOOR_GLASS_BREAK_OK" if failures.is_empty() else "DOOR_GLASS_BREAK_FAILED " + str(failures))
	quit(0 if failures.is_empty() else 1)
