@tool
extends RefCounted
const TOP=preload("res://assets/character/face/face_top_atlas_512x256.png")
const BOTTOM=preload("res://assets/character/face/face_bottom_atlas_512x256.png")
const STATE_KEY: StringName = &"psx_face_pages"
static func _cache() -> Dictionary:
	if not Engine.has_meta(STATE_KEY): Engine.set_meta(STATE_KEY,{})
	return Engine.get_meta(STATE_KEY)
static func clear_cache() -> void:
	if Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)

static func part(material: Material) -> int:
	if not material:return 0
	if material.resource_name.begins_with("M_face_top"):return 1
	if material.resource_name.begins_with("M_face_bottom"):return 2
	return 0

## Repack the 4x2 atlas into two PSX pages, preserving every original 128x128 texel.
static func pages(face_part: int) -> Array[Texture2D]:
	if _cache().has(face_part):return _cache()[face_part]
	var original: Image=(TOP if face_part==1 else BOTTOM).get_image()
	if original.is_compressed():original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	var result: Array[Texture2D]=[]
	for page in 2:
		var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
		for tile in 4:
			var frame := page*4+tile
			image.blit_rect(original,Rect2i((frame%4)*128,(frame/4)*128,128,128),Vector2i((tile%2)*128,(tile/2)*128))
		result.append(ImageTexture.create_from_image(image))
	_cache()[face_part]=result
	return result
