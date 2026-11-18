extends Node3D
## Bola de ácido do Cuspidor (GDD 6.1): voa em arco, fere quem acerta e quem está
## perto do impacto e corrói construções (dano × "structure_damage" do cuspidor).
## Só a do servidor causa dano; nos clientes é só visual (visual_only).

const GRAVITY := 9.0
const SPLASH_RADIUS := 1.3
const MAX_LIFE := 4.0

var velocity := Vector3.ZERO
var damage := 12.0
var structure_multiplier := 2.5
var caster: Node3D
var visual_only := false

var _life := 0.0


func _ready() -> void:
	add_child(Weapon.sphere(0.14, Color(0.55, 0.95, 0.2), Vector3.ZERO, true))
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.3)
	light.light_energy = 0.8
	light.omni_range = 2.5
	add_child(light)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFE:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1 | 2 | 8 | 64)
	if caster and is_instance_valid(caster):
		query.exclude = [caster.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	global_position = hit.position
	if not visual_only:
		_splash(hit.collider)
	_puddle()
	queue_free()


func _splash(direct: Object) -> void:
	var source: Node = caster if is_instance_valid(caster) else null
	var hit_ids := {}
	# Acerto direto: jogador ou peça de construção (ou folha da porta).
	var piece: BuildPiece = direct as BuildPiece
	if direct is BuildPiece.DoorPanel:
		piece = direct.piece
	if piece and piece.health and not piece.health.is_dead:
		piece.health.take_damage(damage * structure_multiplier, source)
	elif direct is Node and Health.find_in(direct):
		Health.find_in(direct).take_damage(damage, source, true)
		hit_ids[direct.get_instance_id()] = true
	# Respingo em jogadores perto.
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if hit_ids.has(p.get_instance_id()):
			continue
		if p.global_position.distance_to(global_position) <= SPLASH_RADIUS + 0.5:
			var h := Health.find_in(p)
			if h:
				h.take_damage(damage * 0.5, source, true)


## Poça que some sozinha.
func _puddle() -> void:
	var puddle := Weapon.cylinder(0.45, 0.02, Color(0.45, 0.8, 0.15), global_position + Vector3.UP * 0.02)
	get_parent().add_child(puddle)
	var tw := puddle.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(puddle, "scale", Vector3(0.1, 1.0, 0.1), 1.0)
	tw.tween_callback(puddle.queue_free)
