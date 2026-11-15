class_name Zombie
extends CharacterBody3D
## Zumbi básico (Fase 1). Status vêm de data/zombies/zombies.json pelo zombie_id.
## Estados (GDD 6.2): vagando → investigando → perseguindo → atacando → perdendo o alvo.
## Percepção: visão em cone com linha de visada + audição (EventBus.noise_emitted).
## A IA só roda no servidor (multiplayer autoritativo, GDD 14); offline o jogo é o servidor.

enum State { WANDER, INVESTIGATE, CHASE, ATTACK, DEAD }

@export var zombie_id := "walker"

@export_group("Percepção")
@export var view_angle_deg := 120.0
## Quanto tempo o zumbi continua indo atrás da última posição vista antes de desistir.
@export var lose_target_time := 4.0

@export_group("Ataque")
@export var attack_range := 1.6
@export var attack_cooldown := 1.6
## Momento do golpe dentro da animação Zombie_Scratch.
@export var attack_hit_delay := 0.55

@export_group("Movimento")
@export var wander_radius := 8.0
@export var chase_speed_multiplier := 1.6
@export var turn_speed := 6.0

var state := State.WANDER
var stats: Dictionary = {}
var target: Node3D
var _last_known_position := Vector3.ZERO
var _time_since_seen := 0.0
var _attack_timer := 0.0
var _wander_wait := 0.0
var _wander_moving := false
var _home := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var model: CharacterModel = $Model
@onready var health: Health = $Health
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var eyes: Node3D = $Eyes


func _ready() -> void:
	stats = GameData.get_entry("zombies", zombie_id)
	if stats.is_empty():
		push_warning("Zumbi '%s' não existe em zombies.json; usando valores padrão." % zombie_id)
	health.reset(_stat("health", 100.0))
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	EventBus.noise_emitted.connect(_on_noise)
	_home = global_position
	_wander_wait = randf_range(0.5, 3.0)
	model.play(&"Zombie_Idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD or not multiplayer.is_server():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_update_perception(delta)

	match state:
		State.WANDER:
			_process_wander(delta)
		State.INVESTIGATE:
			_move_towards(_last_known_position, _speed(), delta)
			if global_position.distance_to(_last_known_position) < 1.5 or agent.is_navigation_finished():
				_set_state(State.WANDER)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_stop(delta)
			if target:
				_face(target.global_position, delta)
			if not model.is_in_action():
				_set_state(State.CHASE)

	move_and_slide()
	_update_animation()


# --- Percepção -----------------------------------------------------------------

func _update_perception(delta: float) -> void:
	var seen := _find_visible_player()
	if seen:
		target = seen
		_last_known_position = seen.global_position
		_time_since_seen = 0.0
		if state in [State.WANDER, State.INVESTIGATE]:
			_set_state(State.CHASE)
	else:
		_time_since_seen += delta


func _find_visible_player() -> Node3D:
	var sight := _stat("sight_range", 15.0)
	var best: Node3D = null
	var best_dist := INF
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		var h := Health.find_in(p)
		if h and h.is_dead:
			continue
		var to_player := p.global_position - global_position
		var dist := to_player.length()
		if dist > sight or dist >= best_dist:
			continue
		# Muito perto, ele "sente" o jogador mesmo de costas.
		if dist > 2.5:
			var forward := -global_basis.z
			var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
			if rad_to_deg(forward.angle_to(flat)) > view_angle_deg * 0.5:
				continue
		if not _has_line_of_sight(p):
			continue
		best = p
		best_dist = dist
	return best


func _has_line_of_sight(p: Node3D) -> bool:
	var from := eyes.global_position
	var to := p.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)  # mundo + construções
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_noise(noise_position: Vector3, loudness: float, source: Node) -> void:
	if state == State.DEAD or source == self:
		return
	var heard_range := loudness * _stat("hearing", 1.0)
	if global_position.distance_to(noise_position) > heard_range:
		return
	_last_known_position = noise_position
	if state == State.WANDER:
		_set_state(State.INVESTIGATE)


# --- Estados ---------------------------------------------------------------------

func _process_wander(delta: float) -> void:
	if not _wander_moving:
		_stop(delta)
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(2.0, wander_radius)
			agent.target_position = _home + offset
			_wander_moving = true
			_wander_wait = 8.0  # tempo máximo andando até o ponto
		return
	_wander_wait -= delta
	_move_towards(agent.target_position, _speed() * 0.7, delta)
	if agent.is_navigation_finished() or _wander_wait <= 0.0:
		_wander_moving = false
		_wander_wait = randf_range(2.0, 5.0)


func _process_chase(delta: float) -> void:
	if target == null or (Health.find_in(target) and Health.find_in(target).is_dead):
		target = null
		_set_state(State.WANDER)
		return
	if _time_since_seen > lose_target_time:
		# Perdeu o alvo: vai até o último lugar onde viu e procura por ali.
		target = null
		_set_state(State.INVESTIGATE)
		return
	var goal := target.global_position if _time_since_seen < 0.2 else _last_known_position
	var dist := global_position.distance_to(target.global_position)
	if dist <= attack_range and _time_since_seen < 0.2:
		if _attack_timer <= 0.0:
			_start_attack()
		else:
			_stop(delta)
			_face(target.global_position, delta)
		return
	_move_towards(goal, _speed() * chase_speed_multiplier, delta)


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_timer = attack_cooldown
	model.play_action(&"Zombie_Scratch")
	var victim := target
	get_tree().create_timer(attack_hit_delay, false).timeout.connect(func() -> void:
		if state == State.DEAD or not is_instance_valid(victim):
			return
		if global_position.distance_to(victim.global_position) <= attack_range + 0.4:
			var h := Health.find_in(victim)
			if h:
				h.take_damage(_stat("damage", 10.0), self)
	)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if new_state == State.INVESTIGATE:
		agent.target_position = _last_known_position
	elif new_state == State.WANDER:
		_wander_moving = false
		_wander_wait = randf_range(1.0, 3.0)


# --- Dano e morte ----------------------------------------------------------------

func _on_damaged(_amount: float, source: Node) -> void:
	if source is Node3D:
		target = source
		_last_known_position = source.global_position
		_time_since_seen = 0.0
		if state != State.ATTACK:
			_set_state(State.CHASE)
	model.play_action(&"Hit_Chest")


func _on_died(_source: Node) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 1
	model.play_action(&"Death01")
	get_tree().create_timer(15.0, false).timeout.connect(queue_free)


# --- Movimento -------------------------------------------------------------------

func _move_towards(goal: Vector3, speed: float, delta: float) -> void:
	agent.target_position = goal
	var next := agent.get_next_path_position()
	# Sem navmesh pronta (primeiro frame), vai em linha reta.
	if next.distance_to(global_position) < 0.01:
		next = goal
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		_stop(delta)
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta)


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)


func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func _speed() -> float:
	return _stat("speed", 1.2)


func _stat(key: String, default: float) -> float:
	return float(stats.get(key, default))


func _update_animation() -> void:
	if state in [State.DEAD, State.ATTACK] or model.is_in_action():
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed < 0.2:
		model.play(&"Zombie_Idle")
	elif flat_speed > 3.5:
		model.play(&"Jog_Fwd")
	else:
		# Ajusta a velocidade da animação ao passo real (~1,1 m/s na animação original).
		model.play(&"Zombie_Walk_Fwd", clampf(flat_speed / 1.1, 0.6, 2.0))
