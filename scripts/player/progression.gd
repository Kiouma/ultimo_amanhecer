class_name Progression
extends Node
## Progressão do personagem (GDD 4.1 e 12), no jogador (nó "Progression").
## - Proficiências (data/proficiencies): sobem pelo uso, nível 1 a 100. Cada nível dá
##   os "effects" do JSON (fração por nível; chaves terminadas em "_add" somam).
## - Nível do personagem (1 a 100): XP de abates, coleta, construção, fabricação (e um
##   pouco de toda XP de proficiência). Cada nível dá 1 ponto passivo (GDD 4.2).
## - Árvore passiva (data/passives): a classe só define o nó de início; aloca-se um nó
##   ligado a outro já alocado. Botão direito devolve o ponto (se não desligar outros).
## - Ascendência (data/ascendancies): no nível 30 escolhe-se uma das 2 da classe; dá um
##   bônus fixo e pontos de ascendência (níveis 30, 45, 60 e 75) para os nós dela.
## - Auras (nó Auras): os bônus recebidos de auras próximas entram como modificadores.
## - Atributos: 5 pontos por nível para Força, Destreza, Inteligência e Sorte (livres para
##   tirar e pôr). A árvore e os itens somam ("str_add"...). Cada ponto vira modificadores
##   (ATTRIBUTE_EFFECTS): Força = vida, regeneração de vida e dano com armas pesadas;
##   Inteligência = mana máxima e escudo de energia; Destreza = velocidade de movimento,
##   regeneração de stamina e dano com armas leves; Sorte = aumento de loot.
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
const MAX_CHAR_LEVEL := 100
## Nível em que a ascendência é escolhida e níveis que dão pontos de ascendência.
const ASCENDANCY_LEVEL := 30
const ASCENDANCY_POINT_LEVELS := [30, 45, 60, 75]
## Atributos (ordem da tela) e o que cada ponto dá.
const ATTRIBUTES := ["str", "dex", "int", "luck"]
const ATTRIBUTE_NAMES := {"str": "Força", "dex": "Destreza", "int": "Inteligência", "luck": "Sorte"}
const ATTRIBUTE_POINTS_PER_LEVEL := 5
const ATTRIBUTE_EFFECTS := {
	"str": {"max_health_add": 1.0, "life_regen_add": 0.01, "heavy.damage": 0.002},
	"dex": {"move_speed": 0.0005, "stamina_regen": 0.003, "light.damage": 0.002},
	"int": {"max_mana_add": 1.0, "energy_shield_add": 1.0},
	"luck": {"loot_bonus": 0.001},
}
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
## Classe (id de data/backgrounds): define o nó de início da árvore passiva.
var char_class := ""
## Nós da árvore passiva alocados: id → true (o nó de início não entra).
var passives := {}
## Ascendência escolhida ("" = nenhuma) e nós dela desbloqueados (id → true).
var ascendancy := ""
var asc_nodes := {}
## Pontos de atributo distribuídos: "str", "dex", "int", "luck" → pontos.
var attributes := {"str": 0, "dex": 0, "int": 0, "luck": 0}
## Pontos passivos livres: 1 por nível acima do 1, menos os nós alocados.
var skill_points: int:
	get:
		return maxi(char_level - 1 - passives.size(), 0)
## Usos por tipo de arma ("bow", "melee", "spell", "thrown").
var mastery_uses := {}
## Habilidades mágicas aprendidas (grimórios): id → nível (1 a MAX_SPELL_LEVEL).
var spells := {}
## Última habilidade conjurada (Q rápido conjura ela).
var last_spell := ""

var _mods := {}
## Bônus de auras recebidos agora (o nó Auras calcula pela distância dos aliados).
var _aura_mods := {}
## Atributos vindos da árvore e dos itens (calculado no _rebuild).
var _attr_bonus := {}
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


## XP do personagem (abates, horda...). Cada nível dá 1 ponto passivo.
func gain_character(amount: float, emit := true) -> void:
	if amount <= 0.0 or not is_multiplayer_authority() or char_level >= MAX_CHAR_LEVEL:
		return
	char_xp += amount
	while char_level < MAX_CHAR_LEVEL and char_xp >= char_xp_to_next(char_level):
		char_xp -= char_xp_to_next(char_level)
		_on_level_up()
	if char_level >= MAX_CHAR_LEVEL:
		char_xp = 0.0
	if emit:
		changed.emit()


func _on_level_up() -> void:
	char_level += 1
	leveled.emit(tr("Nível %d! +1 ponto passivo e +%d de atributo (P)") % [char_level, ATTRIBUTE_POINTS_PER_LEVEL])
	if char_level == ASCENDANCY_LEVEL:
		leveled.emit(tr("Ascendência liberada! Escolha a sua em Personagem (P)"))
	elif char_level in ASCENDANCY_POINT_LEVELS:
		leveled.emit(tr("+1 ponto de ascendência (P)"))


func use_weapon(weapon_type: String) -> void:
	if not is_multiplayer_authority():
		return
	var before := mastery_level(weapon_type)
	mastery_uses[weapon_type] = int(mastery_uses.get(weapon_type, 0)) + 1
	if mastery_level(weapon_type) > before:
		leveled.emit(tr("Maestria de %s: nível %d") % [mastery_name(weapon_type), mastery_level(weapon_type)])
		changed.emit()


# --- Atributos -----------------------------------------------------------------------

## Pontos de atributo ainda livres.
func attribute_points() -> int:
	var spent := 0
	for key: String in attributes:
		spent += int(attributes[key])
	return maxi(ATTRIBUTE_POINTS_PER_LEVEL * (char_level - 1) - spent, 0)


## Põe (amount > 0) ou tira (amount < 0) pontos de um atributo. Retorna quanto mudou.
func spend_attribute(key: String, amount: int) -> int:
	if key not in ATTRIBUTES or amount == 0:
		return 0
	var current := int(attributes.get(key, 0))
	var change := mini(amount, attribute_points()) if amount > 0 else maxi(amount, -current)
	if change == 0:
		return 0
	attributes[key] = current + change
	_rebuild()
	changed.emit()
	return change


## Total do atributo: pontos distribuídos + árvore + itens ("str_add"...).
func attribute_total(key: String) -> int:
	return int(attributes.get(key, 0)) + roundi(float(_attr_bonus.get(key, 0.0)))


## Só os pontos que vêm da árvore e dos itens.
func attribute_bonus(key: String) -> int:
	return roundi(float(_attr_bonus.get(key, 0.0)))


## Tira pontos a mais (save de outra versão, nível que caiu...).
func validate_attributes() -> void:
	for key: String in ATTRIBUTES:
		attributes[key] = maxi(int(attributes.get(key, 0)), 0)
	var budget := ATTRIBUTE_POINTS_PER_LEVEL * (char_level - 1)
	var spent := 0
	for key: String in ATTRIBUTES:
		spent += int(attributes[key])
	if spent > budget:
		for key: String in ATTRIBUTES:
			attributes[key] = 0


# --- Árvore passiva (GDD 4.2) --------------------------------------------------------

## Nó de início da classe (o de data/backgrounds; classe desconhecida: o da primeira).
func start_node() -> String:
	var start := str(GameData.get_entry("backgrounds", char_class).get("tree_start", ""))
	if start != "" and not PassiveTree.node(start).is_empty():
		return start
	for id: String in GameData.get_all("backgrounds"):
		start = str(GameData.get_entry("backgrounds", id).get("tree_start", ""))
		if start != "":
			return start
	return ""


func is_allocated(id: String) -> bool:
	return passives.has(id) or id == start_node()


## Por que não dá para alocar ("" = dá).
func allocate_block_reason(id: String) -> String:
	var data := PassiveTree.node(id)
	if data.is_empty():
		return tr("Nó desconhecido")
	if is_allocated(id):
		return tr("Já alocado")
	if str(data.get("kind", "")) == "start":
		return tr("Início de outra classe")
	if skill_points <= 0:
		return tr("Sem pontos passivos")
	for other: String in PassiveTree.neighbors(id):
		if is_allocated(other):
			return ""
	return tr("Precisa estar ligado a um nó alocado")


func allocate(id: String) -> bool:
	if allocate_block_reason(id) != "":
		return false
	passives[id] = true
	_rebuild()
	changed.emit()
	return true


## Por que não dá para devolver ("" = dá): não pode deixar nós soltos da árvore.
func refund_block_reason(id: String) -> String:
	if not passives.has(id):
		return tr("Não alocado")
	var rest := passives.duplicate()
	rest.erase(id)
	if PassiveTree.connected_from(start_node(), rest).size() - 1 < rest.size():
		return tr("Outros nós dependem deste")
	return ""


func refund(id: String) -> bool:
	if refund_block_reason(id) != "":
		return false
	passives.erase(id)
	_rebuild()
	changed.emit()
	return true


## Devolve todos os pontos passivos.
func reset_passives() -> void:
	passives.clear()
	_rebuild()
	changed.emit()


## Tira nós que não existem mais ou ficaram soltos (dados mudaram, save antigo).
func validate_passives() -> void:
	var valid := {}
	for id: String in passives:
		var data := PassiveTree.node(id)
		if not data.is_empty() and str(data.get("kind", "")) != "start":
			valid[id] = true
	var connected := PassiveTree.connected_from(start_node(), valid)
	passives = {}
	for id: String in valid:
		if connected.has(id):
			passives[id] = true
	if passives.size() > maxi(char_level - 1, 0):
		passives.clear()  # mais nós que pontos (save inconsistente): devolve tudo


# --- Ascendência ----------------------------------------------------------------------

## Ascendências da classe deste personagem.
func ascendancy_options() -> Array:
	var out: Array = []
	for id: String in GameData.get_all("ascendancies"):
		if str(GameData.get_entry("ascendancies", id).get("class", "")) == char_class:
			out.append(id)
	return out


func ascendancy_points_total() -> int:
	var total := 0
	for level: int in ASCENDANCY_POINT_LEVELS:
		if char_level >= level:
			total += 1
	return total


func ascendancy_points() -> int:
	return maxi(ascendancy_points_total() - asc_nodes.size(), 0) if ascendancy != "" else 0


func choose_block_reason(asc_id: String) -> String:
	if ascendancy != "":
		return tr("Ascendência já escolhida")
	if char_level < ASCENDANCY_LEVEL:
		return tr("Disponível no nível %d") % ASCENDANCY_LEVEL
	if asc_id not in ascendancy_options():
		return tr("Não é da sua classe")
	return ""


func choose_ascendancy(asc_id: String) -> bool:
	if choose_block_reason(asc_id) != "":
		return false
	ascendancy = asc_id
	asc_nodes.clear()
	_rebuild()
	leveled.emit(tr("Ascendência: %s") % GameData.get_entry("ascendancies", asc_id).get("name", asc_id))
	changed.emit()
	return true


## Nó da ascendência escolhida ({} se não for dela).
func ascendancy_node(node_id: String) -> Dictionary:
	for n: Dictionary in GameData.get_entry("ascendancies", ascendancy).get("nodes", []):
		if str(n.get("id", "")) == node_id:
			return n
	return {}


## Auras liberadas pelos nós de ascendência desbloqueados ("unlocks_aura").
func unlocked_auras() -> Array:
	var out: Array = []
	for node_id: String in asc_nodes:
		var aura := str(ascendancy_node(node_id).get("unlocks_aura", ""))
		if aura != "":
			out.append(aura)
	return out


func unlock_asc_node(node_id: String) -> bool:
	if ascendancy_node(node_id).is_empty() or asc_nodes.has(node_id) or ascendancy_points() <= 0:
		return false
	asc_nodes[node_id] = true
	_rebuild()
	changed.emit()
	return true


# --- Classe ---------------------------------------------------------------------------

## Classe escolhida no menu: define só o início da árvore passiva. O Mago já conhece a
## habilidade inicial (sem ela não teria o que conjurar). Os itens o Player entrega.
func apply_background(background_id: String) -> void:
	char_class = background_id
	for spell: String in GameData.get_entry("backgrounds", background_id).get("spells", []):
		learn_spell(spell)
		last_spell = spell
	_rebuild()
	changed.emit()


## Auras: bônus recebidos agora (o nó Auras chama quando mudam).
func set_aura_mods(mods: Dictionary) -> void:
	if mods == _aura_mods:
		return
	_aura_mods = mods
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
	var sources: Array = []  # dicionários de efeitos que somam
	for id: String in passives:
		sources.append(PassiveTree.node(id).get("effects", {}))
	if ascendancy != "":
		sources.append(GameData.get_entry("ascendancies", ascendancy).get("effects", {}))
		for node_id: String in asc_nodes:
			sources.append(ascendancy_node(node_id).get("effects", {}))
	sources.append(_aura_mods)
	for effects: Dictionary in sources:
		for key: String in effects:
			mods[key] = float(mods.get(key, 0.0)) + float(effects[key])
	# Equipamento vestido (peças e conjuntos).
	var equipment := get_parent().get_node_or_null(^"Equipment") if get_parent() else null
	if equipment:
		var gear: Dictionary = equipment.mods()
		for key: String in gear:
			mods[key] = float(mods.get(key, 0.0)) + float(gear[key])
	# Atributos: pontos distribuídos + "str_add" etc. (árvore, itens); cada ponto vira
	# os modificadores de ATTRIBUTE_EFFECTS.
	_attr_bonus = {}
	for key: String in ATTRIBUTES:
		_attr_bonus[key] = float(mods.get(key + "_add", 0.0))
		var total := float(attributes.get(key, 0)) + float(_attr_bonus[key])
		var per: Dictionary = ATTRIBUTE_EFFECTS[key]
		for mod: String in per:
			mods[mod] = float(mods.get(mod, 0.0)) + float(per[mod]) * total
	_mods = mods
	_apply_to_player()


## Bônus que não são consultados na hora: mana máxima e redução de dano (servidor).
func _apply_to_player() -> void:
	var player := get_parent()
	if player == null:
		return
	var auras := player.get_node_or_null(^"Auras") as Auras
	var mana: StatPool = player.get_node_or_null(^"Mana")
	if mana:
		if not has_meta(&"base_mana"):
			set_meta(&"base_mana", mana.max_value)
			set_meta(&"base_mana_regen", mana.regen_per_second)
		mana.max_value = maxf(float(get_meta(&"base_mana")) + add("max_mana_add"), 1.0)
		mana.regen_per_second = float(get_meta(&"base_mana_regen")) * mult("mana_regen")
		mana.set_reserved(auras.reserved_fraction("mana") if auras else 0.0)
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
		if not has_meta(&"base_health"):
			set_meta(&"base_health", health.max_health)
		var vitals := Vector3(float(get_meta(&"base_health")) + add("max_health_add"), auras.reserved_fraction("life") if auras else 0.0,
			maxf(add("energy_shield_add"), 0.0))
		if vitals != _sent_vitals:  # evita um RPC a cada recálculo
			_sent_vitals = vitals
			health.set_owner_vitals(vitals.x, vitals.y, vitals.z)
	# Aumento de loot: os drops são sorteados no servidor, que precisa saber o bônus.
	if is_multiplayer_authority():
		var loot := clampf(add("loot_bonus"), 0.0, 2.0)
		if multiplayer.is_server():
			server_loot_bonus = loot
		elif Network.is_online():
			_report_loot_bonus.rpc_id(1, loot)


## Servidor: aumento de loot do dono deste personagem (ver _drop_loot do zumbi).
var server_loot_bonus := 0.0
## Última vida máxima / reserva enviada ao Health.
var _sent_vitals := Vector3(-1, -1, -1)


@rpc("any_peer", "call_remote", "reliable")
func _report_loot_bonus(value: float) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		server_loot_bonus = clampf(value, 0.0, 2.0)
