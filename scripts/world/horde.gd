class_name Horde
extends Node
## Hordas periódicas (GDD 11): a cada `every_days` dias, ao anoitecer, uma horda ataca.
## Tamanho e composição crescem a cada horda e com o número de jogadores.
## Os zumbis surgem em ondas num anel em volta da base (centro das construções) ou
## dos jogadores e caçam o jogador vivo mais perto; se a base bloqueia, eles a atacam
## (cerco, ver Zombie). Termina quando todos morrem (depois da última onda) ou ao
## amanhecer; quem estiver vivo ganha a recompensa.
##
## Aviso: contador no relógio do HUD, faixa na tela e céu avermelhado da tarde do dia
## da horda até o amanhecer (calculado em todas as máquinas a partir do relógio).
## Rede: só o servidor cria e comanda; estado e avisos vão por RPC. F9 (servidor)
## começa uma horda agora, para testes.

@export var every_days := 7
## Ondas por horda e intervalo entre elas (segundos reais).
@export var waves := 3
@export var wave_interval := 45.0
@export var spawn_radius_min := 34.0
@export var spawn_radius_max := 44.0
## Teto de zumbis vivos ao mesmo tempo (desempenho).
@export var max_alive := 60

## Hora em que o céu começa a avermelhar no dia da horda.
const RED_SKY_FROM := 16.0
const HUNT_INTERVAL := 2.0

var active := false
var number := 0
## Zumbis da horda ainda vivos (servidor; nos clientes vem por RPC).
var remaining := 0

var _pending: Array = []  # ondas ainda não criadas: cada uma é uma lista de ids
var _wave_timer := 0.0
var _hunt_timer := 0.0
var _members: Array[Zombie] = []


static func find(tree: SceneTree) -> Horde:
	return tree.get_first_node_in_group("horde") as Horde


func _ready() -> void:
	add_to_group("horde")
	if multiplayer.is_server():
		EventBus.night_started.connect(_on_night_started)
		EventBus.day_started.connect(_on_day_started)
		multiplayer.peer_connected.connect(func(id: int) -> void: _sync_status.rpc_id(id, active, number, remaining))


## Dias até a próxima horda (0 = hoje à noite).
func days_until(day: int) -> int:
	return posmod(-day, every_days)


func is_horde_day(day: int) -> bool:
	return day % every_days == 0


## Texto curto para o relógio do HUD.
func status_text(day: int, _hour: float) -> String:
	if active:
		return "HORDA %d · restam %d" % [number, remaining]
	var left := days_until(day)
	if left == 0:
		return "Horda hoje à noite"
	return "Horda em %d dia%s" % [left, "" if left == 1 else "s"]


func _process(delta: float) -> void:
	_update_sky()
	if not multiplayer.is_server() or not active:
		return
	_wave_timer -= delta
	if not _pending.is_empty() and _wave_timer <= 0.0:
		_wave_timer = wave_interval
		_spawn_wave(_pending.pop_front())
	_hunt_timer -= delta
	if _hunt_timer <= 0.0:
		_hunt_timer = HUNT_INTERVAL
		_command()


func _unhandled_key_input(event: InputEvent) -> void:
	if multiplayer.is_server() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F9 and not active:
		start(number + 1)


# --- Servidor ------------------------------------------------------------------------

func _on_night_started(day: int) -> void:
	if is_horde_day(day) and not active:
		start(day / every_days)


func _on_day_started(_day: int) -> void:
	if active:
		finish(true)


func start(horde_number: int) -> void:
	number = horde_number
	active = true
	_members.clear()
	_pending = composition(number, maxi(get_tree().get_nodes_in_group("player").size(), 1))
	_wave_timer = 0.0
	_hunt_timer = 0.0
	remaining = 0
	for wave: Array in _pending:
		remaining += wave.size()
	_announce_start(number)
	if Network.is_online():
		_announce_start.rpc(number)
	_broadcast()


## Ondas da horda n: listas de ids de zumbi. Cresce com n e com os jogadores.
func composition(n: int, players: int) -> Array:
	var scale := 0.6 + 0.4 * players
	var counts := {
		"walker": roundi((8 + 5 * n) * scale),
		"runner": roundi((1 + 2 * n) * scale),
		"night_infected": roundi(2 * n * scale),
		"brute": roundi(n * scale * 0.7),
		"spitter": roundi((n - 1) * scale),
		"exploder": roundi(n * scale * 0.8),
	}
	var all: Array = []
	for id: String in counts:
		if not GameData.get_entry("zombies", id).is_empty():
			for i in maxi(int(counts[id]), 0):
				all.append(id)
	all.shuffle()
	var out: Array = []
	for w in waves:
		out.append([])
	for i in all.size():
		out[i % waves].append(all[i])
	# Chefe da horda vem na última onda.
	# Hordas pares: Necromante; ímpares: Colosso.
	var boss := "necromancer" if n % 2 == 0 else "colossus"
	if not GameData.get_entry("zombies", boss).is_empty():
		out[waves - 1].append(boss)
	return out


func _spawn_wave(ids: Array) -> void:
	var arena := get_parent()
	if not arena.has_method(&"spawn_zombie"):
		return
	var center := _base_center()
	# Cada onda vem de 1 ou 2 direções (grupos), não de todo lado.
	var directions := [randf() * TAU]
	if ids.size() > 8:
		directions.append(directions[0] + randf_range(1.5, 3.5))
	for k in ids.size():
		if _alive_members() >= max_alive:
			remaining -= 1  # não cabe: conta como fora da horda
			continue
		var angle: float = directions[k % directions.size()] + randf_range(-0.35, 0.35)
		var dist := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = 0.1
		var z: Zombie = arena.spawn_zombie(ids[k], pos)
		z.horde = true
		if z.is_in_group("boss"):
			# Chefe: vida conforme jogadores e horda (solo, horda 1 ≈ 55%).
			var players := maxi(get_tree().get_nodes_in_group("player").size(), 1)
			var factor := (0.4 + 0.15 * players) * (0.6 + 0.4 * number)
			z.health.reset(z.health.max_health * clampf(factor, 0.4, 3.0))
		z.health.died.connect(_on_member_died.bind(z), CONNECT_ONE_SHOT)
		_members.append(z)
	_broadcast()


func _on_member_died(_source: Node, _z: Zombie) -> void:
	remaining = maxi(remaining - 1, 0)
	_broadcast()
	if remaining == 0 and _pending.is_empty():
		finish(true)


## Manda quem está sem alvo atrás do jogador vivo mais perto.
func _command() -> void:
	var players := _living_players()
	for z in _members:
		if not is_instance_valid(z) or z.is_dead():
			continue
		var best: Node3D = null
		for p in players:
			if best == null or p.global_position.distance_to(z.global_position) < best.global_position.distance_to(z.global_position):
				best = p
		if best:
			z.hunt(best.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	_members = _members.filter(func(z: Zombie) -> bool: return is_instance_valid(z) and not z.is_dead())


## Fim da horda. survived: entrega a recompensa a quem está vivo.
func finish(survived: bool) -> void:
	if not active:
		return
	active = false
	_pending.clear()
	for z in _members:
		if is_instance_valid(z):
			z.horde = false
	_members.clear()
	remaining = 0
	if survived:
		var reward := reward_for(number)
		for p in _living_players():
			var inventory := p.get_node(^"Inventory") as Inventory
			for id: String in reward:
				inventory.grant(id, int(reward[id]))
	_announce_end(number, survived)
	if Network.is_online():
		_announce_end.rpc(number, survived)
	_broadcast()


## Recompensa por jogador vivo (GDD 11: itens raros).
func reward_for(n: int) -> Dictionary:
	var out := {"refine_stone": 2 + 2 * n, "refine_stone_uncommon": n, "arcane_crystal": n, "arrow": 10, "ammo_9mm": 6 * n, "medkit_basic": 1}
	if n >= 2:
		out["refine_stone_rare"] = n / 2
	if n >= 4:
		out["refine_stone_epic"] = n / 4
	return out


func _living_players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		var h := Health.find_in(p)
		if h and not h.is_dead:
			out.append(p)
	return out


func _alive_members() -> int:
	var count := 0
	for z in _members:
		if is_instance_valid(z) and not z.is_dead():
			count += 1
	return count


## Centro da base (média das peças de construção) ou dos jogadores.
func _base_center() -> Vector3:
	var points: Array = []
	for piece in Structures.pieces():
		points.append(piece.global_position)
	if points.is_empty():
		for p in _living_players():
			points.append(p.global_position)
	if points.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for v: Vector3 in points:
		sum += v
	return sum / points.size()


# --- Rede e aviso -----------------------------------------------------------------------

func _broadcast() -> void:
	if Network.is_online():
		_sync_status.rpc(active, number, remaining)


@rpc("authority", "call_remote", "reliable")
func _sync_status(is_active: bool, horde_number: int, left: int) -> void:
	active = is_active
	number = horde_number
	remaining = left


@rpc("authority", "call_remote", "reliable")
func _announce_start(horde_number: int) -> void:
	number = horde_number
	active = true
	EventBus.horde_started.emit(horde_number)


@rpc("authority", "call_remote", "reliable")
func _announce_end(horde_number: int, survived: bool) -> void:
	active = false
	EventBus.horde_ended.emit(horde_number, survived)


## Céu avermelhado: da tarde do dia da horda até o amanhecer, ou enquanto ela durar.
func _update_sky() -> void:
	var dn := DayNight.find(get_tree())
	if dn == null:
		return
	var target := 0.0
	if active:
		target = 1.0
	elif is_horde_day(dn.day) and dn.hour >= RED_SKY_FROM:
		target = clampf((dn.hour - RED_SKY_FROM) / (DayNight.NIGHT_START - RED_SKY_FROM), 0.0, 1.0)
	dn.red_sky = move_toward(dn.red_sky, target, get_process_delta_time() * 0.2)
