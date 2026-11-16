class_name Player
extends CharacterBody3D
## Jogador: movimento, pulo, corrida, agachar e câmera em 1ª/3ª pessoa (tecla V).
## Valores provisórios: ajustar com testes (GDD 5.5 e 16).
##
## Rede: o nó se chama com o id do jogador (peer id) e esse jogador é a autoridade
## dele. Na máquina dono, lê teclado/mouse e move; nas outras, só mostra a posição
## e a animação que chegam pelo MultiplayerSynchronizer (net_* abaixo).

## Avisa o HUD sobre o que está na mira para interagir ("" = nada).
signal interaction_prompt_changed(text: String)
## Aviso curto para o HUD ("Você passou mal", "Não dá para colocar aqui"...).
signal notified(text: String)

## Kit inicial provisório (até existir criação de personagem, GDD 4.4).
## Cada entrada: [id, quantidade, slot da hotbar ou -1].
const STARTER_KIT := [
	["bow_wood", 1, 0], ["axe_iron", 1, 1], ["staff_wood", 1, 2], ["bandage", 2, 3],
	["arrow", 15, -1], ["feather", 5, -1], ["stick", 5, -1],
	["berries", 6, 4], ["water_bottle", 1, 5], ["torch", 1, 6], ["hammer", 1, 7],
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
@export var third_person_offset := Vector3(0.5, 0.2, 0.0)

var first_person := true

# Estado de animação replicado para os outros jogadores.
var net_crouching := false
## Agachar é alternado (Ctrl liga/desliga). Correr ou pular levanta.
var _crouch_on := false
## Frio do Congelado: fator de velocidade e tempo restante.
var _chill_factor := 1.0
var _chill_time := 0.0
var net_sprinting := false
var net_on_floor := true
## Segurando uma tocha acesa (luz visível para todos).
var net_torch := false:
	set(value):
		net_torch = value
		if _torch_light:
			_torch_light.visible = value

var _torch_light: OmniLight3D

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
## Capacete, armadura, calça, botas, luvas, anéis e colar.
var equipment: Equipment
## Roda de habilidades do HUD (Q segurado); o HUD preenche.
var skill_wheel: SkillWheel

## Modo construção (tecla B). Só existe no jogador local.
var build: BuildMode

## Modo criativo (Esc > configurações): itens não se gastam, aba Criativo, pode voar.
var creative := false:
	set(value):
		creative = value
		if inventory:
			inventory.creative = value
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
	weapons.setup(self, camera, head, inventory)
	# Fome e sede só correm na máquina do dono (ver Survival).
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
		# Personagem salvo (se escolhido no menu) ou kit inicial + passado.
		if not SaveGame.apply_character(self):
			_give_starter_kit()
			_apply_background(Network.background)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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


## Verdadeiro se este é o personagem controlado nesta máquina.
func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("toggle_camera"):
		first_person = not first_person
		_apply_camera_mode()
	elif event.is_action_pressed("interact") and _focused and not health.is_dead:
		_focused.interact(self)
	elif event.is_action_pressed("attack") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_local():
		# Posição e rotação chegam pela rede; aqui só anima.
		if not health.is_dead:
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

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if creative and captured and Input.is_action_just_pressed("jump"):
		var now := Time.get_ticks_msec()
		if now - _last_jump_ms < DOUBLE_TAP_MS:
			flying = not flying
			notify("Voo %s" % ("ligado (Espaço sobe, Ctrl desce)" if flying else "desligado"))
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

	if not flying and Input.is_action_just_pressed("crouch") and captured:
		_crouch_on = not _crouch_on
	if _crouch_on and (Input.is_action_just_pressed("jump") or Input.is_action_pressed("sprint")):
		_crouch_on = false
	var crouching := _crouch_on
	var target_head := crouch_head_height if crouching else stand_head_height
	head.position.y = lerpf(head.position.y, target_head, minf(10.0 * delta, 1.0))

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := direction * _current_speed(crouching) * (FLY_SPEED_FACTOR if flying else 1.0)
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)

	move_and_slide()

	var sprinting := _wants_sprint(crouching) and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	if sprinting:
		stamina.drain(sprint_stamina_per_second * progression.mult("sprint_stamina") * delta)
		progression.gain("athletics", Vector2(velocity.x, velocity.z).length() * delta * 0.1)
	survival.exerting = sprinting
	net_crouching = crouching
	net_sprinting = sprinting
	net_on_floor = is_on_floor()
	model.update_locomotion(velocity * transform.basis, is_on_floor(), crouching, sprinting)
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
	var reach := interact_range + spring_arm.get_hit_length()
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * reach, 1 | 8 | 32 | BuildPiece.DOOR_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Node = hit.get("collider")
	if target and not target.has_method(&"interact"):
		target = null
	if target and target.has_method(&"has_prompt") and not target.has_prompt():
		target = null  # ex.: árvore (coleta é por golpe, não por E)
	if target and target.global_position.distance_to(global_position) > interact_range + 1.0:
		target = null
	if target != _focused:
		_focused = target
		_has_focus = target != null
		interaction_prompt_changed.emit(_focused.get_prompt() if _focused else "")


func _give_starter_kit() -> void:
	for entry in STARTER_KIT:
		var slot_index: int = entry[2]
		if slot_index >= 0 and inventory.get_slot(slot_index).is_empty():
			inventory.slots[slot_index] = {"id": entry[0], "count": entry[1]}
		else:
			inventory.add_item(entry[0], entry[1])
	inventory.changed.emit()


## Passado escolhido no menu: proficiência inicial e itens extras.
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

## Animação de ação (tiro, golpe, feitiço) aqui e nas telas dos outros jogadores.
## Só toca parado, para não travar as pernas (mistura tronco/pernas fica para depois).
func play_action_synced(anim_name: StringName) -> void:
	_play_action_if_still(anim_name)
	if Network.is_online():
		_remote_action.rpc(anim_name)


@rpc("authority", "call_remote", "unreliable")
func _remote_action(anim_name: StringName) -> void:
	_play_action_if_still(anim_name)


func _play_action_if_still(anim_name: StringName) -> void:
	if Vector2(velocity.x, velocity.z).length() < 0.5:
		model.play_action(anim_name)


## Efeitos de arma (rastro de tiro, dardo) mostrados nas telas dos outros jogadores.
func broadcast_fx(kind: StringName, from: Vector3, to: Vector3, color := Color.WHITE) -> void:
	if Network.is_online():
		_remote_fx.rpc(kind, from, to, color)


@rpc("authority", "call_remote", "unreliable")
func _remote_fx(kind: StringName, from: Vector3, to: Vector3, color: Color) -> void:
	match kind:
		&"tracer":
			Weapon.spawn_tracer(self, from, to)
			Sfx.play("gunshot", from, 2.0)
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
		return  # fome/sede: sem animação de golpe
	if is_local() and source is Zombie:
		progression.gain("toughness", amount * 0.25)
		equipment.wear_on_hit()
	model.play_action(&"Hit_Chest")


func _on_died(_source: Node) -> void:
	model.play_action(&"Death01")
	EventBus.player_died.emit(self)
	if not is_local():
		return
	# Regras de morte (GDD 7): a mochila vai para uma bag aqui; a hotbar (9 slots,
	# o que está "equipado") fica com o jogador. Depois, Fraqueza e perda de XP.
	WorldItems.drop_bag(_empty_backpack(), global_position, display_name())
	death_penalty.on_died()
	await get_tree().create_timer(respawn_delay, false).timeout
	global_position = _spawn_point
	velocity = Vector3.ZERO
	stamina.refill()
	mana.refill()
	survival.refill()
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
	notify("Você vai renascer nesta cama")


## Golpe gelado: lento por um tempo. Vem do servidor; vale na máquina do dono.
func apply_chill(factor: float, duration: float) -> void:
	if is_local():
		_chill(factor, duration)
	elif Network.is_online():
		_remote_chill.rpc_id(get_multiplayer_authority(), factor, duration)


@rpc("any_peer", "call_remote", "reliable")
func _remote_chill(factor: float, duration: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_chill(factor, duration)


func _chill(factor: float, duration: float) -> void:
	if _chill_time <= 0.0:
		notify("Congelando: você está mais lento")
	_chill_factor = clampf(factor, 0.2, 1.0)
	_chill_time = maxf(_chill_time, duration)


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
		notify("Não dá para colocar aqui")
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


## Nome mostrado (ex.: na bag). Sem perfis ainda: "Jogador 1" é o host.
func display_name() -> String:
	var id := get_multiplayer_authority()
	return "Jogador 1" if id == 1 else "Jogador %s" % str(id).left(4)


func _on_revived() -> void:
	model.cancel_action()
	model.play(&"Idle")


func _wants_sprint(crouching: bool) -> bool:
	return Input.is_action_pressed("sprint") and not crouching and stamina.current > 0.0 \
		and not inventory.is_overloaded()


func _current_speed(crouching: bool) -> float:
	if _chill_time > 0.0:
		_chill_time -= get_physics_process_delta_time()
		if _chill_time <= 0.0:
			_chill_factor = 1.0
	var bonus := progression.mult("move_speed") * _chill_factor
	var factor := (overloaded_speed_factor if inventory.is_overloaded() else 1.0) * death_penalty.speed_factor() * bonus
	if crouching:
		return crouch_speed * factor
	if _wants_sprint(crouching) and is_on_floor():
		return sprint_speed * death_penalty.speed_factor() * bonus
	return walk_speed * factor


func _apply_camera_mode() -> void:
	spring_arm.spring_length = 0.0 if first_person else third_person_distance
	spring_arm.position = Vector3.ZERO if first_person else third_person_offset
	# Na 1ª pessoa o corpo some da câmera, mas continua projetando sombra.
	# As armas de 1ª pessoa (viewmodel) só aparecem nesse modo.
	weapons.visible = first_person and not (build and build.active)
	var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = shadow_mode
