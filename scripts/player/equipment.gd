class_name Equipment
extends Node
## Equipamento vestido (nó "Equipment" no jogador): capacete, armadura, calça, bota,
## luva, 2 anéis e colar. Itens "type": "armor" com "slot", "armor" (pontos de
## proteção), "bonus" (modificadores, como as habilidades) e "set" (conjunto).
## Conjuntos (data/sets): 2, 4 e 6 peças do mesmo conjunto dão bônus extras.
## Proteção: armadura A reduz o dano em A/(A+100). Peças com durabilidade gastam ao
## levar golpes; quebradas (0) não protegem nem dão bônus até serem consertadas.
## Os bônus entram na Progression (mult/add), igual às proficiências.

signal changed

const SLOTS := ["head", "chest", "legs", "feet", "hands", "ring1", "ring2", "neck"]
const SLOT_NAMES := {"head": "Capacete", "chest": "Armadura", "legs": "Calça", "feet": "Botas",
	"hands": "Luvas", "ring1": "Anel", "ring2": "Anel", "neck": "Colar"}

## slot → item ({id, count, dur?, q?, r?}).
var items := {}


func inventory() -> Inventory:
	return get_parent().get_node(^"Inventory") as Inventory


## Tipo de slot do item ("ring" para anéis).
static func item_slot(item_id: String) -> String:
	var data := GameData.get_item(item_id)
	return str(data.get("slot", "")) if data.get("type", "") == "armor" else ""


static func fits(item_id: String, slot: String) -> bool:
	var kind := item_slot(item_id)
	return kind != "" and (kind == slot or (kind == "ring" and slot in ["ring1", "ring2"]))


func get_item(slot: String) -> Dictionary:
	return items.get(slot, {})


## Veste o item do slot `index` do inventário (o que estava vestido volta para lá).
## slot "" = escolhe sozinho (anel: o primeiro livre).
func equip_from_inventory(index: int, slot := "") -> bool:
	var inv := inventory()
	var s := inv.get_slot(index)
	if s.is_empty():
		return false
	if slot == "":
		var kind := item_slot(s.id)
		if kind == "":
			return false
		slot = kind
		if kind == "ring":
			slot = "ring2" if not get_item("ring1").is_empty() and get_item("ring2").is_empty() else "ring1"
	if not fits(s.id, slot):
		return false
	var item := {"id": s.id, "count": 1}
	item.merge(Inventory.extra_of(s))
	inv.take_from_slot(index, 1)
	var old := get_item(slot)
	items[slot] = item
	if not old.is_empty():
		_return_to_inventory(old)
	_changed()
	return true


func unequip(slot: String) -> bool:
	var item := get_item(slot)
	if item.is_empty():
		return false
	if inventory().room_for(item.id) <= 0:
		get_parent().notify("Inventário cheio")
		return false
	items.erase(slot)
	_return_to_inventory(item)
	_changed()
	return true


func _return_to_inventory(item: Dictionary) -> void:
	var left := inventory().add_item(item.id, 1, Inventory.extra_of(item))
	if left > 0:
		WorldItems.drop(item.id, 1, (get_parent() as Node3D).global_position + Vector3.UP * 0.3, null, Inventory.extra_of(item))


## Golpe recebido: cada peça com durabilidade gasta 1.
func wear_on_hit() -> void:
	var broke := false
	for slot: String in items:
		var item: Dictionary = items[slot]
		if Inventory.max_durability(item.id) > 0.0 and not Inventory.is_broken(item):
			if inventory().wear(item, 1.0) <= 0.0:
				broke = true
	if broke:
		get_parent().notify("Uma peça de equipamento quebrou: repare na bancada")
		_changed()


func armor_total() -> float:
	var total := 0.0
	for item: Dictionary in items.values():
		if not Inventory.is_broken(item):
			total += float(GameData.get_item(item.id).get("armor", 0.0)) * Inventory.quality_multiplier(item) * Inventory.refine_multiplier(item)
	return total


## Peças (inteiras) de cada conjunto.
func set_counts() -> Dictionary:
	var out := {}
	for item: Dictionary in items.values():
		var set_id := str(GameData.get_item(item.id).get("set", ""))
		if set_id != "" and not Inventory.is_broken(item):
			out[set_id] = int(out.get(set_id, 0)) + 1
	return out


## Modificadores somados (como os das habilidades) para a Progression.
func mods() -> Dictionary:
	var out := {}
	for item: Dictionary in items.values():
		if Inventory.is_broken(item):
			continue
		var bonus: Dictionary = GameData.get_item(item.id).get("bonus", {})
		for key: String in bonus:
			out[key] = float(out.get(key, 0.0)) + float(bonus[key])
	var counts := set_counts()
	for set_id: String in counts:
		var tiers: Dictionary = GameData.get_entry("sets", set_id).get("bonus", {})
		for need: String in tiers:
			if int(counts[set_id]) >= int(need):
				for key: String in tiers[need]:
					out[key] = float(out.get(key, 0.0)) + float(tiers[need][key])
	var armor := armor_total()
	if armor > 0.0:
		out["damage_taken"] = float(out.get("damage_taken", 0.0)) - armor / (armor + 100.0)
	return out


func _changed() -> void:
	changed.emit()
	var prog := Progression.of(get_parent())
	if prog:
		prog._rebuild()
		prog.changed.emit()


func to_save() -> Dictionary:
	return items


func from_save(data: Dictionary) -> void:
	items.clear()
	for slot: String in data:
		var item: Dictionary = data[slot]
		if slot in SLOTS and not GameData.get_item(str(item.get("id", ""))).is_empty():
			item.count = 1
			items[slot] = item
	_changed()
