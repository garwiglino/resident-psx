extends "res://tools/preview_anime_psx.gd"
## Same capture rig as the approved prototype; production renderer only.
var style: Resource
func _initialize() -> void:
	output_prefix="anime-runtime"
	method_description="Production native anime rendering, matching the approved two-tone preview"
	use_production_anime=true
	style=load("res://assets/rendering/anime_psx.tres").duplicate()
	super._initialize()
func capture(name: String,amount: float) -> Image:
	style.enabled=amount>0;style.tones=0 if amount>=.8 else 1
	if style.tones==1:style.shadow_level=.34;style.light_level=1.2
	else:style.shadow_level=.36;style.light_level=1.14
	game.psx_renderer.anime_style=style
	return await super.capture(name,0)
