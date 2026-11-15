class_name CharacterModel
extends Node3D
## Visual do personagem: corpo base (Universal Base Characters), cabelo/sobrancelhas
## e animações (Universal Animation Library 1 e 2). Todos usam o mesmo esqueleto
## de 65 ossos, então as animações tocam direto, sem retarget.
## O Player só chama update_locomotion() e play_action(); não precisa conhecer nomes de animação.

const LIB_BASE := &"ual1"
const LIB_EXTRA := &"ual2"

## Peças extras com o mesmo esqueleto (cabelo, sobrancelhas, roupas futuras).
## São presas ao Skeleton3D do corpo ao iniciar.
@export var attachments: Array[PackedScene] = []
@export var blend_time := 0.2
## A textura de cabelo do pacote é cinza e feita para ser tingida. Vale para cabelo e sobrancelhas.
@export var hair_color := Color(0.22, 0.14, 0.08)
## Multiplica a cor da pele (branco = original). Zumbis usam um tom cinza-esverdeado.
@export var skin_tint := Color.WHITE

var _current := &""
var _in_action := false

@onready var body: Node3D = $Body
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Body/Armature/Skeleton3D


func _ready() -> void:
	for scene in attachments:
		if scene:
			attach(scene)
	set_hair_color(hair_color)
	if skin_tint != Color.WHITE:
		set_skin_tint(skin_tint)
	anim.animation_finished.connect(func(_n: StringName) -> void: _in_action = false)
	play(&"Idle")


## Prende as malhas de uma cena com o mesmo esqueleto ao esqueleto do corpo.
func attach(scene: PackedScene) -> void:
	var instance := scene.instantiate()
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D"):
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
	instance.free()


func set_hair_color(color: Color) -> void:
	hair_color = color
	for mesh: MeshInstance3D in skeleton.get_children():
		if not (String(mesh.name).begins_with("Hair") or String(mesh.name).begins_with("Eyebrows")):
			continue
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = color
				mesh.set_surface_override_material(i, mat)


func set_skin_tint(color: Color) -> void:
	skin_tint = color
	for mesh: MeshInstance3D in skeleton.get_children():
		var n := String(mesh.name)
		if n.begins_with("Hair") or n.begins_with("Eyebrows") or n.begins_with("Eyes"):
			continue
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = color
				mesh.set_surface_override_material(i, mat)


## Escolhe a animação de locomoção a partir do estado do Player.
## local_velocity: velocidade no espaço do personagem (-Z = frente).
func update_locomotion(local_velocity: Vector3, on_floor: bool, crouching: bool, sprinting: bool) -> void:
	if _in_action:
		return
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var moving := flat.length() > 0.3
	var backwards := local_velocity.z > 0.3 and absf(local_velocity.z) > absf(local_velocity.x)
	var speed_scale := -1.0 if backwards else 1.0

	if not on_floor:
		play(&"Jump")
	elif crouching:
		play(&"Crouch_Fwd" if moving else &"Crouch_Idle", speed_scale)
	elif not moving:
		play(&"Idle")
	elif sprinting and not backwards:
		play(&"Sprint")
	else:
		play(&"Jog_Fwd", speed_scale)


## Animações de uma vez só (ataque, recarga, dano). Interrompem a locomoção até acabar.
func play_action(anim_name: StringName) -> void:
	var full := _resolve(anim_name)
	if full.is_empty():
		push_warning("Animação não encontrada: %s" % anim_name)
		return
	anim.speed_scale = 1.0
	anim.play(full, blend_time * 0.5)
	_current = full
	_in_action = true


func is_in_action() -> bool:
	return _in_action


## Libera a locomoção na hora (ex.: ao renascer no meio da animação de morte).
func cancel_action() -> void:
	_in_action = false
	_current = &""


func play(anim_name: StringName, speed_scale := 1.0) -> void:
	var full := _resolve(anim_name)
	if full.is_empty():
		return
	if full == _current and anim.is_playing():
		anim.speed_scale = speed_scale
		return
	anim.speed_scale = speed_scale
	anim.play(full, blend_time)
	_current = full


## Aceita "Idle" ou "ual2/Zombie_Idle"; procura primeiro na UAL1, depois na UAL2.
func _resolve(anim_name: StringName) -> StringName:
	if anim.has_animation(anim_name):
		return anim_name
	for lib in [LIB_BASE, LIB_EXTRA]:
		var full := StringName("%s/%s" % [lib, anim_name])
		if anim.has_animation(full):
			return full
	return &""

