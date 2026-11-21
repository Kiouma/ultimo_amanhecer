class_name Trade
extends Node
## Troca de itens e ouro entre dois jogadores (nó "Trade" do Player, etapa 9).
## 1. invite(outro): o outro recebe um convite (sinal invited) e aceita ou recusa.
## 2. Aceito, os dois abrem a janela (sinal opened). Cada um monta a oferta (itens do
##    próprio inventário + ouro); mudar a oferta tira as confirmações dos dois.
## 3. Quando os dois confirmam, cada lado confere que ainda tem o que ofereceu, tira do
##    inventário e manda para o outro (que recebe no próprio inventário).
## Só a até MAX_DISTANCE metros; se afastar ou morrer cancela.
## Rede: as chamadas vão direto para a máquina do outro jogador (RPC no nó Trade dele).

signal invited(from: Player)
signal opened(partner: Player)
signal changed
signal closed(reason: String)

const MAX_DISTANCE := 10.0

var partner: Player = null
## Minha oferta: [{"index": slot, "id", "count"}] e ouro.
var my_items: Array = []
var my_gold := 0
## Oferta do outro: [{"id", "count", ...estado do item}] e ouro.
var their_items: Array = []
var their_gold := 0
var my_ok := false
var their_ok := false

var _player: Player
var _pending_from: Player = null


func _ready() -> void:
	_player = get_parent() as Player


func is_open() -> bool:
	return is_instance_valid(partner)


func _trade_of(p: Player) -> Trade:
	return p.get_node_or_null(^"Trade") as Trade if p else null


# --- Ações do dono ------------------------------------------------------------------------

func invite(other: Player) -> void:
	if other == null or other == _player or is_open():
		return
	if other.global_position.distance_to(_player.global_position) > MAX_DISTANCE:
		_player.notify(tr("Chegue mais perto para trocar (até %d m)") % int(MAX_DISTANCE))
		return
	_player.notify(tr("Pedido de troca enviado para %s") % other.display_name())
	_send_to(other, &"_r_invite", [])


func accept_invite() -> void:
	var from := _pending_from
	_pending_from = null
	if not is_instance_valid(from) or is_open():
		return
	_open(from)
	_send_to(from, &"_r_accept", [])


func decline_invite() -> void:
	var from := _pending_from
	_pending_from = null
	if is_instance_valid(from):
		_send_to(from, &"_r_cancel", [tr("recusou a troca")])


## Põe (ou tira, se já estava) a pilha do slot `index` na oferta.
func toggle_item(index: int) -> void:
	if not is_open():
		return
	for i in my_items.size():
		if int(my_items[i].index) == index:
			my_items.remove_at(i)
			_offer_changed()
			return
	var s := _player.inventory.get_slot(index)
	if s.is_empty() or my_items.size() >= 12:
		return
	my_items.append({"index": index, "id": s.id, "count": int(s.count)})
	_offer_changed()


func set_gold(amount: int) -> void:
	my_gold = clampi(amount, 0, _player.inventory.gold)
	_offer_changed()


func confirm() -> void:
	if not is_open() or my_ok:
		return
	my_ok = true
	_send_to(partner, &"_r_confirm", [true])
	changed.emit()
	_try_execute()


func cancel(reason := "") -> void:
	if not is_open():
		return
	var p := partner
	_close(reason if reason != "" else tr("Troca cancelada"))
	_send_to(p, &"_r_cancel", [tr("cancelou a troca")])


func _offer_changed() -> void:
	my_ok = false
	their_ok = false
	var payload: Array = []
	for e: Dictionary in my_items:
		var s := _player.inventory.get_slot(int(e.index))
		var item := {"id": e.id, "count": e.count}
		item.merge(Inventory.extra_of(s))
		payload.append(item)
	_send_to(partner, &"_r_offer", [payload, my_gold])
	changed.emit()


func _open(p: Player) -> void:
	partner = p
	my_items.clear()
	their_items.clear()
	my_gold = 0
	their_gold = 0
	my_ok = false
	their_ok = false
	opened.emit(p)


func _close(reason: String) -> void:
	partner = null
	my_items.clear()
	their_items.clear()
	closed.emit(reason)
	if reason != "":
		_player.notify(reason)


## Os dois confirmaram: confere, tira do inventário e entrega ao outro.
func _try_execute() -> void:
	if not (my_ok and their_ok and is_open()):
		return
	var inv := _player.inventory
	for e: Dictionary in my_items:
		var s := inv.get_slot(int(e.index))
		if s.is_empty() or str(s.id) != str(e.id) or int(s.count) < int(e.count):
			cancel(tr("Troca cancelada: a oferta mudou"))
			return
	if inv.gold < my_gold:
		cancel(tr("Troca cancelada: falta ouro"))
		return
	var sent: Array = []
	for e: Dictionary in my_items:
		var taken := inv.take_from_slot(int(e.index), int(e.count))
		if not taken.is_empty():
			sent.append(taken)
	inv.add_gold(-my_gold)
	var p := partner
	_send_to(p, &"_r_deliver", [sent, my_gold])
	_close(tr("Troca feita com %s") % p.display_name())


func _process(_delta: float) -> void:
	if not is_open() or _player == null or not _player.is_local():
		return
	if partner.health.is_dead or _player.health.is_dead \
			or partner.global_position.distance_to(_player.global_position) > MAX_DISTANCE + 2.0:
		cancel(tr("Troca cancelada: longe demais"))


# --- Recebendo do outro jogador -------------------------------------------------------------

func _send_to(p: Player, method: StringName, args: Array) -> void:
	if not is_instance_valid(p):
		return
	if p.is_local() or not Network.is_online():
		var t := _trade_of(p)
		if t:
			match method:
				&"_r_invite": t._on_invite(_player)
				&"_r_accept": t._on_accept(_player)
				&"_r_offer": t._on_offer(_player, args[0], args[1])
				&"_r_confirm": t._on_confirm(_player, args[0])
				&"_r_deliver": t._on_deliver(_player, args[0], args[1])
				&"_r_cancel": t._on_cancel(_player, args[0])
		return
	var peer := p.get_multiplayer_authority()
	var me := _player.get_path()
	var t := _trade_of(p)
	match method:
		&"_r_invite": t._peer_invite.rpc_id(peer, me)
		&"_r_accept": t._peer_accept.rpc_id(peer, me)
		&"_r_offer": t._peer_offer.rpc_id(peer, me, args[0], args[1])
		&"_r_confirm": t._peer_confirm.rpc_id(peer, me, args[0])
		&"_r_deliver": t._peer_deliver.rpc_id(peer, me, args[0], args[1])
		&"_r_cancel": t._peer_cancel.rpc_id(peer, me, args[0])


## Personagem de quem mandou o RPC (pelo id de rede; o caminho do nó pode ser outro em
## cada máquina, então só serve de conferência do nome).
func _sender(from_path: NodePath) -> Player:
	var sender := multiplayer.get_remote_sender_id()
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n is Player and n.get_multiplayer_authority() == sender and n != _player \
				and str(n.name) == str(from_path.get_name(from_path.get_name_count() - 1)):
			return n
	return null


@rpc("any_peer", "call_remote", "reliable")
func _peer_invite(from_path: NodePath) -> void:
	var p := _sender(from_path)
	if p:
		_on_invite(p)


@rpc("any_peer", "call_remote", "reliable")
func _peer_accept(from_path: NodePath) -> void:
	var p := _sender(from_path)
	if p:
		_on_accept(p)


@rpc("any_peer", "call_remote", "reliable")
func _peer_offer(from_path: NodePath, items: Array, gold: int) -> void:
	var p := _sender(from_path)
	if p:
		_on_offer(p, items, gold)


@rpc("any_peer", "call_remote", "reliable")
func _peer_confirm(from_path: NodePath, ok: bool) -> void:
	var p := _sender(from_path)
	if p:
		_on_confirm(p, ok)


@rpc("any_peer", "call_remote", "reliable")
func _peer_deliver(from_path: NodePath, items: Array, gold: int) -> void:
	var p := _sender(from_path)
	if p:
		_on_deliver(p, items, gold)


@rpc("any_peer", "call_remote", "reliable")
func _peer_cancel(from_path: NodePath, reason: String) -> void:
	var p := _sender(from_path)
	if p:
		_on_cancel(p, reason)


func _on_invite(from: Player) -> void:
	if is_open():
		_send_to(from, &"_r_cancel", [tr("já está trocando com outra pessoa")])
		return
	_pending_from = from
	invited.emit(from)


func _on_accept(from: Player) -> void:
	if not is_open():
		_open(from)


func _on_offer(from: Player, items: Array, gold: int) -> void:
	if from != partner:
		return
	their_items = items.slice(0, 12)
	their_gold = maxi(gold, 0)
	my_ok = false
	their_ok = false
	changed.emit()


func _on_confirm(from: Player, ok: bool) -> void:
	if from != partner:
		return
	their_ok = ok
	changed.emit()
	_try_execute()


func _on_deliver(from: Player, items: Array, gold: int) -> void:
	for item: Dictionary in items:
		var id := str(item.get("id", ""))
		if GameData.get_item(id).is_empty():
			continue
		var left := _player.inventory.add_item(id, clampi(int(item.get("count", 1)), 1, 999), Inventory.extra_of(item))
		if left > 0:
			WorldItems.drop(id, left, _player.global_position + Vector3.UP * 0.3, _player, Inventory.extra_of(item))
	if gold > 0:
		_player.inventory.add_gold(clampi(gold, 0, 10000000))
	# A janela fecha quando este lado também entregar (_try_execute), não aqui.
	_player.notify(tr("Recebeu a troca de %s") % from.display_name())


func _on_cancel(from: Player, reason: String) -> void:
	if _pending_from == from:
		_pending_from = null
	if from == partner:
		_close("%s %s" % [from.display_name(), reason])
	elif reason != "":
		_player.notify("%s %s" % [from.display_name(), reason])
