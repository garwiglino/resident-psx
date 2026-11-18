extends SceneTree
var failures: Array[String]=[]
var observations := {}
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(frames := 4) -> void:
	for frame in frames:await process_frame
func run() -> void:
	var stage := Node3D.new();root.add_child(stage)
	var camera := Camera3D.new();stage.add_child(camera);camera.position=Vector3(0,1,2);camera.make_current()
	var lamps: Array[Node3D]=[]
	for name in ["neon","applique","plafonnier"]:
		var lamp: Node3D=load("res://scenes/lighting/"+name+".tscn").instantiate();stage.add_child(lamp);lamps.append(lamp)
		check(lamp.is_in_group("psx_world_lights") and lamp._surface_count>0,"Prefab registers its PSX light and illuminated model surfaces: "+name)
		check(lamp.get_children().size()==2,"Fixture owns one generated model and one local audio player")
		for mesh in lamp._emissive_meshes:
			check(mesh.get_meta("psx_unlit_light_id")==lamp.get_instance_id(),"Every luminous mesh belongs to its own light")
	var first: Node3D=lamps[0]
	var original_sound: AudioStream=first.local_sound
	var original_loop: bool=original_sound.get("loop") if original_sound.is_class("AudioStreamPSX") else false
	await settle()
	check(first.local_audio.playing and first.local_audio.stream.is_class("AudioStreamPSX"),"Assigned neon hum plays as a localized native SPU voice")
	check(first.local_audio.bus==&"Ambience" and first.local_audio.stream.get("loop"),"Local sound loops with its ambience category and the level reverb route")
	check((original_sound.get("loop") if original_sound.is_class("AudioStreamPSX") else false)==original_loop,"Loop preparation never changes the shared imported sound")
	first.audio_reverb=false;first._process(0)
	check(first.local_audio.bus==&"Ambience Dry","Per-fixture reverb can be disabled without losing the ambience category")
	first.audio_follows_flicker=true;first.flicker=true;first.flicker_seed=123;first.flicker_amount=0
	first.flicker_minimum=0;first.flicker_maximum=.25;await settle()
	var energy: float=first.get_render_energy();var glow: Color=first.get_surface_emission()
	check(absf(energy/first.light_energy-.25)<.00001 and absf(glow.r/first.light_color.r-.25)<.00001,"Unlit surface and vertex light use the exact same flicker multiplier")
	if DisplayServer.get_name()!="headless":
		for mesh in first._emissive_meshes:check(mesh.get_instance_shader_parameter("psx_lamp_color")==glow,"Ordinary editor shading receives the same light sample")
	check(absf(first.local_audio.volume_db-first.audio_volume_db-linear_to_db(.25))<.001,"Optional audio modulation follows flicker without restarting its loop")
	var stream_id: int=first.local_audio.stream.get_instance_id();first.flicker_maximum=0;await settle()
	check(first.get_render_energy()==0 and first.get_surface_emission().r==0 and first.local_audio.playing and first.local_audio.stream.get_instance_id()==stream_id,"A flicker blackout keeps the existing audio envelope and loop alive")
	first.enabled=false;await settle()
	check(not first.local_audio.playing and first.get_surface_emission().r==0,"Power-off stops local sound and extinguishes the luminous surface together")
	first.enabled=true;first.flicker=false;await settle()
	check(first.local_audio.playing,"Power-on restores the fixture sound")
	camera.position.x=100;await settle()
	check(not first.local_audio.playing,"Out-of-range fixtures release their SPU voice")
	camera.position.x=0;await settle()
	check(first.local_audio.playing,"Returning in range restores local ambience")
	# The source scene and other instances keep independent materials and settings.
	var source: Node3D=first.model_scene.instantiate()
	var source_tube: MeshInstance3D=source.get_node("Tube-1")
	check(source_tube.get_active_material(0) is StandardMaterial3D,"Binding luminous surfaces never edits the imported model material")
	source.free()
	var clone: Node3D=load("res://scenes/lighting/neon.tscn").instantiate();clone.name="NeonAutre";stage.add_child(clone);clone.audio_enabled=false
	first.flicker=true;clone.flicker=true;first.flicker_seed=123;clone.flicker_seed=123;first.flicker_amount=.8;clone.flicker_amount=.8;first.flicker_maximum=1.1;clone.flicker_maximum=1.1
	var independent := false
	for i in 120:
		if absf(first.sample_energy_at(i/60.0)-clone.sample_energy_at(i/60.0))>.001:independent=true
	check(independent,"Copied fixture seeds still produce independent flicker patterns")
	var custom := Node3D.new();var custom_mesh := MeshInstance3D.new();custom_mesh.name="Ampoule";custom_mesh.mesh=BoxMesh.new()
	var material := StandardMaterial3D.new();material.resource_name="M_light";custom_mesh.material_override=material;custom.add_child(custom_mesh);custom_mesh.owner=custom
	var custom_scene := PackedScene.new();custom_scene.pack(custom);clone.model_scene=custom_scene;await settle()
	check(clone._surface_count==1 and clone.model.get_node("Ampoule").get_active_material(0)!=material,"Custom models with a whole-mesh material override still receive their own luminous material")
	check(custom_mesh.material_override==material,"Whole-mesh binding keeps the source model untouched")
	custom.free()
	first.model_scene=load("res://assets/lighting/models/applique.tscn");await settle()
	check(first.model.has_node("Diffuseur") and first._surface_count>0,"Model replacement rebinds its own luminous surfaces")
	var paths: Array[NodePath]=[NodePath("Diffuseur")]
	first.emissive_material_names=PackedStringArray();first.emissive_mesh_paths=paths;await settle()
	check(first._surface_count==1,"A mesh path can select luminous parts without relying on material names")
	var packed := PackedScene.new();packed.pack(first);var path := "res://exports/editor_tests/lamp_roundtrip.tscn";ResourceSaver.save(packed,path)
	check(FileAccess.get_file_as_string(path).length()<5000,"Saved fixture keeps only settings, not generated geometry or audio data")
	var restored: Node3D=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(restored.model_scene.resource_path.ends_with("models/applique.tscn") and restored.audio_follows_flicker and restored.emissive_mesh_paths==[NodePath("Diffuseur")],"Model, audio and surface selection survive save and load")
	restored.free();observations.initial_surfaces=lamps[0]._surface_count;stage.queue_free();await settle()
	observations.ok=failures.is_empty();observations.errors=failures
	FileAccess.open("res://docs/lamp-fixtures-validation.json",FileAccess.WRITE).store_string(JSON.stringify(observations,"\t"))
	print("LAMP_FIXTURES_OK " if failures.is_empty() else "LAMP_FIXTURES_FAILED ",JSON.stringify(observations));quit(0 if failures.is_empty() else 1)
