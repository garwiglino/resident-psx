extends SceneTree
const Item=preload("res://scripts/inventory/item_definition.gd")
const Card=preload("res://scripts/inventory/card_definition.gd")
const Catalogue=preload("res://scripts/inventory/catalogue.gd")
func _initialize() -> void: call_deferred("run")
func save(resource: Resource,path: String) -> void:
	assert(ResourceSaver.save(resource,path)==OK); resource.take_over_path(path)
func image(path: String,id: String) -> Texture2D:
	var image := Image.new(); assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK)
	var texture := ImageTexture.create_from_image(image)
	save(texture,"res://assets/collection/images/"+id+".res"); return texture
func item(catalogue: Resource,id: String,name: String,kind: int,description: String,stack := 1) -> Resource:
	var value := Item.new(); value.id=StringName(id); value.display_name=name; value.kind=kind; value.description=description; value.stack_limit=stack
	catalogue.items.append(value); return value
func run() -> void:
	for folder in ["res://assets/inventory/items","res://assets/collection/cards","res://assets/collection/images"]: DirAccess.make_dir_recursive_absolute(folder)
	var catalogue := Catalogue.new()
	var medkit := item(catalogue,"medkit","Trousse de soin",Item.Kind.CONSUMABLE,"Restaure 50 points de sante.",5); medkit.healing=50
	var ammo := item(catalogue,"ammo_magnum","Munitions Magnum",Item.Kind.AMMO,"Cartouches pour le Desert Eagle.",99); ammo.ammo_type=&"magnum"
	var pistol := item(catalogue,"desert_eagle","Desert Eagle",Item.Kind.WEAPON,"Pistolet Magnum. Les cartouches du chargeur restent avec l'arme."); pistol.weapon=load("res://assets/weapons/desert_eagle.tres")
	var fuse := item(catalogue,"fuse_16a","Fusible 16 A",Item.Kind.MECHANISM,"Un fusible pour retablir le courant."); fuse.essential=true
	var key := item(catalogue,"key_archives","Cle des archives",Item.Kind.KEY,"Ouvre uniquement la porte des archives."); key.consumed_on_use=false
	var badge := item(catalogue,"access_maintenance","Carte de maintenance",Item.Kind.ACCESS_CARD,"Badge d'acces au secteur maintenance."); badge.consumed_on_use=false
	var wheel := item(catalogue,"valve_wheel","Roue de vanne",Item.Kind.MECHANISM,"Une roue a installer sur une vanne."); wheel.essential=true
	var tool := item(catalogue,"lever_handle","Poignee de levier",Item.Kind.TOOL,"Une poignee reutilisable pour certains mecanismes."); tool.consumed_on_use=false
	var document := item(catalogue,"maintenance_note","Note de maintenance",Item.Kind.DOCUMENT,"Une note laissee par le service technique.")
	document.document_text="NOTE DE MAINTENANCE\n\nLe systeme de secours est hors tension.\nVerifier le fusible avant toute intervention.\n\nNe pas forcer la vanne sans sa roue."
	item(catalogue,"metal_parts","Pieces metalliques",Item.Kind.MATERIAL,"Pieces de rechange pour des interactions definies dans le niveau.",20)
	for value in catalogue.items: save(value,"res://assets/inventory/items/"+String(value.id)+".tres")
	var base := "res://assets/collection/source/"
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"catalogue_jp_fr.json"))
	for row: Dictionary in source.cards:
		var card := Card.new(); card.id=StringName(row.id); card.display_name=row.name; card.description=row.description; card.lore=row.lore; card.rarity=row.rarity; card.source_index=row.index
		card.image=image(base+row.file,String(card.id)); save(card,"res://assets/collection/cards/"+String(card.id)+".tres"); catalogue.cards.append(card)
	catalogue.card_back=image(base+"cartes_64x96/00_dos_commun.png","back")
	catalogue.card_mystery=image(base+"cartes_64x96/16_face_mystere.png","mystery")
	save(catalogue,"res://assets/inventory/catalogue.tres")
	print("INVENTORY_ASSETS_OK ",catalogue.items.size()," item types / ",catalogue.cards.size()," cards"); quit()
