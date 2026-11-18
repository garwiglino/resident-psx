extends Control
const Style=preload("res://scripts/dialogue/dialogue_style.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Speakers=preload("res://assets/dialogue/speakers.tres")
enum Indicator { NONE, NEXT, END }
var style: Style
var body: Label
var speaker: Label
var text_font: Font
var speaker_font: Font
var name_rect := Rect2()
var indicator := Indicator.NONE
var indicator_visible := false
var indicator_offset := 0.0
var _outline := PackedVector2Array()
var _background: ImageTexture
var _background_signature: Array=[]
var _speaker_name := ""

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	size=Vector2(320,240);texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body=Label.new();speaker=Label.new()
	for label in [body,speaker]:
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.clip_text=true
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x",1)
		label.add_theme_constant_override("shadow_offset_y",1)
		label.visible_characters_behavior=TextServer.VC_CHARS_AFTER_SHAPING
		add_child(label)
	speaker.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;speaker.ellipsis_char="…"
	Speakers.changed.connect(_speaker_palette_changed)
	visible=false

func configure(value: Style) -> void:
	style=value
	var base: Font=style.font if style.font else preload("res://assets/fonts/m5x7.ttf")
	if base is FontFile:
		base.antialiasing=TextServer.FONT_ANTIALIASING_NONE
		base.hinting=TextServer.HINTING_NONE
		base.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED;base.oversampling=1
	text_font=base
	if style.glyph_spacing!=0:
		var variation := FontVariation.new();variation.base_font=base;variation.spacing_glyph=style.glyph_spacing
		text_font=variation
	speaker_font=style.name_font if style.name_font else preload("res://assets/fonts/pixel-operator-bold.ttf")
	if speaker_font is FontFile:
		speaker_font.antialiasing=TextServer.FONT_ANTIALIASING_NONE;speaker_font.hinting=TextServer.HINTING_NONE
		speaker_font.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED;speaker_font.oversampling=1
	body.add_theme_font_override("font",text_font);speaker.add_theme_font_override("font",speaker_font)
	for label in [body,speaker]:
		label.add_theme_color_override("font_color",style.text_color)
	body.add_theme_font_size_override("font_size",style.font_size)
	body.add_theme_constant_override("line_spacing",style.line_spacing)
	body.max_lines_visible=style.lines_per_page
	body.position=text_rect().position;body.size=text_rect().size
	speaker.add_theme_font_size_override("font_size",style.name_font_size)
	set_speaker(_speaker_name)

func text_rect() -> Rect2:
	return Rect2(style.box.position+Vector2(12,8),Vector2(maxf(style.box.size.x-30,16),style.box.size.y-15))

func set_speaker(value: String) -> void:
	_speaker_name=value;_make_background()
	speaker.text=Text.plain(value).replace("\n"," ").strip_edges().to_upper();speaker.visible=not speaker.text.is_empty()
	var box := style.box;var x := box.position.x;var y := box.position.y
	var right := box.end.x;var bottom := box.end.y
	_outline=PackedVector2Array([Vector2(x,y+6),Vector2(x+5,y+1)])
	name_rect=Rect2()
	if speaker.visible:
		var tab_left := x+8
		var width := clampf(ceilf(speaker_font.get_string_size(speaker.text,HORIZONTAL_ALIGNMENT_LEFT,-1,style.name_font_size).x)+14,48,box.size.x-20)
		var tab_end := tab_left+width
		var tab_top := y-style.name_tab_height
		name_rect=Rect2(tab_left,tab_top,width,style.name_tab_height)
		_outline.append_array(PackedVector2Array([Vector2(tab_left-1,y+1),Vector2(tab_left-1,tab_top+3),Vector2(tab_left+2,tab_top),Vector2(tab_end-3,tab_top),Vector2(tab_end,tab_top+3),Vector2(tab_end,y)]))
		# The native bold font has 4 px above its capitals; align the actual
		# letter pixels inside the raised tab, not below its lower edge.
		speaker.position=Vector2(tab_left+6,tab_top-2);speaker.size=Vector2(width-10,16)
	else:_outline.append(Vector2(x+6,y))
	_outline.append_array(PackedVector2Array([Vector2(right-6,y),Vector2(right,y+6),Vector2(right,bottom-6),Vector2(right-6,bottom),Vector2(x+6,bottom),Vector2(x,bottom-6)]))
	queue_redraw()

func _speaker_palette_changed() -> void:
	if not style:return
	_make_background();queue_redraw()

func show_page(value: String) -> void:
	body.text=value;body.visible_characters=0;set_indicator(Indicator.NONE)

func indicator_offset_at(clock: float) -> float:
	var phase := fposmod(clock,maxf(style.indicator_period,.2))/maxf(style.indicator_period,.2)
	var descent := clampf(style.indicator_descent_ratio,.1,.45)
	var progress := phase/descent if phase<descent else 1.0-(phase-descent)/(1.0-descent)
	# Ease both ends, with a short descent and a longer return. Only the
	# triangle moves; rasterization stays at the native PSX resolution.
	return smoothstep(0.0,1.0,progress)*style.indicator_travel

func set_indicator(value: int,clock := 0.0) -> void:
	var offset := indicator_offset_at(clock) if value!=Indicator.NONE else 0.0
	if indicator==value and is_equal_approx(indicator_offset,offset):return
	indicator=value;indicator_visible=value!=Indicator.NONE;indicator_offset=offset;queue_redraw()

func _make_background() -> void:
	var top_color: Color=Speakers.top_color_for(_speaker_name,style.top_color)
	var signature: Array=[style.box,top_color,style.bottom_color,style.name_tab_height]
	if signature==_background_signature:return
	_background_signature=signature
	var height := ceili(style.box.size.y)+style.name_tab_height+1
	var image := Image.create(320,height,false,Image.FORMAT_RGBA8)
	var dither: Array[int]=[-4,0,-3,1,2,-2,3,-1,-3,1,-4,0,3,-1,2,-2]
	for y in height:
		var color := top_color.lerp(style.bottom_color,clampf(float(y-style.name_tab_height)/maxf(style.box.size.y,1),0,1))
		for x in 320:
			var grain := -12 if (x&1)==1 and (y&1)==1 else 0
			var pixel := Color(0,0,0,1)
			for channel in 3:
				var value: float=color[channel]*255+dither[(y&3)*4+(x&3)]+grain*(.5 if channel==1 else 1.0)
				pixel[channel]=floorf(clampf(value,0,255)/8.0)/31.0
			image.set_pixel(x,y,pixel)
	_background=ImageTexture.create_from_image(image)

func _draw() -> void:
	if not style or _outline.is_empty():return
	var shadow := PackedVector2Array();var uvs := PackedVector2Array();var colors := PackedColorArray()
	for point in _outline:
		shadow.append(point+Vector2(2,3))
		uvs.append(Vector2(point.x/320.0,(point.y-style.box.position.y+style.name_tab_height)/_background.get_height()))
		colors.append(Color.WHITE)
	draw_colored_polygon(shadow,style.shadow_color)
	draw_polygon(_outline,colors,uvs,_background)
	var inset := Geometry2D.offset_polygon(_outline,-1,Geometry2D.JOIN_SQUARE)
	if not inset.is_empty():
		var inner: PackedVector2Array=inset[0]
		for index in inner.size():inner[index]=inner[index].round()
		inner.append(inner[0]);draw_polyline(inner,style.inner_border_color,1,false)
	var border := _outline.duplicate();border.append(border[0]);draw_polyline(border,style.border_color,1,false)
	if indicator==Indicator.NONE or not indicator_visible:return
	var origin := Vector2(style.box.end.x-15,style.box.end.y-13)
	var triangle := origin+Vector2(0,indicator_offset)
	draw_colored_polygon(PackedVector2Array([triangle,triangle+Vector2(6,0),triangle+Vector2(3,3)]),style.text_color)
	if indicator==Indicator.END:
		draw_rect(Rect2(origin+Vector2(-1,9),Vector2(8,1)),style.text_color)
