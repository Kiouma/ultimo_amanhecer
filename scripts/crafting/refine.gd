class_name Refine
extends RefCounted
## Refino de armas, ferramentas e equipamentos (+1 a +21), feito na bancada.
## Cada nível: +5% de dano (arco, melee, armas de fogo) e de eficiência de coleta;
## na tocha, mais alcance de luz; no equipamento, mais proteção. Multiplica com a qualidade.
##
## Custo: a cada faixa de 5 níveis a pedra sobe de raridade e a quantidade volta a 1:
##   +1..+5 comum (1 a 5 pedras), +6..+10 incomum (1 a 5), +11..+15 rara,
##   +16..+20 épica, +21 lendária (1).
## Chance de sucesso cai com o nível (100% no +1, 10% no +21). Falhar gasta as pedras,
## mas o item não perde nível. Roda na máquina do dono do inventário.

enum Result { NONE, SUCCESS, FAILED }

const STONES := ["refine_stone", "refine_stone_uncommon", "refine_stone_rare", "refine_stone_epic", "refine_stone_legendary"]
const LEVELS_PER_STONE := 5
const CHANCE_DROP := 0.045
const MIN_CHANCE := 0.1


## Itens com durabilidade (armas, ferramentas, equipamentos).
static func can_be_refined(slot: Dictionary) -> bool:
	return not slot.is_empty() and Inventory.max_durability(slot.id) > 0.0


static func is_maxed(slot: Dictionary) -> bool:
	return Inventory.refine_of(slot) >= Inventory.MAX_REFINE


static func _next(slot: Dictionary) -> int:
	return Inventory.refine_of(slot) + 1


## Pedra usada para ir ao próximo nível.
static func stone_for(slot: Dictionary) -> String:
	return STONES[mini((_next(slot) - 1) / LEVELS_PER_STONE, STONES.size() - 1)]


## Quantas pedras: 1, 2, 3, 4, 5 dentro de cada faixa; o +21 custa 1 lendária.
static func cost(slot: Dictionary) -> int:
	var next := _next(slot)
	if next > LEVELS_PER_STONE * (STONES.size() - 1):
		return 1
	return (next - 1) % LEVELS_PER_STONE + 1


## Chance de dar certo (0 a 1).
static func chance(slot: Dictionary) -> float:
	return maxf(MIN_CHANCE, 1.0 - CHANCE_DROP * (_next(slot) - 1))


static func can_refine(inventory: Inventory, slot: Dictionary) -> bool:
	return can_be_refined(slot) and not is_maxed(slot) and inventory.count_of(stone_for(slot)) >= cost(slot)


## Tenta refinar. NONE = não tinha como (faltou pedra, já no máximo).
static func refine(inventory: Inventory, slot: Dictionary, roll := -1.0) -> Result:
	if not can_refine(inventory, slot):
		return Result.NONE
	inventory.remove_item(stone_for(slot), cost(slot))
	if roll < 0.0:
		roll = randf()
	if roll >= chance(slot):
		inventory.changed.emit()
		return Result.FAILED
	slot["r"] = Inventory.refine_of(slot) + 1
	inventory.changed.emit()
	return Result.SUCCESS
