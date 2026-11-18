extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func capture(path: String) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image();image.save_png(path);return image
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func marker_pixels(image: Image,area: Rect2i) -> Array[Vector2i]:
	var pixels: Array[Vector2i]=[]
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var color := image.get_pixel(x,y)
			if color.r>.85 and color.g>.75 and color.b>.5:pixels.append(Vector2i(x,y))
	return pixels
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	await create_timer(.1).timeout
	game.play_dialogue(load("res://assets/dialogue/couloir_example.tres"))
	var controller=game.dialogue;controller.set_process(false)
	await capture("res://docs/dialogue-opening.png")
	check(controller.view.speaker.text=="POLICIERE" and controller.view.body.visible_characters==0,"First frame contains only the window and speaker")
	for index in 12:controller._process(.04);await process_frame
	await capture("res://docs/dialogue-typing.png")
	controller.advance()
	var ready: Image=await capture("res://docs/dialogue-window.png")
	var enlarged: Image=ready.duplicate();enlarged.resize(960,720,Image.INTERPOLATE_NEAREST);enlarged.save_png("res://docs/dialogue-preview.png")
	check(controller.view.body.text=="J'ai entendu quelque chose...\nCa venait du fond du couloir.","Reference dialogue fits exactly two lines without clipping")
	check(controller.view.indicator==controller.View.Indicator.NEXT,"Reference page has next triangle")
	check(not game.player.aiming and game.player.controls_blocked and game.player.is_physics_processing(),"Preview framing uses the regular camera while player animation keeps running")
	var origin: Vector2i=Vector2i(controller.style.box.end)-Vector2i(15,13)
	var bar_area := Rect2i(origin+Vector2i(-1,9),Vector2i(8,1))
	var triangle_area := Rect2i(origin+Vector2i(-1,0),Vector2i(8,8))
	var top_pixels := marker_pixels(ready,triangle_area)
	check(not top_pixels.is_empty() and marker_pixels(ready,bar_area).is_empty(),"Next is a downward triangle without any underline")
	controller._process(controller.style.indicator_period*controller.style.indicator_descent_ratio)
	var down: Image=await capture("res://docs/dialogue-next-down.png")
	var down_pixels := marker_pixels(down,triangle_area)
	var translated: Array[Vector2i]=[]
	for pixel in top_pixels:translated.append(pixel+Vector2i(0,roundi(controller.style.indicator_travel)))
	check(down_pixels==translated,"Actual native pixels move the triangle down by the configured travel")
	check(controller.view.speaker_font.get_font_name()!=controller.view.text_font.get_font_name() and "Bold" in controller.view.speaker_font.get_font_style_name(),"Speaker uses a distinct designed bold pixel font")
	var name: Rect2=controller.view.name_rect
	var outside := 0;var inside := 0
	for y in range(int(name.position.y)+1,int(controller.style.box.position.y)+8):
		for x in range(int(name.position.x)+6,int(name.end.x)-5):
			var pixel := ready.get_pixel(x,y)
			if pixel.r>.85 and pixel.g>.75 and pixel.b>.5:
				if y<int(name.end.y):inside+=1
				else:outside+=1
	check(inside>40 and outside==0,"Actual bold name pixels stay inside their raised tab")
	var blue := ready.get_pixel(200,190)
	check(blue.b>blue.r+.2 and blue.b>blue.g+.2,"Window uses the reference deep blue palette")
	controller.advance();controller.advance()
	var end: Image=await capture("res://docs/dialogue-end.png")
	check(controller.view.indicator==controller.View.Indicator.END,"Final page uses its distinct end marker")
	var final_bar := marker_pixels(end,bar_area)
	check(marker_pixels(end,triangle_area)==top_pixels and final_bar.size()==8,"Final page uses the same triangle plus an underline")
	controller._process(controller.style.indicator_period*controller.style.indicator_descent_ratio)
	var end_down: Image=await capture("res://docs/dialogue-end-down.png")
	check(marker_pixels(end_down,bar_area)==final_bar and marker_pixels(end_down,triangle_area)==down_pixels,"Final underline stays fixed while its triangle moves")
	check(not game.hud.ammo_label.visible and not game.hud.prompt.visible,"Gameplay HUD is hidden under the conversation")
	FileAccess.open("res://docs/dialogue-visual-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"speaker_font":controller.view.speaker_font.get_font_name(),"body_font":controller.view.text_font.get_font_name(),"name_pixels_inside":inside,"name_pixels_outside":outside},"\t"))
	controller.cancel()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame
	print("DIALOGUE_VISUAL_OK: real PSX game frame, reference layout/colors, staged reveal, next/end markers and native-resolution pixel text" if failures.is_empty() else "DIALOGUE_VISUAL_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
