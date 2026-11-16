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


static func give_result(inventory: Inventory, recipe: Dictionary, times: int) -> void:
	_give(inventory, str(recipe.get("result", "")), int(recipe.get("amount", 1)) * times)


static func _give(inventory: Inventory, id: String, count: int) -> void:
	if count <= 0:
		return
	var left := inventory.add_item(id, count)
	if left > 0:
		var player := inventory.get_parent() as Node3D
		WorldItems.drop(id, left, player.global_position + Vector3.UP * 0.3, null)


## Nome da estação para mostrar ("hands" → "mãos").
static func station_name(station: String) -> String:
	match station:
		"hands": return "mãos"
		"campfire": return "fogueira"
		"workbench": return "bancada"
		"forge": return "forja"
		"weapon_bench": return "bancada de armas"
		"arcane_table": return "mesa arcana"
		"electric_bench": return "bancada elétrica"
		_: return station


## "Pena 1 · Graveto 1"
static func describe_ingredients(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		parts.append("%s %d" % [GameData.get_item(id).get("name", id), int(ingredients[id])])
	return " · ".join(parts)
