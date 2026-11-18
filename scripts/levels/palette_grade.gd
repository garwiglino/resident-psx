@tool
extends RefCounted
## Palette/vertex colour arithmetic, before RGB555 quantization and Gouraud.
static func color(source: Color, saturation: float, tint := Color.WHITE, brightness := 1.0) -> Color:
	var grey := source.r*.299 + source.g*.587 + source.b*.114
	return Color((grey+(source.r-grey)*saturation)*tint.r*brightness,
		(grey+(source.g-grey)*saturation)*tint.g*brightness,
		(grey+(source.b-grey)*saturation)*tint.b*brightness,source.a)
