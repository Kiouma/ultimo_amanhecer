class_name WeaponHolder
extends Node3D
## Fica na câmera do jogador. Cria as armas do loadout a partir dos dados e cuida
## de trocar (1-9, rodinha), atacar (botão esquerdo), recarregar (R) e do feitiço
## rápido (Q), que conjura o primeiro feitiço do loadout sem trocar de arma.

signal changed

## Ids de equipment.json (armas) ou spells.json (feitiços), na ordem das teclas 1, 2, 3...
## Provisório até existir inventário/hotbar (Fase 2).
@export var loadout: Array[String] = ["pistol_9mm", "axe_iron", "firebolt"]

## Posição de cada tipo de arma na tela (1ª pessoa).
const VIEW_OFFSETS := {
	"firearm": Vector3(0.2, -0.2, -0.55),
	"melee": Vector3(0.42, -0.52, -0.62),
	"spell": Vector3(0.26, -0.24, -0.6),
}

var weapons: Array[Weapon] = []
var current_index := -1
var user: Player


func setup(player: Player, camera: Camera3D, head: Node3D) -> void:
	user = player
	for id in loadout:
		var weapon := _create_weapon(id)
		if weapon == null:
			continue
		weapon.position = VIEW_OFFSETS.get(_kind_of(weapon), Vector3(0.25, -0.25, -0.45))
		add_child(weapon)
		weapon.setup(_entry_for(id), player, camera, head)
		weapon.visible = false
		weapon.hud_changed.connect(changed.emit)
		weapons.append(weapon)
	if not weapons.is_empty():
		equip(0)


func current() -> Weapon:
	if current_index < 0 or current_index >= weapons.size():
		return null
	return weapons[current_index]


func equip(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current_index:
		return
	var old := current()
	if old:
		old.on_unequip()
		old.visible = false
	current_index = index
	var weapon := current()
	weapon.visible = true
	weapon.on_equip()
	changed.emit()


func _process(_delta: float) -> void:
	if user == null or not _accepts_input():
		return
	var weapon := current()
	if weapon:
		weapon.handle_attack(Input.is_action_pressed("attack"), Input.is_action_just_pressed("attack"))


func _unhandled_input(event: InputEvent) -> void:
	if user == null or not _accepts_input():
		return
	for i in mini(weapons.size(), 9):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			equip(i)
			return
	if event.is_action_pressed("weapon_next"):
		equip(wrapi(current_index + 1, 0, weapons.size()))
	elif event.is_action_pressed("weapon_prev"):
		equip(wrapi(current_index - 1, 0, weapons.size()))
	elif event.is_action_pressed("reload") and current():
		current().reload()
	elif event.is_action_pressed("spell_1"):
		_quick_cast()


func _quick_cast() -> void:
	for weapon in weapons:
		if weapon is SpellCaster:
			(weapon as SpellCaster).cast()
			return


func _accepts_input() -> bool:
	if not user.is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var health := Health.find_in(user)
	return health == null or not health.is_dead


func _create_weapon(id: String) -> Weapon:
	var item := GameData.get_entry("items", id)
	if not item.is_empty():
		match str(item.get("type", "")):
			"firearm": return Firearm.new()
			"melee": return MeleeWeapon.new()
	if not GameData.get_entry("spells", id).is_empty():
		return SpellCaster.new()
	push_warning("Loadout: '%s' não é arma nem feitiço conhecido." % id)
	return null


func _entry_for(id: String) -> Dictionary:
	var item := GameData.get_entry("items", id)
	return item if not item.is_empty() else GameData.get_entry("spells", id)


func _kind_of(weapon: Weapon) -> String:
	if weapon is Firearm:
		return "firearm"
	if weapon is MeleeWeapon:
		return "melee"
	return "spell"
