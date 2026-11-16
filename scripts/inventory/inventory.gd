class_name Inventory
extends Node
## Inventário do jogador (GDD 7 e 13.2): slots com empilhamento e limite de peso.
## Os 9 primeiros slots são a hotbar (teclas 1-9); o resto é a mochila.
## Cada slot é {} (vazio) ou {"id": String, "count": int}.
##
## Rede: o inventário vive na máquina do dono do personagem. O que vem do mundo
## (pegar item do chão) passa pelo servidor, que concede com grant() via RPC.

signal changed

const HOTBAR_SIZE := 9

@export var backpack_size := 24
## Peso máximo em kg. Acima disso o personagem fica lento (ver Player).
@export var max_weight := 40.0

var slots: Array[Dictionary] = []


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
## Armas, feitiços e consumíveis vão primeiro para a hotbar; recursos e munição,
## primeiro para a mochila. Retorna quantos NÃO couberam.
func add_item(id: String, count: int) -> int:
	if GameData.get_item(id).is_empty():
		push_warning("Inventário: item desconhecido '%s'." % id)
		return count
	var left := count
	var limit := GameData.max_stack(id)
	for s in slots:
		if left <= 0:
			break
		if s.get("id", "") == id and int(s.count) < limit:
			var moved := mini(limit - int(s.count), left)
			s.count = int(s.count) + moved
			left -= moved
	for i in _fill_order(id):
		if left <= 0:
			break
		if slots[i].is_empty():
			var moved := mini(limit, left)
			slots[i] = {"id": id, "count": moved}
			left -= moved
	if left != count:
		changed.emit()
	return left


const HOTBAR_FIRST_TYPES := ["bow", "firearm", "melee", "spell", "consumable", "tool"]


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
	return {"id": s.id, "count": taken}


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


func clear() -> void:
	for i in slots.size():
		slots[i] = {}
	changed.emit()


# --- Rede -------------------------------------------------------------------------------

## O servidor concede itens a este jogador (ex.: pegou algo do chão).
## O que não couber volta para o chão, aos pés do jogador.
func grant(id: String, count: int) -> void:
	var owner_id := get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		_receive(id, count)
	elif multiplayer.is_server() and Network.is_online():
		_grant_remote.rpc_id(owner_id, id, count)


@rpc("any_peer", "call_remote", "reliable")
func _grant_remote(id: String, count: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_receive(id, count)


func _receive(id: String, count: int) -> void:
	var left := add_item(id, count)
	if left > 0:
		var player := get_parent() as Node3D
		WorldItems.drop(id, left, player.global_position + Vector3.UP * 0.3, player)
