class_name CharacterModel
extends Node3D
## Visual de personagens e monstros com os modelos KayKit (CC0, Kay Lousberg).
## - Rigados (KayKit Adventurers: Knight, Mage, Ranger, Barbarian, Rogue): esqueleto
##   Rig_Medium; animações do KayKit Character Animations (bibliotecas carregadas uma vez
##   e compartilhadas por todos).
## - Rígidos (KayKit Skeletons 1.0: peças sem esqueleto de animação): animação por código
##   (balanço ao andar, braço no ataque, recuo ao levar dano, queda ao morrer).
## O resto do jogo chama os nomes antigos ("Idle", "Jog_Fwd", "Hit_Chest"...): ALIASES
## traduz para as animações do KayKit. Também mostra a arma na mão (set_held_item).

const ANIM_DIR := "res://assets/animations/kaykit/"
const ANIM_FILES := ["Rig_Medium_General", "Rig_Medium_MovementBasic", "Rig_Medium_MovementAdvanced",
	"Rig_Medium_CombatMelee", "Rig_Medium_CombatRanged", "Rig_Medium_Tools", "Rig_Medium_Special"]
const BODIES := {
	"knight": "res://assets/models/characters/kaykit/Knight.glb",
	"mage": "res://assets/models/characters/kaykit/Mage.glb",
	"ranger": "res://assets/models/characters/kaykit/Ranger.glb",
	"barbarian": "res://assets/models/characters/kaykit/Barbarian.glb",
	"rogue": "res://assets/models/characters/kaykit/Rogue.glb",
	"rogue_hooded": "res://assets/models/characters/kaykit/Rogue_Hooded.glb",
	"skeleton_minion": "res://assets/models/enemies/skeletons/character_skeleton_minion.gltf",
	"skeleton_warrior": "res://assets/models/enemies/skeletons/character_skeleton_warrior.gltf",
	"skeleton_mage": "res://assets/models/enemies/skeletons/character_skeleton_mage.gltf",
	"skeleton_archer": "res://assets/models/enemies/skeletons/character_skeleton_archer.gltf",
}
## Altura do modelo com escala 1 do nó (a cápsula do jogador tem 1,8 m).
const TARGET_HEIGHT := 1.85
## Nome usado no jogo → animação do KayKit.
const ALIASES := {
	"Idle": "Idle_A", "Jog_Fwd": "Running_A", "Walk_Fwd": "Walking_A", "Sprint": "Running_B",
	"Walk_Bwd": "Walking_Backwards", "Crouch_Idle": "Crouching", "Crouch_Fwd": "Sneaking", "Jump": "Jump_Idle",
	"Hit_Chest": "Hit_A", "Death01": "Death_A", "Consume": "Use_Item", "Throw": "Throw",
	"Spell_Simple_Shoot": "Ranged_Magic_Shoot", "Punch_Jab": "Melee_Unarmed_Attack_Punch_A",
	"Punch_Cross": "Melee_Unarmed_Attack_Kick", "Sword_Regular_A": "Melee_1H_Attack_Slice_Diagonal",
	"Sword_Regular_B": "Melee_1H_Attack_Slice_Horizontal", "Sword_Regular_C": "Melee_1H_Attack_Chop",
	"Heavy_A": "Melee_2H_Attack_Chop", "Heavy_B": "Melee_2H_Attack_Slice",
	"Zombie_Idle": "Idle_B", "Zombie_Walk_Fwd": "Walking_B", "Zombie_Scratch": "Melee_1H_Attack_Chop",
}
## Animações que repetem (o pacote vem com todas sem repetição).
const LOOPED := ["Idle_A", "Idle_B", "Running_A", "Running_B", "Walking_A", "Walking_B", "Walking_C",
	"Walking_Backwards", "Crouching", "Sneaking", "Jump_Idle", "Melee_2H_Idle", "Melee_Unarmed_Idle",
	"Melee_Blocking", "Ranged_Bow_Idle", "Ranged_Bow_Aiming_Idle", "Ranged_Magic_Spellcasting",
	"Chopping", "Pickaxing", "Digging", "Fishing_Idle", "Fishing_Reeling", "Skeletons_Idle", "Skeletons_Walking",
	"Running_Strafe_Left", "Running_Strafe_Right", "Crawling", "Sit_Floor_Idle", "Lie_Idle"]
## Peças que dependem do equipamento: cabeça (capacete, chapéu, capuz) e peito (capa).
const HEAD_PARTS := ["Helmet", "HelmetVisor", "Hat", "Hood"]
const CHEST_PARTS := ["Cape"]

static var _libs := {}  # nome → AnimationLibrary (carregadas uma vez)

@export var blend_time := 0.2
## Corpo inicial (chave de BODIES). O jogador troca pela classe; monstros pelo tipo.
@export var body_kind := "knight"
## Multiplica a cor das texturas (branco = original). Monstros usam tons por tipo.
@export var skin_tint := Color.WHITE

var body: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var rigged := false

var _current := &""
var _in_action := false
var _shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
var _outfit := PackedStringArray()
var _hand: Node3D  # onde a arma fica (encaixe da mão direita)
var _held_id := ""
var _held_node: Node3D
var _off_hand: Node3D  # encaixe da mão esquerda (arma secundária)
var _off_id := ""
var _off_node: Node3D
# Rígidos (esqueletos 1.0): peças e estado da animação por código.
var _parts := {}  # "body", "armLeft", "armRight", "head", "jaw" → MeshInstance3D
var _rest := {}  # peça → Transform3D de repouso
var _rigid_time := 0.0
var _rigid_moving := 0.0
var _rigid_action := ""
var _rigid_action_t := 0.0
var _dead_pose := false


func _ready() -> void:
	set_body(body_kind)


# --- Corpo --------------------------------------------------------------------------------

## Troca o corpo (chave de BODIES). Mantém tinta, sombra, traje e arma na mão.
func set_body(kind: String) -> void:
	if not BODIES.has(kind):
		kind = "knight"
	if body and kind == body_kind:
		return
	body_kind = kind
	if body:
		body.queue_free()
		body = null
	if anim:
		anim.queue_free()
		anim = null
	_hand = null
	_held_node = null
	_off_hand = null
	_off_node = null
	_parts.clear()
	_rest.clear()
	_current = &""
	_in_action = false
	var packed := load(BODIES[kind]) as PackedScene
	body = packed.instantiate() as Node3D
	body.name = "Body"
	add_child(body)
	body.rotation.y = PI  # os modelos olham para +Z; o jogo usa -Z como frente
	var found := body.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	rigged = skeleton != null
	body.scale = Vector3.ONE * (TARGET_HEIGHT / _model_height())
	if rigged:
		_setup_rigged()
	else:
		_setup_rigid()
	if skin_tint != Color.WHITE:
		set_skin_tint(skin_tint)
	set_shadow_mode(_shadow_mode)
	set_outfit(_outfit, true)
	var held := _held_id
	_held_id = ""
	set_held_model(held)
	var off := _off_id
	_off_id = ""
	set_offhand_model(off)
	play(&"Idle")


func _model_height() -> float:
	var top := 0.0
	for m: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var aabb := m.get_aabb()
		var t := _relative_transform(m)
		for i in 8:
			top = maxf(top, (t * aabb.get_endpoint(i)).y)
	return maxf(top, 0.5)


## Transformação de um nó relativa ao corpo (fora da árvore não dá para usar global).
func _relative_transform(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != body:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _setup_rigged() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	anim.root_node = anim.get_path_to(body)
	for lib_name: String in _libraries():
		anim.add_animation_library(lib_name, _libs[lib_name])
	anim.animation_finished.connect(func(_n: StringName) -> void: _in_action = false)
	var slot := skeleton.find_bone("handslot.r")
	if slot >= 0:
		var attach := BoneAttachment3D.new()
		attach.bone_name = "handslot.r"
		skeleton.add_child(attach)
		_hand = attach
	var left := skeleton.find_bone("handslot.l")
	if left >= 0:
		var attach_l := BoneAttachment3D.new()
		attach_l.bone_name = "handslot.l"
		skeleton.add_child(attach_l)
		_off_hand = attach_l


## Carrega (uma vez) as bibliotecas de animação dos .glb e marca as que repetem.
static func _libraries() -> Dictionary:
	if _libs.is_empty():
		for file: String in ANIM_FILES:
			var packed := load(ANIM_DIR + file + ".glb") as PackedScene
			if packed == null:
				continue
			var inst := packed.instantiate()
			var players := inst.find_children("*", "AnimationPlayer", true, false)
			if not players.is_empty():
				var lib := (players[0] as AnimationPlayer).get_animation_library("")
				for anim_name: StringName in lib.get_animation_list():
					if String(anim_name) in LOOPED:
						lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				_libs[file.trim_prefix("Rig_Medium_").to_lower()] = lib
			inst.free()
	return _libs


func _setup_rigid() -> void:
	for m: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for key in ["armLeft", "armRight", "head", "jaw", "body"]:
			if String(m.name).ends_with("_" + key):
				_parts[key] = m
				_rest[key] = m.transform
	_hand = _parts.get("armRight")
	_off_hand = _parts.get("armLeft")
	_dead_pose = false


# --- Aparência -----------------------------------------------------------------------------

## Camada de render só dos personagens dos jogadores: a luz de preenchimento da câmera
## (Player) ilumina só ela, para o personagem não sumir na sombra.
const FILL_LAYER := 1 << 1
## Este modelo recebe a luz de preenchimento (jogadores; monstros não).
var fill_lit := false


## Sombra do corpo e das armas (e a camada da luz de preenchimento, nos jogadores).
func set_shadow_mode(mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	_shadow_mode = mode
	for mesh: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = mode
		if fill_lit:
			mesh.layers |= FILL_LAYER


func set_skin_tint(color: Color) -> void:
	skin_tint = color
	if body == null:
		return
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i) as BaseMaterial3D
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = color
				mesh.set_surface_override_material(i, mat)


## Equipamento vestido ("head", "chest"). Por enquanto os acessórios da classe
## (capacete, chapéu, capuz, capa) ficam sempre visíveis: sem eles alguns modelos ficam
## carecas. Quando houver modelos de armadura por peça, eles entram aqui.
const ALWAYS_SHOW_ACCESSORIES := true


func set_outfit(parts: PackedStringArray, force := false) -> void:
	if parts == _outfit and not force:
		return
	_outfit = parts
	if body == null or not rigged:
		return
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var suffix := String(mesh.name).get_slice("_", 1)
		if suffix in HEAD_PARTS:
			mesh.visible = ALWAYS_SHOW_ACCESSORIES or "head" in parts
		elif suffix in CHEST_PARTS:
			mesh.visible = ALWAYS_SHOW_ACCESSORIES or "chest" in parts


## Arma ou ferramenta na mão (id do item; "" = mão vazia). Modelo do campo "model"
## dos dados do item (caminho em res://assets/models/ sem extensão).
func set_held_item(item_id: String) -> void:
	set_held_model(str(GameData.get_item(item_id).get("model", "")) if item_id != "" else "")


## Arma na mão pelo caminho do modelo (ver WeaponModels); "" = mão vazia.
func set_held_model(model_path: String) -> void:
	if model_path == _held_id and (_held_node != null or model_path == ""):
		return
	_held_id = model_path
	if _held_node:
		_held_node.queue_free()
		_held_node = null
	if model_path == "" or _hand == null:
		return
	var node := WeaponModels.instance(model_path)
	if node == null:
		return
	if not rigged:
		# Esqueleto rígido: preso na ponta do braço direito.
		node.position = Vector3(0, -0.42, 0.08)
		node.rotation = Vector3(deg_to_rad(-25), 0, 0)  # em pé, um pouco para a frente
	_hand.add_child(node)
	_held_node = node
	set_shadow_mode(_shadow_mode)


## Arma secundária (escudo, aljava, grimório, segunda adaga) pelo id do item; "" = nada.
func set_offhand_item(item_id: String) -> void:
	set_offhand_model(str(GameData.get_item(item_id).get("model", "")) if item_id != "" else "")


## Arma secundária na mão esquerda pelo caminho do modelo. A aljava vai nas costas.
func set_offhand_model(model_path: String) -> void:
	if model_path == _off_id and (_off_node != null or model_path == ""):
		return
	_off_id = model_path
	if _off_node:
		_off_node.queue_free()
		_off_node = null
	if model_path == "" or _off_hand == null:
		return
	var node := WeaponModels.instance(model_path)
	if node == null:
		return
	var parent: Node3D = _off_hand
	if model_path.ends_with("quiver"):
		# Aljava: presa no peito, virada para as costas.
		parent = self
		node.position = Vector3(0.12, 1.15, 0.18)
		node.rotation = Vector3(deg_to_rad(15), PI, deg_to_rad(-20))
	elif not rigged:
		node.position = Vector3(0, -0.42, 0.08)
		node.rotation = Vector3(deg_to_rad(-25), 0, 0)
	parent.add_child(node)
	_off_node = node
	set_shadow_mode(_shadow_mode)


# --- Animação ------------------------------------------------------------------------------

## Escolhe a animação de locomoção a partir do estado do Player.
## local_velocity: velocidade no espaço do personagem (-Z = frente).
func update_locomotion(local_velocity: Vector3, on_floor: bool, crouching: bool, sprinting: bool) -> void:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	_rigid_moving = flat.length()
	if _in_action:
		return
	var moving := flat.length() > 0.3
	var backwards := local_velocity.z > 0.3 and absf(local_velocity.z) > absf(local_velocity.x)
	if not on_floor:
		play(&"Jump")
	elif crouching:
		play(&"Crouch_Fwd" if moving else &"Crouch_Idle")
	elif not moving:
		play(&"Idle")
	elif backwards:
		play(&"Walk_Bwd")
	elif sprinting:
		play(&"Sprint")
	else:
		play(&"Jog_Fwd")


## Animações de uma vez só (ataque, dano, morte). Interrompem a locomoção até acabar.
## duration > 0: a animação é acelerada/desacelerada para durar isso (ataques seguem o
## tempo do golpe, que já inclui a velocidade de ataque).
func play_action(anim_name: StringName, duration := 0.0) -> void:
	if not rigged:
		_rigid_start(String(anim_name))
		return
	var full := _resolve(anim_name)
	if full.is_empty():
		push_warning("Animação não encontrada: %s" % anim_name)
		return
	var speed := 1.0
	if duration > 0.0:
		speed = clampf(anim.get_animation(full).length / duration, 0.5, 3.5)
	anim.speed_scale = speed
	anim.play(full, blend_time * 0.5)
	_current = full
	_in_action = true


func is_in_action() -> bool:
	return _in_action


## Libera a locomoção na hora (ex.: ao renascer no meio da animação de morte).
func cancel_action() -> void:
	_in_action = false
	_current = &""
	_rigid_action = ""
	if not rigged and _dead_pose:
		_dead_pose = false
		body.rotation = Vector3(0, PI, 0)
		body.position = Vector3.ZERO


func play(anim_name: StringName, speed_scale := 1.0) -> void:
	if not rigged:
		return  # rígido: a locomoção vem de update_locomotion/_process
	var full := _resolve(anim_name)
	if full.is_empty():
		return
	if full == _current and anim.is_playing():
		anim.speed_scale = speed_scale
		return
	anim.speed_scale = speed_scale
	anim.play(full, blend_time)
	_current = full


## "Idle" → "general/Idle_A" (pelos ALIASES), ou um nome do KayKit direto.
func _resolve(anim_name: StringName) -> StringName:
	var wanted := String(ALIASES.get(String(anim_name), String(anim_name)))
	if anim.has_animation(wanted):
		return StringName(wanted)
	for lib: StringName in anim.get_animation_library_list():
		var full := StringName("%s/%s" % [lib, wanted])
		if anim.has_animation(full):
			return full
	return &""


# --- Rígidos: animação por código -----------------------------------------------------------

func _rigid_start(action: String) -> void:
	if action in ["Death01", "Death_A", "Skeletons_Death"]:
		_rigid_action = "death"
	elif action in ["Hit_Chest", "Hit_A"]:
		_rigid_action = "hit"
	else:
		_rigid_action = "attack"
	_rigid_action_t = 0.0
	_in_action = true


func _process(delta: float) -> void:
	if rigged or body == null or _parts.is_empty():
		return
	_rigid_time += delta
	var walk := clampf(_rigid_moving / 2.0, 0.0, 1.5)
	var swing := sin(_rigid_time * (6.0 + walk * 4.0)) * 0.6 * walk
	var bob := absf(sin(_rigid_time * (6.0 + walk * 4.0))) * 0.04 * walk + sin(_rigid_time * 2.0) * 0.01
	var arm_l := swing
	var arm_r := -swing
	var lean := 0.0
	var jaw := sin(_rigid_time * 3.0) * 0.08
	if _rigid_action != "":
		_rigid_action_t += delta
		var t := _rigid_action_t
		match _rigid_action:
			"attack":
				var k := t / 0.6
				arm_r = -2.2 * sin(clampf(k, 0.0, 1.0) * PI)  # levanta e desce o braço
				lean = 0.15 * sin(clampf(k, 0.0, 1.0) * PI)
				jaw = 0.3
				if k >= 1.0:
					_rigid_action = ""
					_in_action = false
			"hit":
				var k := t / 0.35
				lean = -0.3 * sin(clampf(k, 0.0, 1.0) * PI)
				if k >= 1.0:
					_rigid_action = ""
					_in_action = false
			"death":
				var k := clampf(t / 0.6, 0.0, 1.0)
				body.rotation = Vector3(-PI * 0.5 * k, PI, 0)
				body.position = Vector3(0, 0.15 * k, 0)
				_dead_pose = true
				return  # fica caído até cancel_action
	body.position = Vector3(0, bob, 0)
	body.rotation = Vector3(lean, PI, 0)
	_pose("armLeft", Vector3(arm_l, 0, 0))
	_pose("armRight", Vector3(arm_r, 0, 0))
	_pose("jaw", Vector3(jaw, 0, 0))


func _pose(key: String, rot: Vector3) -> void:
	var part := _parts.get(key) as Node3D
	if part:
		var rest: Transform3D = _rest[key]
		part.transform = Transform3D(rest.basis * Basis.from_euler(rot), rest.origin)
