class_name Progression
extends Node
## Progressão do personagem (GDD 4.1 e 12), no jogador (nó "Progression").
## - Proficiências (data/proficiencies): sobem pelo uso, nível 1 a 100. Cada nível dá
##   os "effects" do JSON (fração por nível; chaves terminadas em "_add" somam).
## - Nível do personagem: XP de abates, coleta, construção, fabricação (e um pouco de
##   toda XP de proficiência). Cada nível dá 1 ponto de habilidade (trilhas, GDD 4.2).
## - Maestria de arma: usar um tipo de arma (arco, melee, feitiço, arremesso) dá
##   até +10% de dano com ele.
## Todos os bônus viram modificadores por chave ("melee.damage", "move_speed"...), que
## os sistemas consultam com mult()/apply(). Roda na máquina do dono do personagem;
## o que o servidor precisa (redução de dano) vai para o Health por RPC.

signal changed
## Aviso de subida de nível ("Melee subiu para o nível 5").
signal leveled(text: String)
## Um ataque deste jogador acertou um inimigo (marca de acerto na mira). surprise: ataque surpresa.
signal hit_confirmed(surprise: bool)

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
## Usos por tipo de arma ("bow", "melee", "spell", "thrown").
var mastery_uses := {}
## Habilidades mágicas aprendidas (grimórios): id → nível (1 a MAX_SPELL_LEVEL).
var spells := {}
## Última habilidade conjurada (Q rápido conjura ela).
var last_spell := ""

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


# --- Atributos derivados (painel de status e sistemas) --------------------------------
## Redução de recarga (itens), velocidade de ataque (itens: 100% no golpe/arremesso,
## 20% na puxada do arco), resistência a magia (itens) e capacidade de carga.

const MAX_COOLDOWN_REDUCTION := 0.5
const MAX_SPELL_RESIST := 0.75
const BOW_ATTACK_SPEED_SHARE := 0.2


static func cooldown_reduction(node: Node) -> float:
	var prog := of(node)
	return clampf(prog.add("cooldown_reduction"), 0.0, MAX_COOLDOWN_REDUCTION) if prog else 0.0


static func attack_speed(node: Node) -> float:
	var prog := of(node)
	return maxf(prog.add("attack_speed"), -0.5) if prog else 0.0


static func spell_resist(node: Node) -> float:
	var prog := of(node)
	return clampf(prog.add("spell_resist"), 0.0, MAX_SPELL_RESIST) if prog else 0.0


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
			leveled.emit(tr("%s subiu para o nível %d") % [GameData.get_entry("proficiencies", prof).get("name", prof), level])
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
		leveled.emit(tr("Nível %d! +1 ponto de habilidade (P)") % char_level)
	if emit:
		changed.emit()


func use_weapon(weapon_type: String) -> void:
	if not is_multiplayer_authority():
		return
	var before := mastery_level(weapon_type)
	mastery_uses[weapon_type] = int(mastery_uses.get(weapon_type, 0)) + 1
	if mastery_level(weapon_type) > before:
		leveled.emit(tr("Maestria de %s: nível %d") % [mastery_name(weapon_type), mastery_level(weapon_type)])
		changed.emit()


# --- Habilidades (trilhas, GDD 4.2) ------------------------------------------------

const TRAIL_NAMES := {"shooter": "Arqueiro", "warrior": "Guerreiro", "arcane": "Arcano", "survivor": "Sobrevivente", "brawler": "Pugilista"}


## Por que não dá para aprender ("" = dá).
func learn_block_reason(skill_id: String) -> String:
	var data := GameData.get_entry("skills", skill_id)
	if data.is_empty():
		return tr("Habilidade desconhecida")
	if skills.has(skill_id):
		return tr("Já aprendida")
	var req: Dictionary = data.get("requires", {})
	for prof: String in req:
		if get_level(prof) < int(req[prof]):
			return tr("Precisa de %s nível %d") % [GameData.get_entry("proficiencies", prof).get("name", prof), int(req[prof])]
	if skill_points < int(data.get("cost", 1)):
		return tr("Faltam pontos")
	return ""


func learn(skill_id: String) -> bool:
	if learn_block_reason(skill_id) != "":
		return false
	skill_points -= int(GameData.get_entry("skills", skill_id).get("cost", 1))
	skills[skill_id] = true
	_rebuild()
	leveled.emit(tr("Aprendeu: %s") % GameData.get_entry("skills", skill_id).get("name", skill_id))
	changed.emit()
	return true


## Passado (GDD 4.4): níveis iniciais mais altos. Os itens o Player entrega.
func apply_background(background_id: String) -> void:
	var bonus: Dictionary = GameData.get_entry("backgrounds", background_id).get("bonus", {})
	for prof: String in bonus:
		if levels.has(prof):
			levels[prof] = clampi(get_level(prof) + int(bonus[prof]), 1, MAX_LEVEL)
	# Vocação que já sabe magia (Mago): habilidades iniciais.
	for spell: String in GameData.get_entry("backgrounds", background_id).get("spells", []):
		learn_spell(spell)
		last_spell = spell
	_rebuild()
	changed.emit()


# --- Habilidades mágicas (grimórios) --------------------------------------------------

const MAX_SPELL_LEVEL := 5


## Ler um grimório: aprende (nível 1) ou sobe um nível. Retorna o novo nível (0 = já no máximo).
func learn_spell(spell_id: String) -> int:
	var level := int(spells.get(spell_id, 0))
	if level >= MAX_SPELL_LEVEL:
		return 0
	spells[spell_id] = level + 1
	if last_spell == "":
		last_spell = spell_id
	changed.emit()
	return level + 1


func spell_level(spell_id: String) -> int:
	return int(spells.get(spell_id, 0))


static func mastery_name(weapon_type: String) -> String:
	return str({"bow": TranslationServer.translate("arco"), "melee": TranslationServer.translate("armas brancas"), "spell": TranslationServer.translate("feitiços"), "thrown": TranslationServer.translate("arremesso"), "unarmed": TranslationServer.translate("desarmado")}.get(weapon_type, weapon_type))


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
## caçando ninguém) dá bônus; dá XP. weapon_type: "bow", "melee", "spell", "thrown".
## Retorna o dano final.
static func on_hit(attacker: Node, target: Node, amount: float, weapon_type: String, sneak_mult := 1.0) -> float:
	var prog := of(attacker)
	if prog == null or not prog.is_multiplayer_authority():
		return amount
	var prof: String = {"bow": "firearms", "thrown": "firearms", "melee": "melee", "unarmed": "unarmed", "spell": "magic"}.get(weapon_type, "")
	if weapon_type == "spell" and target is Zombie:
		amount *= 1.0 - clampf(float(target.stats.get("magic_resist", 0.0)), 0.0, 0.9)
	if target is Zombie and not target.is_dead():
		var surprise: bool = target.state in [Zombie.State.WANDER, Zombie.State.INVESTIGATE]
		if surprise:
			amount *= 1.5 * prog.mult("sneak_damage") * sneak_mult  # adaga/faca: mais ainda
			prog.gain("stealth", 3.0)
		prog.gain(prof, 2.0)
		prog.hit_confirmed.emit(surprise)
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
	# Equipamento vestido (peças e conjuntos).
	var equipment := get_parent().get_node_or_null(^"Equipment") if get_parent() else null
	if equipment:
		var gear: Dictionary = equipment.mods()
		for key: String in gear:
			mods[key] = float(mods.get(key, 0.0)) + float(gear[key])
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
	var inventory: Inventory = player.get_node_or_null(^"Inventory")
	if inventory:
		if not has_meta(&"base_weight"):
			set_meta(&"base_weight", inventory.max_weight)
		inventory.max_weight = float(get_meta(&"base_weight")) + add("carry_weight_add")
	var health := Health.find_in(player)
	if health and is_multiplayer_authority():
		health.set_damage_taken_multiplier(mult("damage_taken"), 1.0 - spell_resist(player))
	# Aumento de loot: os drops são sorteados no servidor, que precisa saber o bônus.
	if is_multiplayer_authority():
		var loot := clampf(add("loot_bonus"), 0.0, 2.0)
		if multiplayer.is_server():
			server_loot_bonus = loot
		elif Network.is_online():
			_report_loot_bonus.rpc_id(1, loot)


## Servidor: aumento de loot do dono deste personagem (ver _drop_loot do zumbi).
var server_loot_bonus := 0.0


@rpc("any_peer", "call_remote", "reliable")
func _report_loot_bonus(value: float) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_loot_bonus = clampf(value, 0.0, 2.0)
