extends SceneTree
const Speakers=preload("res://assets/dialogue/speakers.tres")
const Speaker=preload("res://scripts/dialogue/dialogue_speaker.gd")
const View=preload("res://scripts/dialogue/dialogue_view.gd")
const Style=preload("res://scripts/dialogue/dialogue_style.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var catalogue: Resource=Speakers
	var catalogue_hash := FileAccess.get_sha256(Speakers.resource_path)
	var original := Speakers.entries.duplicate()
	var first := Speaker.new();first.speaker_name="TEST COULEUR A";first.use_top_color=true;first.top_color=Color(.6,.12,.08)
	var second := Speaker.new();second.speaker_name="TEST COULEUR B";second.use_top_color=true;second.top_color=Color(.08,.45,.25)
	var added := original.duplicate();added.append(first);added.append(second);catalogue.entries=added
	var style := Style.new();style.top_color=Color(.12,.17,.45);style.bottom_color=Color(.15,.15,.18)
	var base_top := style.top_color;var base_bottom := style.bottom_color;var base_border := style.border_color
	var viewports: Array[SubViewport]=[];var views: Array[Control]=[]
	for name in [first.speaker_name,second.speaker_name,"INCONNU"]:
		var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.disable_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport);viewports.append(viewport)
		var view := View.new();viewport.add_child(view);view.configure(style);view.set_speaker(name);view.show_page("Une couleur par interlocuteur.");view.body.visible_characters=-1;view.visible=true;views.append(view)
	var a: Image=views[0]._background.get_image();var b: Image=views[1]._background.get_image();var default: Image=views[2]._background.get_image()
	check(a.get_pixel(150,0)!=b.get_pixel(150,0) and a.get_pixel(150,0)!=default.get_pixel(150,0),"Speaker palette changes the upper window and name tab")
	for x in range(0,320,7):check(a.get_pixel(x,a.get_height()-1)==b.get_pixel(x,b.get_height()-1) and a.get_pixel(x,a.get_height()-1)==default.get_pixel(x,default.get_height()-1),"Bottom endpoint stays identical for every speaker")
	check(style.top_color==base_top and style.bottom_color==base_bottom and style.border_color==base_border,"Speaker palettes never mutate the shared dialogue style")
	check(Speakers.top_color_for(" test couleur a ",base_top)==first.top_color,"Speaker matching ignores case and surrounding spaces")
	views[0].set_speaker(second.speaker_name);check(views[0]._background.get_image().get_data()==b.get_data(),"Changing the active speaker refreshes the palette")
	views[0].set_speaker("");check(views[0]._background.get_image().get_data()==default.get_data(),"Anonymous lines reset to the common color without inheriting the previous speaker")
	views[0].set_speaker(first.speaker_name);first.use_top_color=false
	check(views[0]._background.get_image().get_data()==default.get_data(),"Disabling the override restores the shared style immediately")
	first.use_top_color=true;first.top_color=Color(.45,.18,.6)
	check(views[0]._background.get_image().get_data()!=a.get_data(),"Editing the speaker entry updates a visible window")
	var save_path := "res://exports/editor_tests/speaker_color_roundtrip.tres"
	check(ResourceSaver.save(first,save_path)==OK,"Speaker colors save in the existing speaker resource")
	var restored: Resource=ResourceLoader.load(save_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.use_top_color and restored.top_color==first.top_color,"Color and override choice survive saving and loading")
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var sheet := Image.create(960,240,false,Image.FORMAT_RGBA8)
		for i in 3:sheet.blit_rect(viewports[i].get_texture().get_image(),Rect2i(0,0,320,240),Vector2i(i*320,0))
		sheet.save_png("res://docs/dialogue-speaker-colors.png")
	catalogue.entries=original
	check(FileAccess.get_sha256(Speakers.resource_path)==catalogue_hash,"Validation preserves the artist's speaker catalogue on disk")
	for viewport in viewports:viewport.queue_free()
	await process_frame
	var result := {"ok":failures.is_empty(),"errors":failures}
	FileAccess.open("res://docs/speaker-colors-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SPEAKER_COLORS_OK " if failures.is_empty() else "SPEAKER_COLORS_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
