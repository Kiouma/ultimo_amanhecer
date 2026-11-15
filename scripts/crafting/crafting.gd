class_name Crafting
extends RefCounted
## Fabricação a partir das receitas de data/recipes/*.json (GDD 8).
## Por enquanto só a estação "hands" (mãos, sem bancada), usada pela tela de
## inventário. Estações, qualidade e tempo de fabricação entram na Fase 3.
## Roda na máquina do dono do inventário (o inventário é local, ver Inventory).


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


## Gasta os ingredientes e entrega o resultado. O que não couber cai no chão.
## Retorna true se fabricou.
static func craft(inventory: Inventory, recipe: Dictionary, times := 1) -> bool:
	if times <= 0 or not can_craft(inventory, recipe, times):
		return false
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		inventory.remove_item(id, int(ingredients[id]) * times)
	var result := str(recipe.get("result", ""))
	var left := inventory.add_item(result, int(recipe.get("amount", 1)) * times)
	if left > 0:
		var player := inventory.get_parent() as Node3D
		WorldItems.drop(result, left, player.global_position + Vector3.UP * 0.3, player)
	return true


## "Pena 1 · Graveto 1"
static func describe_ingredients(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for id: String in ingredients:
		parts.append("%s %d" % [GameData.get_item(id).get("name", id), int(ingredients[id])])
	return " · ".join(parts)
