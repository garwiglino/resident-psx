extends RefCounted
## Slot transactions are independent of UI, scene, audio and world actions.
signal changed
const Item=preload("res://scripts/inventory/item_definition.gd")
var sections: Dictionary={&"items":[],&"equipment":[]}
var revision := 0
var _next_uid := 1

func _init(item_capacity := 16,equipment_capacity := 16) -> void:
	for section in sections:
		var capacity: int=item_capacity if section==&"items" else equipment_capacity
		for index in capacity: sections[section].append({})
func slot(section: StringName,index: int) -> Dictionary:
	var slots: Array=sections.get(section,[])
	return slots[index] if index>=0 and index<slots.size() else {}
func locate(uid: String) -> Dictionary:
	if uid.is_empty(): return {}
	for section in sections:
		for index in sections[section].size():
			if sections[section][index].get("uid","")==uid: return {"section":section,"index":index,"entry":sections[section][index]}
	return {}
func count(id: StringName) -> int:
	var total := 0
	for section in sections:
		for entry: Dictionary in sections[section]:
			if not entry.is_empty() and entry.item.id==id: total+=int(entry.quantity)
	return total
func capacity_for(item: Resource,state: Dictionary={}) -> int:
	if not item or item.id.is_empty(): return 0
	var available := 0; var maximum: int=item.maximum_stack()
	for entry: Dictionary in sections[item.section()]:
		if entry.is_empty(): available+=maximum
		elif maximum>1 and entry.item.id==item.id and entry.state==state: available+=maximum-int(entry.quantity)
	return available
func add(item: Resource,quantity := 1,state: Dictionary={}) -> bool:
	if quantity<=0 or capacity_for(item,state)<quantity: return false
	var remaining := quantity; var maximum: int=item.maximum_stack(); var slots: Array=sections[item.section()]
	if maximum>1:
		for entry: Dictionary in slots:
			if entry.is_empty() or entry.item.id!=item.id or entry.state!=state: continue
			var amount := mini(remaining,maximum-int(entry.quantity)); entry.quantity+=amount; remaining-=amount
			if remaining==0: break
	for index in slots.size():
		if remaining==0: break
		if not slots[index].is_empty(): continue
		var amount := mini(remaining,maximum)
		slots[index]={"uid":"slot_%d" % _next_uid,"item":item,"quantity":amount,"state":state.duplicate(true)}
		_next_uid+=1; remaining-=amount
	_notify(); return true
func take(uid: String,quantity := 1) -> Dictionary:
	var location := locate(uid)
	if location.is_empty() or quantity<=0 or int(location.entry.quantity)<quantity: return {}
	var result: Dictionary=location.entry.duplicate(true); result.quantity=quantity
	location.entry.quantity-=quantity
	if location.entry.quantity==0: sections[location.section][location.index]={}
	_notify(); return result
func remove_id(id: StringName,quantity := 1) -> bool:
	if quantity<0 or count(id)<quantity: return false
	var remaining := quantity
	for section in sections:
		for index in sections[section].size():
			var entry: Dictionary=sections[section][index]
			if entry.is_empty() or entry.item.id!=id: continue
			var amount := mini(remaining,int(entry.quantity)); entry.quantity-=amount; remaining-=amount
			if entry.quantity==0: sections[section][index]={}
			if remaining==0: _notify(); return true
	return quantity==0
func move(uid: String,target_section: StringName,target_index: int) -> bool:
	var source := locate(uid)
	if source.is_empty() or source.entry.item.section()!=target_section: return false
	var slots: Array=sections.get(target_section,[])
	if target_index<0 or target_index>=slots.size(): return false
	if source.section==target_section and source.index==target_index: return true
	var target: Dictionary=slots[target_index]
	var maximum: int=source.entry.item.maximum_stack()
	if not target.is_empty() and maximum>1 and target.item.id==source.entry.item.id and target.state==source.entry.state:
		var amount := mini(int(source.entry.quantity),maximum-int(target.quantity))
		if amount>0:
			target.quantity+=amount; source.entry.quantity-=amount
			if source.entry.quantity==0: sections[source.section][source.index]={}
		else: slots[target_index]=source.entry; sections[source.section][source.index]=target
	else:
		if not target.is_empty() and target.item.section()!=source.section: return false
		slots[target_index]=source.entry; sections[source.section][source.index]=target
	_notify(); return true
func _notify() -> void:
	revision+=1; changed.emit()
func snapshot() -> Dictionary:
	var data := {"version":1,"next_uid":_next_uid,"sections":{}}
	for section in sections:
		var rows: Array=[]
		for entry: Dictionary in sections[section]:
			rows.append({} if entry.is_empty() else {"uid":entry.uid,"id":String(entry.item.id),"path":entry.item.resource_path,"quantity":entry.quantity,"state":entry.state.duplicate(true)})
		data.sections[String(section)]=rows
	return data
func restore(data: Dictionary,resolver: Callable) -> bool:
	if data.get("version",0)!=1 or not data.get("sections") is Dictionary: return false
	var replacement := {}; var used := {}
	for section in sections:
		var rows: Variant=data.sections.get(String(section),[])
		if not rows is Array or rows.size()!=sections[section].size(): return false
		var result: Array=[]
		for row in rows:
			if not row is Dictionary: return false
			if row.is_empty(): result.append({}); continue
			var item: Resource=resolver.call(StringName(row.get("id","")),String(row.get("path","")))
			var quantity: int=int(row.get("quantity",0)); var uid := String(row.get("uid",""))
			if not item or item.section()!=section or quantity<1 or quantity>item.maximum_stack() or uid.is_empty() or used.has(uid) or not row.get("state",{}) is Dictionary: return false
			used[uid]=true; result.append({"uid":uid,"item":item,"quantity":quantity,"state":row.get("state",{}).duplicate(true)})
		replacement[section]=result
	var next := maxi(int(data.get("next_uid",1)),1)
	for uid: String in used:
		if uid.begins_with("slot_") and uid.trim_prefix("slot_").is_valid_int(): next=maxi(next,int(uid.trim_prefix("slot_"))+1)
	sections=replacement; _next_uid=next; _notify(); return true
