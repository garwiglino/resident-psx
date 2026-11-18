extends RefCounted
const Item=preload("res://scripts/inventory/item_definition.gd")
static func draw_icon(node: Control,item: Resource,rect: Rect2) -> void:
	if item.icon: node.draw_texture_rect(item.icon,rect,false,item.icon_tint); return
	var c := rect.get_center(); var s := rect.size.x/24.0; var ink: Color=Color(.88,.87,.77)*item.icon_tint
	match item.kind:
		Item.Kind.CONSUMABLE:
			node.draw_rect(Rect2(c-Vector2(10,7)*s,Vector2(20,14)*s),Color(.3,.5,.36))
			node.draw_rect(Rect2(c-Vector2(2,5)*s,Vector2(4,10)*s),ink); node.draw_rect(Rect2(c-Vector2(5,2)*s,Vector2(10,4)*s),ink)
		Item.Kind.WEAPON:
			node.draw_polygon(PackedVector2Array([c+Vector2(-11,-7)*s,c+Vector2(10,-7)*s,c+Vector2(10,-2)*s,c+Vector2(2,-2)*s,c+Vector2(4,8)*s,c+Vector2(-2,8)*s,c+Vector2(-4,-2)*s,c+Vector2(-11,-2)*s]),PackedColorArray([ink]))
			node.draw_line(c+Vector2(-9,-4)*s,c+Vector2(8,-4)*s,Color(.25,.29,.3),s)
		Item.Kind.AMMO:
			for x in [-6,0,6]:
				node.draw_rect(Rect2(c+Vector2(x-2,-6)*s,Vector2(4,14)*s),Color(.72,.57,.29)); node.draw_circle(c+Vector2(x,-6)*s,2*s,ink)
		Item.Kind.KEY:
			node.draw_circle(c+Vector2(-6,-4)*s,5*s,ink,false,2*s); node.draw_line(c+Vector2(-2,0)*s,c+Vector2(8,10)*s,ink,2*s)
			node.draw_line(c+Vector2(3,5)*s,c+Vector2(7,1)*s,ink,2*s); node.draw_line(c+Vector2(6,8)*s,c+Vector2(10,4)*s,ink,2*s)
		Item.Kind.ACCESS_CARD:
			node.draw_rect(Rect2(c-Vector2(10,7)*s,Vector2(20,14)*s),ink); node.draw_rect(Rect2(c+Vector2(-9,-3)*s,Vector2(18,3)*s),Color(.2,.31,.37))
		Item.Kind.DOCUMENT:
			node.draw_rect(Rect2(c-Vector2(8,11)*s,Vector2(16,22)*s),ink)
			for y in [-5,0,5]: node.draw_line(c+Vector2(-5,y)*s,c+Vector2(5,y)*s,Color(.27,.28,.27),s)
		Item.Kind.MECHANISM:
			node.draw_circle(c,8*s,ink,false,2*s)
			for p in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]: node.draw_line(c-p*8*s,c+p*8*s,ink,2*s)
		Item.Kind.TOOL:
			node.draw_line(c+Vector2(-7,9)*s,c+Vector2(7,-8)*s,ink,3*s); node.draw_circle(c+Vector2(6,-7)*s,5*s,ink,false,2*s)
		_:
			node.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-10)*s,c+Vector2(10,0)*s,c+Vector2(0,10)*s,c+Vector2(-10,0)*s]),ink)
