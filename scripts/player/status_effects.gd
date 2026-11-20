class_name StatusEffects
extends Node
## Buffs e debuffs temporários do jogador (data/effects), nó "Effects" do Player.
## - Cada efeito: duração, acúmulos ("max_stacks"; acumular soma e renova a duração;
##   1 = só renova), modificadores ("mods" × força × acúmulos, como os da árvore) e dano
##   por segundo ("dps", com "moving_mult" andando, ex.: sangramento).
## - "power": força padrão (ex.: lentidão 0,4 = 40% mais lento); quem aplica pode mudar.
## - Fogueira: ficar REST_TIME segundos perto de uma dá "Descansado" (renova enquanto
##   ficar perto).
## Rede: roda no dono do personagem. O servidor (monstros, armadilhas) usa
## StatusEffects.give(), que chega ao dono por RPC. Os outros não precisam ver.

signal changed

const TICK := 0.5
const REST_RADIUS := 6.0
const REST_TIME := 10.0

## id → {"time_left", "duration", "stacks", "power"}
var active := {}

var _player: Player
var _tick := 0.0
var _near_fire := 0.0
var _dot_carry := 0.0


func _ready() -> void:
	_player = get_parent() as Player


static func of(node: Node) -> StatusEffects:
	return node.get_node_or_null(^"Effects") as StatusEffects if node else null


## Aplica um efeito a um jogador de qualquer máquina (o servidor chama para monstros).
## duration/power < 0 = valores padrão do efeito.
static func give(target: Node, effect_id: String, duration := -1.0, power := -1.0, stacks := 1) -> void:
	var fx := of(target)
	if fx == null:
		return
	if target.is_multiplayer_authority():
		fx.apply(effect_id, duration, power, stacks)
	elif Network.is_online():
		fx._remote_apply.rpc_id(target.get_multiplayer_authority(), effect_id, duration, power, stacks)


@rpc("any_peer", "call_remote", "reliable")
func _remote_apply(effect_id: String, duration: float, power: float, stacks: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:  # só o servidor manda
		apply(effect_id, clampf(duration, -1.0, 600.0), clampf(power, -1.0, 5.0), clampi(stacks, 1, 10))


static func data(effect_id: String) -> Dictionary:
	return GameData.get_entry("effects", effect_id)


func apply(effect_id: String, duration := -1.0, power := -1.0, stacks := 1) -> void:
	var d := data(effect_id)
	if d.is_empty() or _player == null or _player.health.is_dead:
		return
	var dur := float(d.get("duration", 5.0)) if duration < 0.0 else duration
	var pw := float(d.get("power", 1.0)) if power < 0.0 else power
	var max_stacks := int(d.get("max_stacks", 1))
	var fresh := not active.has(effect_id)
	var e: Dictionary = active.get(effect_id, {"stacks": 0, "power": pw})
	e["stacks"] = mini(int(e.stacks) + stacks, max_stacks) if max_stacks > 1 else 1
	e["power"] = maxf(float(e.power), pw)
	e["duration"] = maxf(dur, float(e.get("time_left", 0.0)))
	e["time_left"] = e.duration
	active[effect_id] = e
	if fresh and str(d.get("kind", "")) == "debuff":
		_player.notify(tr("%s!") % d.get("name", effect_id))
	_update_mods()


func remove(effect_id: String) -> void:
	if active.erase(effect_id):
		_update_mods()


func clear() -> void:
	active.clear()
	_update_mods()


func has(effect_id: String) -> bool:
	return active.has(effect_id)


## Modificadores somados de todos os efeitos (Progression soma com o resto).
func _update_mods() -> void:
	var mods := {}
	for effect_id: String in active:
		var e: Dictionary = active[effect_id]
		var per: Dictionary = data(effect_id).get("mods", {})
		for key: String in per:
			mods[key] = float(mods.get(key, 0.0)) + float(per[key]) * float(e.power) * int(e.stacks)
	if _player:
		_player.progression.set_effect_mods(mods)
	changed.emit()


func _process(delta: float) -> void:
	if _player == null or not _player.is_multiplayer_authority():
		return
	_tick += delta
	if _tick < TICK:
		return
	var span := _tick
	_tick = 0.0
	if _player.health.is_dead:
		if not active.is_empty():
			clear()
		_near_fire = 0.0
		return
	# Tempo e dano por segundo.
	var expired: Array = []
	var damage := 0.0
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length() > 0.5
	for effect_id: String in active:
		var e: Dictionary = active[effect_id]
		var d := data(effect_id)
		e.time_left = float(e.time_left) - span
		var dps := float(d.get("dps", 0.0)) * int(e.stacks) * float(e.power)
		if moving:
			dps *= float(d.get("moving_mult", 1.0))
		damage += dps * span
		if float(e.time_left) <= 0.0:
			expired.append(effect_id)
	for effect_id: String in expired:
		active.erase(effect_id)
	if damage > 0.0:
		# Fonte = o próprio jogador: a Resistência não reduz (como a antiga fome).
		_player.health.take_damage(damage, _player)
	if not expired.is_empty():
		_update_mods()
	else:
		changed.emit()
	_check_campfire(span)


## Perto de uma fogueira por REST_TIME segundos: "Descansado" (e renova enquanto ficar).
func _check_campfire(span: float) -> void:
	if Structures.stations_near("campfire", _player.global_position, REST_RADIUS).is_empty():
		_near_fire = 0.0
		return
	_near_fire += span
	if _near_fire < REST_TIME:
		return
	var e: Dictionary = active.get("rested", {})
	var full := float(data("rested").get("duration", 180.0))
	if e.is_empty():
		apply("rested")
		_player.notify(tr("Descansado: regeneração maior e +10% de velocidade por 3 min"))
	elif float(e.time_left) < full - 5.0:
		e.time_left = full
		e.duration = full


## Para o HUD: [[id, segundos restantes, duração, acúmulos], ...] (buffs primeiro).
func list() -> Array:
	var out: Array = []
	for effect_id: String in active:
		var e: Dictionary = active[effect_id]
		out.append([effect_id, float(e.time_left), float(e.duration), int(e.stacks)])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return str(data(a[0]).get("kind", "")) == "buff" and str(data(b[0]).get("kind", "")) != "buff")
	return out
