extends SceneTree
const Lamp=preload("res://scripts/lighting/psx_lamp_3d.gd")
const MODEL := "res://assets/props/neon_light_01/neon_light_01.tscn"
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var path := "res://assets/props/neon_light_01/neon_light_01.mesh.res"
	var digest := FileAccess.get_sha256(path)
	var lamp := Lamp.new();lamp.model_scene=load(MODEL);root.add_child(lamp)
	check(lamp._surface_count==1,"Existing exported paged M_light resolves without re-export")
	var mesh: MeshInstance3D=lamp.model.get_node("Modele")
	check(mesh.get_meta("psx_unlit_surfaces",PackedInt32Array())==PackedInt32Array([1]),"Only luminous face is unlit; housing retains vertex lighting")
	var source: Node3D=load(MODEL).instantiate();var original: MeshInstance3D=source.get_node("Modele")
	for surface in mesh.mesh.get_surface_count():
		check(mesh.mesh==original.mesh,"Original geometry and UVs remain shared and unchanged")
		if surface!=1:check(mesh.get_active_material(surface)==original.get_active_material(surface),"Housing material remains unchanged")
	var glowing: StandardMaterial3D=mesh.get_active_material(1)
	var previous: StandardMaterial3D=original.get_active_material(1)
	check(glowing!=previous and glowing.albedo_texture==previous.albedo_texture and glowing.albedo_color==previous.albedo_color,"Luminous clone retains source texture and color")
	check(previous.get_meta_list().is_empty(),"Source material metadata is never modified")
	for name in ["M_light","mlight","m_light.001","prop__m_light__384_512_128_64","prop__mlight__couleur"]:
		var material := StandardMaterial3D.new();material.resource_name=name
		check(lamp._matches_emissive_material(material),"Recognizes Blender luminous material name: "+name)
	for name in ["M_surfaces","M_light_cover","prop__m_light_cover__0_0_64_64"]:
		var material := StandardMaterial3D.new();material.resource_name=name
		check(not lamp._matches_emissive_material(material),"Does not bind unrelated materials: "+name)
	var explicit := StandardMaterial3D.new();explicit.resource_name="arbitrary_page_1";explicit.set_meta("psx_source_material","M_light")
	check(lamp._matches_emissive_material(explicit),"New exports resolve original material metadata independently of page name")
	lamp.position=Vector3(5,3,2);lamp.rotation.y=.7;lamp.scale=Vector3(1.2,1.2,1.2)
	var faces := lamp.get_editor_pick_faces()
	check(faces.size()==54,"Editor picking covers all 18 triangles in the actual model")
	var bvh := TriangleMesh.new();check(bvh.create_from_faces(faces),"Selection geometry builds from the actual exported faces")
	check(not bvh.intersect_ray(Vector3(0,-1,0),Vector3.UP).is_empty(),"Selection ray hits the visible neon rather than its invisible collision body")
	lamp.model_position=Vector3(.1,.2,.3)
	for frame in 3:await process_frame
	var moved := lamp.get_editor_pick_faces()
	check(moved.size()==faces.size() and moved[0].is_equal_approx(faces[0]+Vector3(.1,.2,.3)),"Model offsets update selection geometry in lamp-local space")
	check(FileAccess.get_sha256(path)==digest,"Actual exported asset is unchanged on disk")
	source.free();lamp.queue_free();await process_frame
	FileAccess.open("res://docs/neon-export-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("NEON_EXPORT_OK " if failures.is_empty() else "NEON_EXPORT_FAILED ",JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
