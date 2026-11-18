extends RefCounted
const Renderer=preload("res://scripts/psx_renderer.gd")
class LegacyNative extends RefCounted:
	func get_statistics() -> Dictionary:return {"version":16}
var failures: Array[String]=[]
var measurements: Array=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 8) -> void:
	for frame in count:await plugin.get_tree().process_frame
func sample(plugin: EditorPlugin,renderer: Node,label: String,count: int) -> Dictionary:
	var values: Array[float]=[]
	for frame in count:
		renderer.render_editor();values.append(renderer.last_process_us/1000.0)
		await plugin.get_tree().process_frame
	values.sort()
	var total := 0.0
	for value in values:total+=value
	var result := {"scenario":label,"cpu_ms_mean":total/values.size(),"cpu_ms_p95":values[mini(int(values.size()*.95),values.size()-1)],"samples":count,"triangles":renderer.triangle_count,"native":renderer.native_geometry!=null}
	measurements.append(result);print("NEON_PERFORMANCE_SAMPLE ",JSON.stringify(result));return result
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,30)
	var path := "res://scenes/examples/inventory_demo.tscn"
	var digest := FileAccess.get_sha256(path)
	EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D");await settle(plugin,20)
	var root := EditorInterface.get_edited_scene_root()
	plugin.toggle.button_pressed=true
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=60
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(3.5,1.6,4)).looking_at(Vector3(3.5,1.6,0))
	await settle(plugin,20)
	check(plugin.views.has(0),"Actual level is rendered in the editor")
	if not plugin.views.has(0):plugin.get_tree().quit(1);return
	var view=plugin.views[0];var renderer: Node=view.renderer
	check(renderer.native_geometry!=null and int(renderer.native_geometry.get_statistics().version)>=17,"Current engine renders the neon level natively")
	if not renderer.native_geometry:plugin.get_tree().quit(1);return
	var native: RefCounted=renderer.native_geometry
	var rebuilds: int=view.rebuilds;var atlas: int=renderer.atlas_texture.get_instance_id()
	plugin.set_process(false)
	var neon: Node3D=root.get_node("Neon");var flicker: bool=neon.flicker
	neon.flicker=false;await sample(plugin,renderer,"native_v17_constant_neon",35)
	neon.flicker=true;await sample(plugin,renderer,"native_v17_flickering_neon",35)
	check(view.rebuilds==rebuilds and renderer.atlas_texture.get_instance_id()==atlas,"Flicker never rebuilds the level or its texture atlas")
	# Explicitly reproduce the old downgrade, with only three measured frames.
	renderer.native_geometry=null
	await sample(plugin,renderer,"old_whole_level_script_fallback",3)
	renderer.native_geometry=LegacyNative.new();renderer._check_native_compatibility()
	check(renderer.native_geometry==null and renderer.native_restart_required=={"loaded":16,"required":17},"An old loaded DLL is recognized before any fallback frames")
	renderer.last_process_us=-1
	var start := Time.get_ticks_usec()
	for frame in 100:renderer.render_editor()
	var guarded_ms := (Time.get_ticks_usec()-start)/1000.0
	check(renderer.last_process_us==-1 and guarded_ms<10,"Incompatible editor preview never runs the slow script renderer")
	plugin.set_process(true);await settle(plugin,12)
	check(plugin.restart_notice.visible and plugin.restart_notice.text.contains("v16") and plugin.restart_notice.text.contains("v17"),"Toolbar clearly identifies the loaded and required native versions")
	check(not view.background.visible and view.source_camera==null,"Incompatible preview restores the editable normal viewport without a black PSX overlay")
	check(driver.forced_camera.cull_mask & ((1<<20)-1)!=0,"Normal editor scene layers and selection remain available")
	neon.flicker=flicker;renderer.native_geometry=native;renderer.rebuild_editor_geometry();await settle(plugin,15)
	check(renderer.native_restart_required.is_empty() and not plugin.restart_notice.visible and view.background.visible,"A compatible native renderer restores the PSX preview and clears its notice")
	check(FileAccess.get_sha256(path)==digest,"Profiling does not save or change the artist's level")
	driver.free()
	var result := {"ok":failures.is_empty(),"errors":failures,"measurements":measurements,"blocked_preview_100_calls_ms":guarded_ms,"native":native.get_statistics()}
	FileAccess.open("res://docs/neon-editor-performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("NEON_PERFORMANCE_EDITOR_OK " if failures.is_empty() else "NEON_PERFORMANCE_EDITOR_FAILED ",JSON.stringify(result))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
