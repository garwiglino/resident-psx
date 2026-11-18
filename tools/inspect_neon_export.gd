extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var path := "res://assets/props/neon_light_01/neon_light_01.tscn"
	var source: Node3D=load(path).instantiate();var mesh: MeshInstance3D=source.get_node("Modele")
	var surfaces: Array=[]
	for i in mesh.mesh.get_surface_count():
		var material: Material=mesh.get_active_material(i)
		surfaces.append({"index":i,"name":material.resource_name if material else "","type":material.get_class() if material else "","meta":material.get_meta_list() if material else [],"vertices":mesh.mesh.surface_get_array_len(i)})
	var result := {"bounds":str(mesh.mesh.get_aabb()),"surfaces":surfaces}
	FileAccess.open("res://docs/neon-export-diagnosis.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result))
	source.free();quit()
