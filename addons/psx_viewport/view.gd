@tool
extends RefCounted
const Renderer=preload("res://scripts/psx_renderer.gd")
const Surface=preload("res://addons/psx_viewport/surface.gd")
const SCENE_LAYERS := (1<<20)-1
var destination: SubViewport
var source_camera: Camera3D
var scene_root: Node3D
var buffer: SubViewport
var camera: Camera3D
var renderer: Node2D
var background: CanvasLayer
var surface: Control
var environment: Environment
var rebuilds := 0
var renders := 0
var original_update_mode := SubViewport.UPDATE_WHEN_VISIBLE

func setup(host: Node,viewport: SubViewport,scene: Node3D,settings: Dictionary) -> void:
	destination=viewport;scene_root=scene
	original_update_mode=destination.render_target_update_mode
	buffer=SubViewport.new();buffer.name="PSXEditorBuffer"
	buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.disable_3d=true
	buffer.world_2d=World2D.new()
	buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
	host.add_child(buffer)
	camera=Camera3D.new();buffer.add_child(camera)
	renderer=Renderer.new();buffer.add_child(renderer)
	for property in settings:renderer.set(property,settings[property])
	renderer.setup_editor(scene,camera)
	background=CanvasLayer.new();background.name="PSXEditorBackground";background.layer=-100
	background.custom_viewport=destination;destination.add_child(background)
	surface=Surface.new();surface.name="PSXEditorImage";surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	surface.texture=buffer.get_texture();background.add_child(surface)
	environment=Environment.new();environment.background_mode=Environment.BG_CANVAS
	environment.background_canvas_max_layer=background.layer
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	rebuilds=1

func restore_camera() -> void:
	if not is_instance_valid(source_camera):return
	# Restore from the live Node properties. They were never changed by the preview.
	var rid := source_camera.get_camera_rid()
	RenderingServer.camera_set_cull_mask(rid,source_camera.cull_mask)
	RenderingServer.camera_set_environment(rid,source_camera.environment.get_rid() if source_camera.environment else RID())
	source_camera=null

func suspend() -> void:
	restore_camera()
	if is_instance_valid(background):background.visible=false
	if is_instance_valid(buffer):buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(destination):
		destination.render_target_update_mode=original_update_mode
		RenderingServer.viewport_set_environment_mode(destination.get_viewport_rid(),RenderingServer.VIEWPORT_ENVIRONMENT_INHERIT)

func rebuild_geometry() -> void:
	renderer.rebuild_editor_geometry();rebuilds+=1

func render(settings: Dictionary) -> void:
	if not renderer.native_restart_required.is_empty():suspend();return
	var active := destination.get_camera_3d()
	if not active or not is_instance_valid(scene_root):suspend();return
	if active!=source_camera:restore_camera();source_camera=active
	background.visible=true;surface.size=Vector2(destination.size)
	destination.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	# The editor root disables environments. Explicitly enable this viewport
	# so BG_CANVAS is scheduled before the gizmo pass, not over it.
	RenderingServer.viewport_set_environment_mode(destination.get_viewport_rid(),RenderingServer.VIEWPORT_ENVIRONMENT_ENABLED)
	var rect: Rect2=surface.frame_rect()
	var ratio := rect.size.y/maxf(surface.size.y,1.0)
	var aspect := surface.size.x/maxf(surface.size.y,1.0)
	var half_fov := tan(deg_to_rad(active.fov)*.5)
	if active.keep_aspect==Camera3D.KEEP_WIDTH:half_fov/=aspect
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.projection=active.projection
	camera.fov=clampf(rad_to_deg(2*atan(half_fov*ratio)),1,179)
	camera.size=maxf(active.size*ratio/(aspect if active.keep_aspect==Camera3D.KEEP_WIDTH else 1.0),.001)
	camera.near=maxf(active.near,.001);camera.far=active.far
	camera.global_transform=active.global_transform
	for property in settings:renderer.set(property,settings[property])
	renderer.render_editor()
	buffer.render_target_update_mode=SubViewport.UPDATE_ONCE
	surface.queue_redraw();renders+=1
	# Hide only the normal scene rendering. Reserved editor gizmo layers survive.
	# Keep Camera3D.cull_mask intact so editor picking still sees the scene.
	RenderingServer.camera_set_cull_mask(active.get_camera_rid(),active.cull_mask&~SCENE_LAYERS)
	RenderingServer.camera_set_environment(active.get_camera_rid(),environment.get_rid())

func dispose() -> void:
	suspend()
	if is_instance_valid(background):background.free()
	if is_instance_valid(buffer):buffer.free()
	background=null;buffer=null;renderer=null;camera=null;surface=null
