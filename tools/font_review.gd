extends SceneTree
var view: SubViewport
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.hud.toast("Soin utilisé / +50 santé")
	game.hud.prompt.text=game.hud.plain_text("[ E ] INSÉRER LE FUSIBLE")
	Input.action_press("aim")
	for i in 12:
		await process_frame
	RenderingServer.force_draw(false)
	view.get_texture().get_image().save_png("res://docs/font-gameplay.png")
	Input.action_release("aim")
	var p: Label=game.hud.prompt
	var font := p.get_theme_font("font")
	var size := p.get_theme_font_size("font_size")
	var required := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789[]/+-'"
	var missing := ""
	for character in required:
		if not font.has_char(character.unicode_at(0)):
			missing+=character
	var longest := "[ E ] OUVRIR L'ISSUE DE SECOURS"
	var width := font.get_string_size(longest,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	print("FONT_REVIEW family=",font.get_font_name()," size=",size," missing=",missing," prompt_width=",width," available=",p.size.x)
	if not missing.is_empty() or width>p.size.x:
		push_error("Font coverage or HUD width failure")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
		audio.stream=null
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	quit(0 if missing.is_empty() and width<=270 else 1)
