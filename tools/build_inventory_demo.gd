extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,root: Node) -> void:
	node.owner=root
	for child in node.get_children(): own(child,root)
func run() -> void:
	var Map=load("res://scripts/modular_map/map_3d.gd"); var Layout=load("res://scripts/modular_map/layout.gd")
	var Settings=load("res://scripts/levels/psx_level_settings.gd"); var Light=load("res://scripts/psx_light_3d.gd")
	var catalogue: Resource=load("res://assets/inventory/catalogue.tres")
	var map: Node3D=Map.new(); map.name="Map"; map.layout=Layout.new(); map.kit=load("res://assets/environment/modular_2m/default_kit.tres"); map.event_namespace="demo_inventaire"
	var a: int=map.layout.add_room(); var b: int=map.layout.add_room()
	for x in 6:
		for z in 3: map.layout.paint_cell(Vector2i(x,z),a if x<3 else b)
	map.layout.paint_edge("v:3:1",Layout.Kind.DOOR,"solid"); map.layout.edges["v:3:1"]["required_item_id"]="key_archives"
	var settings: Node=Settings.new(); settings.name="ReglagesNiveau"; settings.ambient_light_color=Color(.2,.2,.2); settings.profile=load("res://scripts/audio/level_audio_profile.gd").new(); map.add_child(settings)
	var gameplay := Node3D.new(); gameplay.name="Gameplay"; map.add_child(gameplay)
	var spawn := Marker3D.new(); spawn.name="PlayerSpawn"; spawn.position=Vector3(3,.05,4.5); gameplay.add_child(spawn)
	for x in [3,9]:
		var lamp: Node3D=Light.new(); lamp.name="Lampe"+str(x); lamp.position=Vector3(x,2.6,3); lamp.light_energy=3; lamp.light_range=6; map.add_child(lamp)
	var ids := [&"key_archives",&"ammo_magnum",&"medkit",&"maintenance_note",&"valve_wheel"]
	for index in ids.size():
		var pickup: Node3D=load("res://scenes/inventory/item_pickup.tscn").instantiate(); pickup.name="Objet_"+String(ids[index]); pickup.item=catalogue.item(ids[index]); pickup.position=Vector3(1.0+index,0,1.2)
		if ids[index]==&"ammo_magnum": pickup.quantity=12
		map.add_child(pickup)
	for index in 3:
		var card: Node3D=load("res://scenes/inventory/card_pickup.tscn").instantiate(); card.name="Carte_"+str(index+1); card.card_id=catalogue.cards[index].id; card.position=Vector3(7+index*1.5,0,2); map.add_child(card)
	var target: Node3D=load("res://scenes/inventory/item_target.tscn").instantiate(); target.position=Vector3(10,0,4); target.interaction_label="INSTALLER LA ROUE"; map.add_child(target)
	var action: Resource=load("res://scripts/world_events/world_action.gd").new(); action.kind=1; action.id=&"demo.valve_installed"; target.actions.append(action)
	for child in map.get_children(): own(child,map)
	var packed := PackedScene.new(); packed.pack(map)
	DirAccess.make_dir_recursive_absolute("res://scenes/examples")
	var path := "res://scenes/examples/inventory_demo.tscn"
	if FileAccess.file_exists(path): path="res://exports/modular/inventory_demo_new.tscn"
	assert(ResourceSaver.save(packed,path)==OK); map.free(); print("INVENTORY_DEMO_OK ",path); quit()
