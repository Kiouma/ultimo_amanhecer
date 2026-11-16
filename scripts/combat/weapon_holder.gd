class_name WeaponHolder
extends Node3D
## Fica na câmera do jogador e segue a hotbar do inventário (teclas 1-9, rodinha).
## O item do slot selecionado define o que o botão esquerdo faz:
## - arma de fogo / melee / feitiço: cria (uma vez) e mostra a arma;
## - consumível (bandagem, kit médico): usa e gasta um;
## - outro item ou vazio: mãos livres.
## R recarrega; Q conjura o primeiro feitiço da hotbar sem trocar de slot.

signal changed

## Mãos livres: soco fraco que também coleta (mal) madeira.
const FISTS := {
	"id": "", "name": "Mãos livres", "type": "melee", "damage": 6, "stamina_cost": 5,
	"range": 1.7, "attack_time": 0.45, "hit_delay": 0.18, "noise": 0.05,
	"gather": {"tree": 0.3}, "combo": ["Punch_Jab", "Punch_Cross"], "no_viewmodel": true,
}

## Posição de cada tipo de arma na tela (1ª pessoa).
const VIEW_OFFSETS := {
	"bow": Vector3(0.02, -0.1, -0.5),
	"firearm": Vector3(0.2, -0.2, -0.55),
	"melee": Vector3(0.42, -0.52, -0.62),
	"spell": Vector3(0.26, -0.24, -0.6),
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
		return "Mãos livres"
	return Inventory.display_name_of(s)


func hud_text() -> String:
	var s := selected_item()
	if is_hammer(s) and not Inventory.is_broken(s) and user.build:
		return user.build.hammer_text()
	if (_current and _current.is_broken()) or Inventory.is_broken(s):
		return "QUEBRADO · repare na bancada"
	if _current and _current.data.get("no_viewmodel", false):
		return "×%d" % int(s.count) if not s.is_empty() and int(s.count) > 1 else "soco"
	if _current:
		return _current.hud_text()
	if not s.is_empty() and int(s.count) > 1:
		return "×%d" % int(s.count)
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "consumable":
		return "clique para usar"
	if not s.is_empty() and GameData.get_item(s.id).get("type", "") == "station":
		return "clique para colocar à frente"
	return ""


func _refresh() -> void:
	var s := selected_item()
	var weapon: Weapon = null
	if not s.is_empty():
		weapon = _weapon_for(s.id)
	# Sem arma na mão (slot vazio ou recurso): soco. Consumível continua sendo "usar".
	if weapon == null and not is_hammer(s) and (s.is_empty() or not GameData.get_item(s.id).get("type", "") in ["consumable", "station"]):
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
	# Tocha na mão = luz (GDD 11: a noite é escura).
	user.net_torch = s.get("id", "") == "torch" and not Inventory.is_broken(s)
	user.set_torch_power(Inventory.refine_multiplier(s) if user.net_torch else 1.0)
	changed.emit()


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
	if _current:
		_current.handle_attack(Input.is_action_pressed("attack"), Input.is_action_just_pressed("attack"))
	elif Input.is_action_just_pressed("attack"):
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
		_quick_cast()


## Usa o item selecionado (consumíveis): cura ("heals"), comida ("food"), água ("water").
## Não gasta se não ajudar em nada. Cura passa pelo servidor (Health.heal).
func use_selected() -> void:
	var s := selected_item()
	if s.is_empty() or _use_cooldown > 0.0:
		return
	var data := GameData.get_item(s.id)
	if is_hammer(s):
		if user.build and user.build.hammer_repair(selected):
			_use_cooldown = 0.6
		return
	if data.get("type", "") == "station":
		if user.place_station(selected):
			_use_cooldown = 0.5
		return
	if data.get("type", "") != "consumable":
		return
	var heals := float(data.get("heals", 0.0))
	var can_heal := heals > 0.0 and user.health.current < user.health.max_health
	var fed := user.survival.consume(float(data.get("food", 0.0)), float(data.get("water", 0.0)))
	if not can_heal and not fed:
		return  # nada a ganhar: não desperdiça
	if can_heal:
		user.health.heal(heals)
	inventory.take_from_slot(selected, 1)
	# Garrafa: beber devolve a garrafa vazia.
	if data.has("returns"):
		Crafting.give_result(inventory, {"result": data.returns, "amount": 1}, 1)
	# Água suja e afins: chance de passar mal.
	if randf() < float(data.get("sick_chance", 0.0)):
		user.health.take_damage(float(data.get("sick_damage", 10.0)), user)
		user.notify("Você passou mal (%s)" % str(data.get("name", s.id)).to_lower())
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
		user.notify("A tocha apagou: repare na bancada")


static func is_hammer(s: Dictionary) -> bool:
	return not s.is_empty() and GameData.get_item(s.id).get("use", "") == "hammer"


func _quick_cast() -> void:
	var index := inventory.find_in_hotbar("spell")
	if index < 0:
		return
	var caster := _weapon_for(inventory.get_slot(index).id) as SpellCaster
	if caster:
		caster.cast()


func _accepts_input() -> bool:
	if not user.is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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
		"firearm": weapon = Firearm.new()
		"melee": weapon = MeleeWeapon.new()
		"spell": weapon = SpellCaster.new()
		_: return null
	weapon.position = VIEW_OFFSETS.get(kind, Vector3(0.25, -0.25, -0.45))
	add_child(weapon)
	weapon.setup(data, user, _camera, _head)
	weapon.visible = false
	weapon.hud_changed.connect(changed.emit)
	_cache[id] = weapon
	return weapon
