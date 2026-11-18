extends Node3D

const Materials = preload("res://scripts/psx_materials.gd")
var mats: Dictionary = {}

func build() -> void:
	name = "Annexe09"
	var floor_tex = load("res://assets/textures/floor.png")
	var wall_tex = load("res://assets/textures/wall.png")
	var steel_tex = load("res://assets/textures/steel.png")
	mats.floor = Materials.make(Color(0.72,0.75,0.69),floor_tex)
	mats.wall = Materials.make(Color(0.85,0.85,0.78),wall_tex)
	mats.metal = Materials.make(Color(0.63,0.70,0.66),steel_tex)
	mats.dark = Materials.make(Color(0.12,0.17,0.17),steel_tex)
	mats.wood = Materials.make(Color(0.7,0.63,0.52),load("res://assets/textures/wood.png"))
	mats.trim = Materials.make(Color(0.25,0.30,0.28))
	mats.red = Materials.make(Color(0.28,0.06,0.035))
	mats.white = Materials.make(Color(0.69,0.7,0.59))
	mats.glass = Materials.make(Color(0.16,0.27,0.25))
	# Small architectural panels give vertex lights enough vertices without pixel lighting.
	for z in range(-30,9,2):
		for x in range(-5,6,2):
			box("Dalle",Vector3(x,-0.12,z),Vector3(2,0.24,2),mats.floor)
		box("Plafond",Vector3(0,3.35,z),Vector3(12,0.18,2),mats.dark)
		for side in [-1,1]:
			box("Mur",Vector3(side*6,1.6,z),Vector3(0.2,3.2,2),mats.wall)
			box("Plinthe",Vector3(side*5.85,0.13,z),Vector3(0.12,0.25,2),mats.trim,false)
	box("Fond",Vector3(0,1.6,9),Vector3(12,3.2,0.25),mats.wall)
	box("Fond sortie",Vector3(0,1.6,-31),Vector3(12,3.2,0.25),mats.wall)
	for z in [2,-6,-14,-22]:
		for side in [-1,1]:
			box("Pilier",Vector3(side*2.65,1.6,z),Vector3(0.42,3.2,0.55),mats.wall)
			box("Socle pilier",Vector3(side*2.65,0.35,z),Vector3(0.54,0.7,0.66),mats.trim)
		box("Poutre",Vector3(0,3.02,z),Vector3(5.7,0.55,0.55),mats.trim)
	# Partitioned rooms: evidence stores on the left, technical workshop on the right.
	for z in [0,-8,-16,-24]:
		for side in [-1,1]:
			box("Cloison annexe",Vector3(side*4.3,1.5,z),Vector3(3.4,3.0,0.18),mats.wall)
			box("Linteau porte",Vector3(side*2.65,2.7,z-4),Vector3(0.18,0.6,7.8),mats.wall)
			for offset in [-2.8,2.8]:
				box("Trumeau",Vector3(side*2.65,1.2,z-4+offset),Vector3(0.18,2.4,2.1),mats.wall)
	# Reception.
	box("Comptoir",Vector3(-4.2,0.55,4.0),Vector3(2.6,1.1,1.1),mats.wood)
	box("Plateau",Vector3(-4.2,1.14,4.0),Vector3(2.8,0.12,1.3),mats.dark)
	box("Moniteur",Vector3(-4.4,1.48,4.0),Vector3(0.55,0.52,0.48),mats.dark)
	box("Écran",Vector3(-4.4,1.49,4.25),Vector3(0.43,0.33,0.02),Materials.make(Color(0.16,0.23,0.18),null,Vector2.ONE,Color(0.04,0.11,0.07)),false)
	box("Clavier",Vector3(-4.25,1.23,4.48),Vector3(0.65,0.05,0.25),mats.white,false)
	for x in [3.1,4.2,5.3]:
		chair(Vector3(x,0,5.1))
	for z in [-3,-11,-19,-27]:
		for x in [-5.3,-4.5,-3.7]:
			locker(Vector3(x,0,z))
	for z in [-4,-12,-20]:
		box("Table atelier",Vector3(4.45,0.85,z),Vector3(2.2,0.14,1.0),mats.metal)
		for x in [3.6,5.3]:
			box("Pied table",Vector3(x,0.43,z),Vector3(0.08,0.8,0.7),mats.dark)
		box("Caisse",Vector3(4.8,0.4,z-1.5),Vector3(1,0.8,0.8),mats.wood)
		box("Caisse dessus",Vector3(4.8,1.02,z-1.5),Vector3(.78,.45,.65),mats.wood)
	for z in [4,-4,-12,-20,-28]:
		var warm: bool = z==4 or z==-12
		var glow := Color(0.8,0.49,0.23) if warm else Color(0.39,0.74,0.66)
		var x := -2.8 if warm else 2.7
		box("Applique",Vector3(x,2.8,z+1),Vector3(0.8,0.1,0.25),mats.dark,false)
		box("Tube lumineux",Vector3(x,2.73,z+1),Vector3(0.65,0.035,0.15),Materials.make(glow,null,Vector2.ONE,glow*0.8),false)
	for x in [-1.7,-1.4]:
		var pipe := cylinder("Conduite",Vector3(x,3.05,-10),0.065,39,mats.metal)
		pipe.rotation.x = PI/2
	for z in [5,-3,-11,-19,-27]:
		box("Rail câbles",Vector3(2.1,3.06,z),Vector3(0.14,0.13,7.8),mats.dark,false)
	# Central props break sight lines without blocking the entire corridor.
	box("Chariot",Vector3(1.35,0.55,-9),Vector3(0.9,0.12,1.65),mats.metal)
	for x in [.98,1.72]:
		for z in [-9.65,-8.35]:
			box("Pied chariot",Vector3(x,0.3,z),Vector3(0.07,0.5,0.07),mats.dark,false)
	box("Linge",Vector3(1.35,0.69,-9.1),Vector3(0.73,0.18,1.2),mats.white)
	box("Archives tombées",Vector3(-1.5,0.3,-17.7),Vector3(1.2,0.6,0.8),mats.wood)
	# Door is opened by game.gd; its collision body is named for easy editing.
	box("Bloc sortie gauche",Vector3(-3.6,1.5,-29.7),Vector3(4.8,3,0.3),mats.wall)
	box("Bloc sortie droit",Vector3(3.6,1.5,-29.7),Vector3(4.8,3,0.3),mats.wall)
	box("Linteau sortie",Vector3(0,2.82,-29.7),Vector3(2.5,0.35,0.3),mats.trim)
	var door := box("ExitDoor",Vector3(0,1.25,-29.7),Vector3(2.25,2.5,0.18),mats.metal)
	door.name = "ExitDoor"
	box("Barre anti-panique",Vector3(0,1.12,-29.54),Vector3(1.7,0.08,0.08),mats.white,false)
	box("Boîtier électrique",Vector3(5.75,1.3,-20),Vector3(.3,1.1,.8),mats.dark)
	box("Panneau électrique",Vector3(5.56,1.3,-20),Vector3(.03,.9,.65),mats.metal,false)
	for z in [-20.15,-19.9]:
		box("Voyant",Vector3(5.53,1.55,z),Vector3(.02,.055,.055),Materials.make(Color(.8,.13,.05),null,Vector2.ONE,Color(.3,.04,.01)),false)
	sign_text("ANNEXE 09",Vector3(-.45,2.48,1.68),0.045)
	sign_text("SCELLÉS",Vector3(-4.25,2.1,-.11),0.034)
	sign_text("MAINTENANCE",Vector3(4.25,2.1,-16.11),0.026)
	sign_text("ISSUE DE SECOURS",Vector3(0,2.76,-29.49),0.022,Color(0.65,0.8,0.64))
	sign_text("09 / B",Vector3(-4.2,2.2,8.8),0.06)
	for pos in [Vector3(-.8,.007,-12.5),Vector3(.8,.007,-24.5)]:
		var stain := cylinder("Trace",pos,.36,.006,mats.red,9)
		stain.scale.z=.6
	for i in 13:
		var paper := box("Dossier épars",Vector3(sin(i*5.3)*2.1,.015,-5-i*1.5),Vector3(.20,.008,.28),mats.white,false)
		paper.rotation.y=i*1.7
	var env_node := WorldEnvironment.new()
	env_node.name = "Atmosphere"
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(.027,.044,.046)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(.2,.23,.25)
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env_node.environment=env
	add_child(env_node)

func box(label: String, pos: Vector3, size: Vector3, mat: Material, solid := true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name=label
	body.position=pos
	add_child(body)
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size=size
	shape.subdivide_width=0
	shape.subdivide_height=0
	shape.subdivide_depth=0
	mesh.mesh=shape
	mesh.material_override=mat
	body.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size=size
		collision.shape=box_shape
		body.add_child(collision)
	return body

func cylinder(label: String, pos: Vector3, radius: float, height: float, mat: Material, sides := 8) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name=label
	var shape := CylinderMesh.new()
	shape.top_radius=radius
	shape.bottom_radius=radius
	shape.height=height
	shape.radial_segments=sides
	shape.rings=4
	mesh.mesh=shape
	mesh.material_override=mat
	mesh.position=pos
	add_child(mesh)
	return mesh

func locker(pos: Vector3) -> void:
	box("Casier",pos+Vector3(0,1.0,0),Vector3(.72,2.0,.55),mats.metal)
	box("Porte casier",pos+Vector3(0,1.0,.29),Vector3(.65,1.9,.035),mats.dark,false)
	box("Poignée",pos+Vector3(.20,1.05,.33),Vector3(.035,.15,.04),mats.white,false)
	for y in [1.6,1.67,1.74]:
		box("Aération",pos+Vector3(0,y,.32),Vector3(.4,.018,.012),mats.trim,false)

func chair(pos: Vector3) -> void:
	box("Assise",pos+Vector3(0,.45,0),Vector3(.7,.12,.6),mats.dark)
	box("Dossier",pos+Vector3(0,.78,.28),Vector3(.7,.6,.10),mats.dark)
	for x in [-.26,.26]:
		box("Pied siège",pos+Vector3(x,.22,0),Vector3(.04,.44,.45),mats.metal,false)

func sign_text(text: String, pos: Vector3, pixel_size: float, color := Color(.75,.76,.66)) -> void:
	var sign_label := Label3D.new()
	sign_label.name="Signalétique"
	sign_label.text=text
	sign_label.font_size=48
	sign_label.pixel_size=pixel_size/10
	sign_label.modulate=color
	sign_label.no_depth_test=false
	sign_label.outline_size=0
	sign_label.position=pos
	add_child(sign_label)
