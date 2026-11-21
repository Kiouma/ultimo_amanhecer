class_name Equipment
extends Node
## Equipamento vestido (nó "Equipment" no jogador): arma, arma secundária, capacete,
## armadura, calça, bota, luva, 2 anéis e colar. Itens "type": "armor" com "slot",
## "armor" (pontos de proteção), "bonus" (modificadores, como as habilidades) e "set"
## (conjunto). Conjuntos (data/sets): 2, 4 e 6 peças do mesmo conjunto dão bônus extras.
## Proteção: armadura A reduz o dano em A/(A+100). Peças com durabilidade gastam ao
## levar golpes; quebradas (0) não protegem nem dão bônus até serem consertadas.
## Os bônus entram na Progression (mult/add), igual às proficiências.
##
## Arma (slot fixo "weapon"): o que o clique esquerdo usa (armas, cajados, ferramentas).
## Arma secundária ("offhand"), conforme a arma principal:
## - aljava ("offhand": "quiver"): só com arco/besta;
## - escudo e grimório ("shield", "grimoire") e tocha: com armas de uma mão (não com
##   arco nem com armas de duas mãos, "two_handed");
## - empunhadura dupla: uma arma com "dual_wield" (adaga) nas duas mãos: mais velocidade
##   de ataque e o dano da segunda arma com efetividade reduzida (DUAL_WIELD_*).
## Fora dessas combinações, a secundária fica inativa (não dá bônus).

signal changed

const SLOTS := ["weapon", "offhand", "head", "chest", "legs", "feet", "hands", "ring1", "ring2", "neck"]
const SLOT_NAMES := {"weapon": "Arma", "offhand": "Arma secundária", "head": "Capacete", "chest": "Armadura",
	"legs": "Calça", "feet": "Botas", "hands": "Luvas", "ring1": "Anel", "ring2": "Anel", "neck": "Colar"}
## Tipos de item que vão no slot de arma.
const WEAPON_TYPES := ["melee", "bow", "thrown", "focus", "tool"]
## Empunhadura dupla: velocidade de ataque a mais e quanto do dano da segunda arma entra.
const DUAL_WIELD_SPEED := 0.25
const DUAL_WIELD_DAMAGE := 0.5

## slot → item ({id, count, dur?, q?, r?}).
var items := {}


func inventory() -> Inventory:
	return get_parent().get_node(^"Inventory") as Inventory


## Tipo de slot do item ("ring" para anéis, "weapon", "offhand").
static func item_slot(item_id: String) -> String:
	var data := GameData.get_item(item_id)
	var type := str(data.get("type", ""))
	if type == "armor":
		return str(data.get("slot", ""))
	if type == "offhand":
		return "offhand"
	if type in WEAPON_TYPES:
		return "weapon"
	return ""


## Pode ir na mão secundária: itens de mão secundária, armas de empunhadura dupla e a tocha.
static func offhand_capable(item_id: String) -> bool:
	var data := GameData.get_item(item_id)
	return str(data.get("type", "")) == "offhand" or bool(data.get("dual_wield", false)) or bool(data.get("offhand_ok", false))


static func fits(item_id: String, slot: String) -> bool:
	if slot == "offhand":
		return offhand_capable(item_id)
	var kind := item_slot(item_id)
	return kind != "" and (kind == slot or (kind == "ring" and slot in ["ring1", "ring2"]))


func get_item(slot: String) -> Dictionary:
	return items.get(slot, {})


## Arma principal (dados) e se ela ocupa as duas mãos.
func _main_data() -> Dictionary:
	var w := get_item("weapon")
	return GameData.get_item(w.id) if not w.is_empty() else {}


## A secundária vestida vale com a arma principal atual? ("" = vale; senão, o motivo.)
func offhand_block_reason() -> String:
	var off := get_item("offhand")
	if off.is_empty():
		return ""
	var data := GameData.get_item(off.id)
	var main := _main_data()
	var main_type := str(main.get("type", ""))
	var kind := str(data.get("offhand", ""))
	if kind == "quiver":
		return "" if main_type == "bow" else tr("Aljava só funciona com arco ou besta")
	if bool(data.get("dual_wield", false)) and str(data.get("type", "")) != "offhand":
		return "" if bool(main.get("dual_wield", false)) else tr("Empunhadura dupla: as duas mãos precisam de uma arma leve como a adaga")
	if main_type == "bow" or bool(main.get("two_handed", false)):
		return tr("A arma principal usa as duas mãos")
	return ""


func offhand_active() -> bool:
	return not get_item("offhand").is_empty() and offhand_block_reason() == "" \
		and not Inventory.is_broken(get_item("offhand"))


## Empunhadura dupla ativa (duas armas "dual_wield").
func dual_wielding() -> bool:
	return offhand_active() and bool(GameData.get_item(get_item("offhand").id).get("dual_wield", false)) \
		and str(GameData.get_item(get_item("offhand").id).get("type", "")) != "offhand"


## Peças que contam (bônus, armadura, conjuntos): inteiras e, a secundária, ativa.
func _counted() -> Array:
	var out: Array = []
	for slot: String in items:
		var item: Dictionary = items[slot]
		if Inventory.is_broken(item) or slot == "weapon":
			continue
		if slot == "offhand" and not offhand_active():
			continue
		out.append(item)
	return out


## Veste o item do slot `index` do inventário (o que estava vestido volta para lá).
## slot "" = escolhe sozinho (anel: o primeiro livre; adaga com outra adaga na mão:
## vai para a secundária).
func equip_from_inventory(index: int, slot := "") -> bool:
	var inv := inventory()
	var s := inv.get_slot(index)
	if s.is_empty():
		return false
	if slot == "":
		var kind := item_slot(s.id)
		if kind == "" and offhand_capable(s.id):
			kind = "offhand"
		if kind == "":
			return false
		slot = kind
		if kind == "ring":
			slot = "ring2" if not get_item("ring1").is_empty() and get_item("ring2").is_empty() else "ring1"
		elif kind == "weapon" and bool(GameData.get_item(s.id).get("dual_wield", false)) \
				and bool(_main_data().get("dual_wield", false)) and get_item("offhand").is_empty():
			slot = "offhand"
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
	if slot == "offhand" or slot == "weapon":
		var reason := offhand_block_reason()
		if reason != "":
			get_parent().notify(tr("Arma secundária inativa: %s") % reason)
	return true


## Personagem sem arma na mão (novo ou de uma versão antiga, quando a arma ficava na
## hotbar): veste a primeira arma do inventário.
func auto_equip_weapon() -> void:
	if not get_item("weapon").is_empty():
		return
	var inv := inventory()
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not s.is_empty() and str(GameData.get_item(s.id).get("type", "")) in ["melee", "bow", "focus"]:
			equip_from_inventory(i, "weapon")
			return

func unequip(slot: String) -> bool:
	var item := get_item(slot)
	if item.is_empty():
		return false
	if inventory().room_for(item.id) <= 0:
		get_parent().notify(tr("Inventário cheio"))
		return false
	items.erase(slot)
	_return_to_inventory(item)
	_changed()
	return true


func _return_to_inventory(item: Dictionary) -> void:
	var left := inventory().add_item(item.id, 1, Inventory.extra_of(item))
	if left > 0:
		WorldItems.drop(item.id, 1, (get_parent() as Node3D).global_position + Vector3.UP * 0.3, null, Inventory.extra_of(item))


## Golpe recebido: cada peça de proteção com durabilidade gasta 1 (armas gastam ao usar).
func wear_on_hit() -> void:
	var broke := false
	for slot: String in items:
		var item: Dictionary = items[slot]
		if slot == "weapon" or not str(GameData.get_item(item.id).get("type", "")) in ["armor", "offhand"]:
			continue
		if Inventory.max_durability(item.id) > 0.0 and not Inventory.is_broken(item):
			if inventory().wear(item, 1.0) <= 0.0:
				broke = true
	if broke:
		get_parent().notify(tr("Uma peça de equipamento quebrou: repare na bancada"))
		_changed()


func armor_total() -> float:
	var total := 0.0
	for item: Dictionary in _counted():
		total += float(GameData.get_item(item.id).get("armor", 0.0)) * Inventory.quality_multiplier(item) * Inventory.refine_multiplier(item)
	return total


## Peças (inteiras) de cada conjunto.
func set_counts() -> Dictionary:
	var out := {}
	for item: Dictionary in _counted():
		var set_id := str(GameData.get_item(item.id).get("set", ""))
		if set_id != "":
			out[set_id] = int(out.get(set_id, 0)) + 1
	return out


## Modificadores somados (como os das habilidades) para a Progression.
func mods() -> Dictionary:
	var out := {}
	for item: Dictionary in _counted():
		var bonus: Dictionary = GameData.get_item(item.id).get("bonus", {})
		for key: String in bonus:
			out[key] = float(out.get(key, 0.0)) + float(bonus[key])
	if dual_wielding():
		out["attack_speed"] = float(out.get("attack_speed", 0.0)) + DUAL_WIELD_SPEED
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
