extends SceneTree
const Model=preload("res://scripts/inventory/inventory_model.gd")
const Item=preload("res://scripts/inventory/item_definition.gd")
var errors: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func definition(id: String,kind: int,stack := 1) -> Resource:
	var item := Item.new(); item.id=StringName(id); item.kind=kind; item.stack_limit=stack; return item
func run() -> void:
	var model := Model.new(4,4); var herb := definition("herb",Item.Kind.CONSUMABLE,5)
	check(model.add(herb,7),"Pickup fills stacks then opens another slot")
	check(model.slot(&"items",0).quantity==5 and model.slot(&"items",1).quantity==2,"Stacks respect their maximum")
	var key := definition("key_a",Item.Kind.KEY,99); var badge := definition("badge",Item.Kind.ACCESS_CARD,99)
	check(model.add(key,2),"Two identical physical keys occupy two distinct slots")
	check(model.slot(&"items",2).quantity==1 and model.slot(&"items",3).quantity==1,"Keys never stack despite authoring limit")
	var before := model.snapshot()
	check(not model.add(badge) and model.snapshot()==before,"Full inventory rejects an atomic pickup without losing anything")
	var uid: String=model.slot(&"items",0).uid
	check(not model.move(uid,&"equipment",0),"General items cannot enter the weapon/ammo section")
	check(model.move(uid,&"items",2) and model.slot(&"items",0).item==key,"Drag swaps occupied slots")
	check(not key.can_discard() and not badge.can_discard(),"Keys and access cards are protected")
	check(model.take(uid,3).quantity==3 and model.count(&"herb")==4,"Quantity extraction removes exactly the selected amount")
	check(model.move(String(model.slot(&"items",1).uid),&"items",2) and model.slot(&"items",2).quantity==4,"Compatible stacks merge by drag/drop")
	var registry := {herb.id:herb,key.id:key,badge.id:badge}
	var data := model.snapshot(); var restored := Model.new(4,4)
	check(restored.restore(data,func(id: StringName,_path: String): return registry.get(id)),"Slot order, IDs, quantities and metadata survive serialization")
	check(restored.snapshot()==data,"Roundtrip is lossless")
	var broken: Dictionary=data.duplicate(true); broken.sections.items[2].quantity=999
	check(not restored.restore(broken,func(id: StringName,_path: String): return registry.get(id)) and restored.snapshot()==data,"Invalid snapshots cannot partly overwrite the inventory")
	FileAccess.open("res://docs/inventory-model-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":errors.is_empty(),"errors":errors},"\t"))
	print("INVENTORY_MODEL_OK" if errors.is_empty() else "INVENTORY_MODEL_FAILED "+str(errors)); quit(0 if errors.is_empty() else 1)
