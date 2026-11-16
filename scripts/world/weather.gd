class_name Weather
extends Node
## Clima (GDD 10.3): limpo, chuva, neblina, tempestade e frio extremo.
## O servidor sorteia um novo clima de tempos em tempos e manda para todos.
## Efeitos:
## - chuva: abafa sons (zumbis ouvem 30% menos); tempestade: 45% menos, relâmpagos e
##   Raio em cadeia 30% mais forte;
## - neblina: zumbis enxergam 45% menos (e a névoa fecha a sua visão);
## - frio extremo: neve, fome 60% mais rápida longe de uma fogueira (6 m).

const STATES := {
	"clear": {"name": "Céu limpo", "weight": 50, "hearing": 1.0, "sight": 1.0, "fog": 1.0},
	"rain": {"name": "Chuva", "weight": 20, "hearing": 0.7, "sight": 0.85, "fog": 2.0},
	"fog": {"name": "Neblina", "weight": 14, "hearing": 1.0, "sight": 0.55, "fog": 6.0},
	"storm": {"name": "Tempestade", "weight": 8, "hearing": 0.55, "sight": 0.75, "fog": 3.0},
	"cold": {"name": "Frio extremo", "weight": 8, "hearing": 1.0, "sight": 0.9, "fog": 1.6},
}
## Duração de cada clima, em segundos reais.
const MIN_DURATION := 150.0
const MAX_DURATION := 360.0
const COLD_HUNGER_FACTOR := 1.6
const CAMPFIRE_WARMTH := 6.0

var state := "clear"

var _timer := 60.0
var _env: Environment
var _base_fog_density := 0.0
var _base_fog_enabled := false
var _particles: GPUParticles3D
var _flash: DirectionalLight3D
var _flash_timer := 8.0


static func find(tree: SceneTree) -> Weather:
	return tree.get_first_node_in_group("weather") as Weather


## Fatores consultados pelos sistemas (1 = sem efeito). Funcionam sem clima (null).
static func hearing_factor(tree: SceneTree) -> float:
	var w := find(tree)
	return float(STATES[w.state].hearing) if w else 1.0


static func sight_factor(tree: SceneTree) -> float:
	var w := find(tree)
	return float(STATES[w.state].sight) if w else 1.0


static func lightning_factor(tree: SceneTree) -> float:
	var w := find(tree)
	return 1.3 if w and w.state == "storm" else 1.0


## Fome mais rápida no frio, a não ser perto de uma fogueira.
static func hunger_factor(tree: SceneTree, position: Vector3) -> float:
	var w := find(tree)
	if w == null or w.state != "cold":
		return 1.0
	if not Structures.stations_near("campfire", position, CAMPFIRE_WARMTH).is_empty():
		return 1.0
	return COLD_HUNGER_FACTOR


func display_name() -> String:
	return str(STATES[state].name)


func _ready() -> void:
	add_to_group("weather")
	var world_env := get_parent().get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_env:
		_env = world_env.environment
		_base_fog_enabled = _env.fog_enabled
		_base_fog_density = _env.fog_density if _env.fog_enabled else 0.003
	_flash = DirectionalLight3D.new()
	_flash.light_color = Color(0.8, 0.85, 1.0)
	_flash.light_energy = 0.0
	_flash.rotation = Vector3(deg_to_rad(-70), 0.4, 0)
	add_child(_flash)
	_build_particles()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _sync.rpc_id(id, state))
	_apply()


func _process(delta: float) -> void:
	_follow_camera()
	if state == "storm":
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(5.0, 14.0)
			_lightning()
	if not multiplayer.is_server():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(MIN_DURATION, MAX_DURATION)
		set_state(_roll())


func _unhandled_key_input(event: InputEvent) -> void:
	# F10 (servidor): troca o clima, para testes.
	if multiplayer.is_server() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F10:
		var keys := STATES.keys()
		set_state(keys[(keys.find(state) + 1) % keys.size()])


func set_state(new_state: String) -> void:
	if not STATES.has(new_state):
		return
	state = new_state
	_apply()
	if Network.is_online():
		_sync.rpc(state)


@rpc("authority", "call_remote", "reliable")
func _sync(new_state: String) -> void:
	state = new_state
	_apply()


func _roll() -> String:
	var total := 0.0
	for id: String in STATES:
		total += float(STATES[id].weight)
	var roll := randf() * total
	for id: String in STATES:
		roll -= float(STATES[id].weight)
		if roll <= 0.0:
			return id
	return "clear"


func _apply() -> void:
	if _env:
		var factor := float(STATES[state].fog)
		_env.fog_enabled = _base_fog_enabled or factor > 1.0
		_env.fog_density = _base_fog_density * factor
	if _particles:
		var mat := _particles.process_material as ParticleProcessMaterial
		match state:
			"rain", "storm":
				_particles.emitting = true
				_particles.amount_ratio = 1.0 if state == "storm" else 0.6
				mat.initial_velocity_min = 16.0
				mat.initial_velocity_max = 20.0
				(_particles.draw_pass_1 as QuadMesh).size = Vector2(0.02, 0.5)
				(_particles.draw_pass_1.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(0.7, 0.8, 0.95, 0.45)
			"cold":
				_particles.emitting = true
				_particles.amount_ratio = 0.5
				mat.initial_velocity_min = 1.0
				mat.initial_velocity_max = 2.0
				(_particles.draw_pass_1 as QuadMesh).size = Vector2(0.06, 0.06)
				(_particles.draw_pass_1.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.9)
			_:
				_particles.emitting = false
	EventBus.weather_changed.emit(state)


func _lightning() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		Sfx.play("thunder", cam.global_position + Vector3(randf_range(-30, 30), 20, randf_range(-30, 30)), 4.0)
	var tw := create_tween()
	tw.tween_property(_flash, "light_energy", 2.5, 0.05)
	tw.tween_property(_flash, "light_energy", 0.0, 0.1)
	tw.tween_property(_flash, "light_energy", 1.8, 0.05)
	tw.tween_property(_flash, "light_energy", 0.0, 0.4)


## Chuva/neve: caixa de partículas que acompanha a câmera desta máquina.
func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 2500
	_particles.lifetime = 2.0
	_particles.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	_particles.top_level = true
	_particles.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(18, 1, 18)
	mat.direction = Vector3.DOWN
	mat.spread = 4.0
	mat.gravity = Vector3(0, -2, 0)
	_particles.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.5)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	draw.albedo_color = Color(0.7, 0.8, 0.95, 0.45)
	quad.material = draw
	_particles.draw_pass_1 = quad
	add_child(_particles)


func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _particles:
		_particles.global_position = cam.global_position + Vector3.UP * 10.0
