@tool
class_name PSXLight3D
extends Marker3D
## Source du moteur PSX. Eclaire les sommets du decor et des personnages.
enum LightType { OMNI, SPOT, DIRECTIONAL }
enum FlickerStyle { FLUORESCENT, CANDLE, FAULTY, RANDOM }
@export var enabled := true
@export_enum("Omni","Spot","Directionnelle") var light_type: int=LightType.OMNI:
	set(value):
		light_type=value
		notify_property_list_changed()
@export var light_color := Color.WHITE
@export_range(0.0,16.0,.05) var light_energy := 1.0
@export_range(.1,50.0,.1,"suffix:m") var light_range := 6.0
## Ouverture totale du cone. Le spot eclaire vers l'axe local -Z.
@export_range(1.0,179.0,1.0,"degrees") var spot_angle_degrees := 45.0
## Largeur du bord progressif, de 0 (dur) a 1 (doux).
@export_range(0.0,1.0,.05) var spot_softness := .35
@export_group("Flicker")
@export var flicker := false:
	set(value): flicker=value; notify_property_list_changed()
@export_enum("Neon","Bougie","Panne electrique","Aleatoire") var flicker_style: int=FlickerStyle.FLUORESCENT:
	set(value): flicker_style=value; notify_property_list_changed()
@export_range(.1,60,.1,"suffix:Hz") var flicker_speed := 12.0
@export_range(0,1,.01) var flicker_amount := .65
@export_range(0,2,.01) var flicker_minimum := 0.0
@export_range(0,2,.01) var flicker_maximum := 1.1
@export_range(0,1,.01) var dropout_chance := .08
@export_range(.01,1,.01,"suffix:s") var dropout_duration := .08
## 0 = fresh random seed per lamp. A fixed seed is still mixed with its node path.
@export var flicker_seed := 0:
	set(value): flicker_seed=value; _random_seed=0
var _random_seed := 0
var _flicker_frame := -1
var _frame_energy := 0.0

func get_render_energy() -> float:
	if not flicker: return light_energy
	var frame := Engine.get_process_frames()
	if frame!=_flicker_frame:
		_flicker_frame=frame; _frame_energy=sample_energy_at(Time.get_ticks_msec()*.001)
	return _frame_energy

func sample_energy_at(seconds: float) -> float:
	if not flicker: return light_energy
	if _random_seed==0:
		_random_seed=absi(hash(str(flicker_seed)+":"+str(get_path()))) if flicker_seed else absi(hash(str(get_instance_id())+":"+str(Time.get_ticks_usec())))
		if _random_seed==0: _random_seed=1
	var time := seconds*flicker_speed+_random(0,7)*4096
	var value := 1.0
	match flicker_style:
		FlickerStyle.CANDLE:
			var movement := _smooth_noise(time*.35,1)*.65+_smooth_noise(time*.9,2)*.25+_smooth_noise(time*.08,3)*.1
			value=1.0+flicker_amount*(movement-.55)*.6
		FlickerStyle.FLUORESCENT:
			value=1.0-flicker_amount*pow(_random(floori(time),4),7)
		FlickerStyle.FAULTY:
			var burst := _random(floori(time*.15),5)
			value=1.0-flicker_amount*(1.0 if burst<.3 and _random(floori(time*1.8),6)<.6 else .05*_random(floori(time),4))
		FlickerStyle.RANDOM:
			value=1.0-flicker_amount*_smooth_noise(time,8)
	if flicker_style!=FlickerStyle.CANDLE and dropout_chance>0:
		var period := maxf(dropout_duration*3,.15)
		var local_seconds := seconds+_random(0,10)*4096
		var slot := floori(local_seconds/period)
		if _random(slot,9)<dropout_chance and fmod(local_seconds,period)<dropout_duration: value=0.0
	return light_energy*clampf(value,minf(flicker_minimum,flicker_maximum),maxf(flicker_minimum,flicker_maximum))

func _random(tick: int, channel: int) -> float:
	var value := (_random_seed ^ (tick*374761393) ^ (channel*668265263)) & 0xffffffff
	value=((value^(value>>16))*0x7feb352d)&0xffffffff
	value=((value^(value>>15))*0x27d4eb2d)&0xffffffff
	return float((value^(value>>16))&0xffffff)/16777215.0

func _smooth_noise(time: float, channel: int) -> float:
	var tick := floori(time); var t := time-tick
	return lerpf(_random(tick,channel),_random(tick+1,channel),t*t*(3-2*t))

func _validate_property(property: Dictionary) -> void:
	if property.name.begins_with("flicker_") and property.name!="flicker" and not flicker: property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name in ["dropout_chance","dropout_duration"] and (not flicker or flicker_style==FlickerStyle.CANDLE): property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="light_range" and light_type==LightType.DIRECTIONAL:property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name in ["spot_angle_degrees","spot_softness"] and light_type!=LightType.SPOT:property.usage&=~PROPERTY_USAGE_EDITOR

func _enter_tree() -> void:
	add_to_group("psx_world_lights")
	gizmo_extents=.25
