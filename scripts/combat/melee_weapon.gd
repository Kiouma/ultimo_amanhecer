class_name MeleeWeapon
extends Weapon
## Arma corpo a corpo: golpe em arco na frente do jogador, acerta vários zumbis.
## Gasta stamina por golpe e faz pouco barulho (GDD 5.3). Segurar o botão encadeia o combo.
## Também coleta: o golpe atinge o recurso na mira (árvore, rocha), conforme o
## fator "gather" do item (ver ResourceNode).

const DEFAULT_COMBO := [&"Sword_Regular_A", &"Sword_Regular_B", &"Sword_Regular_C"]

## Quantos inimigos um golpe pode acertar de uma vez.
@export var max_targets := 3

var _combo_index := 0
var _combo_timer := 0.0


func _process(delta: float) -> void:
	super(delta)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0:
		_combo_index = 0


func handle_attack(held: bool, _just_pressed: bool) -> void:
	if not held or cooldown > 0.0:
		return
	var stamina: StatPool = user.get(&"stamina")
	if stamina and not stamina.spend(stat("stamina_cost", 12.0)):
		return
	cooldown = stat("attack_time", 0.65)
	_combo_timer = cooldown + 0.6
	var combo: Array = data.get("combo", DEFAULT_COMBO)
	var anim := StringName(combo[_combo_index % combo.size()])
	var direction := 1.0 if _combo_index % 2 == 0 else -1.0
	_combo_index = (_combo_index + 1) % combo.size()

	play_body_anim(anim)
	_swing(direction)
	make_noise(stat("noise", 0.2))
	get_tree().create_timer(stat("hit_delay", 0.25)).timeout.connect(_hit)


func _hit() -> void:
	if not is_instance_valid(user):
		return
	var reach := stat("range", 2.2)
	var forward := -head.global_basis.z
	var shape := SphereShape3D.new()
	shape.radius = reach * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), head.global_position + forward * reach * 0.5 + Vector3.DOWN * 0.3)
	query.collision_mask = 4  # zumbis
	query.exclude = [user.get_rid()]
	var results := user.get_world_3d().direct_space_state.intersect_shape(query, 16)
	var hits := 0
	for r in results:
		if hits >= max_targets:
			break
		if deal_damage(r.collider, stat("damage", 35.0)):
			hits += 1
	if _hit_resource(reach):
		hits += 1
	if hits > 0:
		kick(Vector3(0, 0, 0.03), Vector3(0, 0, 0), 0.08)  # tranco do impacto


## Recurso na mira (árvore, rocha): pede a coleta. Retorna true se acertou um.
func _hit_resource(reach: float) -> bool:
	var from := camera.global_position
	var length := reach + from.distance_to(head.global_position)  # 3ª pessoa: câmera atrás
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * length, 1)
	query.exclude = [user.get_rid()]
	var hit := user.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Object = hit.get("collider")
	if target is ResourceNode and not target.data.get("by_hand", false):
		if target.global_position.distance_to(user.global_position) <= reach + 1.5:
			target.request_gather(user, data)
			return true
	return false


func hud_text() -> String:
	return "stamina %d" % int(stat("stamina_cost", 12.0))


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
	var handle := cylinder(0.018, 0.45, Color(0.4, 0.28, 0.16), Vector3(0, 0.12, 0))
	add_child(handle)
	add_child(box(Vector3(0.02, 0.13, 0.16), Color(0.55, 0.57, 0.6), Vector3(0, 0.33, -0.07)))  # lâmina
	rotation = Vector3(deg_to_rad(-20), deg_to_rad(-10), deg_to_rad(-15))
