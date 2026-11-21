class_name Affixes
extends RefCounted
## Afixos dos equipamentos (etapa 10, GDD 8.4). Dados em data/affixes.
## - Todo item equipável fabricado (arma, arma secundária, armadura, joia, ferramenta) tem
##   6 slots de afixo: 0 a 2 são prefixos (dano, vida, mana...), 3 a 5 sufixos
##   (velocidades, regenerações, resistências, atributos...). Guardado no item em "aff":
##   [null = fechado | [id do afixo, valor]] × 6.
## - Ao fabricar, abrem de 1 a 6 slots (sorteio; qualidade e Crafting puxam para cima).
## - A Upgrading Machine abre slots fechados e re-sorteia os afixos.
## - Os valores usam as mesmas chaves de modificador da árvore passiva; o Equipment soma.

const SLOTS := 6
## Pesos de 1 a 6 slots abertos ao fabricar.
const OPEN_WEIGHTS := [40.0, 28.0, 16.0, 9.0, 5.0, 2.0]


static func data(affix_id: String) -> Dictionary:
	return GameData.get_entry("affixes", affix_id)


## Categorias do item para filtrar afixos: "weapon", "offhand", "armor" (+ o slot:
## "head", "hands", "feet"...), "jewelry" (anéis e colar), "tool" (+ "rod").
static func categories(item_id: String) -> Array:
	var d := GameData.get_item(item_id)
	var slot := Equipment.item_slot(item_id)
	var out: Array = []
	match slot:
		"weapon": out.append("weapon")
		"offhand": out.append("offhand")
		"ring", "neck": out.append("jewelry")
		"axe", "pickaxe", "rod":
			out.append("tool")
			out.append(slot)
		"":
			if Equipment.offhand_capable(item_id):
				out.append("offhand")
		_:
			out.append("armor")
			out.append(slot)
	if str(d.get("tool", "")) == "" and slot == "weapon" and str(d.get("type", "")) == "tool":
		out.clear()  # martelo e tocha: sem afixos
	return out


## O item pode ter afixos (equipável fabricado, não consumível).
static func can_have(item_id: String) -> bool:
	return not categories(item_id).is_empty() and GameData.max_stack(item_id) == 1


static func open_count(item: Dictionary) -> int:
	var n := 0
	for e: Variant in item.get("aff", []):
		if e != null:
			n += 1
	return n


## Sorteia os afixos de um item recém-fabricado.
static func roll_new(item_id: String, quality := 1, skill := 1) -> Array:
	var weights: Array = OPEN_WEIGHTS.duplicate()
	var shift := clampf((quality - 1) * 4.0 + (skill - 1) * 0.5, 0.0, 30.0)
	weights[0] = maxf(weights[0] - shift, 4.0)
	for i in range(1, weights.size()):
		weights[i] += shift * 0.2
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := randf() * total
	var open := 1
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			open = i + 1
			break
	var aff: Array = [null, null, null, null, null, null]
	var order := [0, 1, 2, 3, 4, 5]
	order.shuffle()
	for i in open:
		var slot: int = order[i]
		aff[slot] = roll_one(item_id, "prefix" if slot < 3 else "suffix", aff)
	return aff


## Sorteia um afixo do grupo que sirva no item e não repita a chave de outro slot.
static func roll_one(item_id: String, group: String, current: Array) -> Variant:
	var cats := categories(item_id)
	var used := {}
	for e: Variant in current:
		if e != null:
			used[str(data(str(e[0])).get("key", ""))] = true
	var pool: Array = []
	for id: String in GameData.get_all("affixes"):
		var d := data(id)
		if str(d.get("group", "")) != group or used.has(str(d.get("key", ""))):
			continue
		for c: String in d.get("for", []):
			if c in cats:
				pool.append(id)
				break
	if pool.is_empty():
		return null
	var pick: String = pool[randi() % pool.size()]
	return [pick, roll_value(pick)]


static func roll_value(affix_id: String) -> float:
	var d := data(affix_id)
	var lo := float(d.get("min", 0.0))
	var hi := float(d.get("max", lo))
	var step := float(d.get("step", 0.01))
	return snappedf(randf_range(lo, hi), step)


## Modificadores dos afixos abertos do item (somados pelo Equipment).
static func mods_of(item: Dictionary) -> Dictionary:
	var out := {}
	for e: Variant in item.get("aff", []):
		if e == null:
			continue
		var key := str(data(str(e[0])).get("key", ""))
		if key != "":
			out[key] = float(out.get(key, 0.0)) + float(e[1])
	return out


## Texto de um afixo ("+12% de dano mágico").
static func describe(entry: Variant) -> String:
	if entry == null:
		return ""
	var d := data(str(entry[0]))
	var v := float(entry[1])
	var text := ("%d%%" % roundi(v * 100.0)) if d.get("pct", false) else (str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)
	return TranslationServer.translate(str(d.get("name", "%s"))) % text


## Linhas para a dica do item: prefixos, sufixos e quantos slots estão fechados.
static func lines(item: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var aff: Array = item.get("aff", [])
	if aff.is_empty():
		return out
	var locked := 0
	for i in aff.size():
		if aff[i] == null:
			locked += 1
		else:
			out.append(("◆ " if i < 3 else "◇ ") + describe(aff[i]))
	if locked > 0:
		out.append(TranslationServer.translate("%d slot(s) de afixo fechado(s) (Upgrading Machine)") % locked)
	return out


# --- Upgrading Machine: custos -----------------------------------------------------------

## Abrir o próximo slot: ouro e Pó arcano sobem com quantos já estão abertos.
static func unlock_cost(item: Dictionary) -> Dictionary:
	var n := open_count(item)
	return {"gold": 150 * (n + 1), "arcane_dust": n + 1}


## Re-sortear todos os afixos abertos.
static func reroll_cost(_item: Dictionary) -> Dictionary:
	return {"gold": 250, "arcane_crystal": 1}


## Subir a qualidade (Q → Q+1): pedra de refino da raridade da qualidade atual + ouro.
static func quality_cost(item: Dictionary) -> Dictionary:
	var q := int(item.get("q", 1))
	return {"gold": 200 * q, str(Refine.STONES[clampi(q - 1, 0, Refine.STONES.size() - 1)]): 3}


static func can_pay(inventory: Inventory, cost: Dictionary) -> bool:
	if inventory.gold < int(cost.get("gold", 0)):
		return false
	for id: String in cost:
		if id != "gold" and inventory.count_of(id) < int(cost[id]):
			return false
	return true


static func pay(inventory: Inventory, cost: Dictionary) -> void:
	inventory.add_gold(-int(cost.get("gold", 0)))
	for id: String in cost:
		if id != "gold":
			inventory.remove_item(id, int(cost[id]))


static func describe_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in cost:
		if id == "gold":
			parts.append(TranslationServer.translate("%d de ouro") % int(cost.gold))
		else:
			parts.append("%d %s" % [int(cost[id]), str(GameData.get_item(id).get("name", id))])
	return ", ".join(parts)


## Abre um slot fechado (sorteado) e sorteia o afixo dele. Retorna o texto do afixo.
static func unlock_slot(item: Dictionary) -> String:
	if not item.has("aff"):
		item["aff"] = [null, null, null, null, null, null]
	var aff: Array = item.aff
	var locked: Array = []
	for i in aff.size():
		if aff[i] == null:
			locked.append(i)
	if locked.is_empty():
		return ""
	locked.shuffle()
	for slot: int in locked:
		var entry: Variant = roll_one(str(item.id), "prefix" if slot < 3 else "suffix", aff)
		if entry != null:
			aff[slot] = entry
			return describe(entry)
	return ""


## Re-sorteia todos os afixos abertos (mesmos slots).
static func reroll(item: Dictionary) -> void:
	var aff: Array = item.get("aff", [])
	var fresh: Array = []
	for i in aff.size():
		fresh.append(null)
	for i in aff.size():
		if aff[i] != null:
			fresh[i] = roll_one(str(item.id), "prefix" if i < 3 else "suffix", fresh)
	item["aff"] = fresh
