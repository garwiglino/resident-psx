extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var Map=load("res://scripts/modular_map/map_3d.gd")
	var Layout=load("res://scripts/modular_map/layout.gd")
	var map: Node3D=Map.new(); map.name="Map"
	map.layout=Layout.new(); map.kit=load("res://assets/environment/modular_2m/default_kit.tres")
	map.event_namespace="exemple_modulaire"
	var a: int=map.layout.add_room(); var b: int=map.layout.add_room(); var c: int=map.layout.add_room()
	map.layout.rooms={a:"Entree",b:"Bureau",c:"Couloir"}
	for x in 6:
		for z in 5: map.layout.paint_cell(Vector2i(x,z),c if z>=3 else (a if x<3 else b))
	map.layout.paint_edge("v:3:1",Layout.Kind.DOOR,"solid")
	map.layout.paint_edge("h:1:3",Layout.Kind.DOOR,"glass")
	map.layout.paint_edge("h:4:3",Layout.Kind.DOOR,"double")
	map.layout.paint_edge("h:1:0",Layout.Kind.WINDOW,"boarded")
	map.layout.paint_edge("h:4:0",Layout.Kind.WINDOW,"glass")
	var gameplay := Node3D.new(); gameplay.name="Gameplay"; map.add_child(gameplay); gameplay.owner=map
	var spawn := Marker3D.new(); spawn.name="PlayerSpawn"; spawn.position=Vector3(3,.05,3)
	gameplay.add_child(spawn); spawn.owner=map
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new(); settings.name="ReglagesNiveau"
	settings.profile=load("res://scripts/audio/level_audio_profile.gd").new(); map.add_child(settings); settings.owner=map
	DirAccess.make_dir_recursive_absolute("res://scenes/maps")
	var packed := PackedScene.new(); packed.pack(map)
	var output := "res://scenes/maps/modular_example.tscn"
	if FileAccess.file_exists(output): output="res://exports/modular/new_modular_example.tscn"
	assert(ResourceSaver.save(packed,output)==OK)
	map.free(); print("MODULAR_EXAMPLE_OK"); quit()
