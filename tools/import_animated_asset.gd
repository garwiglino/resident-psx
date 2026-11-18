extends RefCounted
## Geometry/animation data are regenerated. The small artist-owned scene is
## created once and never overwritten by subsequent Blender exports.
const Util=preload("res://tools/import_blender_asset.gd")
const PSX=preload("res://scripts/psx_materials.gd")
const SOURCE_TAG := "resident_psx_source_object"

static func _own(root: Node,node: Node) -> void:
	for child in node.get_children():child.owner=root;_own(root,child)
static func _dispose(root: Node) -> void:
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):mesh.mesh=null;mesh.material_override=null
	root.free()
static func _materials(request: Dictionary,input: String) -> Dictionary:
	var result := {};var images := {}
	for row in request.get("materials",[]):
		if not row is Dictionary or not Util.vector_row(row.get("color"),4):return {}
		var texture: Texture2D;var path: String=row.get("texture","")
		if not path.is_empty():
			if path.is_absolute_path() or ".." in path:return {}
			if not images.has(path):
				var image := Image.new()
				if image.load_png_from_buffer(FileAccess.get_file_as_bytes(input.get_base_dir().path_join(path)))!=OK:return {}
				if image.get_width()>256 or image.get_height()>256:return {}
				images[path]=ImageTexture.create_from_image(image)
			texture=images[path]
		var c: Array=row.color;var material := PSX.make(Color(c[0],c[1],c[2],c[3]),texture)
		material.resource_name=row.get("source_material",row.get("name","Materiau"))
		material.set_meta("psx_source_material",material.resource_name)
		material.cull_mode=BaseMaterial3D.CULL_DISABLED if row.get("two_sided",false) else BaseMaterial3D.CULL_BACK
		if row.get("transparent",false):material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		result[String(row.get("gltf_name",row.get("name","")))]=material
	return result

static func import_asset(request: Dictionary,input: String,output_root: String) -> Dictionary:
	var name: String=request.get("asset_name","")
	if not Util.safe_name(name):return Util.fail("Nom du modele anime invalide.")
	if not output_root.is_empty() and (not output_root.begins_with("res://") or ".." in output_root):return Util.fail("Dossier de sortie invalide.")
	var relative: String=request.get("gltf","")
	if relative.is_empty() or relative.is_absolute_path() or ".." in relative:return Util.fail("Chemin GLB invalide.")
	var source := input.get_base_dir().path_join(relative)
	if not FileAccess.file_exists(source):return Util.fail("GLB du modele anime introuvable.")
	var materials := _materials(request,input)
	if materials.is_empty():return Util.fail("Pages de materiaux du modele anime invalides.")
	var fps := float(request.get("fps",30))
	if not is_finite(fps) or fps<1 or fps>240:return Util.fail("Frequence d'animation invalide.")
	var document := GLTFDocument.new();var state := GLTFState.new()
	state.use_named_skin_binds=true;state.handle_binary_image_mode=GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var error := document.append_from_file(source,state)
	if error!=OK:return Util.fail("Impossible de lire le modele GLB : %s" % error_string(error))
	var imported := document.generate_scene(state,fps,false,false) as Node3D
	if not imported:return Util.fail("Le GLB n'a pas produit de hierarchie 3D.")
	var model := Node3D.new();model.name="ModeleExporte";model.add_to_group("psx_dynamic_geometry",true)
	model.set_meta("psx_asset_type","animated")
	var origin := Node3D.new();origin.name="Origine";model.add_child(origin);origin.add_child(imported)
	var tree := Engine.get_main_loop() as SceneTree;tree.root.add_child(model)
	var source_nodes := {};var pivot: Node3D
	# Read exported IDs on the actual nodes. get_scene_node() may refer to a
	# skeleton helper for skinned glTF nodes, which is not a stable authoring path.
	for node: Node3D in model.find_children("*","Node3D",true,false):
		var source_name: String=node.get_meta("extras",{}).get(SOURCE_TAG,"")
		if source_name.is_empty():continue
		node.set_meta(SOURCE_TAG,source_name);source_nodes[source_name]=node
		if source_name==request.get("root_object",""):pivot=node
	if not pivot:_dispose(model);return Util.fail("La racine exportee est introuvable dans la hierarchie GLB.")
	# Remove presentation translation once, at a common ancestor. Every local
	# transform, inverse bind, animated curve and bone-attached marker is retained.
	origin.position=-pivot.global_position
	var triangles := 0;var skeletons := []
	for node in model.find_children("*","Node",true,false):
		if node is MeshInstance3D and node.mesh:
			var geometry := node.mesh as ArrayMesh
			if not geometry:_dispose(model);return Util.fail("Mesh anime non pris en charge.")
			for surface in geometry.get_surface_count():
				var old: Material=node.get_active_material(surface);var source_material: String=old.resource_name if old else ""
				if not old or not old.has_meta("psx_source_material"):
					if not materials.has(source_material):_dispose(model);return Util.fail("Materiau GLB sans page PSX : "+source_material)
					geometry.surface_set_material(surface,materials[source_material])
				var arrays := geometry.surface_get_arrays(surface);var indices: Variant=arrays[Mesh.ARRAY_INDEX]
				triangles+=(indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
		elif node is Skeleton3D:
			var bones := []
			for bone in node.get_bone_count():bones.append(node.get_bone_name(bone))
			skeletons.append({"path":String(model.get_path_to(node)),"bones":bones})
	var node_paths := {};var cameras := [];var clips := []
	for source_name: String in source_nodes:node_paths[source_name]=String(model.get_path_to(source_nodes[source_name]))
	for node in model.find_children("*","Node",true,false):
		if node is AnimationPlayer:
			for clip_name in node.get_animation_list():clips.append({"player":String(model.get_path_to(node)),"name":String(clip_name),"length":node.get_animation(clip_name).length})
		if node is Camera3D:node.current=false;cameras.append(String(model.get_path_to(node)))
	_own(model,model)
	var packed := PackedScene.new();error=packed.pack(model)
	_dispose(model)
	if error!=OK:return Util.fail("Impossible de preparer la scene du modele anime.")
	var folder := "res://assets/props/"+name if output_root.is_empty() else output_root.path_join(name)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:return Util.fail("Impossible de creer le dossier du modele anime.")
	var model_path := folder.path_join(name+".model.scn");var scene_path := folder.path_join(name+".tscn")
	var glb_path := folder.path_join("source.glb");var info_path := folder.path_join("source.json")
	var preserve := FileAccess.file_exists(scene_path)
	if preserve:
		var previous: Variant=JSON.parse_string(FileAccess.get_file_as_string(info_path)) if FileAccess.file_exists(info_path) else null
		if not previous is Dictionary or previous.get("asset_type","")!="animated":return Util.fail("Ce nom appartient deja a un autre objet. Choisir un nouveau nom pour le modele anime.")
	var saved := Util.backup([model_path,scene_path,glb_path,info_path])
	if saved.is_empty():return Util.fail("Impossible de sauvegarder l'ancien modele anime.")
	if not Util.atomic_save(packed,model_path):Util.rollback(saved);return Util.fail("Impossible d'enregistrer les donnees du modele anime.")
	if not preserve:
		var editable := Node3D.new();editable.name=name;editable.set_meta("psx_asset_type","animated")
		var instance: Node3D=packed.instantiate();instance.name="Modele";editable.add_child(instance);instance.owner=editable
		var wrapper := PackedScene.new();error=wrapper.pack(editable);_dispose(editable)
		if error!=OK or not Util.atomic_save(wrapper,scene_path):Util.rollback(saved);return Util.fail("Impossible de creer la scene editable du modele.")
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(glb_path))!=OK:Util.rollback(saved);return Util.fail("Impossible de conserver le GLB source de l'export.")
	var metadata := request.duplicate();metadata.erase("materials")
	metadata.merge({"resource":scene_path,"model_resource":model_path,"nodes":node_paths,"skeletons":skeletons,"animations":clips,"cameras":cameras,"triangles":triangles,"scene_preserved":preserve,"backup":saved.folder},true)
	var file := FileAccess.open(info_path,FileAccess.WRITE)
	if not file:Util.rollback(saved);return Util.fail("Impossible d'enregistrer les informations d'export.")
	file.store_string(JSON.stringify(metadata,"\t"));file.close()
	return {"ok":true,"resource":scene_path,"model_resource":model_path,"asset_uid":ResourceUID.id_to_text(Util.existing_uid(scene_path)),"triangles":triangles,"animations":clips,"scene_preserved":preserve,"backup":saved.folder,"message":"Modele anime mis a jour ; scene Godot conservee." if preserve else "Modele anime pret. Construire les interactions dans sa scene de placement Godot."}
