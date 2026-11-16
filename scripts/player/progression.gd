class_name Progression
extends Node
## Progressão do personagem (GDD 4.1 e 12), no jogador (nó "Progression").
## - Proficiências (data/proficiencies): sobem pelo uso, nível 1 a 100. Cada nível dá
##   os "effects" do JSON (fração por nível; chaves terminadas em "_add" somam).
## - Nível do personagem: XP de abates, coleta, construção, fabricação (e um pouco de
##   toda XP de proficiência). Cada nível dá 1 ponto de habilidade (trilhas, GDD 4.2).
## - Maestria de arma: usar um tipo de arma (arco, arma de fogo, melee, feitiço) dá
##   até +10% de dano com ele.
## Todos os bônus viram modificadores por chave ("melee.damage", "move_speed"...), que
## os sistemas consultam com mult()/apply(). Roda na máquina do dono do personagem;
## o que o servidor precisa (redução de dano) vai para o Health por RPC.

signal changed
## Aviso de subida de nível ("Melee subiu para o nível 5").
signal leveled(text: String)

const MAX_LEVEL := 100
const MAX_MASTERY := 10
## XP por minuto de cada proficiência acima da qual o ganho cai para SOFT_CAP_FACTOR
## (evita subir pulando em loop, GDD 4.1).
const SOFT_CAP_PER_MINUTE := 60.0
const SOFT_CAP_FACTOR := 0.2
## Fração da XP de proficiência que também vai para o nível do personagem.
const CHAR_SHARE := 0.5

var levels := {}   # proficiência → nível
var xp := {}       # proficiência → XP rumo ao próximo nível
var char_level := 1
var char_xp := 0.0
var skill_points := 0
## Habilidades aprendidas (trilhas, GDD 4.2): id → true.
var skills := {}
## Usos por tipo de arma ("bow", "firearm", "melee", "spell").
var mastery_uses := {}

var _mods := {}
var _recent := {}  # proficiência → [início da janela (s), XP na janela]


static func of(node: Node) -> Progression:
	return node.get_node_or_null(^"Progression") as Progression if node else null


func _ready() -> void:
	for id: String in GameData.get_all("proficiencies"):
		levels[id] = 1
		xp[id] = 0.0
	_rebuild()


# --- Consulta ------------------------------------------------------------------------

func get_level(prof: String) -> int:
	return int(levels.get(prof, 1))


## Multiplicador da chave (1 = sem bônus).
func mult(key: String) -> float:
	return maxf(1.0 + float(_mods.get(key, 0.0)), 0.25)


## Soma da chave (chaves "_add").
func add(key: String) -> float:
	return float(_mods.get(key, 0.0))


func apply(key: String, value: float) -> float:
	return value * mult(key)


## Nível de maestria de um tipo de arma (0 a 10): raiz dos usos / 3.
func mastery_level(weapon_type: String) -> int:
	return mini(int(sqrt(float(mastery_uses.get(weapon_type, 0)) / 3.0)), MAX_MASTERY)


func mastery_mult(weapon_type: String) -> float:
	return 1.0 + 0.01 * mastery_level(weapon_type)


static func xp_to_next(level: int) -> float:
	return 10.0 * pow(float(level), 1.4)


static func char_xp_to_next(level: int) -> float:
	return 60.0 * pow(float(level), 1.5)


# --- Ganho --------------------------------------------------------------------------

## XP de proficiência (e um pouco para o personagem). Só no dono.
func gain(prof: String, amount: float) -> void:
	if amount <= 0.0 or not levels.has(prof) or not is_multiplayer_authority():
		return
	amount = _soft_cap(prof, amount)
	var level := get_level(prof)
	if level < MAX_LEVEL:
		xp[prof] = float(xp[prof]) + amount
		while level < MAX_LEVEL and float(xp[prof]) >= xp_to_next(level):
			xp[prof] = float(xp[prof]) - xp_to_next(level)
			level += 1
			levels[prof] = level
			leveled.emit("%s subiu para o nível %d" % [GameData.get_entry("proficiencies", prof).get("name", prof), level])
		_rebuild()
	gain_character(amount * CHAR_SHARE, false)
	changed.emit()


## XP do personagem (abates, horda...). Cada nível dá 1 ponto de habilidade.
func gain_character(amount: float, emit := true) -> void:
	if amount <= 0.0 or not is_multiplayer_authority():
		return
	char_xp += amount
	while char_xp >= char_xp_to_next(char_level):
		char_xp -= char_xp_to_next(char_level)
		char_level += 1
		skill_points += 1
		leveled.emit("Nível %d! +1 ponto de habilidade (P)" % char_level)
	if emit:
		changed.emit()


func use_weapon(weapon_type: String) -> void:
	if not is_multiplayer_authority():
		return
	var before := mastery_level(weapon_type)
	mastery_uses[weapon_type] = int(mastery_uses.get(weapon_type, 0)) + 1
	if mastery_level(weapon_type) > before:
		leveled.emit("Maestria de %s: nível %d" % [mastery_name(weapon_type), mastery_level(weapon_type)])
		changed.emit()


# --- Habilidades (trilhas, GDD 4.2) ------------------------------------------------

const TRAIL_NAMES := {"shooter": "Atirador", "warrior": "Guerreiro", "arcane": "Arcano", "survivor": "Sobrevivente"}


## Por que não dá para aprender ("" = dá).
func learn_block_reason(skill_id: String) -> String:
	var data := GameData.get_entry("skills", skill_id)
	if data.is_empty():
		return "Habilidade desconhecida"
	if skills.has(skill_id):
		return "Já aprendida"
	var req: Dictionary = data.get("requires", {})
	for prof: String in req:
		if get_level(prof) < int(req[prof]):
			return "Precisa de %s nível %d" % [GameData.get_entry("proficiencies", prof).get("name", prof), int(req[prof])]
	if skill_points < int(data.get("cost", 1)):
		return "Faltam pontos"
	return ""


func learn(skill_id: String) -> bool:
	if learn_block_reason(skill_id) != "":
		return false
	skill_points -= int(GameData.get_entry("skills", skill_id).get("cost", 1))
	skills[skill_id] = true
	_rebuild()
	leveled.emit("Aprendeu: %s" % GameData.get_entry("skills", skill_id).get("name", skill_id))
	changed.emit()
	return true


static func mastery_name(weapon_type: String) -> String:
	return {"bow": "arco", "firearm": "armas de fogo", "melee": "armas brancas", "spell": "feitiços"}.get(weapon_type, weapon_type)


## Abate (vem do servidor): XP do personagem.
@rpc("any_peer", "call_remote", "reliable")
func award_kill(amount: float) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	gain_character(amount)


## Servidor: manda a XP do abate para o dono deste personagem.
func send_kill_xp(amount: float) -> void:
	if is_multiplayer_authority():
		gain_character(amount)
	else:
		award_kill.rpc_id(get_multiplayer_authority(), amount)


## Morte (DeathPenalty): perde parte da XP acumulada rumo aos próximos níveis.
func lose_xp_fraction(fraction: float) -> void:
	char_xp *= 1.0 - fraction
	for prof: String in xp:
		xp[prof] = float(xp[prof]) * (1.0 - fraction)
	changed.emit()


func _soft_cap(prof: String, amount: float) -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var window: Array = _recent.get(prof, [now, 0.0])
	if now - float(window[0]) > 60.0:
		window = [now, 0.0]
	var used := float(window[1])
	var full := clampf(SOFT_CAP_PER_MINUTE - used, 0.0, amount)
	var result := full + (amount - full) * SOFT_CAP_FACTOR
	window[1] = used + amount
	_recent[prof] = window
	return result


# --- Ganchos de combate -------------------------------------------------------------

## Antes de aplicar dano de um ataque do jogador: ataque surpresa (alvo que não está
## caçando ninguém) dá bônus; dá XP. weapon_type: "bow", "firearm", "melee", "spell".
## Retorna o dano final.
static func on_hit(attacker: Node, target: Node, amount: float, weapon_type: String) -> float:
	var prog := of(attacker)
	if prog == null or not prog.is_multiplayer_authority():
		return amount
	var prof: String = {"bow": "firearms", "firearm": "firearms", "melee": "melee", "spell": "magic"}.get(weapon_type, "")
	if target is Zombie and not target.is_dead():
		if target.state in [Zombie.State.WANDER, Zombie.State.INVESTIGATE]:
			amount *= 1.5 * prog.mult("sneak_damage")
			prog.gain("stealth", 3.0)
		prog.gain(prof, 2.0)
	return amount


# --- Modificadores ------------------------------------------------------------------

func _rebuild() -> void:
	var mods := {}
	for prof: String in levels:
		var effects: Dictionary = GameData.get_entry("proficiencies", prof).get("effects", {})
		for key: String in effects:
			mods[key] = float(mods.get(key, 0.0)) + float(effects[key]) * (get_level(prof) - 1)
	for skill_id: String in skills:
		var effects: Dictionary = GameData.get_entry("skills", skill_id).get("effects", {})
		for key: String in effects:
			mods[key] = float(mods.get(key, 0.0)) + float(effects[key])
	_mods = mods
	_apply_to_player()


## Bônus que não são consultados na hora: mana máxima e redução de dano (servidor).
func _apply_to_player() -> void:
	var player := get_parent()
	if player == null:
		return
	var mana: StatPool = player.get_node_or_null(^"Mana")
	if mana:
		if not has_meta(&"base_mana"):
			set_meta(&"base_mana", mana.max_value)
		mana.max_value = float(get_meta(&"base_mana")) + add("max_mana_add")
		mana.changed.emit(mana.current, mana.max_value)
	var stamina: StatPool = player.get_node_or_null(^"Stamina")
	if stamina:
		if not has_meta(&"base_stamina"):
			set_meta(&"base_stamina", stamina.max_value)
		stamina.max_value = float(get_meta(&"base_stamina")) + add("max_stamina_add")
	var health := Health.find_in(player)
	if health and is_multiplayer_authority():
		health.set_damage_taken_multiplier(mult("damage_taken"))
