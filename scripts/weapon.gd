extends Node3D
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")
signal shot_event
const AnimationAssets = preload("res://scripts/animation_assets.gd")
const MagazineReload = preload("res://scripts/magazine_reload.gd")
## Mechanical animation is local to this asset; the hand attachment owns its world motion.
@export var idle_clip := "pistol_idle"
@export var fire_clip := "pistol_fire"
@export var reload_clip := "pistol_reload"
@export var muzzle_bone := "b_muzzlespot"
@export_dir var animations_directory := "res://assets/weapons/animations"
@export_group("Chargeur")
@export_range(1,60,1) var magazine_drop_frame := 6
@export_range(1,60,1) var magazine_insert_frame := 17
@export_file("*.json") var magazine_hand_mount_file := "res://assets/weapons/reload_magazine_mount.json"
@export_group("Flash et lumiere")
@export_range(.015,.15,.005,"suffix:s") var flash_duration := .055
@export_range(.05,.5,.01,"suffix:m") var flash_size := .16
@export_range(0.0,1.0,.05) var flash_opacity := .5
@export var flash_light_color := Color(1.0,.56,.18)
@export_range(0.0,8.0,.1) var flash_light_energy := 2.8
@export_range(.5,8.0,.1,"suffix:m") var flash_light_range := 3.2
@export_group("Ejection")
@export var bullet_bone := "b_bullet"
## La culasse est ouverte a l'image 2, puis revenue a l'image 4 (24 images/s).
@export_range(0.0,.2,.001,"suffix:s") var ejection_delay := 1.0/24
@export_range(.05,.3,.005,"suffix:s") var bullet_reset_delay := 3.0/24
@export_range(.5,4.0,.1,"suffix:m/s") var ejection_speed := 1.8
@export_range(.2,3.0,.1,"suffix:s") var casing_lifetime := 1.2
@export_group("Son des douilles")
@export var casing_floor_sounds: Array[AudioStream]=[
	preload("res://assets/audio/weapons/bullet_floor_01.wav"),
	preload("res://assets/audio/weapons/bullet_floor_02.wav"),
	preload("res://assets/audio/weapons/bullet_floor_03.wav")]
@export_range(-40.0,0.0,.5,"suffix:dB") var casing_floor_volume_db := -18.0
@export_range(1.0,30.0,.5,"suffix:m") var casing_floor_max_distance := 10.0
@export_group("Son du chargeur")
@export var magazine_floor_sound: AudioStream=preload("res://assets/audio/weapons/mag_floor.wav")
## Le fichier fourni commence par environ 20 ms de quasi-silence avant le choc.
@export_range(0.0,.1,.001,"suffix:s") var magazine_floor_start_offset := .02
@export_range(-40.0,0.0,.5,"suffix:dB") var magazine_floor_volume_db := -16.0
@export_range(1.0,30.0,.5,"suffix:m") var magazine_floor_max_distance := 12.0
var model: Node3D
var skeleton: Skeleton3D
var mixer: AnimationPlayer
var flash_mesh: MeshInstance3D
var flash_time_left := 0.0
var flash_variant := -1
var flash_angle := 0.0
var flash_scale := 1.0
var flash_position := Vector3.ZERO
var shot_time := -1.0
var shot_serial := 0
var magazines := MagazineReload.new()
var reload_time := -1.0
var reload_return_blend_time := .24
var _reload_duration := 0.0
var _reload_fps := 24.0
var fire_event_delay := 1.0/24
var _shot_event_emitted := false
var _pending_shot_event := false
var casings: Array[Dictionary]=[]
var _case_cursor := 0
var _attached_case := -1
var _bullet_bone := -1
var _bullet_pose := Transform3D.IDENTITY
var _ejected := false
var _pending_eject := false
var _floor_sounds: Array[AudioStream]=[]
var _floor_players: Array[AudioStreamPlayer3D]=[]
var _floor_cursor := 0
var _floor_variant := -1
var _magazine_floor_players: Array[AudioStreamPlayer3D]=[]
var _magazine_floor_cursor := 0

func _ready() -> void:
	model=get_node("Model")
	skeleton=model.find_child("Skeleton3D",true,false)
	mixer=AnimationPlayer.new()
	mixer.name="WeaponAnimations"
	model.add_child(mixer)
	mixer.root_node=NodePath("..")
	mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	for file in DirAccess.get_files_at(animations_directory):
		if file.ends_with(".glb"):
			var path := animations_directory.path_join(file)
			var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.get_basename()+".json")) if FileAccess.file_exists(path.get_basename()+".json") else {}
			var name: String=metadata.get("clip",file.get_basename())
			if name==fire_clip:fire_event_delay=1.0/maxf(float(metadata.get("fps",24.0)),1.0)
			if name==reload_clip:_reload_fps=maxf(float(metadata.get("fps",24.0)),1.0)
			var animation := Animation.new()
			animation.length=0
			for source_animation in AnimationAssets.read(path):
				animation.length=maxf(animation.length,source_animation.length)
				for track in source_animation.get_track_count():
					source_animation.copy_track(track,animation)
			animation.loop_mode=Animation.LOOP_LINEAR if metadata.get("loop",name.contains("idle")) else Animation.LOOP_NONE
			library.add_animation(name,animation)
	for imported in model.find_children("*","AnimationPlayer",true,false):
		if imported!=mixer:imported.active=false
	mixer.add_animation_library("",library)
	mixer.animation_finished.connect(func(clip: String):play_idle(reload_return_blend_time if clip==reload_clip else .08))
	play_idle()
	mixer.advance(0)
	_setup_ejection()
	magazines.setup(self,skeleton)
	_setup_flash()
	_setup_casing_audio()
	_setup_magazine_audio()

func play_idle(blend := .08) -> void:
	if mixer.has_animation(idle_clip):mixer.play(idle_clip,blend)

func play_action(clip: String) -> bool:
	if not mixer.has_animation(clip):return false
	mixer.play(clip,.04)
	return true

func fire() -> void:
	if reload_time>=0:cancel_reload()
	_restore_bullet()
	_release_attached_case()
	shot_time=0;shot_serial+=1;_ejected=false;_pending_eject=false
	_shot_event_emitted=false;_pending_shot_event=false
	# A previous shot's short flash may finish during the next wind-up.
	if mixer.has_animation(fire_clip):
		mixer.stop(true);mixer.play(fire_clip,0);mixer.advance(0)
	if _bullet_bone>=0:_bullet_pose=skeleton.get_bone_pose(_bullet_bone)

func configure_reload_hand(target: Skeleton3D,controller: CharacterBody3D) -> void:
	magazines.configure_hand(target,controller,magazine_hand_mount_file)

func reload_weapon(duration := 0.0,player_fps := 0.0) -> void:
	_restore_bullet();_release_attached_case()
	shot_time=-1;flash_time_left=0;_pending_shot_event=false;_pending_eject=false
	reload_time=0;_reload_duration=duration
	if mixer.has_animation(reload_clip):
		_reload_duration=maxf(_reload_duration,mixer.get_animation(reload_clip).length)
		mixer.stop(true);mixer.play(reload_clip,0);mixer.advance(0)
	magazines.drop_frame=magazine_drop_frame;magazines.insert_frame=magazine_insert_frame
	magazines.start(player_fps if player_fps>0 else _reload_fps)
	if _bullet_bone>=0:_bullet_pose=skeleton.get_bone_pose(_bullet_bone)
	magazines.capture()

func cancel_reload() -> void:
	reload_time=-1;magazines.cancel()

func deactivate() -> void:
	reload_time=-1;magazines.cancel(true)
	_release_attached_case()
	_restore_bullet()
	shot_time=-1;flash_time_left=0;_pending_eject=false;_ejected=false
	_pending_shot_event=false;_shot_event_emitted=false
	flash_mesh.visible=false
	for casing in casings:
		casing.time_left=0;casing.attached=false;casing.mesh.visible=false
	play_idle()

func get_muzzle_transform() -> Transform3D:
	if skeleton:
		var bone := skeleton.find_bone(muzzle_bone)
		if bone>=0:return skeleton.global_transform*skeleton.get_bone_global_pose(bone)
	return global_transform

func _setup_flash() -> void:
	flash_mesh=MeshInstance3D.new();flash_mesh.name="MuzzleFlash"
	var quad := QuadMesh.new();quad.size=Vector2.ONE
	flash_mesh.mesh=quad
	var material := StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/effects/muzzle_flash_atlas.png")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mesh.material_override=material
	flash_mesh.add_to_group("psx_sprite")
	flash_mesh.set_meta("psx_sprite_frame",0)
	add_child(flash_mesh);flash_mesh.top_level=true;flash_mesh.visible=false

func update_flash(camera: Camera3D) -> void:
	flash_mesh.visible=flash_time_left>0
	if not flash_mesh.visible:return
	var basis := camera.global_basis*Basis(Vector3.BACK,flash_angle)
	flash_mesh.global_transform=Transform3D(basis.scaled_local(Vector3.ONE*flash_size*flash_scale),flash_position)

func _setup_ejection() -> void:
	_bullet_bone=skeleton.find_bone(bullet_bone)
	if _bullet_bone<0:return
	_bullet_pose=skeleton.get_bone_pose(_bullet_bone)
	var source: MeshInstance3D=model.find_child("bullet",true,false)
	if not source or not source.skin:return
	var bind := Transform3D.IDENTITY
	for index in source.skin.get_bind_count():
		var bone := source.skin.get_bind_bone(index)
		if bone<0:bone=skeleton.find_bone(source.skin.get_bind_name(index))
		if bone==_bullet_bone:bind=source.skin.get_bind_pose(index);break
	var mesh := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for vertex in vertices.size():
			vertices[vertex]=bind*vertices[vertex]
			normals[vertex]=(bind.basis*normals[vertex]).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(surface,source.get_active_material(surface))
	# Reuse pre-registered meshes: no renderer rebuild or allocation on a shot.
	for index in 8:
		var casing := MeshInstance3D.new();casing.name="EjectedBullet%d" % index;casing.mesh=mesh
		add_child(casing);casing.top_level=true;casing.visible=false
		casings.append({"mesh":casing,"time_left":0.0,"transform":Transform3D.IDENTITY,"velocity":Vector3.ZERO,"spin":Vector3.ZERO,"attached":false,"bounces":0,"serial":0,"floor_sound_played":false})

func _setup_casing_audio() -> void:
	for source in casing_floor_sounds:
		if source:_floor_sounds.append(get_node("/root/PSXAudio").prepare(source))
	if _floor_sounds.is_empty():return
	# Reuse voices and prepare SPU data before gameplay, never on collision.
	for index in 4:
		var audio := AudioStreamPlayer3D.new()
		audio.name="CasingFloor%d" % index
		AudioRouting.set_category(audio,&"Weapon Handling")
		audio.stream=_floor_sounds[0]
		audio.volume_db=casing_floor_volume_db
		audio.max_distance=casing_floor_max_distance
		add_child(audio);audio.top_level=true
		_floor_players.append(audio)

func _play_casing_floor(position: Vector3) -> void:
	if _floor_sounds.is_empty():return
	var count := _floor_sounds.size()
	var choice := randi_range(0,count-1 if _floor_variant<0 or count==1 else count-2)
	_floor_variant=choice+1 if count>1 and _floor_variant>=0 and choice>=_floor_variant else choice
	var audio := _floor_players[_floor_cursor]
	_floor_cursor=(_floor_cursor+1)%_floor_players.size()
	AudioRouting.stop(audio)
	audio.stream=_floor_sounds[_floor_variant]
	audio.global_position=position
	AudioRouting.play(audio)

func _setup_magazine_audio() -> void:
	if not magazine_floor_sound:return
	var prepared: AudioStream=get_node("/root/PSXAudio").prepare(magazine_floor_sound)
	for index in 4:
		var audio := AudioStreamPlayer3D.new();audio.name="MagazineFloor%d" % index
		AudioRouting.set_category(audio,&"Weapon Handling")
		audio.stream=prepared;audio.volume_db=magazine_floor_volume_db
		audio.max_distance=magazine_floor_max_distance
		add_child(audio);audio.top_level=true
		_magazine_floor_players.append(audio)

func _play_magazine_floor(position: Vector3) -> void:
	if _magazine_floor_players.is_empty():return
	var audio := _magazine_floor_players[_magazine_floor_cursor]
	_magazine_floor_cursor=(_magazine_floor_cursor+1)%_magazine_floor_players.size()
	# The sound stays at the first floor contact, independently of later bounces.
	AudioRouting.stop(audio);audio.global_position=position;AudioRouting.play(audio,magazine_floor_start_offset)

func _restore_bullet() -> void:
	if _bullet_bone>=0:skeleton.set_bone_pose(_bullet_bone,_bullet_pose)

func _release_attached_case() -> void:
	if _attached_case<0:return
	var casing := casings[_attached_case]
	casing.attached=false
	casing.mesh.global_transform=casing.transform;casing.mesh.visible=casing.time_left>0
	_attached_case=-1
	_restore_bullet()

func advance_animation(delta: float) -> void:
	_restore_bullet()
	magazines.restore()
	mixer.advance(delta)
	magazines.capture()
	if _bullet_bone>=0:_bullet_pose=skeleton.get_bone_pose(_bullet_bone)
	flash_time_left=maxf(flash_time_left-delta,0)
	if reload_time>=0:reload_time+=delta
	magazines.advance(reload_time,delta)
	if reload_time>=_reload_duration and reload_time>=0:reload_time=-1
	if shot_time>=0:
		shot_time+=delta
		if not _shot_event_emitted and shot_time+0.00000001>=fire_event_delay:_pending_shot_event=true
		if not _ejected and shot_time+0.000001>=ejection_delay:_pending_eject=true
		if _attached_case>=0 and shot_time+0.000001>=bullet_reset_delay:_release_attached_case()
	for casing in casings:
		if casing.time_left<=0:continue
		casing.time_left=maxf(casing.time_left-delta,0)
		var transform: Transform3D=casing.transform
		var before := transform.origin
		casing.velocity+=Vector3.DOWN*9.8*delta
		transform.origin+=casing.velocity*delta
		transform.basis=Basis.from_euler(casing.spin*delta)*transform.basis
		if delta>0 and casing.bounces<2:
			var query := PhysicsRayQueryParameters3D.create(before,transform.origin,1)
			var collision := get_world_3d().direct_space_state.intersect_ray(query)
			if not collision.is_empty():
				transform.origin=collision.position+collision.normal*.003
				if not casing.floor_sound_played and collision.normal.dot(Vector3.UP)>=.5:
					casing.floor_sound_played=true
					_play_casing_floor(collision.position)
				casing.velocity=casing.velocity.bounce(collision.normal)*.28
				casing.spin*=.4;casing.bounces+=1
		elif casing.bounces>=2:
			casing.velocity=Vector3.ZERO;casing.spin=Vector3.ZERO;transform.origin=before
		casing.transform=transform
		casing.mesh.global_transform=transform
		casing.mesh.visible=not casing.attached and casing.time_left>0

func sync_after_attachment() -> void:
	# Image 1 is t=0. Dispatch image 2 after the hand/look pose is current,
	# from the same clock as the animation rather than an independent timer.
	if _pending_shot_event:
		_pending_shot_event=false;_shot_event_emitted=true
		flash_time_left=flash_duration
		flash_position=get_muzzle_transform().origin
		var choice := randi_range(0,15 if flash_variant<0 else 14)
		flash_variant=choice+1 if flash_variant>=0 and choice>=flash_variant else choice
		flash_angle=randf_range(-PI,PI);flash_scale=randf_range(.85,1.15)
		flash_mesh.set_meta("psx_sprite_frame",flash_variant)
		shot_event.emit()
	if _pending_eject and not casings.is_empty():
		_restore_bullet()
		_release_attached_case()
		var casing := casings[_case_cursor]
		var transform := skeleton.global_transform*skeleton.get_bone_global_pose(_bullet_bone)
		var forward := (get_muzzle_transform().origin-transform.origin).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		casing.transform=transform;casing.velocity=right*ejection_speed+Vector3.UP*randf_range(.9,1.3)-forward*.2
		casing.spin=Vector3(randf_range(10,20),randf_range(-15,15),randf_range(12,24))
		casing.time_left=casing_lifetime;casing.attached=true;casing.mesh.visible=false;casing.bounces=0;casing.serial=shot_serial
		casing.floor_sound_played=false
		_attached_case=_case_cursor;_case_cursor=(_case_cursor+1)%casings.size()
		_pending_eject=false;_ejected=true
		if shot_time+0.000001>=bullet_reset_delay:_release_attached_case()
	if _attached_case>=0:
		skeleton.set_bone_global_pose(_bullet_bone,skeleton.global_transform.affine_inverse()*casings[_attached_case].transform)
	magazines.sync()
