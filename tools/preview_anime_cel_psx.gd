extends "res://tools/preview_anime_psx.gd"
## Review only: split the projected triangles at lighting thresholds on the CPU.
## Each resulting triangle still uses the production PSX texture/raster shader.
## Unlike simply quantizing the original vertices, this preserves a hard band
## boundary instead of letting Gouraud interpolate back across the whole face.
var outline_nodes: Array[MeshInstance3D]=[]

func _initialize() -> void:
	output_prefix="anime-cel-preview"
	method_description="Character cel-light bands split into triangles on the CPU, thin inverted-geometry contour; existing PSX raster, textures, UVs, RGB555 and dithering; world unchanged"
	super._initialize()

func capture(name: String,amount: float) -> Image:
	var renderer: Node=game.psx_renderer
	if amount>0 and outline_nodes.is_empty():
		var extra: Array[Dictionary]=[]
		for source: Dictionary in renderer.entries:
			if not source.get("depth_correct",false) or not source.skeleton or not source.node.is_visible_in_tree():continue
			var node := MeshInstance3D.new();node.name="ReviewOnlyInk";node.mesh=source.node.mesh;game.add_child(node);node.global_transform=source.node.global_transform;outline_nodes.append(node)
			var shell: Dictionary=source.duplicate()
			shell.node=node;shell.unlit=true;shell.unlit_light_id=0;shell.light_occluder=false;shell.light_static_receiver=false;shell.torch_receiver=false
			shell.page_index=0;shell.texture_page=0;shell.face_part=0;shell.textured=false;shell.sprite=false;shell.color=Color(.025,.02,.04);shell.emission=Color.BLACK
			var positions: PackedVector3Array=source.vertices.duplicate();var normals: PackedVector3Array=source.normals
			for vertex in positions.size():positions[vertex]+=normals[vertex].normalized()*.006
			shell.vertices=positions
			var triangles: PackedInt32Array=source.indices.duplicate()
			for triangle in range(0,triangles.size(),3):
				var temporary := triangles[triangle+1];triangles[triangle+1]=triangles[triangle+2];triangles[triangle+2]=temporary
			shell.indices=triangles;extra.append(shell)
		renderer.entries.append_array(extra);renderer._configure_native_geometry()
	for node in outline_nodes:node.visible=amount>0
	return await super.capture(name,amount)

func interpolate_vertex(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
	return {"point":a.point.lerp(b.point,t),"uv":a.uv.lerp(b.uv,t),"light":a.light.lerp(b.light,t),"luma":lerpf(a.luma,b.luma,t),"q":lerpf(a.q,b.q,t),"score":lerpf(a.score,b.score,t),"flags":a.flags,"page":a.page}

func snap_cut_vertex(vertex: Dictionary,source: Array,page_size: Vector2) -> Dictionary:
	# New cel edges are geometry too: retain integer screen positions and texel
	# coordinates. Re-evaluate the original depth plane at the snapped point.
	var point: Vector2=vertex.point.floor()
	var edge_b: Vector2=source[1].point-source[0].point
	var edge_c: Vector2=source[2].point-source[0].point
	var delta: Vector2=point-source[0].point
	var determinant := edge_b.cross(edge_c)
	if absf(determinant)<.00001:return vertex
	var b := delta.cross(edge_c)/determinant
	var c := edge_b.cross(delta)/determinant
	var a := 1.0-b-c
	var result := vertex.duplicate()
	result.point=point
	result.q=source[0].q*a+source[1].q*b+source[2].q*c
	result.score=source[0].score*a+source[1].score*b+source[2].score*c
	var uv: Vector2=source[0].uv*a+source[1].uv*b+source[2].uv*c
	result.uv=(uv*page_size).round()/page_size
	return result

func clip_light(polygon: Array,threshold: float,above: bool) -> Array:
	var result: Array=[]
	if polygon.is_empty():return result
	var previous: Dictionary=polygon.back()
	var previous_inside: bool=previous.luma>=threshold if above else previous.luma<=threshold
	for current: Dictionary in polygon:
		var current_inside: bool=current.luma>=threshold if above else current.luma<=threshold
		if current_inside!=previous_inside:
			var t: float=(threshold-previous.luma)/(current.luma-previous.luma)
			result.append(interpolate_vertex(previous,current,t))
		if current_inside:result.append(current)
		previous=current;previous_inside=current_inside
	return result

func stylize_packets(renderer: Node,amount: float) -> void:
	var limits: Array=[.09,.46,.94] if amount<.8 else [.09,.63]
	var tones: Array=[0.0,.34,.77,1.2] if amount<.8 else [0.0,.36,1.14]
	var fog: Color=Grade.color(renderer.fog_color,renderer.saturation)
	var fog_rgb := Vector3(fog.r,fog.g,fog.b)
	var skip_pages := {}
	for entry: Dictionary in renderer.entries:
		if entry.get("unlit",false) or int(entry.get("unlit_light_id",0))!=0:skip_pages[int(entry.get("page_index",entry.get("page",0)))]=true
	var source_triangles := 0
	var result_triangles := 0
	for packet: Dictionary in renderer.primitives:
		if int(packet.get("blend_mode",0))!=0:continue
		var original_colors: PackedColorArray=packet.colors
		var original_points: PackedVector2Array=packet.points
		var original_uvs: PackedVector2Array=packet.uvs
		var inverse: PackedFloat32Array=packet.inverse_depths
		var channels: PackedFloat32Array=packet.depth_channels
		var extended: bool=packet.get("extended_pages",false)
		var stride := 4 if extended else 2
		var original_indices: PackedInt32Array=packet.indices
		var points := PackedVector2Array();var colors := PackedColorArray();var uvs := PackedVector2Array()
		var depths := PackedFloat32Array();var depth_channels := PackedFloat32Array();var indices := PackedInt32Array()
		for triangle in range(0,original_indices.size(),3):
			var polygon: Array=[]
			var flags := roundi(original_colors[original_indices[triangle]].a*255)
			var page: int=roundi(channels[original_indices[triangle]*stride+2]) if extended else flags&31
			var page_rect: Vector4=renderer.entries[0].atlas_pages[page]
			var page_size := Vector2(maxf(page_rect.z,1),maxf(page_rect.w,1))
			var scale := 128.0 if page else 255.0
			var skip: bool=(flags&32)!=0 or (flags&64)==0 or skip_pages.has(page)
			for corner in 3:
				var index := original_indices[triangle+corner]
				var color := original_colors[index]
				var depth := 1.0/maxf(inverse[index],.00000001)
				var fog_weight := clampf((depth-renderer.fog_start)/maxf(renderer.fog_end-renderer.fog_start,.001),0,.88) if renderer.fog_enabled else 0.0
				var light := (Vector3(color.r,color.g,color.b)*255.0/scale-fog_rgb*fog_weight)/(1-fog_weight)
				polygon.append({"point":original_points[index],"uv":original_uvs[index],"light":light,"luma":light.dot(Vector3(.299,.587,.114)),"q":inverse[index],"score":channels[index*stride+1],"flags":flags,"page":page,"raw_color":color})
			source_triangles+=1
			for band in (1 if skip else tones.size()):
				var section: Array=polygon
				if not skip:
					if band>0:section=clip_light(section,limits[band-1],true)
					if band<limits.size():section=clip_light(section,limits[band],false)
				if section.size()<3:continue
				for fan in range(1,section.size()-1):
					var corners: Array=[section[0],section[fan],section[fan+1]]
					if not skip and renderer.vertex_snapping:
						for corner in 3:corners[corner]=snap_cut_vertex(corners[corner],polygon,page_size)
					var edge_a: Vector2=corners[1].point-corners[0].point
					var edge_b: Vector2=corners[2].point-corners[0].point
					if absf(edge_a.cross(edge_b))<.00001:continue
					result_triangles+=1
					for vertex: Dictionary in corners:
						var shade: Vector3=vertex.light
						if not skip:
							var hue: Vector3=Vector3.ONE.lerp(vertex.light/maxf(vertex.luma,.001),.35)
							var tint := Vector3(.86,.9,1.1) if band<=1 else Vector3(1.04,1.02,.96)
							var toon: Vector3=hue*tint*tones[band]
							shade=vertex.light*.9 if band==0 else toon
						var depth: float=1.0/maxf(vertex.q,.00000001)
						var fog_weight := clampf((depth-renderer.fog_start)/maxf(renderer.fog_end-renderer.fog_start,.001),0,.88) if renderer.fog_enabled else 0.0
						var encoded := (shade*(1-fog_weight)+fog_rgb*fog_weight)*scale
						indices.append(points.size());points.append(vertex.point);uvs.append(vertex.uv)
						colors.append(vertex.raw_color if skip else Color(clampf(floorf(encoded.x),0,255)/255.0,clampf(floorf(encoded.y),0,255)/255.0,clampf(floorf(encoded.z),0,255)/255.0,float(flags)/255.0))
						depths.append(vertex.q);depth_channels.append(vertex.q);depth_channels.append(vertex.score)
						if extended:depth_channels.append(float(page));depth_channels.append(0.0)
		packet.points=points;packet.uvs=uvs;packet.colors=colors;packet.inverse_depths=depths;packet.depth_channels=depth_channels;packet.indices=indices
	renderer._prepare_perspective_meshes();renderer.queue_redraw()
	report["source_triangles"]=source_triangles;report["cel_triangles"]=result_triangles
