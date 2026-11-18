extends SceneTree
const Radio=preload("res://scripts/dialogue/intercom_filter.gd")
var report: Array[Dictionary]=[]
var backup_directory := ""
func _initialize() -> void:call_deferred("run")
func scan(directory: String,files: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["tscn","tres"]:
			var path := directory+"/"+file
			if FileAccess.get_file_as_string(path).contains('[sub_resource type="AudioStreamPSX"'):files.append(path)
	for folder in DirAccess.get_directories_at(directory):scan(directory+"/"+folder,files)
func regex(pattern: String) -> RegEx:
	var expression := RegEx.new();assert(expression.compile(pattern)==OK);return expression
func externalize(path: String) -> bool:
	var original := FileAccess.get_file_as_string(path)
	var root_resource: Resource=load(path)
	assert(root_resource,"Cannot load "+path)
	var headers := regex('(?m)^\\[(?:sub_resource|resource|node|connection|editable)\\b[^\\n]*\\]\\r?\\n').search_all(original)
	var externals: Dictionary={}
	for match in regex('(?m)^\\[ext_resource [^\\n]*path="([^"]+)"[^\\n]*id="([^"]+)"[^\\n]*\\]').search_all(original):externals[match.get_string(2)]=match.get_string(1)
	var blocks: Array[Dictionary]=[];var sources: Dictionary={}
	for index in headers.size():
		var first: int=headers[index].get_start();var last: int=headers[index+1].get_start() if index+1<headers.size() else original.length()
		var text := original.substr(first,last-first)
		var native := regex('^\\[sub_resource type="AudioStreamPSX" id="([^"]+)"\\]').search(text)
		if native:blocks.append({"id":native.get_string(1),"text":text})
		var prepared := regex('(?m)^intercom_audio = SubResource\\("([^"]+)"\\)').search(text)
		var source := regex('(?m)^audio = ExtResource\\("([^"]+)"\\)').search(text)
		if prepared and source:sources[prepared.get_string(1)]=externals[source.get_string(1)]
	var changed := original;var declarations := "";var samples: Array[Dictionary]=[]
	# Resolve all old subresources before assigning their new external paths.
	for block in blocks:
		if not sources.has(block.id):continue
		block["stream"]=ResourceLoader.load(path+"::"+block.id,"AudioStream")
		assert(block.stream and block.stream.is_class("AudioStreamPSX"),"Cannot read sample "+block.id)
	for block in blocks:
		if not block.has("stream"):continue
		var stream: AudioStream=block.stream;var source: AudioStream=load(sources[block.id])
		var left: PackedByteArray=stream.get("adpcm_left");var right: PackedByteArray=stream.get("adpcm_right")
		var frame_count: int=stream.get("frame_count");var rate: int=stream.get("mix_rate")
		var saved := Radio.store_prepared(source,stream)
		assert(saved and saved.resource_path.ends_with(".res") and saved.resource_path.begins_with(Radio.CACHE_DIRECTORY))
		assert(saved.get("adpcm_left")==left and saved.get("adpcm_right")==right,"SPU sample bytes must not change")
		assert(saved.get("frame_count")==frame_count and saved.get("mix_rate")==rate,"Voice timing must not change")
		var id := "radio_external_"+String(block.id)
		assert(not original.contains('id="'+id+'"'),"External ID already exists")
		declarations+='[ext_resource type="AudioStreamPSX" path="'+saved.resource_path+'" id="'+id+'"]\n'
		changed=changed.replace(block.text,"").replace('SubResource("'+block.id+'")','ExtResource("'+id+'")')
		samples.append({"old_id":block.id,"source":sources[block.id],"binary_resource":saved.resource_path,"frames":frame_count,"rate":rate,"adpcm_bytes":left.size()+right.size()})
	if samples.is_empty():return true
	var insert := changed.find("\n[sub_resource")
	if insert<0:insert=changed.find("\n[resource]")
	if insert<0:insert=changed.find("\n[node")
	assert(insert>=0,"No scene/resource section to insert before")
	changed=changed.insert(insert+1,declarations+"\n")
	assert(FileAccess.get_file_as_string(path)==original,"Source changed while preparing samples; run again: "+path)
	var backup := backup_directory+"/"+path.trim_prefix("res://")
	assert(DirAccess.make_dir_recursive_absolute(backup.get_base_dir())==OK)
	assert(DirAccess.copy_absolute(path,backup)==OK)
	var output := FileAccess.open(path,FileAccess.WRITE);assert(output);output.store_string(changed);output.close()
	report.append({"path":path,"bytes_before":original.to_utf8_buffer().size(),"bytes_after":changed.to_utf8_buffer().size(),"samples":samples})
	print("EXTERNALIZED_AUDIO ",path," ",original.to_utf8_buffer().size()," -> ",changed.to_utf8_buffer().size()," bytes; ",samples.size()," SPU samples unchanged")
	return true
func run() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":","").replace("-","")
	backup_directory="res://exports/backups/intercom_external_"+stamp
	var files: Array[String]=[]
	for folder in ["res://scenes","res://assets/dialogue","res://assets/audio/dialogs"]:scan(folder,files)
	for path in files:
		if externalize(path)!=true:print("INTERCOM_EXTERNALIZATION_FAILED ",path);quit(1);return
	FileAccess.open("res://docs/intercom-externalization.json",FileAccess.WRITE).store_string(JSON.stringify({"backup":backup_directory,"files":report},"\t"))
	print("INTERCOM_EXTERNALIZATION_OK: text scenes retained; native ADPCM bytes and voice timings preserved")
	quit()
