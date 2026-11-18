extends Resource
## Tabler Icons (MIT), small outline sprites drawn at native resolution without filtering.
enum Kind { POINTER, POINT, OPEN_HAND, GRAB, BLOCKED, AIM, HIT }
@export_group("Images - pixels natifs")
@export var pointer: Texture2D=preload("res://assets/ui/cursors/thin/pointer.svg")
@export var hand_point: Texture2D=preload("res://assets/ui/cursors/thin/hand_point.svg")
@export var hand_open: Texture2D=preload("res://assets/ui/cursors/thin/hand_open.svg")
@export var hand_grab: Texture2D=preload("res://assets/ui/cursors/thin/hand_grab.svg")
@export var blocked: Texture2D=preload("res://assets/ui/cursors/thin/blocked.svg")
@export var aim: Texture2D=preload("res://assets/ui/cursors/thin/aim.svg")
@export var hit: Texture2D=preload("res://assets/ui/cursors/thin/hit.svg")
@export_group("Couleurs")
@export var pointer_color := Color(28.0/31,28.0/31,26.0/31)
@export var interaction_color := Color(31.0/31,30.0/31,27.0/31)
@export var grab_color := Color(28.0/31,27.0/31,24.0/31)
@export var blocked_color := Color(17.0/31,17.0/31,16.0/31)
@export var aim_color := Color(28.0/31,28.0/31,26.0/31,.9)
@export var hit_color := Color(31.0/31,30.0/31,27.0/31)
@export var shadow_color := Color(1.0/31,1.0/31,1.0/31,.9)
@export_group("Points actifs - pixels natifs")
@export var pointer_hotspot := Vector2(2,2)
@export var hand_hotspot := Vector2(6,2)
@export var grab_hotspot := Vector2(8,8)
@export var aim_hotspot := Vector2(6,6)
@export var hit_hotspot := Vector2(5,5)
var _nearest_textures: Dictionary={}
func _source_texture(kind: int) -> Texture2D:
	match kind:
		Kind.POINT:return hand_point
		Kind.OPEN_HAND:return hand_open
		Kind.GRAB:return hand_grab
		Kind.BLOCKED:return blocked
		Kind.AIM:return aim
		Kind.HIT:return hit
	return pointer
func texture(kind: int) -> Texture2D:
	var source := _source_texture(kind)
	if not source:return null
	if _nearest_textures.has(source):return _nearest_textures[source]
	# SVG rasterization embeds antialiasing in alpha, even with nearest sampling.
	# Convert once before tint/fade so both icon edges and hit timing stay correct.
	var image := source.get_image()
	if not image or image.is_empty():return source
	image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x,y);pixel.a=1.0 if pixel.a>=.5 else 0.0;image.set_pixel(x,y,pixel)
	var nearest := ImageTexture.create_from_image(image)
	_nearest_textures[source]=nearest;return nearest
func hotspot(kind: int) -> Vector2:
	match kind:
		Kind.POINT:return hand_hotspot
		Kind.OPEN_HAND,Kind.GRAB,Kind.BLOCKED:return grab_hotspot
		Kind.AIM:return aim_hotspot
		Kind.HIT:return hit_hotspot
	return pointer_hotspot
func color(kind: int) -> Color:
	match kind:
		Kind.POINT,Kind.OPEN_HAND:return interaction_color
		Kind.GRAB:return grab_color
		Kind.BLOCKED:return blocked_color
		Kind.AIM:return aim_color
		Kind.HIT:return hit_color
	return pointer_color
func draw(canvas: CanvasItem,kind: int,at: Vector2,opacity := 1.0) -> void:
	var image := texture(kind)
	if not image:return
	var tint := color(kind);tint.a*=opacity
	var origin := (at-hotspot(kind)).round();var shadow := shadow_color;shadow.a*=opacity
	canvas.draw_texture(image,origin+Vector2.ONE,shadow)
	canvas.draw_texture(image,origin,tint)
