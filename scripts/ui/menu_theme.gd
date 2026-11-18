extends RefCounted

const TEXT := Color(0xe7e0caff)
const MUTED := Color(0xa4aabbff)
const ACCENT := Color(0xe0b86dff)
const INSET := Color(0x0e131cff)
const LINE := Color(0x4b5668ff)
const SHADE := Color(0,0,0,.53)
const BODY=preload("res://assets/fonts/m5x7.ttf")
const TITLE=preload("res://assets/fonts/mgs1-codec-original.ttf")

static func box(color: Color,border: Color,padding := Vector2i(0,0)) -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color=color
	frame.border_color=border
	frame.set_border_width_all(1)
	frame.anti_aliasing=false
	for side in [SIDE_LEFT,SIDE_RIGHT]:frame.set_content_margin(side,padding.x)
	for side in [SIDE_TOP,SIDE_BOTTOM]:frame.set_content_margin(side,padding.y)
	return frame

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font=BODY
	theme.default_font_size=16
	theme.set_color("font_color","Label",TEXT)
	var heading := TITLE.duplicate() as FontFile
	heading.antialiasing=TextServer.FONT_ANTIALIASING_NONE
	heading.hinting=TextServer.HINTING_NONE
	heading.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED
	heading.oversampling=1.0
	var panel := _bevel(Color8(41,48,62),Color8(17,22,31),LINE.lightened(.22),Vector2i(9,8),65)
	for type in ["Panel","PanelContainer"]:theme.set_stylebox("panel",type,panel)

	theme.set_type_variation("MenuInset","Panel")
	theme.set_stylebox("panel","MenuInset",_bevel(Color8(25,32,44),INSET,LINE,Vector2i.ZERO,33))
	theme.set_stylebox("selected","MenuInset",_bevel(Color8(46,56,72),Color8(23,30,42),ACCENT,Vector2i.ZERO,33))
	theme.set_type_variation("MenuHeading","Label")
	theme.set_font("font","MenuHeading",heading)
	theme.set_color("font_color","MenuHeading",TEXT)
	theme.set_type_variation("MenuCaption","Label")
	theme.set_color("font_color","MenuCaption",ACCENT)
	theme.set_type_variation("MenuHint","Label")
	theme.set_color("font_color","MenuHint",MUTED)

	_button_styles(theme,"Button",Vector2i(5,2))
	theme.set_type_variation("MenuCompact","Button")
	_button_styles(theme,"MenuCompact",Vector2i(5,1))
	theme.set_type_variation("MenuTab","Button")
	theme.set_font("font","MenuTab",heading)
	_button_styles(theme,"MenuTab",Vector2i(6,2))
	theme.set_stylebox("panel","TooltipPanel",box(INSET,LINE,Vector2i(5,3)))
	theme.set_color("font_color","TooltipLabel",TEXT)
	for type in ["VScrollBar","HScrollBar"]:
		theme.set_stylebox("scroll",type,box(INSET,LINE,Vector2i(2,2)))
		theme.set_stylebox("grabber",type,box(LINE,LINE.lightened(.1),Vector2i(2,2)))
		theme.set_stylebox("grabber_highlight",type,box(LINE,ACCENT,Vector2i(2,2)))
		theme.set_stylebox("grabber_pressed",type,box(LINE,ACCENT,Vector2i(2,2)))
	return theme

static func fit_button(button: Button) -> void:
	button.clip_text=true
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS

static func _button_styles(theme: Theme,type: String,padding: Vector2i) -> void:
	var normal := _bevel(Color8(52,61,76),Color8(26,33,44),LINE.lightened(.16),padding,23)
	var hover := _bevel(Color8(66,76,93),Color8(34,43,57),LINE.lightened(.42),padding,23)
	var pressed := _bevel(Color8(52,63,82),Color8(25,34,48),ACCENT,padding,23)
	var focus := box(Color.TRANSPARENT,ACCENT)
	focus.draw_center=false
	focus.set_corner_radius_all(2)
	focus.corner_detail=1
	theme.set_stylebox("normal",type,normal)
	theme.set_stylebox("hover",type,hover)
	theme.set_stylebox("pressed",type,pressed)
	theme.set_stylebox("hover_pressed",type,pressed)
	theme.set_stylebox("focus",type,focus)
	theme.set_stylebox("disabled",type,_bevel(Color8(29,35,46),INSET,LINE.darkened(.35),padding,23))
	for color in ["font_color","font_hover_color","font_focus_color"]:
		theme.set_color(color,type,TEXT)
	theme.set_color("font_pressed_color",type,ACCENT)
	theme.set_color("font_hover_pressed_color",type,ACCENT)
	theme.set_color("font_disabled_color",type,MUTED.darkened(.28))

static func _bevel(top: Color,bottom: Color,edge: Color,padding: Vector2i,height: int) -> StyleBoxTexture:
	var image := Image.create(9,height,false,Image.FORMAT_RGBA8)
	for y in height:
		var fill := top.lerp(bottom,float(y)/float(height-1))
		for x in image.get_width():
			var left := mini(x,8-x)
			var above := mini(y,height-1-y)
			var rim := mini(mini(left,above),left+above-2)
			if rim<0:continue
			var tone := fill
			if rim==0:
				tone=edge.darkened(.34) if x>=7 or y>=height-2 else edge
			elif rim==1:
				tone=fill.darkened(.3) if x>=6 or y>=height-3 else fill.lightened(.13)
			image.set_pixel(x,y,Color(roundf(tone.r*31)/31,roundf(tone.g*31)/31,roundf(tone.b*31)/31))
	var frame := StyleBoxTexture.new()
	frame.texture=ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:frame.set_texture_margin(side,3)
	for side in [SIDE_LEFT,SIDE_RIGHT]:frame.set_content_margin(side,padding.x)
	for side in [SIDE_TOP,SIDE_BOTTOM]:frame.set_content_margin(side,padding.y)
	return frame
