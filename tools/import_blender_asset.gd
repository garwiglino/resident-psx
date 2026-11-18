extends SceneTree
## Native companion of the Blender add-on. No editor or GLB reimport is required.
const Data=preload("res://scripts/modular_map/kit_data.gd")
const PSX=preload("res://scripts/psx_materials.gd")
const MODULES=["door_01","door_glass","wall_door","wall_door_double","wall_loop","wall_loop_simple","wall_loop_window","window_glass","window_condemned","floor","ceiling"]

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args();var input := "";var kit := "res://assets/environment/modular_2m/default_kit.tres";var output := ""
	for i in args.size()-1:
		match args[i]:
			"--input":input=args[i+1]
			"--kit":kit=args[i+1]
			"--output-root":output=args[i+1]
	var result := import_asset(input,kit,output)
	if not result.has("ok"):result=fail("La conversion a rencontre une erreur. Voir le journal d'export.")
	if not input.is_empty():
		var response := FileAccess.open(input.get_basename()+".result.json",FileAccess.WRITE)
		if response:response.store_string(JSON.stringify(result,"\t"))
	print("BLENDER_PSX_EXPORT_OK " if result.ok else "BLENDER_PSX_EXPORT_FAILED ",JSON.stringify(result))
	await process_frame
	quit(0 if result.ok else 1)

static func fail(message: String) -> Dictionary:return {"ok":false,"message":message}
static func safe_name(value: String) -> bool:
	if value.is_empty() or value.length()>80:return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":return false
	return true
static func vector_row(row: Variant,size: int) -> bool:
	if not row is Array or row.size()!=size:return false
	for value in row:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)):return false
	return true
static func existing_uid(path: String) -> int:
	if not FileAccess.file_exists(path):return ResourceUID.INVALID_ID
	var uid := ResourceLoader.get_resource_uid(path)
	if uid!=ResourceUID.INVALID_ID:return uid
	if path.get_extension() in ["tscn","tres"]:
		var text_file := FileAccess.open(path,FileAccess.READ)
		if not text_file:return ResourceUID.INVALID_ID
		var pattern := RegEx.new();pattern.compile('uid="([^"]+)"')
		var match_uid := pattern.search(text_file.get_line())
		return ResourceUID.text_to_id(match_uid.get_string(1)) if match_uid else ResourceUID.INVALID_ID
	# The standalone converter has no editor UID lookup callback. Read the
	# uncompressed .res header produced here when the generic loader returns -1.
	var file := FileAccess.open(path,FileAccess.READ)
	if not file or file.get_buffer(4).get_string_from_ascii()!="RSRC":return ResourceUID.INVALID_ID
	file.big_endian=file.get_32()!=0;file.get_32()
	var major := file.get_32();file.get_32();var version := file.get_32()
	if major!=4 or version<3:return ResourceUID.INVALID_ID
	var length := file.get_32()
	if length>4096 or file.get_length()<file.get_position()+length+20:return ResourceUID.INVALID_ID
	file.seek(file.get_position()+length);file.get_64();var flags := file.get_32();uid=file.get_64()
	return uid if flags&2 else ResourceUID.INVALID_ID
static func atomic_save(resource: Resource,path: String,flags := 0) -> bool:
	var pending := path.get_basename()+".pending."+path.get_extension()
	var uid := existing_uid(path)
	if uid==ResourceUID.INVALID_ID:uid=ResourceUID.create_id()
	if ResourceSaver.save(resource,pending,flags)!=OK:return false
	if ResourceSaver.set_uid(pending,uid)!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending));return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(pending),ProjectSettings.globalize_path(path))!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending));return false
	if ResourceUID.has_id(uid):ResourceUID.set_id(uid,path)
	else:ResourceUID.add_id(uid,path)
	resource.take_over_path(path);return true
static func backup(paths: Array[String]) -> Dictionary:
	var folder := "res://exports/backups/blender_addon/%d_%d/" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:return {}
	var files := {}
	for path in paths:
		if FileAccess.file_exists(path):
			var destination := folder+path.replace("res://","").replace("/","__")
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(destination))!=OK:return {}
			files[path]=destination
		else:files[path]=""
	return {"folder":folder,"files":files}
static func rollback(saved: Dictionary) -> void:
	for path: String in saved.files:
		var original: String=saved.files[path]
		if original.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:DirAccess.copy_absolute(ProjectSettings.globalize_path(original),ProjectSettings.globalize_path(path))

static func import_asset(input: String,kit_path := "res://assets/environment/modular_2m/default_kit.tres",output_root := "") -> Dictionary:
	if not FileAccess.file_exists(input):return fail("Fichier d'export Blender introuvable.")
	var request: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if request is Dictionary and int(request.get("format_version",0))==2 and request.get("asset_type","")=="animated":
		var animated: Script=load("res://tools/import_animated_asset.gd")
		if not animated or not animated.can_instantiate():return fail("L'importeur anime est incomplet. Mettre a jour les outils du projet.")
		return animated.import_asset(request,input,output_root)
	if not request is Dictionary or int(request.get("format_version",0))!=1:return fail("Format d'export Blender invalide.")
	var type: String=request.get("asset_type","");var name: String=request.get("asset_name","")
	if not type in MODULES and type not in ["prop","stairs"]:return fail("Type de module inconnu.")
	if not safe_name(name):return fail("Nom d'export invalide : utiliser lettres, chiffres et underscores.")
	if not kit_path.begins_with("res://") or ".." in kit_path:return fail("Le kit doit etre une ressource du projet.")
	if not output_root.is_empty() and (not output_root.begins_with("res://") or ".." in output_root):return fail("Dossier de sortie invalide.")
	var prefab: bool=type in ["prop","stairs"]
	var folder := ("res://assets/props/"+name if prefab else "res://assets/environment/custom_modules/"+type) if output_root.is_empty() else output_root.path_join(name if prefab else type)
	var collision: String=request.get("collision","BOX");var collision_points := PackedVector3Array()
	if prefab and collision=="CUSTOM":
		var faces: Variant=request.get("collision_faces",null)
		if not faces is Array or faces.is_empty() or faces.size()%3!=0:return fail("Le mesh de collision personnalise doit contenir des triangles.")
		for point in faces:
			if not vector_row(point,3):return fail("Coordonnees de collision invalides.")
			collision_points.append(Vector3(point[0],point[1],point[2]))
	if type=="stairs" and collision!="CUSTOM":return fail("Un escalier exige son mesh de collision separe.")
	var rows: Variant=request.get("surfaces",null);var materials: Variant=request.get("materials",null)
	if not rows is Array or rows.is_empty() or not materials is Array or materials.is_empty():return fail("Le modele doit contenir une geometrie et des materiaux.")
	var data := Data.new();data.source_sha256=request.get("geometry_sha256","")
	var texture_copies := {};var texture_cache := {}
	for description in materials:
		if not description is Dictionary or not vector_row(description.get("color"),4):return fail("Couleur de materiau invalide.")
		var texture: Texture2D
		var texture_path: String=description.get("texture","")
		if not texture_path.is_empty():
			if texture_path.is_absolute_path() or ".." in texture_path:return fail("Chemin de texture invalide.")
			var source := input.get_base_dir().path_join(texture_path)
			if not texture_cache.has(source):
				var image := Image.new()
				if image.load_png_from_buffer(FileAccess.get_file_as_bytes(source))!=OK:return fail("Texture manquante : "+texture_path)
				if image.get_width()>256 or image.get_height()>256:return fail("Une page PSX ne doit pas depasser 256 x 256 texels.")
				texture_cache[source]=ImageTexture.create_from_image(image)
			texture=texture_cache[source];texture_copies[source]=folder.path_join(texture_path)
		var c: Array=description.color
		var material := PSX.make(Color(c[0],c[1],c[2],c[3]),texture)
		material.resource_name=description.get("name","Materiau")
		if not String(description.get("source_material","")).is_empty():material.set_meta("psx_source_material",description.source_material)
		if description.get("transparent",false):material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		data.materials.append(material)
	var surfaces: Array[Dictionary]=[];var triangles := 0
	for row in rows:
		if not row is Dictionary:return fail("Surface invalide.")
		var vertices: Variant=row.get("vertices",null);var normals: Variant=row.get("normals",null);var uv: Variant=row.get("uv",null);var gradients: Variant=row.get("uv_dx",null)
		if not vertices is Array or vertices.is_empty() or vertices.size()%3!=0 or not normals is Array or not uv is Array or not gradients is Array:return fail("Triangles incomplets.")
		if vertices.size()!=normals.size() or vertices.size()!=uv.size() or vertices.size()!=gradients.size():return fail("UV ou normales incompletes.")
		var index := int(row.get("material",-1))
		if index<0 or index>=data.materials.size():return fail("Indice de materiau invalide.")
		var points := PackedVector3Array();var directions := PackedVector3Array();var coords := PackedVector2Array();var dx := PackedVector2Array()
		for i in vertices.size():
			if not vector_row(vertices[i],3) or not vector_row(normals[i],3) or not vector_row(uv[i],2) or not vector_row(gradients[i],2):return fail("Donnees geometriques invalides.")
			points.append(Vector3(vertices[i][0],vertices[i][1],vertices[i][2]));directions.append(Vector3(normals[i][0],normals[i][1],normals[i][2]).normalized())
			coords.append(Vector2(uv[i][0],uv[i][1]));dx.append(Vector2(gradients[i][0],gradients[i][1]))
		surfaces.append({"vertices":points,"normals":directions,"uv":coords,"uv_dx":dx,"material":index});triangles+=points.size()/3
	data.modules[type]=surfaces
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=surface.vertices;arrays[Mesh.ARRAY_NORMAL]=surface.normals;arrays[Mesh.ARRAY_TEX_UV]=surface.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(mesh.get_surface_count()-1,data.materials[surface.material])
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:return fail("Impossible de creer le dossier de sortie.")
	var result_path: String;var saved: Dictionary
	if prefab:
		if not collision in ["NONE","BOX","TRIMESH","CUSTOM"]:return fail("Type de collision inconnu.")
		var mesh_path := folder.path_join(name+".mesh.res");result_path=folder.path_join(name+".tscn")
		var shape_path := folder.path_join(name+".collision.res")
		saved=backup([mesh_path,result_path,shape_path])
		if saved.is_empty():return fail("Impossible de sauvegarder l'ancien decor.")
		if not atomic_save(mesh,mesh_path):return fail("Impossible d'enregistrer le mesh du decor.")
		var root := Node3D.new();root.name=name;root.set_meta("psx_asset_type",type)
		var visual := MeshInstance3D.new();visual.name="Modele";visual.mesh=mesh;root.add_child(visual);visual.owner=root
		if collision!="NONE":
			var body := StaticBody3D.new();body.name="Collision";root.add_child(body);body.owner=root
			var node := CollisionShape3D.new();node.name="CollisionShape3D";body.add_child(node);node.owner=root
			if collision=="BOX":
				var box := BoxShape3D.new();var bounds := mesh.get_aabb();box.size=bounds.size.max(Vector3.ONE*.001);node.shape=box;node.position=bounds.get_center()
			elif collision=="CUSTOM":
				var custom := ConcavePolygonShape3D.new();custom.backface_collision=true;custom.set_faces(collision_points);node.shape=custom
				body.set_meta("source_mesh",request.get("collision_source",""))
			else:node.shape=mesh.create_trimesh_shape()
			if not atomic_save(node.shape,shape_path):root.free();rollback(saved);return fail("Impossible d'enregistrer la collision du decor.")
		var packed := PackedScene.new();var packed_ok := packed.pack(root)==OK;root.free()
		if not packed_ok or not atomic_save(packed,result_path):rollback(saved);return fail("Impossible d'enregistrer le decor.")
	else:
		if not ResourceLoader.exists(kit_path):return fail("Kit de la carte introuvable.")
		var original: Resource=load(kit_path)
		if not original or not "module_overrides" in original:return fail("Le projet Godot doit recevoir la mise a jour de l'exporteur PSX.")
		var kit: Resource=original.duplicate();result_path=folder.path_join(type+".res")
		saved=backup([result_path,kit_path])
		if saved.is_empty():return fail("Impossible de sauvegarder l'ancien module.")
		if not atomic_save(data,result_path):return fail("Impossible d'enregistrer le module.")
		var overrides: Dictionary[String,Resource]=kit.module_overrides.duplicate();overrides[type]=data;kit.module_overrides=overrides
		if not atomic_save(kit,kit_path):rollback(saved);return fail("Impossible de mettre a jour le kit de la carte.")
	for source: String in texture_copies:
		var destination: String=texture_copies[source];DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
		DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))
	var metadata := {"asset_type":type,"asset_name":name,"source_blend":request.get("source_blend",""),"source_objects":request.get("source_objects",[]),"collision_source":request.get("collision_source",""),"collision_triangles":collision_points.size()/3,"origin_mode":request.get("origin_mode",""),"triangles":triangles,"resource":result_path,"geometry_sha256":data.source_sha256,"backup":saved.folder,"notes":request.get("notes",[])}
	var manifest := FileAccess.open(folder.path_join("source.json"),FileAccess.WRITE)
	if manifest:manifest.store_string(JSON.stringify(metadata,"\t"))
	return {"ok":true,"resource":result_path,"asset_uid":ResourceUID.id_to_text(existing_uid(result_path)),"triangles":triangles,"backup":saved.folder,"message":"Escalier pret a glisser dans Godot." if type=="stairs" else ("Decor pret a glisser dans Godot." if prefab else "Module mis a jour dans Cartes 2m.")}
