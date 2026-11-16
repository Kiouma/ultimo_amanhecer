extends Node3D
## Flecha disparada pelo arco: voa com gravidade, aponta para onde está indo,
## causa dano no primeiro corpo vivo que acertar (cabeça = dano dobrado).
## Se cravar no chão/parede, fica alguns segundos e pode virar uma flecha
## recuperável no chão (recover_chance).
## visual_only: cópia nas telas dos outros jogadores (não causa dano nem deixa item).

## Gravidade "de jogo" (mais leve que a real): queda perceptível sem frustrar.
const GRAVITY := 6.0
const HEADSHOT_HEIGHT := 1.45
const HEADSHOT_MULTIPLIER := 2.0

var damage := 40.0
var velocity := Vector3.ZERO
var caster: Node
var recover_chance := 0.6
var item_id := "arrow"
var visual_only := false
var max_lifetime := 6.0

var _age := 0.0
var _stuck := false


func _ready() -> void:
	add_child(Weapon.box(Vector3(0.015, 0.015, 0.7), Color(0.6, 0.5, 0.35), Vector3(0, 0, 0.1)))
	add_child(Weapon.box(Vector3(0.05, 0.005, 0.1), Color(0.9, 0.9, 0.9), Vector3(0, 0, 0.4)))  # penas
	_orient()


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	_age += delta
	if _age > max_lifetime:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1 | 4 | 8 | 64)
	if caster is CollisionObject3D:
		query.exclude = [caster.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		_orient()
		return
	_on_hit(hit.collider, hit.position)


func _on_hit(target: Object, at: Vector3) -> void:
	global_position = at
	var health := Health.find_in(target) if target is Node else null
	if health and not health.is_dead:
		if not visual_only:
			var amount := damage
			if target is Node3D and at.y - target.global_position.y > HEADSHOT_HEIGHT:
				amount *= HEADSHOT_MULTIPLIER * (caster.progression.mult("headshot_damage") if caster is Player else 1.0)
			amount = Progression.on_hit(caster, target, amount, "bow")
			health.take_damage(amount, caster)
		queue_free()
		return
	# Cravou no cenário: fica um tempo e talvez dê para recuperar.
	_stuck = true
	if not visual_only and randf() < recover_chance:
		WorldItems.drop(item_id, 1, at, null)  # flecha recuperada: qualquer um pega na hora
		queue_free()
		return
	get_tree().create_timer(10.0, false).timeout.connect(queue_free)


func _orient() -> void:
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)
