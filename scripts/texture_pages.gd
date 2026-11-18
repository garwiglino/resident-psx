@tool
extends RefCounted
## Logical PSX texture pages packed without reordering polygons.
const PACKET_PAGES := 32 # Legacy packet table; larger levels use a separate page address.
const FaceTextures=preload("res://scripts/face_texture_pages.gd")
const Grade=preload("res://scripts/levels/palette_grade.gd")

static func pack_pages(sources: Array[Texture2D],atlas_size: Vector2i) -> Array[Rect2i]:
	var free: Array[Rect2i]=[Rect2i(Vector2i.ZERO,atlas_size)]
	var rects: Array[Rect2i]=[]
	for texture in sources:
		var size := Vector2i(mini(texture.get_width(),256),mini(texture.get_height(),256))
		var best := -1
		var best_area := 2147483647
		for i in free.size():
			if free[i].size.x>=size.x and free[i].size.y>=size.y:
				var area := free[i].size.x*free[i].size.y
				if area<best_area:
					best=i
					best_area=area
		if best<0:
			return []
		var space := free[best]
		free.remove_at(best)
		rects.append(Rect2i(space.position,size))
		if space.size.x>size.x:
			free.append(Rect2i(space.position+Vector2i(size.x,0),Vector2i(space.size.x-size.x,size.y)))
		if space.size.y>size.y:
			free.append(Rect2i(space.position+Vector2i(0,size.y),Vector2i(space.size.x,space.size.y-size.y)))
	return rects

static func build(entries: Array[Dictionary],blank: Texture2D,tint := Color.WHITE,saturation := 1.0,brightness := 1.0) -> Dictionary:
	var sources: Array[Texture2D]=[]
	var seen: Dictionary={blank.get_rid():true}
	var images: Dictionary={}
	var contents: Dictionary={}
	var aliases: Dictionary={}
	for entry in entries:
		var textures: Array=FaceTextures.pages(entry.face_part) if entry.get("face_part",0)>0 else [entry.texture]
		if entry.get("reflection_texture"):
			textures.append(entry.reflection_texture)
		for texture in textures:
			if not seen.has(texture.get_rid()):
				seen[texture.get_rid()]=true
				var source: Image=texture.get_image().duplicate()
				if source.is_compressed():source.decompress()
				source.convert(Image.FORMAT_RGBA8);source.clear_mipmaps()
				var size := Vector2i(mini(source.get_width(),256),mini(source.get_height(),256))
				if source.get_size()!=size:source.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
				var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(source.get_data())
				var key := str(size)+":"+hash.finish().hex_encode()
				if contents.has(key):aliases[texture.get_rid()]=contents[key];continue
				contents[key]=texture.get_rid();images[texture.get_rid()]=source
				sources.append(texture)
	sources.sort_custom(func(a: Texture2D,b: Texture2D): return mini(a.get_height(),256)*mini(a.get_width(),256)>mini(b.get_height(),256)*mini(b.get_width(),256))
	var atlas_size := Vector2i(512,512)
	var rects := pack_pages(sources,atlas_size)
	# The draw atlas is storage, not a PSX page. Growing it never changes the
	# source texels, logical page wrapping, palette, or polygon ordering.
	while rects.size()!=sources.size() and atlas_size.y<8192:
		if atlas_size.x<=atlas_size.y:atlas_size.x*=2
		else:atlas_size.y*=2
		rects=pack_pages(sources,atlas_size)
	assert(rects.size()==sources.size(),"PSX draw atlas exceeds 8192 x 8192 texels")
	var image := Image.create(atlas_size.x,atlas_size.y,false,Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var pages := PackedVector4Array()
	pages.resize(maxi(PACKET_PAGES,sources.size()+1))
	pages[0]=Vector4(0,0,1,1) # untextured Gouraud polygons
	var lookup: Dictionary={blank.get_rid():0}
	for i in sources.size():
		var texture: Texture2D=sources[i]
		var rect: Rect2i=rects[i]
		var source: Image=images[texture.get_rid()]
		# Edit a private palette image, never the imported texture. Native image
		# saturation avoids rebuilding hundreds of thousands of Color objects
		# when the artist drags a level slider in the inspector.
		if saturation!=1.0 or brightness!=1.0:
			source=source.duplicate(); source.adjust_bcs(brightness,1.0,saturation)
		# Store the high five bits of each RGB channel once, preserving alpha cutout.
		var bytes := source.get_data()
		for at in range(0,bytes.size(),4):
			if tint!=Color.WHITE:
				bytes[at]=clampi(roundi(bytes[at]*tint.r),0,255)
				bytes[at+1]=clampi(roundi(bytes[at+1]*tint.g),0,255)
				bytes[at+2]=clampi(roundi(bytes[at+2]*tint.b),0,255)
			bytes[at]=bytes[at]&248
			bytes[at+1]=bytes[at+1]&248
			bytes[at+2]=bytes[at+2]&248
		source=Image.create_from_data(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8,bytes)
		image.blit_rect(source,Rect2i(Vector2i.ZERO,rect.size),rect.position)
		lookup[texture.get_rid()]=i+1
		pages[i+1]=Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y)
	for alias: RID in aliases:lookup[alias]=lookup[aliases[alias]]
	var atlas := ImageTexture.create_from_image(image)
	atlas.resource_name="PSX texture pages RGB555"
	var page_image := Image.create(mini(pages.size(),1024),ceili(pages.size()/1024.0),false,Image.FORMAT_RGBAF)
	for i in pages.size():page_image.set_pixel(i%1024,i/1024,Color(pages[i].x,pages[i].y,pages[i].z,pages[i].w))
	var page_lookup := ImageTexture.create_from_image(page_image)
	var has_reflections := false
	for entry in entries:
		var face: int=entry.get("face_part",0)
		var page: int
		if face:
			var face_pages := FaceTextures.pages(face)
			entry["face_pages"]=PackedInt32Array([lookup[face_pages[0].get_rid()],lookup[face_pages[1].get_rid()]])
			page=entry.face_pages[0]
		else:page=lookup[entry.texture.get_rid()]
		# Keep effect/depth flags separate from the full logical page address.
		entry["page_index"]=page
		entry["texture_page"]=(page&31)|32 if entry.get("sprite",false) or entry.get("translucent",false) else (page&31)
		entry["textured"]=entry.texture!=blank
		entry["draw_texture"]=atlas
		entry["atlas_pages"]=pages
		entry["logical_texture_size"]=Vector2(128,128) if face else Vector2(pages[page].z,pages[page].w)
		var reflection: Texture2D=entry.get("reflection_texture")
		entry["reflection_page"]=int(lookup[reflection.get_rid()]) if reflection else 0
		has_reflections=has_reflections or reflection!=null or entry.get("scene_reflection",0)>0
	return {"texture":atlas,"pages":pages,"lookup":page_lookup,"extended":pages.size()>PACKET_PAGES,
		"has_reflections":has_reflections,"page_count":sources.size()+1,"source_count":seen.size(),"size":atlas_size}
