class_name Refine
extends RefCounted
## Refino de armas e ferramentas (+1 a +12), feito na bancada.
## Gasta Pedra de refino, que só cai de inimigos ("drops" em zombies.json).
## Cada nível: +5% de dano (arco, melee, armas de fogo) e de eficiência de coleta;
## na tocha, mais alcance de luz. Soma (multiplica) com a qualidade.
## Sempre dá certo (sem falha). Roda na máquina do dono do inventário.

const STONE := "refine_stone"


## Só itens com durabilidade (armas e ferramentas).
static func can_be_refined(slot: Dictionary) -> bool:
	return not slot.is_empty() and Inventory.max_durability(slot.id) > 0.0


static func is_maxed(slot: Dictionary) -> bool:
	return Inventory.refine_of(slot) >= Inventory.MAX_REFINE


## Pedras para ir do nível atual ao próximo: +1..+3 = 1, +4..+6 = 2, +7..+9 = 3, +10..+12 = 4.
static func cost(slot: Dictionary) -> int:
	var next := Inventory.refine_of(slot) + 1
	return ceili(next / 3.0)


static func can_refine(inventory: Inventory, slot: Dictionary) -> bool:
	return can_be_refined(slot) and not is_maxed(slot) and inventory.count_of(STONE) >= cost(slot)


static func refine(inventory: Inventory, slot: Dictionary) -> bool:
	if not can_refine(inventory, slot):
		return false
	inventory.remove_item(STONE, cost(slot))
	slot["r"] = Inventory.refine_of(slot) + 1
	inventory.changed.emit()
	return true
