class_name Auras
extends Node
## Auras (data/auras): bônus em área para os aliados próximos (e o próprio jogador),
## pagos com uma reserva de mana ou de vida enquanto ficam ligadas. Nó "Auras" do Player.
##
## - Cada aura tem a reserva escolhida pelo jogador (1% a 35% do recurso): o efeito
##   cresce na mesma proporção ("effects" do JSON são por 1% reservado).
## - Nível (1 a MAX_LEVEL): sobe com o tempo ligada COM A RESERVA NO MÁXIMO (35%); com
##   menos, os segundos não contam. Cada nível dá +LEVEL_BONUS de efeito.
## - Efeito e raio crescem com "aura_effect" e "aura_radius".
## - Reserva (reservations()), nesta ordem:
##   1. soma bruta das % das auras de mana ligadas;
##   2. conversor (Pacto de Sangue, "kind": "converter"): de 0% a 50% dessa soma vai
##      para a vida; ele também tem custo próprio ("cost", % de vida);
##   3. "mana_reservation_efficiency" reduz só a parte que ficou em mana;
##   4. "life_reservation_efficiency" reduz só a parte em vida (convertida + custo).
##   Cada recurso vai até MAX_RESERVED.
## - Auras com "unlock": "ascendancy" só abrem por um nó de ascendência ("unlocks_aura").
## - A mesma aura de dois jogadores não soma: vale a mais forte. Conversores não são
##   bônus em área: não vão para net_auras.
##
## Rede: o dono escreve as auras ligadas em Player.net_auras ("id,força,raio;...") e o
## MultiplayerSynchronizer espalha. Cada máquina calcula só o que o SEU jogador recebe.

signal changed

const MIN_PERCENT := 1
const MAX_PERCENT := 35
const DEFAULT_PERCENT := 20
## Conversor: fração da reserva de mana que vai para a vida (0% a 50%).
const MAX_CONVERSION := 50
const DEFAULT_CONVERSION := 25
const MAX_EFFICIENCY := 0.6
const MAX_RESERVED := 1.0
const MAX_LEVEL := 20
const LEVEL_BONUS := 0.04
const BASE_RADIUS := 12.0
## Raio máximo aceito de outro jogador (proteção contra valores absurdos).
const MAX_NET_RADIUS := 40.0
const MAX_NET_STRENGTH := 100.0
const TICK := 0.5

## Reserva escolhida por aura (mesmo desligada): id → % (1 a 35).
var percent := {}
## Auras ligadas: id → true.
var active := {}
## Nível e XP (segundos ligada rumo ao próximo nível) por aura.
var levels := {}
var xp := {}

var _player: Player
var _timer := 0.0
var _parsed_cache := {}  # texto de net_auras → lista decodificada
var _ring: MeshInstance3D
var _ring_text := "-"


func _ready() -> void:
	_player = get_parent() as Player
	_build_ring()


static func of(node: Node) -> Auras:
	return node.get_node_or_null(^"Auras") as Auras if node else null


# --- Consulta ------------------------------------------------------------------------

func data(id: String) -> Dictionary:
	return GameData.get_entry("auras", id)


func level(id: String) -> int:
	return clampi(int(levels.get(id, 1)), 1, MAX_LEVEL)


func is_converter(id: String) -> bool:
	return str(data(id).get("kind", "")) == "converter"


## Limites da barra: auras 1% a 35%; conversor 0% a 50%.
func percent_range(id: String) -> Vector2i:
	return Vector2i(0, MAX_CONVERSION) if is_converter(id) else Vector2i(MIN_PERCENT, MAX_PERCENT)


func get_percent(id: String) -> int:
	var r := percent_range(id)
	var fallback := DEFAULT_CONVERSION if is_converter(id) else DEFAULT_PERCENT
	return clampi(int(percent.get(id, fallback)), r.x, r.y)


func is_active(id: String) -> bool:
	return active.has(id)


func is_unlocked(id: String) -> bool:
	if _player == null:
		return false
	if str(data(id).get("unlock", "")) == "ascendancy":
		return id in _player.progression.unlocked_auras()
	return _player.progression.char_level >= int(data(id).get("unlock_level", 1))


## Texto de por que está bloqueada ("" = liberada).
func lock_reason(id: String) -> String:
	if is_unlocked(id):
		return ""
	if str(data(id).get("unlock", "")) == "ascendancy":
		return tr("Liberada por um nó de ascendência (%s)") % ", ".join(_unlocking_ascendancies(id))
	return tr("Disponível no nível %d") % int(data(id).get("unlock_level", 1))


func _unlocking_ascendancies(id: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for asc_id: String in GameData.get_all("ascendancies"):
		for n: Dictionary in GameData.get_entry("ascendancies", asc_id).get("nodes", []):
			if str(n.get("unlocks_aura", "")) == id:
				names.append(str(GameData.get_entry("ascendancies", asc_id).get("name", asc_id)))
	return names


static func xp_to_next(lvl: int) -> float:
	return 90.0 * pow(float(lvl), 1.3)


func _efficiency(key: String) -> float:
	return clampf(_player.progression.add(key), 0.0, MAX_EFFICIENCY) if _player else 0.0


## Reserva (frações, sem o limite) com um conjunto de auras ligadas e as % dadas:
## {"mana": x, "life": y}. Ordem: conversão, depois eficiência de cada recurso.
func reservations(on: Variant = null, pcts: Dictionary = {}) -> Dictionary:
	if on == null:
		on = active
	var gross_mana := 0.0
	var gross_life := 0.0
	var conversion := 0.0
	for id: String in on:
		var pct := float(pcts.get(id, get_percent(id))) / 100.0
		if is_converter(id):
			conversion = clampf(pct, 0.0, MAX_CONVERSION / 100.0)
			gross_life += float(data(id).get("cost", 0.0)) / 100.0
		elif str(data(id).get("resource", "mana")) == "life":
			gross_life += pct
		else:
			gross_mana += pct
	var mana := gross_mana * (1.0 - conversion) * (1.0 - _efficiency("mana_reservation_efficiency"))
	var life := (gross_mana * conversion + gross_life) * (1.0 - _efficiency("life_reservation_efficiency"))
	return {"mana": mana, "life": life}


## Soma reservada de um recurso ("mana" ou "life"), 0 a MAX_RESERVED.
func reserved_fraction(resource: String) -> float:
	return minf(float(reservations().get(resource, 0.0)), MAX_RESERVED)


## Quanto esta aura reserva de verdade agora (ou se for ligada): {"mana": x, "life": y}.
## Para o conversor: o custo próprio mais a mana que ele passa para a vida.
func cost_of(id: String) -> Dictionary:
	var without := active.duplicate()
	without.erase(id)
	var with_it := active.duplicate()
	with_it[id] = true
	var a := reservations(without)
	var b := reservations(with_it)
	return {"mana": float(b.mana) - float(a.mana), "life": float(b.life) - float(a.life)}


func _fits(on: Dictionary, pcts: Dictionary = {}) -> bool:
	var r := reservations(on, pcts)
	return float(r.mana) <= MAX_RESERVED + 0.0001 and float(r.life) <= MAX_RESERVED + 0.0001


## Está ganhando tempo de nível agora: ligada e com a reserva no máximo (35%).
func levels_now(id: String) -> bool:
	return active.has(id) and not is_converter(id) and get_percent(id) >= MAX_PERCENT


## Força de uma aura ligada (multiplica os efeitos por 1%).
func strength(id: String) -> float:
	var aura_effect := _player.progression.mult("aura_effect") if _player else 1.0
	return get_percent(id) * (1.0 + LEVEL_BONUS * (level(id) - 1)) * aura_effect


func radius() -> float:
	return BASE_RADIUS * (_player.progression.mult("aura_radius") if _player else 1.0)


## Efeitos com uma força dada: {"melee.damage": 0.16, ...}.
func effects_at(id: String, power: float) -> Dictionary:
	var out := {}
	var per: Dictionary = data(id).get("effects", {})
	for key: String in per:
		out[key] = float(per[key]) * power
	return out


# --- Ações do dono ---------------------------------------------------------------------

## Liga/desliga. Retorna "" se deu certo, ou o motivo.
func toggle(id: String) -> String:
	if data(id).is_empty():
		return tr("Aura desconhecida")
	if active.has(id):
		active.erase(id)
		_apply()
		return ""
	if not is_unlocked(id):
		return lock_reason(id)
	var with_it := active.duplicate()
	with_it[id] = true
	if not _fits(with_it):
		return tr("Reserva insuficiente: diminua a % desta ou de outra aura")
	active[id] = true
	_apply()
	return ""


## Muda a reserva escolhida. Ligada, não deixa passar do que sobra do recurso.
## Retorna o valor que ficou.
func set_percent(id: String, value: int) -> int:
	var r := percent_range(id)
	value = clampi(value, r.x, r.y)
	if active.has(id):
		while value > r.x and not _fits(active, {id: value}):
			value -= 1
	percent[id] = value
	if active.has(id):
		_apply()
	else:
		changed.emit()
	return value


## Reaplica reservas e o que os outros veem (depois de carregar ou mudar a árvore).
func _apply() -> void:
	if _player == null:
		return
	_player.progression._rebuild()
	_publish()
	_refresh_received()
	changed.emit()


func _publish() -> void:
	if not _player.is_multiplayer_authority():
		return
	var parts: PackedStringArray = []
	for id: String in active:
		if is_converter(id):
			continue  # não é bônus em área
		parts.append("%s,%.2f,%.1f" % [id, strength(id), radius()])
	_player.net_auras = ";".join(parts)


# --- Laço --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _player == null:
		return
	_timer = TICK
	_update_ring()
	if not _player.is_multiplayer_authority():
		return
	_gain_xp(TICK)
	# A força muda com a árvore (aura_effect/raio): mantém o texto publicado em dia.
	_publish()
	_refresh_received()


func _gain_xp(seconds: float) -> void:
	if _player.health.is_dead:
		return
	for id: String in active:
		var lvl := level(id)
		if lvl >= MAX_LEVEL or not levels_now(id):
			continue
		xp[id] = float(xp.get(id, 0.0)) + seconds
		if float(xp[id]) >= xp_to_next(lvl):
			xp[id] = float(xp[id]) - xp_to_next(lvl)
			levels[id] = lvl + 1
			_player.notify(tr("%s subiu para o nível %d") % [data(id).get("name", id), lvl + 1])
			_publish()
			changed.emit()


## Bônus que o jogador desta máquina recebe agora (das auras de todos por perto).
func _refresh_received() -> void:
	if _player.health.is_dead:
		_player.progression.set_aura_mods({})
		return
	var best := {}  # id → força
	for p: Node in get_tree().get_nodes_in_group("player"):
		var other := p as Player
		if other == null or other.health.is_dead or other.net_auras == "":
			continue
		var dist := other.global_position.distance_to(_player.global_position)
		for entry: Array in _parse(other.net_auras):
			if dist <= float(entry[2]) and float(entry[1]) > float(best.get(entry[0], 0.0)):
				best[entry[0]] = float(entry[1])
	var mods := {}
	for id: String in best:
		var effects := effects_at(id, float(best[id]))
		for key: String in effects:
			mods[key] = float(mods.get(key, 0.0)) + float(effects[key])
	_player.progression.set_aura_mods(mods)


## Auras recebidas agora: [[id, força, nome do jogador], ...] (HUD).
func received() -> Array:
	var out: Array = []
	if _player == null:
		return out
	var best := {}
	for p: Node in get_tree().get_nodes_in_group("player"):
		var other := p as Player
		if other == null or other.health.is_dead or other.net_auras == "":
			continue
		var dist := other.global_position.distance_to(_player.global_position)
		for entry: Array in _parse(other.net_auras):
			if dist <= float(entry[2]) and float(entry[1]) > float(best.get(entry[0], [0.0])[0]):
				best[entry[0]] = [float(entry[1]), other]
	for id: String in best:
		out.append([id, best[id][0], best[id][1]])
	return out


## "id,força,raio;..." → [[id, força, raio], ...], com limites.
func _parse(text: String) -> Array:
	if _parsed_cache.has(text):
		return _parsed_cache[text]
	var out: Array = []
	for part: String in text.split(";", false):
		var bits := part.split(",")
		if bits.size() != 3 or data(bits[0]).is_empty():
			continue
		out.append([bits[0], clampf(bits[1].to_float(), 0.0, MAX_NET_STRENGTH), clampf(bits[2].to_float(), 0.0, MAX_NET_RADIUS)])
	if _parsed_cache.size() > 64:
		_parsed_cache.clear()
	_parsed_cache[text] = out
	return out


# --- Visual: anel nos pés de quem tem aura ligada (todos veem) ------------------------

func _build_ring() -> void:
	if _player == null:
		return
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.85
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.05, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.6)
	_ring.material_override = mat
	_ring.visible = false
	_player.add_child.call_deferred(_ring)


func _update_ring() -> void:
	if _ring == null or _player.net_auras == _ring_text:
		return
	_ring_text = _player.net_auras
	var entries := _parse(_ring_text)
	_ring.visible = not entries.is_empty()
	if entries.is_empty():
		return
	var color := Color.WHITE
	if entries.size() == 1:
		color = Color.from_string(str(data(entries[0][0]).get("color", "#ffffff")), Color.WHITE)
	else:
		color = Color(1.0, 0.92, 0.6)
	color.a = 0.6
	(_ring.material_override as StandardMaterial3D).albedo_color = color


# --- Salvamento ---------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"percent": percent, "active": active.keys(), "levels": levels, "xp": xp}


func from_save(d: Dictionary) -> void:
	percent = {}
	for id: String in d.get("percent", {}):
		var r := percent_range(id)
		percent[id] = clampi(int(d.percent[id]), r.x, r.y)
	levels = {}
	for id: String in d.get("levels", {}):
		levels[id] = clampi(int(d.levels[id]), 1, MAX_LEVEL)
	xp = {}
	for id: String in d.get("xp", {}):
		xp[id] = float(d.xp[id])
	active = {}
	for id: Variant in d.get("active", []):
		if not data(str(id)).is_empty() and is_unlocked(str(id)):
			active[str(id)] = true
	if not _fits(active):
		active.clear()  # dados mudaram e não cabe mais: desliga tudo
	_apply()
