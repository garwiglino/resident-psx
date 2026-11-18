extends RefCounted
## Sweeps the full volume, including lateral offsets. A centre ray also handles
## a start volume touching thin geometry (cast_motion ignores initial overlaps).
var shape := SphereShape3D.new()
var query := PhysicsShapeQueryParameters3D.new()
var ray := PhysicsRayQueryParameters3D.new()
func setup(body: CollisionObject3D) -> void:
	query.shape=shape;query.margin=.005;query.exclude=[body.get_rid()]
	ray.exclude=query.exclude;ray.hit_back_faces=true;ray.hit_from_inside=true
func sweep(space: PhysicsDirectSpaceState3D,start: Vector3,end: Vector3,radius: float,mask: int,clearance := 0.0) -> Vector3:
	var motion := end-start
	var length := motion.length()
	if length<.00001 or mask==0:return end
	shape.radius=radius;query.transform=Transform3D(Basis.IDENTITY,start)
	query.motion=motion;query.collision_mask=mask
	var fraction := 1.0
	var cast := space.cast_motion(query)
	if not cast.is_empty() and cast[0]<1.0:fraction=maxf(0,cast[0]-clearance/length)
	ray.from=start;ray.to=end;ray.collision_mask=mask
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():fraction=minf(fraction,maxf(0,(start.distance_to(hit.position)-radius-clearance)/length))
	return start+motion*fraction
