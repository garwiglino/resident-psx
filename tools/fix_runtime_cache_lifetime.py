"""Move resource-owning static caches to explicit application-owned contexts."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
p=root/'scripts/audio/psx_audio_routing.gd';source=p.read_text(encoding='utf8')
source=source.replace('@static_unload\n','')
names=re.findall(r'^static var (\w+)',source,re.M)
source=re.sub(r'^static var [^\n]+\n','',source,flags=re.M)
start=source.index('static func release_cached_effects()');end=source.index('static func setup()',start)
source=source[:start]+'''const STATE_KEY: StringName = &"psx_audio_routing_context"
static func _state() -> Dictionary:
\tif not Engine.has_meta(STATE_KEY):
\t\tEngine.set_meta(STATE_KEY,{"_configured":false,"_warned":false,"_output":null,"_send":null,"_master_sync_frame":-1,"_output_slot":-1,"_send_slot":-1})
\treturn Engine.get_meta(STATE_KEY)

static func release_cached_effects() -> void:
\tif Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)

'''+source[end:]
for function in ['setup','sync_master']:
    match=re.search(r'^static func '+function+r'\([^\n]*\n.*?(?=^static func|\Z)',source,re.M|re.S)
    block=match.group();first,body=block.split('\n',1)
    for name in names: body=re.sub(r'(?<![\w.])'+re.escape(name)+r'\b','state.'+name,body)
    source=source[:match.start()]+first+'\n\tvar state := _state()\n'+body+source[match.end():]
p.write_text(source,encoding='utf8')
p=root/'scripts/dialogue/intercom_filter.gd';source=p.read_text(encoding='utf8').replace('@static_unload\n','')
source=source.replace('static var cache: Dictionary={}\n','''const STATE_KEY: StringName = &"psx_intercom_cache"
static func _cache() -> Dictionary:
\tif not Engine.has_meta(STATE_KEY): Engine.set_meta(STATE_KEY,{})
\treturn Engine.get_meta(STATE_KEY)
static func clear_cache() -> void:
\tif Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)
''')
source=re.sub(r'\bcache\.',r'_cache().',source);source=re.sub(r'\bcache\[',r'_cache()[',source)
p.write_text(source,encoding='utf8')
p=root/'scripts/face_texture_pages.gd';source=p.read_text(encoding='utf8')
source=source.replace('static var _pages: Dictionary={}\n','''const STATE_KEY: StringName = &"psx_face_pages"
static func _cache() -> Dictionary:
\tif not Engine.has_meta(STATE_KEY): Engine.set_meta(STATE_KEY,{})
\treturn Engine.get_meta(STATE_KEY)
static func clear_cache() -> void:
\tif Engine.has_meta(STATE_KEY): Engine.remove_meta(STATE_KEY)
''')
source=source.replace('_pages.','_cache().').replace('_pages[','_cache()[')
p.write_text(source,encoding='utf8')
print('RUNTIME_CACHE_LIFETIME_UPDATED')
