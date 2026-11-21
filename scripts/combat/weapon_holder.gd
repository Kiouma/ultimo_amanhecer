class_name WeaponHolder
extends Node3D
## Arma na mão: a do slot fixo de arma do equipamento (Equipment "weapon"). O item
## define o que o botão esquerdo faz:
## - arco / melee / cajado / arremesso: cria (uma vez) e usa a arma;
## - martelo: conserta (clique) e melhora (R) a construção na mira;
## - nada na mão: soco.
## As teclas 1 a 5 são das habilidades (Skills). Consumíveis, livros de habilidade e
## estações se usam pelo inventário (clique duplo: use_item).

signal changed

## Mãos livres: soco fraco que também coleta (mal) madeira.
const FISTS := {
	"id": "", "name": "Mãos livres", "type": "unarmed", "damage": 8, "stamina_cost": 5,
	"range": 1.7, "attack_time": 0.45, "hit_delay": 0.18, "noise": 0.05,
	"gather": {"tree": 0.3}, "combo": ["Punch_Jab", "Punch_Cross"], "no_viewmodel": true,
}

## Posição de cada tipo de arma (viewmodel escondido; usado pelos efeitos).
const VIEW_OFFSETS := {
	"bow": Vector3(0.02, -0.1, -0.5),
	"melee": Vector3(0.42, -0.52, -0.62),
	"spell": Vector3(0.26, -0.24, -0.6),
	"focus": Vector3(0.3, -0.4, -0.55),
	"thrown": Vector3(0.28, -0.25, -0.45),
}

var user: Player
var inventory: Inventory

var _camera: Camera3D
var _head: Node3D
## Armas já criadas, por id do item (reaproveitadas ao trocar de volta).
var _cache: Dictionary = {}
var _current: Weapon
var _use_cooldown := 0.0
var _torch_burn := 0.0
var _hud_timer := 0.0
## Até quando o clique não ataca (acabou de soltar uma habilidade de área com ele).
var suppress_until := 0


func setup(player: Player, camera: Camera3D, head: Node3D, inv: Inventory) -> void:
	user = player
	_camera = camera
	_head = head
	inventory = inv
	inventory.changed.connect(_refresh)
	user.equipment.changed.connect(_refresh)
	_refresh()


func current() -> Weapon:
	return _current


## Item na mão (slot de arma do equipamento; {} se vazio).
func selected_item() -> Dictionary:
	return user.equipment.get_item("weapon") if user and user.equipment else {}


## Item na mão secundária, se estiver valendo ({} se não).
func offhand_item() -> Dictionary:
	return user.equipment.get_item("offhand") if user and user.equipment and user.equipment.offhand_active() else {}


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
		return tr("soco")
	if _current:
		return _current.hud_text()
	return ""


func _refresh() -> void:
	var s := selected_item()
	var weapon: Weapon = null
	if not s.is_empty():
		weapon = _weapon_for(s.id)
	# Sem arma (mão vazia, tocha): soco. Martelo: usa o clique para consertar.
	if weapon == null and not is_hammer(s):
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
		_current.slot = {} if _current == _cache.get("") else s
		_current.set_refine_fx(Inventory.refine_fx_tier(_current.slot))
	# Tocha na mão (principal ou secundária) = luz (GDD 11: a noite é escura).
	var torch := _torch_item()
	user.net_torch = not torch.is_empty() and not Inventory.is_broken(torch)
	user.set_torch_power(Inventory.refine_multiplier(torch) if user.net_torch else 1.0)
	changed.emit()


## A tocha segurada (mão principal ou secundária), ou {}.
func _torch_item() -> Dictionary:
	for s: Dictionary in [selected_item(), user.equipment.get_item("offhand")]:
		if s.get("id", "") == "torch":
			return s
	return {}


func _process(delta: float) -> void:
	_use_cooldown = maxf(_use_cooldown - delta, 0.0)
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
	elif just and is_hammer(selected_item()) and _use_cooldown <= 0.0:
		if user.build and user.build.hammer_repair(selected_item()):
			_use_cooldown = 0.6


func _unhandled_input(event: InputEvent) -> void:
	if user == null or not _accepts_input():
		return
	if event.is_action_pressed("reload") and is_hammer(selected_item()):
		if _use_cooldown <= 0.0 and user.build.hammer_upgrade(selected_item()):
			_use_cooldown = 0.6
	elif event.is_action_pressed("reload") and _current:
		_current.reload()


## Usa um item do inventário (clique duplo): equipamento (veste/empunha), livro de
## habilidade (aprende), estação/armadilha (coloca à frente) ou consumível (cura ou
## buff). Retorna true se usou.
func use_item(index: int) -> bool:
	var s := inventory.get_slot(index)
	if s.is_empty() or _use_cooldown > 0.0 or user.health.is_dead:
		return false
	var data := GameData.get_item(s.id)
	var type := str(data.get("type", ""))
	if Equipment.item_slot(s.id) != "" or Equipment.offhand_capable(s.id):
		if user.equipment.equip_from_inventory(index):
			user.notify(tr("Equipou: %s") % tr(str(data.get("name", s.id))))
			_use_cooldown = 0.3
			return true
		return false
	if type == "skill_book":
		if user.skills and user.skills.read_book(data):
			inventory.consume_from_slot(index, 1)
			_use_cooldown = 1.0
			user.play_action_synced(&"Consume")
			return true
		return false
	if type in Structures.PLACEABLE_TYPES:
		if user.place_station(index):
			_use_cooldown = 0.5
			return true
		return false
	if type != "consumable":
		return false
	var prog := user.progression
	var heals := float(data.get("heals", 0.0)) * prog.mult("heal")
	var can_heal := heals > 0.0 and user.health.current < user.health.cap()
	# Comida: buff temporário (data/effects), ex.: frutas regeneram vida por 10 s. Não
	# gasta com a vida cheia. A cura de comida também cresce com "heal".
	var effect_id := str(data.get("effect", ""))
	# Só regeneração de vida: não gasta com a vida cheia. Outros bônus (peixes: mana,
	# stamina, vida máxima, loot) valem sempre.
	var mods: Dictionary = StatusEffects.data(effect_id).get("mods", {}) if effect_id != "" else {}
	var only_life := mods.keys().all(func(k: String) -> bool: return k == "life_regen_add")
	var regenerates := effect_id != "" and (user.health.current < user.health.cap() or not only_life)
	if regenerates:
		user.effects.apply(effect_id, -1.0, prog.mult("heal"))
	if not can_heal and not regenerates:
		user.notify(tr("Vida cheia"))
		return false  # nada a ganhar: não desperdiça
	if can_heal:
		user.health.heal(heals)
	inventory.consume_from_slot(index, 1)
	prog.gain("survival", 1.0)
	_use_cooldown = 1.0
	user.play_action_synced(&"Consume")
	return true


## Tocha acesa queima 1 de durabilidade por segundo; no fim, apaga e fica 0/x (nunca
## some): repare na bancada.
func _burn_torch(delta: float) -> void:
	if user == null or not user.is_multiplayer_authority() or not user.net_torch:
		return
	_torch_burn += delta
	if _torch_burn < 1.0:
		return
	_torch_burn -= 1.0
	if inventory.wear(_torch_item(), 1.0) <= 0.0:
		user.net_torch = false
		user.notify(tr("A tocha apagou: repare na bancada"))


static func is_hammer(s: Dictionary) -> bool:
	return not s.is_empty() and GameData.get_item(s.id).get("use", "") == "hammer"


func _accepts_input() -> bool:
	if not user.is_multiplayer_authority() or not MouseMode.playing():
		return false
	if user.build and user.build.active:
		return false  # mouse e roda são do modo construção
	if user.skills and (user.skills.is_aiming() or user.skills.is_channeling()):
		return false  # o clique é da habilidade (círculo no chão) ou está girando
	if Time.get_ticks_msec() < suppress_until:
		return false
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
