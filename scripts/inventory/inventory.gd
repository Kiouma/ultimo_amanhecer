class_name Inventory
extends Node
## Inventário do jogador (GDD 7 e 13.2): slots com empilhamento e limite de peso.
## Os 9 primeiros slots são a hotbar (teclas 1-9); o resto é a mochila.
## Cada slot é {} (vazio) ou {"id": String, "count": int}, mais dados extras de itens
## que não empilham: "dur" (durabilidade atual), "mag" (balas no pente), "q" (qualidade 1-5)
## e "r" (refino 0-21).
## Os extras acompanham o item ao soltar, ir para a bag e ser pego de novo.

## Chaves de estado do item que viajam com ele.
const EXTRA_KEYS := ["dur", "mag", "q", "r"]

## Qualidade (GDD 8.3): cada nível acima de 1 dá +12% em dano, durabilidade e eficiência.
const QUALITY_STEP := 0.12
const MAX_QUALITY := 5
## Refino (+1 a +21): cada nível dá +5% de dano/eficiência.
const REFINE_STEP := 0.05
const MAX_REFINE := 21
## Cores por nível de qualidade/raridade (1 cinza, 2 verde, 3 azul, 4 roxo, 5 laranja).
const TIER_COLORS := [Color(0.55, 0.55, 0.55), Color(0.4, 0.8, 0.4), Color(0.35, 0.6, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.6, 0.2)]
## Brilho do refino, a cada 3 níveis (+3, +6 ... +21).
const REFINE_FX_COLORS := [Color(0.95, 0.95, 0.95), Color(0.45, 1.0, 0.45), Color(0.4, 0.7, 1.0), Color(0.8, 0.45, 1.0), Color(1.0, 0.6, 0.15), Color(1.0, 0.25, 0.25), Color(1.0, 0.9, 0.3)]
## Modo criativo: quem tem pelo menos 1 unidade "tem" esta quantidade, e nada se gasta.
const CREATIVE_COUNT := 999
##
## Rede: o inventário vive na máquina do dono do personagem. O que vem do mundo
## (pegar item do chão) passa pelo servidor, que concede com grant() via RPC.

signal changed
## Recebeu itens de fora (coletou, pegou do chão, recompensa): o HUD mostra "+1 Madeira".
signal received(id: String, count: int)
## Ouro mudou (valor novo e quanto mudou).
signal gold_changed(amount: int, delta: int)

## A barra de itens (1 a 9) saiu: as teclas 1 a 5 são das habilidades e a arma fica no
## slot fixo do equipamento. Todos os slots são mochila (0 mantém o código antigo).
const HOTBAR_SIZE := 0

@export var backpack_size := 40
## Peso máximo em kg. Acima disso o personagem fica lento (ver Player).
@export var max_weight := 60.0

var slots: Array[Dictionary] = []
## Modo criativo (ver Player.creative): itens não se gastam nem se desgastam.
var creative := false
## Ouro carregado (moeda; sem peso). Cai de monstros, dividido entre quem está perto.
var gold := 0


func _ready() -> void:
	slots.resize(HOTBAR_SIZE + backpack_size)
	for i in slots.size():
		slots[i] = {}


# --- Consulta -------------------------------------------------------------------------

func get_slot(index: int) -> Dictionary:
	return slots[index] if index >= 0 and index < slots.size() else {}


func count_of(id: String) -> int:
	var total := 0
	for s in slots:
		if s.get("id", "") == id:
			total += int(s.count)
	if creative and total > 0:
		return maxi(total, CREATIVE_COUNT)
	return total


func total_weight() -> float:
	var total := 0.0
	for s in slots:
		if not s.is_empty():
			total += float(GameData.get_item(s.id).get("weight", 0.0)) * int(s.count)
	return total


## Quantos desse item ainda cabem (completando pilhas e usando slots vazios).
func room_for(id: String) -> int:
	var limit := GameData.max_stack(id)
	var room := 0
	for s in slots:
		if s.is_empty():
			room += limit
		elif s.id == id:
			room += maxi(limit - int(s.count), 0)
	return room


func is_overloaded() -> bool:
	return total_weight() > max_weight


## Primeiro slot da hotbar com um item do tipo pedido (ex.: "spell"), ou -1.
func find_in_hotbar(type: String) -> int:
	for i in HOTBAR_SIZE:
		if not slots[i].is_empty() and GameData.get_item(slots[i].id).get("type", "") == type:
			return i
	return -1


# --- Mudanças -------------------------------------------------------------------------

## Adiciona itens: completa pilhas existentes, depois ocupa slots vazios.
## extra: estado do item ({"dur": 40}), só para itens que não empilham.
## Armas, feitiços e consumíveis vão primeiro para a hotbar; recursos e munição,
## primeiro para a mochila. Retorna quantos NÃO couberam.
func add_item(id: String, count: int, extra: Dictionary = {}) -> int:
	if GameData.get_item(id).is_empty():
		push_warning("Inventário: item desconhecido '%s'." % id)
		return count
	var left := count
	var limit := GameData.max_stack(id)
	for s in slots:
		if left <= 0:
			break
		if limit > 1 and s.get("id", "") == id and int(s.count) < limit:
			var moved := mini(limit - int(s.count), left)
			s.count = int(s.count) + moved
			left -= moved
	for i in _fill_order(id):
		if left <= 0:
			break
		if slots[i].is_empty():
			var moved := mini(limit, left)
			slots[i] = {"id": id, "count": moved}
			if limit == 1:
				for key in EXTRA_KEYS:
					if extra.has(key):
						slots[i][key] = extra[key]
			left -= moved
	if left != count:
		changed.emit()
	return left


const HOTBAR_FIRST_TYPES := ["bow", "melee", "focus", "thrown", "consumable", "tool", "station", "trap"]


func _fill_order(id: String) -> Array:
	var hotbar := range(HOTBAR_SIZE)
	var backpack := range(HOTBAR_SIZE, slots.size())
	if str(GameData.get_item(id).get("type", "")) in HOTBAR_FIRST_TYPES:
		return hotbar + backpack
	return backpack + hotbar


## Tira itens de onde houver (mochila primeiro, para não esvaziar a hotbar).
## Só tira se tiver tudo. Retorna true se tirou.
func remove_item(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	if creative:
		return true
	var left := count
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		if slots[i].get("id", "") == id:
			var taken := mini(int(slots[i].count), left)
			slots[i].count = int(slots[i].count) - taken
			left -= taken
			if int(slots[i].count) <= 0:
				slots[i] = {}
	changed.emit()
	return true


## Tira até `count` itens de um slot específico e devolve o que tirou ({} se nada).
func take_from_slot(index: int, count: int) -> Dictionary:
	var s := get_slot(index)
	if s.is_empty() or count <= 0:
		return {}
	var taken := mini(count, int(s.count))
	s.count = int(s.count) - taken
	if int(s.count) <= 0:
		slots[index] = {}
	changed.emit()
	var out := {"id": s.id, "count": taken}
	out.merge(extra_of(s))
	return out


## Gasta (come, lê, coloca) itens de um slot. No criativo não gasta.
func consume_from_slot(index: int, count: int) -> void:
	if creative:
		return
	take_from_slot(index, count)


## Arrastar de um slot para outro: junta pilhas iguais, senão troca.
func move_slot(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size():
		return
	var a := slots[from]
	var b := slots[to]
	if a.is_empty():
		return
	if not b.is_empty() and b.id == a.id:
		var room := GameData.max_stack(a.id) - int(b.count)
		var moved := mini(room, int(a.count))
		b.count = int(b.count) + moved
		a.count = int(a.count) - moved
		if int(a.count) <= 0:
			slots[from] = {}
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## Divide uma pilha ao meio num slot vazio (botão direito na tela de inventário).
func split_slot(index: int) -> void:
	var s := get_slot(index)
	if s.is_empty() or int(s.count) < 2:
		return
	for i in slots.size():
		if slots[i].is_empty():
			var half := int(s.count) / 2
			s.count = int(s.count) - half
			slots[i] = {"id": s.id, "count": half}
			changed.emit()
			return


## Estado extra de um slot (só as chaves de EXTRA_KEYS).
static func extra_of(slot: Dictionary) -> Dictionary:
	var out := {}
	for key in EXTRA_KEYS:
		if slot.has(key):
			out[key] = slot[key]
	return out


# --- Durabilidade (GDD 8.3) -----------------------------------------------------------

## Durabilidade máxima base do item (0 = não se desgasta).
static func max_durability(id: String) -> float:
	return float(GameData.get_item(id).get("durability", 0.0))


## Qualidade do slot (1 se não tiver: achado, kit inicial).
static func quality_of(slot: Dictionary) -> int:
	return clampi(int(slot.get("q", 1)), 1, MAX_QUALITY)


## Multiplicador da qualidade: Q1 = 1,0 ... Q5 = 1,48.
static func quality_multiplier(slot: Dictionary) -> float:
	return 1.0 + QUALITY_STEP * (quality_of(slot) - 1)


## Nível de refino do slot (0 a 21).
static func refine_of(slot: Dictionary) -> int:
	return clampi(int(slot.get("r", 0)), 0, MAX_REFINE)


## Multiplicador do refino: +0 = 1,0 ... +21 = 2,05.
static func refine_multiplier(slot: Dictionary) -> float:
	return 1.0 + REFINE_STEP * refine_of(slot)


## Faixa do brilho do refino: 0 = sem brilho, 1 (+3) ... 7 (+21).
static func refine_fx_tier(slot: Dictionary) -> int:
	return refine_of(slot) / 3


## Nível de cor do slot (fundo): qualidade de armas/ferramentas/equipamentos ou
## "tier" do item (pedras de refino). 0 = sem cor.
static func tier_of(slot: Dictionary) -> int:
	if slot.is_empty():
		return 0
	if max_durability(slot.id) > 0.0:
		return quality_of(slot)
	return clampi(int(GameData.get_item(slot.id).get("tier", 0)), 0, MAX_QUALITY)


## Nome com refino e qualidade: "Machado de ferro +3 · Q2".
static func display_name_of(slot: Dictionary) -> String:
	if slot.is_empty():
		return ""
	var text := str(GameData.get_item(slot.id).get("name", slot.id))
	if refine_of(slot) > 0:
		text += " +%d" % refine_of(slot)
	if max_durability(slot.id) > 0.0:
		text += " · Q%d" % quality_of(slot)
	return text


## Durabilidade máxima deste item, já com a qualidade.
static func max_durability_of(slot: Dictionary) -> float:
	if slot.is_empty():
		return 0.0
	return max_durability(slot.id) * quality_multiplier(slot)


## Durabilidade atual do slot (cheia se nunca foi usado).
static func durability_of(slot: Dictionary) -> float:
	if slot.is_empty():
		return 0.0
	return float(slot.get("dur", max_durability_of(slot)))


static func is_broken(slot: Dictionary) -> bool:
	return not slot.is_empty() and max_durability(slot.id) > 0.0 and durability_of(slot) <= 0.0


## Gasta durabilidade de um slot (dicionário do próprio inventário). Retorna a que sobrou.
func wear(slot: Dictionary, amount: float) -> float:
	if slot.is_empty() or max_durability(slot.id) <= 0.0:
		return 0.0
	if creative:
		return durability_of(slot)
	slot["dur"] = maxf(durability_of(slot) - amount, 0.0)
	changed.emit()
	return slot.dur


func clear() -> void:
	for i in slots.size():
		slots[i] = {}
	changed.emit()


# --- Rede -------------------------------------------------------------------------------

## O servidor concede itens a este jogador (ex.: pegou algo do chão).
## O que não couber volta para o chão, aos pés do jogador.
func grant(id: String, count: int, extra: Dictionary = {}) -> void:
	var owner_id := get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		_receive(id, count, extra)
	elif multiplayer.is_server() and Network.is_online():
		_grant_remote.rpc_id(owner_id, id, count, extra)


@rpc("any_peer", "call_remote", "reliable")
func _grant_remote(id: String, count: int, extra: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_receive(id, count, extra)


func _receive(id: String, count: int, extra: Dictionary = {}) -> void:
	var left := add_item(id, count, extra)
	if count - left > 0:
		received.emit(id, count - left)
	if left > 0:
		var player := get_parent() as Node3D
		WorldItems.drop(id, left, player.global_position + Vector3.UP * 0.3, player, extra)


# --- Ouro ---------------------------------------------------------------------------------

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold, amount)


## Perde uma fração do ouro (morte). Retorna quanto perdeu.
func lose_gold_fraction(fraction: float) -> int:
	var lost := int(floor(gold * clampf(fraction, 0.0, 1.0)))
	add_gold(-lost)
	return lost
