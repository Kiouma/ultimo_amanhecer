class_name Crafting
extends RefCounted
## Fabricação a partir das receitas de data/recipes/*.json (GDD 8).
## Estações: "hands" (mãos), "campfire", "workbench"... A fila com tempo fica em
## CraftQueue. Qualidade entra depois. Roda na máquina do dono do inventário.


## Receitas de uma estação, na ordem dos arquivos.
static func recipes_for(station: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for recipe: Dictionary in GameData.get_all("recipes").values():
		if str(recipe.get("station", "")) == station:
			out.append(recipe)
	return out


static func can_craft(inventory: Inventory, recipe: Dictionary, times := 1) -> bool:
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		if inventory.count_of(id) < int(ingredients[id]) * times:
			return false
	return true


## Quantas vezes dá para fabricar com o que tem.
static func max_times(inventory: Inventory, recipe: Dictionary) -> int:
	var best := 999999
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		best = mini(best, inventory.count_of(id) / maxi(int(ingredients[id]), 1))
	return best if not ingredients.is_empty() else 0


## Fabricação instantânea (usada em testes). No jogo, use CraftQueue.enqueue (com tempo).
static func craft(inventory: Inventory, recipe: Dictionary, times := 1) -> bool:
	if times <= 0 or not can_craft(inventory, recipe, times):
		return false
	take_ingredients(inventory, recipe, times)
	give_result(inventory, recipe, times)
	return true


static func take_ingredients(inventory: Inventory, recipe: Dictionary, times: int) -> void:
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		inventory.remove_item(id, int(ingredients[id]) * times)


## Devolve ingredientes (cancelar na fila). O que não couber cai no chão.
static func give_ingredients(inventory: Inventory, recipe: Dictionary, times: int) -> void:
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		_give(inventory, id, int(ingredients[id]) * times)


## Entrega o resultado. Armas/ferramentas (com "durability") saem uma a uma com
## qualidade sorteada; o resto empilha normal.
static func give_result(inventory: Inventory, recipe: Dictionary, times: int) -> void:
	var id := str(recipe.get("result", ""))
	var count := int(recipe.get("amount", 1)) * times
	if Inventory.max_durability(id) <= 0.0 or not recipe.has("ingredients"):
		_give(inventory, id, count)
		return
	for i in count:
		var quality := roll_quality(crafting_skill(inventory))
		_give(inventory, id, 1, {"q": quality})
		if quality >= 4:
			var player := inventory.get_parent()
			if player.has_method(&"notify"):
				player.notify(TranslationServer.translate("%s de qualidade %d!") % [GameData.get_item(id).get("name", id), quality])


## Chances base de Q1..Q5 (em %), sem proficiência.
const QUALITY_WEIGHTS := [50.0, 30.0, 14.0, 5.0, 1.0]


## Sorteia a qualidade. Cada nível de skill acima de 1 tira 1 ponto de Q1 e espalha
## para cima (a proficiência de Crafting chega na Fase 6).
static func roll_quality(skill_level := 1) -> int:
	var weights: Array = QUALITY_WEIGHTS.duplicate()
	var shift := clampf(float(skill_level - 1), 0.0, 45.0)
	weights[0] -= shift
	weights[1] += shift * 0.4
	weights[2] += shift * 0.3
	weights[3] += shift * 0.2
	weights[4] += shift * 0.1
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for q in weights.size():
		roll -= weights[q]
		if roll <= 0.0:
			return q + 1
	return 1


## Nível de Crafting de quem fabrica (1 enquanto a progressão não existir).
static func crafting_skill(inventory: Inventory) -> int:
	var progression := inventory.get_parent().get_node_or_null(^"Progression")
	if progression and progression.has_method(&"get_level"):
		return int(progression.get_level("crafting"))
	return 1


static func _give(inventory: Inventory, id: String, count: int, extra: Dictionary = {}) -> void:
	if count <= 0:
		return
	var left := inventory.add_item(id, count, extra)
	if left > 0:
		var player := inventory.get_parent() as Node3D
		WorldItems.drop(id, left, player.global_position + Vector3.UP * 0.3, null, extra)


## Nome da estação para mostrar ("hands" → "mãos").
static func station_name(station: String) -> String:
	match station:
		"hands": return TranslationServer.translate("mãos")
		"campfire": return TranslationServer.translate("fogueira")
		"workbench": return TranslationServer.translate("bancada")
		"forge": return TranslationServer.translate("forja")
		"weapon_bench": return TranslationServer.translate("bancada de armas")
		"arcane_table": return TranslationServer.translate("mesa arcana")
		"electric_bench": return TranslationServer.translate("bancada elétrica")
		_: return station


## "Pena 1 · Madeira 1"
static func describe_ingredients(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		parts.append("%s %d" % [GameData.get_item(id).get("name", id), int(ingredients[id])])
	return " · ".join(parts)
