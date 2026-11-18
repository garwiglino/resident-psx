extends RefCounted
## Rigid visual heading: authored pelvis/leg poses and root tracks stay intact.
## This layer can be restored with the other pose layers for cinematic ownership.
var node: Node3D
var base_rotation := Basis.IDENTITY
var yaw := 0.0
var applied := false
func setup(target: Node3D) -> void:
	node=target;base_rotation=node.basis.orthonormalized()
func advance(target: float,delta: float,response: float) -> void:
	var alpha := 1.0-exp(-maxf(delta,0)/response) if response>.00001 else 1.0
	yaw=lerp_angle(yaw,target,alpha)
	if absf(yaw-target)<.00001:yaw=target
func restore() -> void:
	if not applied:return
	node.basis=base_rotation.scaled_local(node.scale);applied=false
func apply() -> void:
	if absf(yaw)<.000001:return
	node.basis=(Basis(Vector3.UP,yaw)*base_rotation).scaled_local(node.scale);applied=true
func reset() -> void:
	restore();yaw=0
