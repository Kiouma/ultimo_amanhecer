extends Area3D
## Projétil mágico simples (dardo de fogo). Voa reto, acerta o primeiro corpo e some.
## visual_only: cópia mostrada nas telas dos outros jogadores; não causa dano
## (o dano é pedido ao servidor só pela cópia de quem conjurou).

var damage := 30.0
var speed := 22.0
var max_lifetime := 4.0
var direction := Vector3.FORWARD
var caster: Node
var color := Color(1.0, 0.45, 0.1)
var visual_only := false
## Tipo para o Progression.on_hit ("spell" usa a resistência a magia do monstro).
var weapon_type := "spell"
## Chamado (na máquina de quem disparou) com o alvo atingido: efeitos das habilidades.
var on_hit: Callable

var _age := 0.0
## Evita acertar duas vezes no mesmo frame (raio + sinal de colisão).
var _exploded := false


func _ready() -> void:
	collision_layer = 16  # projéteis
	collision_mask = 1 | 4 | 8 | 64  # mundo, zumbis, construções, portas
	monitoring = true
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 0.15
	add_child(shape)
	add_child(Weapon.sphere(0.12, color, Vector3.ZERO, true))
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 5.0
	add_child(light)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > max_lifetime:
		queue_free()
		return
	# Raio curto à frente para não atravessar nada em alta velocidade.
	var step := direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, collision_mask)
	if caster is CollisionObject3D:
		query.exclude = [caster.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.collider, hit.position)
		return
	global_position += step


func _on_body_entered(body: Node3D) -> void:
	if body != caster:
		_explode(body, global_position)


func _explode(target: Object, at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	if target is Node and not visual_only:
		var health := Health.find_in(target)
		if health and not health.is_dead:
			health.take_damage(Progression.on_hit(caster, target, damage, weapon_type), caster)
			if on_hit.is_valid():
				on_hit.call(target)
	var burst := Weapon.sphere(0.2, color, Vector3.ZERO, true)
	get_tree().current_scene.add_child(burst)
	burst.global_position = at
	var tw := burst.create_tween()
	tw.tween_property(burst, "scale", Vector3.ONE * 3.0, 0.2)
	tw.parallel().tween_property(burst, "transparency", 1.0, 0.2)
	tw.tween_callback(burst.queue_free)
	queue_free()
