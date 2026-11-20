class_name Player
extends CharacterBody3D
## Jogador: movimento, pulo, corrida, agachar e câmera em 3ª pessoa (estilo RPG de ação).
## - Câmera própria (não segue o giro do corpo): gira segurando o botão direito do mouse,
##   roda do mouse aproxima/afasta (até 2x a distância padrão). O mouse fica sempre livre.
## - WASD anda em relação à câmera e o corpo vira para onde anda.
## - Clicar num inimigo seleciona o alvo (anel vermelho). Armas à distância e feitiços vão
##   no alvo; sem alvo, no ponto do mundo sob o cursor. Ao atacar, o personagem vira para
##   o alvo/cursor e anda mais devagar enquanto dura o ataque.
## Valores provisórios: ajustar com testes (GDD 5.5 e 16).
##
## Rede: o nó se chama com o id do jogador (peer id) e esse jogador é a autoridade
## dele. Na máquina dono, lê teclado/mouse e move; nas outras, só mostra a posição
## e a animação que chegam pelo MultiplayerSynchronizer (net_* abaixo).

## Avisa o HUD sobre o que está na mira para interagir ("" = nada).
signal interaction_prompt_changed(text: String)
## Aviso curto para o HUD ("Você passou mal", "Não dá para colocar aqui"...).
signal notified(text: String)

## Kit inicial de todo personagem novo: o resto se coleta, acha ou fabrica.
## Cada entrada: [id, quantidade, slot da hotbar ou -1].
const STARTER_KIT := [
	["torch", 1, 0], ["berries", 5, 1],
]

@export_group("Movimento")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 2.5
@export var jump_velocity := 4.5
@export var acceleration := 12.0
## Stamina gasta por segundo correndo (GDD 7).
@export var sprint_stamina_per_second := 8.0
## Velocidade com o inventário acima do peso máximo (fração da normal).
@export var overloaded_speed_factor := 0.55
## Alcance para interagir (pegar itens, portas...).
@export var interact_range := 2.8
## Raio da coleta automática de itens no chão (0 desliga).
@export var auto_pickup_radius := 1.3

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
@export var third_person_offset := Vector3(0.0, 0.35, 0.0)
## Zoom da câmera (roda do mouse): de ZOOM_MIN até 2x a distância padrão.
const ZOOM_MIN := 1.5
const ZOOM_STEP := 0.35
## Velocidade enquanto ataca (fração da normal).
const ATTACK_MOVE_FACTOR := 0.4
## Alcance máximo do alvo selecionado (passa disso, o alvo é solto).
const TARGET_RANGE := 60.0

## Câmera: giro (yaw) e inclinação (pitch) próprios, e distância (zoom).
var camera_yaw := 0.0
var camera_pitch := -0.3
var _zoom := 3.5
## Inimigo selecionado (clique). Armas à distância e feitiços miram nele.
var target: Node3D = null
var _target_ring: MeshInstance3D
## Até quando (ms) o personagem está atacando: anda mais devagar.
var _attack_until := 0

# Estado de animação replicado para os outros jogadores.
var net_crouching := false
## Agachar: alternado (Ctrl liga/desliga) ou segurado, conforme Configurações. Correr ou pular levanta.
var _crouch_on := false
## Correr no modo alternado (Shift liga/desliga; parar de andar ou acabar a stamina desliga).
var _sprint_on := false
var net_sprinting := false
var net_on_floor := true
## Segurando uma tocha acesa (luz visível para todos).
var net_torch := false:
	set(value):
		net_torch = value
		if _torch_light:
			_torch_light.visible = value

var _torch_light: OmniLight3D

## Auras ligadas pelo dono ("id,força,raio;..."), replicadas: aliados perto recebem o
## bônus (ver Auras).
var net_auras := ""

## Classe do personagem (data/backgrounds): define o corpo KayKit ("model"). Replicada.
var net_class := "":
	set(value):
		net_class = value
		if is_node_ready():
			model.set_body(str(GameData.get_entry("backgrounds", value).get("model", "knight")))

## Item na mão (id), replicado: os outros veem a arma/ferramenta no modelo.
var net_held := "":
	set(value):
		net_held = value
		if is_node_ready():
			model.set_held_item(value)

## Peças de traje vestidas (nomes separados por vírgula), replicadas: todos veem a roupa.
var net_outfit := "":
	set(value):
		net_outfit = value
		if is_node_ready():
			model.set_outfit(PackedStringArray(value.split(",", false)))

var _noise_timer := 0.0
var _spawn_point := Vector3.ZERO
var _spawn_point_set := false
## Dormiu numa cama: renasce nela.
var has_bed := false
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
@onready var inventory: Inventory = $Inventory
@onready var survival: Survival = $Survival
@onready var death_penalty: DeathPenalty = $DeathPenalty
@onready var craft_queue: CraftQueue = $CraftQueue
## Proficiências, nível e habilidades (criado no _ready, em todas as máquinas).
var progression: Progression
var auras: Auras
var effects: StatusEffects
## Capacete, armadura, calça, botas, luvas, anéis e colar.
var equipment: Equipment
## Roda de habilidades do HUD (Q segurado); o HUD preenche.
var skill_wheel: SkillWheel

## Modo construção (tecla B). Só existe no jogador local.
var build: BuildMode

## Modo criativo (Esc > configurações): invencível, itens não se gastam, aba Criativo, pode voar.
var creative := false:
	set(value):
		creative = value
		if inventory:
			inventory.creative = value
		if health:
			health.set_invulnerable(value)
		if not value:
			flying = false
		EventBus.creative_changed.emit(value)
## Voando (só no criativo): Espaço sobe, Ctrl desce. Espaço duas vezes liga/desliga.
var flying := false:
	set(value):
		flying = value and creative
		if flying:
			_crouch_on = false
const FLY_SPEED_FACTOR := 2.0
const FLY_VERTICAL := 7.0
const DOUBLE_TAP_MS := 300
var _last_jump_ms := -10000

var _focused: Node = null
var _has_focus := false
var _pickup_timer := 0.0
## Itens já pedidos ao servidor (nome -> hora), para não repetir o pedido enquanto ele responde.
var _pickup_pending := {}


func _enter_tree() -> void:
	# O nome do nó é o id do jogador dono (o servidor cria assim, ver arena.gd).
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	spring_arm.add_excluded_object(get_rid())
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	_torch_light = OmniLight3D.new()
	_torch_light.light_color = Color(1.0, 0.7, 0.4)
	_torch_light.light_energy = 2.6
	_torch_light.omni_range = 10.0
	_torch_light.shadow_enabled = true
	_torch_light.position = Vector3(0.35, -0.25, -0.3)
	_torch_light.visible = net_torch
	head.add_child(_torch_light)
	equipment = Equipment.new()
	equipment.name = "Equipment"
	add_child(equipment)
	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.leveled.connect(notify)
	auras = Auras.new()
	auras.name = "Auras"
	add_child(auras)
	effects = StatusEffects.new()
	effects.name = "Effects"
	add_child(effects)
	equipment.changed.connect(_update_outfit)
	model.set_body(str(GameData.get_entry("backgrounds", net_class).get("model", "knight")))
	model.set_held_item(net_held)
	model.set_outfit(PackedStringArray(net_outfit.split(",", false)))
	weapons.setup(self, camera, head, inventory)
	weapons.changed.connect(_update_held)
	# Regeneração de vida só corre na máquina do dono (ver Survival).
	survival.set_process(is_local())
	death_penalty.set_process(is_local())
	craft_queue.set_process(is_local())
	if is_local():
		var exploration := Exploration.new()
		exploration.name = "Exploration"
		add_child(exploration)
		build = BuildMode.new()
		build.name = "BuildMode"
		add_child(build)
		build.setup(self)
		camera.current = true
		mouse_sensitivity = Settings.mouse_sensitivity
		Settings.changed.connect(_on_settings_changed)
		# Personagem escolhido no menu: o salvo (itens, níveis...) ou, se for novo, kit
		# inicial + passado.
		if not SaveGame.apply_character(self):
			_give_starter_kit()
			_apply_background(SaveGame.character_background())
		MouseMode.refresh()
		net_class = progression.char_class  # corpo da classe (salva ou escolhida no menu)
		camera_yaw = rotation.y
		_zoom = third_person_distance
		_update_outfit()
		_update_held()
		_apply_camera_mode()
	else:
		# Personagem de outro jogador: sem câmera, sem armas de 1ª pessoa, corpo visível.
		camera.current = false
		weapons.visible = false
		set_process_unhandled_input(false)
	# Nós criados aqui (Progression, Equipment, Exploration, BuildMode...) nasceram depois
	# do set_multiplayer_authority do _enter_tree: reaplica para eles serem do dono também.
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())
	EventBus.player_spawned.emit(self)


func _on_settings_changed() -> void:
	mouse_sensitivity = Settings.mouse_sensitivity
	if not Settings.sprint_toggle:
		_sprint_on = false


## Dono: traje a partir do equipamento vestido (peças com "outfit"; quebradas não aparecem).
## Peças vestidas que mudam o modelo: "head" (capacete/chapéu/capuz) e "chest" (capa).
func _update_outfit() -> void:
	if not is_local():
		return
	var parts := PackedStringArray()
	for slot: String in ["head", "chest"]:
		var item := equipment.get_item(slot)
		if not item.is_empty() and not Inventory.is_broken(item):
			parts.append(slot)
	net_outfit = ",".join(parts)


## Arma ou ferramenta selecionada na hotbar (para o modelo em 3ª pessoa e os outros).
func _update_held() -> void:
	if not is_local():
		return
	var item := weapons.selected_item()
	net_held = str(item.get("id", "")) if not item.is_empty() else ""


## Verdadeiro se este é o personagem controlado nesta máquina.
func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and MouseMode.looking():
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch = clampf(camera_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-80.0), deg_to_rad(35.0))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and MouseMode.playing():
		# Segurar o botão direito gira a câmera.
		MouseMode.set_rotating(event.pressed, get_viewport())
	elif event is InputEventMouseButton and event.pressed and MouseMode.playing() \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not (build and build.active):
		var step := -ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP
		_zoom = clampf(_zoom + step, ZOOM_MIN, third_person_distance * 2.0)
		spring_arm.spring_length = _zoom
	elif event.is_action_pressed("interact") and _focused and not health.is_dead:
		_focused.interact(self)
	elif event.is_action_pressed("attack") and MouseMode.playing():
		_pick_target()


func _physics_process(delta: float) -> void:
	if not is_local():
		# Posição e rotação chegam pela rede; entre pacotes, anda pela velocidade recebida
		# (liso mesmo com a internet atrasando alguns pacotes) e anima.
		if not health.is_dead:
			position += Vector3(velocity.x, 0.0, velocity.z) * delta
			model.update_locomotion(velocity * transform.basis, net_on_floor, net_crouching, net_sprinting)
		return

	if not _spawn_point_set:
		# Num cliente a posição inicial chega pela rede depois do _ready; por isso aqui.
		_spawn_point = global_position
		_spawn_point_set = true

	if health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return

	var captured := MouseMode.playing()  # nenhuma tela aberta: teclas valem
	if creative and captured and Input.is_action_just_pressed("jump"):
		var now := Time.get_ticks_msec()
		if now - _last_jump_ms < DOUBLE_TAP_MS:
			flying = not flying
			notify(tr("Voo %s") % (tr("ligado (Espaço sobe, Ctrl desce)") if flying else tr("desligado")))
			now = -10000
		_last_jump_ms = now
	if flying:
		var up := 0.0
		if captured and Input.is_action_pressed("jump"):
			up += 1.0
		if captured and Input.is_action_pressed("crouch"):
			up -= 1.0
		velocity.y = lerpf(velocity.y, up * FLY_VERTICAL, minf(acceleration * delta, 1.0))
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		progression.gain("athletics", 0.3)

	if captured and Settings.sprint_toggle and Input.is_action_just_pressed("sprint"):
		_sprint_on = not _sprint_on
	if not flying and captured:
		if Settings.crouch_toggle:
			if Input.is_action_just_pressed("crouch"):
				_crouch_on = not _crouch_on
		else:
			_crouch_on = Input.is_action_pressed("crouch")
	if _crouch_on and Settings.crouch_toggle and (Input.is_action_just_pressed("jump") or _sprint_pressed()):
		_crouch_on = false
	var crouching := _crouch_on
	var target_head := crouch_head_height if crouching else stand_head_height
	head.position.y = lerpf(head.position.y, target_head, minf(10.0 * delta, 1.0))

	_update_target_ring()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _sprint_on and (input.length() < 0.1 or stamina.current <= 0.0):
		_sprint_on = false  # corrida alternada para quando o jogador para ou cansa
	var direction := (Basis(Vector3.UP, camera_yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	if direction.length() > 0.1 and Time.get_ticks_msec() >= _attack_until:
		# O corpo vira para onde anda (atacando, fica virado para o alvo).
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(12.0 * delta, 1.0))
	var target := direction * _current_speed(crouching) * (FLY_SPEED_FACTOR if flying else 1.0)
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)

	move_and_slide()

	var sprinting := _wants_sprint(crouching) and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	if sprinting:
		stamina.drain(sprint_stamina_per_second * progression.mult("sprint_stamina") * delta)
		progression.gain("athletics", Vector2(velocity.x, velocity.z).length() * delta * 0.1)
	net_crouching = crouching
	net_sprinting = sprinting
	net_on_floor = is_on_floor()
	model.update_locomotion(velocity * transform.basis, is_on_floor(), crouching, sprinting)
	_update_camera_rig()
	_emit_footstep_noise(delta, crouching, sprinting)
	_update_focus()
	_auto_pickup(delta)


## Pega sozinho itens bem perto (se couberem). A regra da espera de quem soltou
## é conferida aqui (para não pedir à toa) e de novo no servidor.
func _auto_pickup(delta: float) -> void:
	_pickup_timer -= delta
	if auto_pickup_radius <= 0.0 or _pickup_timer > 0.0:
		return
	_pickup_timer = 0.2
	var now := Time.get_ticks_msec()
	var me := get_multiplayer_authority()
	for item in WorldItems.all_items():
		if item is DeathBag:
			continue  # bag só com E (pega tudo de uma vez)
		if item.is_queued_for_deletion() or global_position.distance_to(item.global_position) > auto_pickup_radius:
			continue
		if now - int(_pickup_pending.get(item.name, -100000)) < 1000:
			continue
		if not WorldItems.can_auto_pickup(item, me) or inventory.room_for(item.item_id) <= 0:
			continue
		_pickup_pending[item.name] = now
		WorldItems.request_pickup(item, self, true)


## O que está na mira e pode ser usado com E (itens no chão etc.).
func _update_focus() -> void:
	if _has_focus and not is_instance_valid(_focused):
		# O que estava na mira sumiu (colhido, pego por outro jogador...). Objeto liberado
		# compara igual a null, por isso a flag _has_focus.
		_focused = null
		_has_focus = false
		interaction_prompt_changed.emit("")
	# Sob o cursor e perto; senão, o interagível mais próximo ao alcance.
	var hit := cursor_ray(30.0, 1 | 8 | 32 | BuildPiece.DOOR_LAYER)
	var found: Node = _usable(hit.get("collider"))
	if found == null:
		var shape := SphereShape3D.new()
		shape.radius = interact_range
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.8)
		query.collision_mask = 1 | 8 | 32 | BuildPiece.DOOR_LAYER
		query.exclude = [get_rid()]
		var best := INF
		for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 24):
			var node := _usable(r.collider)
			if node:
				var d := (node as Node3D).global_position.distance_to(global_position)
				if d < best:
					best = d
					found = node
	if found != _focused:
		_focused = found
		_has_focus = found != null
		interaction_prompt_changed.emit(_focused.get_prompt() if _focused else "")


## O nó pode ser usado com E agora (tem interact, tem aviso e está ao alcance)?
func _usable(collider: Object) -> Node:
	var node := collider as Node3D
	if node == null or not node.has_method(&"interact"):
		return null
	if node.has_method(&"has_prompt") and not node.has_prompt():
		return null  # ex.: árvore (coleta é por golpe, não por E)
	if node.global_position.distance_to(global_position) > interact_range + 1.0:
		return null
	return node


func _give_starter_kit() -> void:
	for entry in STARTER_KIT:
		var slot_index: int = entry[2]
		if slot_index >= 0 and inventory.get_slot(slot_index).is_empty():
			inventory.slots[slot_index] = {"id": entry[0], "count": entry[1]}
		else:
			inventory.add_item(entry[0], entry[1])
	inventory.changed.emit()


## Classe escolhida no menu: início da árvore passiva e itens extras.
func _apply_background(background_id: String) -> void:
	var data := GameData.get_entry("backgrounds", background_id)
	if data.is_empty():
		return
	progression.apply_background(background_id)
	var items: Dictionary = data.get("starting_items", {})
	for id: String in items:
		var left := inventory.add_item(id, int(items[id]))
		if left > 0:
			WorldItems.drop(id, left, global_position + Vector3.UP * 0.3, null)


func _emit_footstep_noise(delta: float, crouching: bool, sprinting: bool) -> void:
	_noise_timer -= delta
	if _noise_timer > 0.0 or not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 0.5:
		return
	_noise_timer = noise_interval
	var loudness := crouch_noise if crouching else (sprint_noise if sprinting else walk_noise)
	Sfx.play("step", global_position, -14.0 if crouching else (-4.0 if sprinting else -9.0), 0.2)
	Network.emit_noise(global_position, loudness * progression.mult("noise"), self)
	if crouching and _zombie_nearby(12.0):
		progression.gain("stealth", 0.25)


## Algum zumbi vivo e sem caçar ninguém por perto? (XP de furtividade)
func _zombie_nearby(radius: float) -> bool:
	for z: Node3D in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(global_position) <= radius and not z.is_dead() \
				and z.state in [Zombie.State.WANDER, Zombie.State.INVESTIGATE]:
			return true
	return false


# --- Ações visíveis para todos -----------------------------------------------------

## Animação de ação (golpe, tiro, feitiço) aqui e nas telas dos outros jogadores.
## duration > 0: a animação dura isso (acelera com a velocidade de ataque). Ataques
## (attack = true) viram o corpo para o alvo/cursor e deixam o personagem mais lento.
func play_action_synced(anim_name: StringName, duration := 0.0, attack := false) -> void:
	if attack and is_local():
		_attack_until = Time.get_ticks_msec() + int(maxf(duration, 0.3) * 1000.0)
		face_point(aim_point(60.0))
	model.play_action(anim_name, duration)
	if Network.is_online():
		_remote_action.rpc(anim_name, duration)


@rpc("authority", "call_remote", "unreliable")
func _remote_action(anim_name: StringName, duration: float) -> void:
	model.play_action(anim_name, duration)


# --- Mira: cursor, alvo e origem dos tiros ------------------------------------------

## Raio da câmera pelo cursor (ou pelo centro, girando a câmera). Retorna o dicionário
## do intersect_ray, sempre com "position" (sem acerto: o ponto a max_range) e "dir".
func cursor_ray(max_range: float, mask := 1 | 4 | 8) -> Dictionary:
	var viewport := get_viewport()
	var screen := viewport.get_mouse_position() if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			else viewport.get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var reach := max_range + spring_arm.get_hit_length()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, mask)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		hit = {"position": from + dir * reach, "miss": true}
	hit["dir"] = dir
	hit["from"] = from
	return hit


## Ponto para onde ataques à distância vão: o alvo (peito), ou o ponto sob o cursor.
func aim_point(max_range: float) -> Vector3:
	if has_target():
		return target.global_position + Vector3.UP * 1.1
	return cursor_ray(max_range).position


## De onde saem flechas, feitiços e facas: na frente do peito, na direção do ponto.
func shot_origin(toward: Vector3) -> Vector3:
	var chest := global_position + Vector3.UP * 1.35
	var flat := Vector3(toward.x - chest.x, 0.0, toward.z - chest.z)
	return chest + (flat.normalized() * 0.5 if flat.length() > 0.01 else -global_basis.z * 0.5)


## Vira o corpo (na hora) para um ponto.
func face_point(point: Vector3) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() > 0.1:
		rotation.y = atan2(-flat.x, -flat.z)


func has_target() -> bool:
	return is_instance_valid(target) and not (target.get(&"health") != null and target.health.is_dead) \
		and target.global_position.distance_to(global_position) <= TARGET_RANGE


## Clique: se o cursor está em cima de um inimigo, ele vira o alvo.
func _pick_target() -> void:
	var hit := cursor_ray(TARGET_RANGE, 4)
	var collider: Object = hit.get("collider")
	if collider is Node3D and (collider as Node).is_in_group("zombies"):
		target = collider


func _update_target_ring() -> void:
	if not has_target():
		target = null
		if _target_ring:
			_target_ring.visible = false
		return
	if _target_ring == null:
		_target_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.68
		torus.rings = 32
		torus.ring_segments = 4
		_target_ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.25, 0.2, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_target_ring.material_override = mat
		_target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_target_ring.top_level = true
		add_child(_target_ring)
	_target_ring.visible = true
	var s := maxf(target.scale.x, 1.0)
	_target_ring.global_transform = Transform3D(Basis().scaled(Vector3.ONE * s), target.global_position + Vector3.UP * 0.06)


## Efeitos de arma (rastro de tiro, dardo) mostrados nas telas dos outros jogadores.
func broadcast_fx(kind: StringName, from: Vector3, to: Vector3, color := Color.WHITE) -> void:
	if Network.is_online():
		_remote_fx.rpc(kind, from, to, color)


@rpc("authority", "call_remote", "unreliable")
func _remote_fx(kind: StringName, from: Vector3, to: Vector3, color: Color) -> void:
	match kind:
		&"tracer":
			Weapon.spawn_tracer(self, from, to)
			Sfx.play("spell", from, -3.0)
		&"ring":
			SpellCaster._ring_fx(self, from, from.distance_to(to), color)
		&"arrow":
			Sfx.play("bow", from)
			var arrow: Node3D = Bow.ARROW.new()
			arrow.visual_only = true
			arrow.caster = self
			arrow.velocity = to - from
			get_tree().current_scene.add_child(arrow)
			arrow.global_position = from
		&"bolt":
			Sfx.play("spell", from, -3.0)
			var bolt: Area3D = SpellCaster.PROJECTILE.new()
			bolt.visual_only = true
			bolt.color = color
			bolt.caster = self
			get_tree().current_scene.add_child(bolt)
			bolt.global_position = from
			bolt.direction = (to - from).normalized()


# --- Vida, morte e renascimento -----------------------------------------------------

func _on_damaged(amount: float, source: Node) -> void:
	if source == self:
		return  # dano do próprio dono: sem animação de golpe
	if is_local() and source is Zombie:
		progression.gain("toughness", amount * 0.25)
		equipment.wear_on_hit()
	model.play_action(&"Hit_Chest")


func _on_died(_source: Node) -> void:
	model.play_action(&"Death01")
	EventBus.player_died.emit(self)
	if not is_local():
		return
	# Regras de morte (PROXIMOS_PASSOS, seção 13): nada cai no chão; perde 15% da XP
	# rumo ao próximo nível e 15% do ouro, e ganha Fraqueza.
	death_penalty.on_died()
	await get_tree().create_timer(respawn_delay, false).timeout
	global_position = _spawn_point
	velocity = Vector3.ZERO
	stamina.refill()
	mana.refill()
	survival.reset()
	health.reset()  # pede ao servidor; quando voltar, dispara revived


## Alcance/brilho da tocha (refino da tocha aumenta). Local; a luz em si é sincronizada por net_torch.
func set_torch_power(multiplier: float) -> void:
	if _torch_light:
		_torch_light.omni_range = 10.0 * multiplier
		_torch_light.light_energy = 2.6 * minf(multiplier, 1.3)


## Cama: passa a renascer aqui.
func set_respawn_point(at: Vector3) -> void:
	_spawn_point = at
	_spawn_point_set = true
	has_bed = true
	notify(tr("Você vai renascer nesta cama"))


## Golpe gelado: debuff Lentidão (factor 0,6 = 40% mais lento). Vem do servidor.
func apply_chill(factor: float, duration: float) -> void:
	StatusEffects.give(self, "slow", duration, clampf(1.0 - factor, 0.0, 0.8))


## Ouro de um abate (vem do servidor, já dividido entre quem estava perto).
func give_gold(amount: int) -> void:
	if is_local():
		_receive_gold(amount)
	elif Network.is_online():
		_remote_gold.rpc_id(get_multiplayer_authority(), amount)


@rpc("any_peer", "call_remote", "reliable")
func _remote_gold(amount: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_receive_gold(clampi(amount, 0, 100000))


func _receive_gold(amount: int) -> void:
	if amount <= 0:
		return
	inventory.add_gold(amount)
	notify(tr("+%d de ouro") % amount)


## Mostra um aviso curto no HUD (só faz sentido no jogador local).
func notify(text: String) -> void:
	notified.emit(text)


## Coloca uma estação (item do tipo "station") 2 m à frente, no chão.
## Retorna true se colocou (e tirou o item do slot).
func place_station(slot_index: int) -> bool:
	var s := inventory.get_slot(slot_index)
	if s.is_empty():
		return false
	var forward := -global_basis.z
	var from := global_position + forward * 2.0 + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, 1 | 8)  # chão ou piso/fundação
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.8 or not Structures.can_place_at(hit.position):
		notify(tr("Não dá para colocar aqui"))
		return false
	inventory.consume_from_slot(slot_index, 1)
	Structures.place(s.id, hit.position, rotation.y, float(s.get("dur", -1.0)))
	return true


## Tira tudo da mochila (slots depois da hotbar) e devolve como lista de pilhas.
func _empty_backpack() -> Array:
	var contents: Array = []
	for i in range(Inventory.HOTBAR_SIZE, inventory.slots.size()):
		var s := inventory.get_slot(i)
		if not s.is_empty():
			var stack := {"id": s.id, "count": int(s.count)}
			stack.merge(Inventory.extra_of(s))
			contents.append(stack)
			inventory.slots[i] = {}
	inventory.changed.emit()
	return contents


## Nome mostrado (ex.: na bag): o do personagem escolhido no menu (nesta máquina).
func display_name() -> String:
	if is_local() and SaveGame.character_name() != "":
		return SaveGame.character_name()
	var id := get_multiplayer_authority()
	return tr("Jogador 1") if id == 1 else tr("Jogador %s") % str(id).left(4)


func _on_revived() -> void:
	model.cancel_action()
	model.play(&"Idle")


## Shift: segurado ou alternado (Configurações).
func _sprint_pressed() -> bool:
	if not MouseMode.playing():
		return false
	return _sprint_on if Settings.sprint_toggle else Input.is_action_pressed("sprint")


## Sobrecarregado ainda corre, mas no ritmo reduzido (antes travava a corrida sem aviso).
func _wants_sprint(crouching: bool) -> bool:
	return _sprint_pressed() and not crouching and stamina.current > 0.0


func _current_speed(crouching: bool) -> float:
	var bonus := progression.mult("move_speed") * (ATTACK_MOVE_FACTOR if Time.get_ticks_msec() < _attack_until else 1.0)
	var factor := (overloaded_speed_factor if inventory.is_overloaded() else 1.0) * death_penalty.speed_factor() * bonus
	if crouching:
		return crouch_speed * factor
	if _wants_sprint(crouching) and is_on_floor():
		return sprint_speed * factor
	return walk_speed * factor


## Só 3ª pessoa: braço da câmera no zoom atual; as armas de 1ª pessoa (viewmodel)
## ficam escondidas (a arma aparece na mão do modelo).
func _apply_camera_mode() -> void:
	_zoom = clampf(_zoom, ZOOM_MIN, third_person_distance * 2.0)
	spring_arm.spring_length = _zoom
	spring_arm.position = third_person_offset
	weapons.visible = false
	model.set_shadow_mode(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


## A câmera tem giro próprio: o Head (filho do corpo) desfaz o giro do corpo.
func _update_camera_rig() -> void:
	head.rotation = Vector3(camera_pitch, camera_yaw - rotation.y, 0.0)
