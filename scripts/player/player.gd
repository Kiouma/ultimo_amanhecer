class_name Player
extends CharacterBody3D
## Controlador básico do jogador (Fase 0/1 do roadmap).
## Movimento, pulo, corrida, agachar e câmera em 1ª/3ª pessoa (tecla V).
## Valores provisórios: ajustar com testes (GDD 5.5 e 16).

@export_group("Movimento")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 2.5
@export var jump_velocity := 4.5
@export var acceleration := 12.0
## Stamina gasta por segundo correndo (GDD 7).
@export var sprint_stamina_per_second := 8.0

@export_group("Barulho")
## Raio (em metros) em que zumbis ouvem os passos (GDD 5.1). Multiplicado pela audição do zumbi.
@export var walk_noise := 6.0
@export var sprint_noise := 14.0
@export var crouch_noise := 1.5
@export var noise_interval := 0.5

@export_group("Morte (provisório)")
## Fase 1: renasce no ponto inicial. Regras do GDD 7 (bag, perda de XP) entram na Fase 2.
@export var respawn_delay := 3.0

@export_group("Câmera")
@export var mouse_sensitivity := 0.0025
@export var stand_head_height := 1.6
@export var crouch_head_height := 1.0
@export var third_person_distance := 3.5
@export var third_person_offset := Vector3(0.5, 0.2, 0.0)

var first_person := true
var _noise_timer := 0.0
var _spawn_point := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
## Visual do personagem (corpo, cabelo e animações). Ver character_model.gd.
@onready var model: CharacterModel = $Model
@onready var health: Health = $Health
@onready var stamina: StatPool = $Stamina
@onready var mana: StatPool = $Mana
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D
@onready var weapons: WeaponHolder = $Head/SpringArm3D/Camera3D/WeaponHolder


func _ready() -> void:
	spring_arm.add_excluded_object(get_rid())
	_spawn_point = global_position
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	weapons.setup(self, camera, head)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera_mode()
	EventBus.player_spawned.emit(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("toggle_camera"):
		first_person = not first_person
		_apply_camera_mode()
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("attack") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var crouching := Input.is_action_pressed("crouch")
	var target_head := crouch_head_height if crouching else stand_head_height
	head.position.y = lerpf(head.position.y, target_head, minf(10.0 * delta, 1.0))

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := direction * _current_speed(crouching)
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)

	move_and_slide()

	var sprinting := _wants_sprint(crouching) and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	if sprinting:
		stamina.drain(sprint_stamina_per_second * delta)
	model.update_locomotion(velocity * transform.basis, is_on_floor(), crouching, sprinting)
	_emit_footstep_noise(delta, crouching, sprinting)


func _emit_footstep_noise(delta: float, crouching: bool, sprinting: bool) -> void:
	_noise_timer -= delta
	if _noise_timer > 0.0 or not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 0.5:
		return
	_noise_timer = noise_interval
	var loudness := crouch_noise if crouching else (sprint_noise if sprinting else walk_noise)
	EventBus.noise_emitted.emit(global_position, loudness, self)


func _on_damaged(_amount: float, _source: Node) -> void:
	model.play_action(&"Hit_Chest")


func _on_died(_source: Node) -> void:
	model.play_action(&"Death01")
	EventBus.player_died.emit(self)
	await get_tree().create_timer(respawn_delay, false).timeout
	global_position = _spawn_point
	velocity = Vector3.ZERO
	health.reset()
	stamina.refill()
	mana.refill()
	model.cancel_action()
	model.play(&"Idle")


func _wants_sprint(crouching: bool) -> bool:
	return Input.is_action_pressed("sprint") and not crouching and stamina.current > 0.0


func _current_speed(crouching: bool) -> float:
	if crouching:
		return crouch_speed
	if _wants_sprint(crouching) and is_on_floor():
		return sprint_speed
	return walk_speed


func _apply_camera_mode() -> void:
	spring_arm.spring_length = 0.0 if first_person else third_person_distance
	spring_arm.position = Vector3.ZERO if first_person else third_person_offset
	# Na 1ª pessoa o corpo some da câmera, mas continua projetando sombra.
	# As armas de 1ª pessoa (viewmodel) só aparecem nesse modo.
	weapons.visible = first_person
	var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = shadow_mode
