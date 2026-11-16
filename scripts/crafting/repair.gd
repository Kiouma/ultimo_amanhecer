class_name Repair
extends RefCounted
## Reparar e desmontar itens (GDD 8.3), feito na bancada.
## - Reparar: volta a durabilidade ao máximo. Custo = metade dos ingredientes da
##   receita do item, proporcional ao desgaste (mínimo 1). Itens sem receita usam o
##   campo "repair" do JSON (custo para 100% de desgaste). "repairable": false impede.
## - Desmontar: destrói o item e devolve metade dos ingredientes da receita,
##   proporcional à durabilidade que sobra (ou o campo "salvage" do JSON).
## Roda na máquina do dono do inventário.

const SALVAGE_TYPES := ["bow", "melee", "firearm", "tool", "station", "trap"]


## Receita que fabrica este item ({} se não houver).
static func recipe_for(id: String) -> Dictionary:
	for recipe: Dictionary in GameData.get_all("recipes").values():
		if str(recipe.get("result", "")) == id:
			return recipe
	return {}


## Fração desgastada (0 = novo, 1 = quebrado).
static func wear_fraction(slot: Dictionary) -> float:
	var max_dur := Inventory.max_durability_of(slot)
	return 0.0 if max_dur <= 0.0 else clampf(1.0 - Inventory.durability_of(slot) / max_dur, 0.0, 1.0)


static func is_repairable(slot: Dictionary) -> bool:
	if slot.is_empty() or Inventory.max_durability(slot.id) <= 0.0:
		return false
	var data := GameData.get_item(slot.id)
	if not data.get("repairable", true):
		return false
	return data.has("repair") or not recipe_for(slot.id).is_empty()


## Materiais para reparar ({} se não precisa ou não dá).
static func repair_cost(slot: Dictionary) -> Dictionary:
	var missing := wear_fraction(slot)
	if missing <= 0.0 or not is_repairable(slot):
		return {}
	var data := GameData.get_item(slot.id)
	var base: Dictionary = data.get("repair", {})
	var factor := missing
	if base.is_empty():
		base = recipe_for(slot.id).get("ingredients", {})
		factor = missing * 0.5
	var cost := {}
	for id: String in base:
		cost[id] = maxi(ceili(float(base[id]) * factor), 1)
	return cost


static func can_repair(inventory: Inventory, slot: Dictionary) -> bool:
	var cost := repair_cost(slot)
	if cost.is_empty():
		return false
	for id: String in cost:
		if inventory.count_of(id) < int(cost[id]):
			return false
	return true


static func repair(inventory: Inventory, slot: Dictionary) -> bool:
	if not can_repair(inventory, slot):
		return false
	var cost := repair_cost(slot)
	for id: String in cost:
		inventory.remove_item(id, int(cost[id]))
	slot["dur"] = Inventory.max_durability_of(slot)
	inventory.changed.emit()
	return true


static func is_salvageable(slot: Dictionary) -> bool:
	if slot.is_empty():
		return false
	var data := GameData.get_item(slot.id)
	return str(data.get("type", "")) in SALVAGE_TYPES and (data.has("salvage") or not recipe_for(slot.id).is_empty())


## O que desmontar este slot devolve.
static func salvage_result(slot: Dictionary) -> Dictionary:
	if not is_salvageable(slot):
		return {}
	var data := GameData.get_item(slot.id)
	var condition := 1.0 - wear_fraction(slot)
	var base: Dictionary = data.get("salvage", {})
	var factor := condition
	if base.is_empty():
		base = recipe_for(slot.id).get("ingredients", {})
		factor = condition * 0.5
	var out := {}
	for id: String in base:
		var amount := roundi(float(base[id]) * factor * int(slot.count))
		if amount > 0:
			out[id] = amount
	return out


## Não desmonta se não devolveria nada (item muito gasto): evita perder o item à toa.
static func salvage(inventory: Inventory, index: int) -> bool:
	var slot := inventory.get_slot(index)
	var result := salvage_result(slot)
	if result.is_empty():
		return false
	inventory.take_from_slot(index, int(slot.count))
	for id: String in result:
		Crafting.give_result(inventory, {"result": id, "amount": result[id]}, 1)
	return true


## "Madeira 1 · Sucata 2"
static func describe(materials: Dictionary) -> String:
	if materials.is_empty():
		return "nada"
	var parts: PackedStringArray = []
	for id: String in materials:
		parts.append("%s %d" % [GameData.get_item(id).get("name", id), int(materials[id])])
	return " · ".join(parts)
