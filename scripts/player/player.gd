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

@export_group("Câmera")
@export var mouse_sensitivity := 0.0025
@export var stand_head_height := 1.6
@export var crouch_head_height := 1.0
@export var third_person_distance := 3.5
@export var third_person_offset := Vector3(0.5, 0.2, 0.0)

var first_person := true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
## Visual do personagem. Pode ser a cápsula provisória ou um modelo .glb importado.
@onready var model: Node3D = $Model


func _ready() -> void:
	spring_arm.add_excluded_object(get_rid())
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


func _current_speed(crouching: bool) -> float:
	if crouching:
		return crouch_speed
	if Input.is_action_pressed("sprint") and is_on_floor():
		return sprint_speed
	return walk_speed


func _apply_camera_mode() -> void:
	spring_arm.spring_length = 0.0 if first_person else third_person_distance
	spring_arm.position = Vector3.ZERO if first_person else third_person_offset
	model.visible = not first_person
