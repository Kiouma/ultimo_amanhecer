class_name WeaponHolder
extends Node3D
## Fica na câmera do jogador e segue a hotbar do inventário (teclas 1-9, rodinha).
## O item do slot selecionado define o que o botão esquerdo faz:
## - arco / melee / feitiço: cria (uma vez) e mostra a arma;
## - consumível (poção, comida): usa e gasta um;
## - outro item ou vazio: mãos livres.
## Q conjura a última habilidade sem trocar de slot.

signal changed

## Mãos livres: soco fraco que também coleta (mal) madeira.
const FISTS := {
	"id": "", "name": "Mãos livres", "type": "unarmed", "damage": 8, "stamina_cost": 5,
	"range": 1.7, "attack_time": 0.45, "hit_delay": 0.18, "noise": 0.05,
	"gather": {"tree": 0.3}, "combo": ["Punch_Jab", "Punch_Cross"], "no_viewmodel": true,
}

## Posição de cada tipo de arma na tela (1ª pessoa).
const VIEW_OFFSETS := {
	"bow": Vector3(0.02, -0.1, -0.5),
	"melee": Vector3(0.42, -0.52, -0.62),
	"spell": Vector3(0.26, -0.24, -0.6),
	"focus": Vector3(0.3, -0.4, -0.55),
	"thrown": Vector3(0.28, -0.25, -0.45),
}

var selected := 0
var user: Player
var inventory: Inventory

var _camera: Camera3D
var _head: Node3D
## Armas já criadas, por id do item (reaproveitadas ao voltar para o slot).
var _cache: Dictionary = {}
var _current: Weapon
var _use_cooldown := 0.0
var _torch_burn := 0.0
var _hud_timer := 0.0
## Q: hora em que foi apertado (para saber se foi toque ou segurar).
var _q_down := -1
var _wheel_open := false
const WHEEL_HOLD_MS := 250


func setup(player: Player, camera: Camera3D, head: Node3D, inv: Inventory) -> void:
	user = player
	_camera = camera
	_head = head
	inventory = inv
	inventory.changed.connect(_refresh)
	_refresh()


func current() -> Weapon:
	return _current


## Item no slot selecionado ({} se vazio).
func selected_item() -> Dictionary:
	return inventory.get_slot(selected) if inventory else {}


func select(index: int) -> void:
	selected = wrapi(index, 0, Inventory.HOTBAR_SIZE)
	_refresh()


func display_name() -> String:
	var s := selected_item()
	if s.is_empty():
		return tr("Mãos livres")
	return Inventory.display_name_of(s)


func hud_text() -> String:
	var s := selected_item()
	if is_hammer(s) and not Inventory.is_broken(s) and user.build:
		return user.build.hammer_text()
	if (_current and _current.is_broken()) or Inventory.is_broken(s):
		return tr("QUEBRADO · repare na bancada")
	if _current and _current.data.get("no_viewmodel", false):
		return "×%d" % int(s.count) if not s.is_empty() and int(s.count) > 1 else "soco"
	if _current:
		return _current.hud_text()
	if not s.is_empty() and int(s.count) > 1:
		return "×%d" % int(s.count)
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "consumable":
		return tr("clique para usar")
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "grimoire":
		return tr("clique para ler")
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "armor":
		return tr("clique para vestir")
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "focus":
		var spell := user.progression.last_spell
		return tr("clique: %s (Nv %d)") % [GameData.get_item(spell).get("name", "—"), user.progression.spell_level(spell)] if spell != "" else tr("sem habilidade")
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") in Structures.PLACEABLE_TYPES:
		return tr("clique para colocar à frente")
	return ""


func _refresh() -> void:
	var s := selected_item()
	var weapon: Weapon = null
	if not s.is_empty():
		weapon = _weapon_for(s.id)
	# Sem arma na mão (slot vazio ou recurso): soco. Consumível continua sendo "usar".
	if weapon == null and not is_hammer(s) and (s.is_empty() or not GameData.get_item(s.id).get("type", "") in ["consumable", "station", "trap", "grimoire", "armor", "focus"]):
		weapon = _fists()
	if weapon != _current:
		if _current:
			_current.on_unequip()
			_current.visible = false
		_current = weapon
		if _current:
			_current.visible = true
			_current.on_equip()
	if _current:
		_current.slot = s
		_current.set_refine_fx(Inventory.refine_fx_tier(s))
	# Tocha na mão = luz (GDD 11: a noite é escura).
	user.net_torch = s.get("id", "") == "torch" and not Inventory.is_broken(s)
	user.set_torch_power(Inventory.refine_multiplier(s) if user.net_torch else 1.0)
	changed.emit()


func _process(delta: float) -> void:
	_use_cooldown = maxf(_use_cooldown - delta, 0.0)
	_update_q()
	_burn_torch(delta)
	# Martelo: o texto do HUD depende da peça na mira.
	if is_hammer(selected_item()):
		_hud_timer -= delta
		if _hud_timer <= 0.0:
			_hud_timer = 0.2
			changed.emit()
	if user == null or not _accepts_input():
		return
	# Mouse livre: clique em cima da HUD não é ataque.
	var can := MouseMode.can_attack(get_viewport())
	var held := can and Input.is_action_pressed("attack")
	var just := can and Input.is_action_just_pressed("attack")
	# Atacando: a mana sai do "fora de ação" (regeneração acelerada só depois de 3 s parado).
	if held and user.mana:
		user.mana.mark_action()
	if _current:
		_current.handle_attack(held, just)
	elif just:
		use_selected()


func _unhandled_input(event: InputEvent) -> void:
	if user == null or not _accepts_input():
		return
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			select(i)
			return
	if event.is_action_pressed("weapon_next"):
		select(selected + 1)
	elif event.is_action_pressed("weapon_prev"):
		select(selected - 1)
	elif event.is_action_pressed("reload") and is_hammer(selected_item()):
		if _use_cooldown <= 0.0 and user.build.hammer_upgrade(selected):
			_use_cooldown = 0.6
	elif event.is_action_pressed("reload") and _current:
		_current.reload()
	elif event.is_action_pressed("spell_1"):
		_q_down = Time.get_ticks_msec()


## Usa o item selecionado (consumíveis): cura na hora ("heals", poções) ou regeneração
## temporária ("regen" vida/s por "regen_time" s, comida). Não gasta se não ajudar em
## nada. Cura passa pelo servidor (Health.heal).
func use_selected() -> void:
	var s := selected_item()
	if s.is_empty() or _use_cooldown > 0.0:
		return
	var data := GameData.get_item(s.id)
	if is_hammer(s):
		if user.build and user.build.hammer_repair(selected):
			_use_cooldown = 0.6
		return
	if data.get("type", "") == "focus":
		if Inventory.is_broken(s):
			user.notify(tr("Cajado quebrado: repare na bancada"))
			return
		if await cast_spell(user.progression.last_spell):
			inventory.wear(inventory.get_slot(selected), 1.0)
		return
	if data.get("type", "") == "armor":
		if user.equipment.equip_from_inventory(selected):
			user.notify(tr("Vestiu: %s") % data.get("name", s.id))
			_use_cooldown = 0.4
		return
	if data.get("type", "") == "grimoire":
		if _read_grimoire(data):
			inventory.consume_from_slot(selected, 1)
			_use_cooldown = 1.0
		return
	if data.get("type", "") in Structures.PLACEABLE_TYPES:
		if user.place_station(selected):
			_use_cooldown = 0.5
		return
	if data.get("type", "") != "consumable":
		return
	var prog := user.progression
	var heals := float(data.get("heals", 0.0)) * prog.mult("heal")
	var can_heal := heals > 0.0 and user.health.current < user.health.cap()
	var regen := float(data.get("regen", 0.0)) * prog.mult("heal")
	var regenerates := regen > 0.0 and user.survival.add_food_regen(regen, float(data.get("regen_time", 10.0)))
	if not can_heal and not regenerates:
		user.notify(tr("Vida cheia"))
		return  # nada a ganhar: não desperdiça
	if can_heal:
		user.health.heal(heals)
	inventory.consume_from_slot(selected, 1)
	prog.gain("survival", 1.0)
	_use_cooldown = 1.0
	user.play_action_synced(&"Consume")


## Tocha acesa queima 1 de durabilidade por segundo; no fim, apaga e fica 0/x no
## inventário (nunca some): repare na bancada.
func _burn_torch(delta: float) -> void:
	if user == null or not user.is_multiplayer_authority() or not user.net_torch:
		return
	_torch_burn += delta
	if _torch_burn < 1.0:
		return
	_torch_burn -= 1.0
	var s := selected_item()
	if inventory.wear(s, 1.0) <= 0.0:
		user.net_torch = false
		user.notify(tr("A tocha apagou: repare na bancada"))


## Grimório (GDD 12): ensina os feitiços que ainda não estão no inventário.
## Pede um nível mínimo de Magia. Some ao ser lido (se ensinou algo).
func _read_grimoire(data: Dictionary) -> bool:
	var req: Dictionary = data.get("requires", {})
	for prof: String in req:
		if user.progression.get_level(prof) < int(req[prof]):
			user.notify(tr("Difícil demais: precisa de %s nível %d") % [GameData.get_entry("proficiencies", prof).get("name", prof), int(req[prof])])
			return false
	var learned: PackedStringArray = []
	for spell_id: String in data.get("teaches", []):
		var level := user.progression.learn_spell(spell_id)
		if level == 1:
			learned.append(tr("aprendeu %s (roda do Q)") % GameData.get_item(spell_id).get("name", spell_id))
		elif level > 1:
			learned.append(tr("%s subiu para o nível %d") % [GameData.get_item(spell_id).get("name", spell_id), level])
	if learned.is_empty():
		user.notify(tr("Você já domina o que este grimório ensina (nível máximo)"))
		return false
	user.notify(", ".join(learned))
	user.progression.last_spell = str(data.get("teaches", [""])[0])
	user.progression.gain("magic", 10.0)
	user.play_action_synced(&"Consume")
	return true


static func is_hammer(s: Dictionary) -> bool:
	return not s.is_empty() and GameData.get_item(s.id).get("use", "") == "hammer"


## Q: tocar conjura a última habilidade; segurar abre a roda e soltar só troca para a
## escolhida (não conjura: a próxima tocada no Q conjura).
func _update_q() -> void:
	if _q_down < 0 or user == null:
		return
	var held := Time.get_ticks_msec() - _q_down
	if Input.is_action_pressed("spell_1"):
		if not _wheel_open and held >= WHEEL_HOLD_MS and user.skill_wheel and user.progression.spells.size() > 0:
			_wheel_open = true
			user.skill_wheel.open(user.progression.spells.keys())
		return
	# Soltou.
	_q_down = -1
	var spell := user.progression.last_spell
	if _wheel_open:
		_wheel_open = false
		spell = user.skill_wheel.close()
		if spell == "":
			return  # cancelou
		if spell != user.progression.last_spell:
			user.progression.last_spell = spell
			user.progression.changed.emit()
			changed.emit()
		user.notify(tr("Habilidade selecionada: %s") % str(GameData.get_item(spell).get("name", spell)))
		return
	cast_spell(spell)


## Conjura uma habilidade aprendida (pelo Q ou pelo cajado).
func cast_spell(spell_id: String) -> bool:
	if spell_id == "" or user.progression.spell_level(spell_id) <= 0:
		user.notify(tr("Nenhuma habilidade aprendida (leia um grimório)"))
		return false
	var caster := caster_for(spell_id)
	return caster != null and await caster.cast()


## Objeto que conjura a habilidade (criado uma vez, invisível).
func caster_for(spell_id: String) -> SpellCaster:
	return _weapon_for(spell_id) as SpellCaster


func _accepts_input() -> bool:
	if not user.is_multiplayer_authority() or not MouseMode.playing():
		return false
	if user.build and user.build.active:
		return false  # mouse e roda são do modo construção
	return not user.health.is_dead


func _fists() -> Weapon:
	if not _cache.has(""):
		var fists := MeleeWeapon.new()
		add_child(fists)
		fists.setup(FISTS, user, _camera, _head)
		fists.visible = false
		_cache[""] = fists
	return _cache[""]


func _weapon_for(id: String) -> Weapon:
	if _cache.has(id):
		return _cache[id]
	var data := GameData.get_item(id)
	var weapon: Weapon = null
	var kind := str(data.get("type", ""))
	match kind:
		"bow": weapon = Bow.new()
		"melee": weapon = MeleeWeapon.new()
		"spell": weapon = SpellCaster.new()
		"focus": weapon = FocusWeapon.new()
		"thrown": weapon = ThrownWeapon.new()
		_: return null
	weapon.position = VIEW_OFFSETS.get(kind, Vector3(0.25, -0.25, -0.45))
	add_child(weapon)
	weapon.setup(data, user, _camera, _head)
	weapon.visible = false
	weapon.hud_changed.connect(changed.emit)
	_cache[id] = weapon
	return weapon
