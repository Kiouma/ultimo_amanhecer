class_name MeleeWeapon
extends Weapon
## Arma corpo a corpo: golpe em arco na frente do jogador, acerta vários zumbis.
## Gasta stamina por golpe e faz pouco barulho (GDD 5.3). Segurar o botão encadeia o combo.
## (Coleta de árvores e rochas é com E e ferramenta no slot: ver Gathering.)

const DEFAULT_COMBO := [&"Sword_Regular_A", &"Sword_Regular_B", &"Sword_Regular_C"]

## Quantos inimigos um golpe pode acertar de uma vez.
@export var max_targets := 3

## Empunhadura dupla (duas adagas).
const DUAL_COMBO := ["Melee_Dualwield_Attack_Slice", "Melee_Dualwield_Attack_Stab", "Melee_Dualwield_Attack_Chop"]

var _combo_index := 0
var _combo_timer := 0.0
## Golpe carregado: segurando o botão.
const CHARGE_START := 0.22
const CHARGE_FULL := 1.5
const CHARGE_MAX_BONUS := 1.5  # +150% no máximo (2,5×)
var _pressing := false
var _press_time := 0.0
var _power := 1.0


func _process(delta: float) -> void:
	super(delta)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0:
		_combo_index = 0


## Toque = golpe normal. Segurar = carregar: gasta stamina enquanto segura e o golpe
## sai mais forte ao soltar (até 2,5×). Sem stamina, o golpe sai sozinho.
func handle_attack(held: bool, just_pressed: bool) -> void:
	if just_pressed and not _pressing and cooldown <= 0.0:
		if is_broken():
			warn_broken()
			return
		_pressing = true
		_press_time = 0.0
	if not _pressing:
		return
	var stamina: StatPool = user.get(&"stamina")
	if held:
		var dt := get_process_delta_time()
		_press_time += dt
		if _press_time > CHARGE_START and _press_time < CHARGE_FULL and stamina:
			if stamina.current <= 0.5:
				_release_charge()
				return
			stamina.drain(stat("stamina_cost", 12.0) * 0.9 * dt)
		if _press_time > CHARGE_START:
			hud_changed.emit()
		return
	_release_charge()


func channel_fraction() -> float:
	if not _pressing or _press_time <= CHARGE_START:
		return -1.0
	return clampf((_press_time - CHARGE_START) / (CHARGE_FULL - CHARGE_START), 0.0, 1.0)


func channel_label() -> String:
	return tr("Golpe carregado")


func on_unequip() -> void:
	_pressing = false
	_press_time = 0.0


func _release_charge() -> void:
	var f := maxf(channel_fraction(), 0.0)
	_pressing = false
	_press_time = 0.0
	_power = 1.0 + CHARGE_MAX_BONUS * f * user.progression.mult("melee.channel")
	hud_changed.emit()
	_attack()


func _attack() -> void:
	var stamina: StatPool = user.get(&"stamina")
	if stamina and not stamina.spend(stat("stamina_cost", 12.0)):
		return
	cooldown = stat("attack_time", 0.65)
	_combo_timer = cooldown + 0.6
	var combo: Array = data.get("combo", DEFAULT_COMBO)
	if user.equipment and user.equipment.dual_wielding():
		combo = DUAL_COMBO  # duas armas: golpes com as duas mãos
	var anim := StringName(combo[_combo_index % combo.size()])
	var direction := 1.0 if _combo_index % 2 == 0 else -1.0
	_combo_index = (_combo_index + 1) % combo.size()

	play_body_anim(anim, cooldown)
	_swing(direction)
	make_noise(stat("noise", 0.2))
	Sfx.play("swing", user.global_position + Vector3.UP * 1.4, -6.0)
	count_use()
	get_tree().create_timer(stat("hit_delay", 0.25)).timeout.connect(_hit)


func _hit() -> void:
	if not is_instance_valid(user):
		return
	var reach := stat("range", 2.2)
	# Na frente do corpo (o personagem vira para o alvo/cursor ao atacar).
	var forward := -user.global_basis.z
	var shape := SphereShape3D.new()
	shape.radius = reach * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), user.global_position + Vector3.UP * 1.1 + forward * reach * 0.5)
	query.collision_mask = 4  # zumbis
	query.exclude = [user.get_rid()]
	var results := user.get_world_3d().direct_space_state.intersect_shape(query, 16)
	var hits := 0
	for r in results:
		if hits >= max_targets:
			break
		if deal_damage(r.collider, stat("damage", 35.0) * _power):
			hits += 1
	if hits > 0:
		wear(1.0)  # só desgasta quando acerta algo
		kick(Vector3(0, 0, 0.03), Vector3(0, 0, 0), 0.08)  # tranco do impacto


func hud_text() -> String:
	return tr("stamina %d") % int(stat("stamina_cost", 12.0))


func _swing(direction: float) -> void:
	if data.get("no_viewmodel", false):
		return
	var t := stat("attack_time", 0.65)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Levanta, desce cortando na diagonal, volta.
	tw.tween_property(self, "rotation", _rest_rotation + Vector3(0.6, 0.3 * direction, 0.5 * direction), t * 0.25)
	tw.tween_property(self, "rotation", _rest_rotation + Vector3(-1.1, -0.5 * direction, -0.6 * direction), t * 0.25)
	tw.parallel().tween_property(self, "position", _rest_position + Vector3(-0.15 * direction, -0.05, -0.15), t * 0.25)
	tw.tween_property(self, "rotation", _rest_rotation, t * 0.5)
	tw.parallel().tween_property(self, "position", _rest_position, t * 0.5)


func _build_viewmodel() -> void:
	if data.get("no_viewmodel", false):
		return  # mãos livres (soco)
	var model := model_viewmodel(0.55)
	if model:
		model.position = Vector3(0, -0.08, 0)
		add_child(model)
		rotation = Vector3(deg_to_rad(-20), deg_to_rad(-10), deg_to_rad(-15))
		return
	var handle := cylinder(0.018, 0.45, Color(0.4, 0.28, 0.16), Vector3(0, 0.12, 0))
	add_child(handle)
	add_child(box(Vector3(0.02, 0.13, 0.16), Color(0.55, 0.57, 0.6), Vector3(0, 0.33, -0.07)))  # lâmina
	rotation = Vector3(deg_to_rad(-20), deg_to_rad(-10), deg_to_rad(-15))
