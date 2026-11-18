class_name DayNight
extends Node
## Ciclo dia/noite (GDD 11). Fica no nível; controla o sol, a lua, o céu e o relógio.
## Dia: 06h às 20h. Noite: 20h às 06h (zumbis mais rápidos e atentos, ver Zombie).
## Emite EventBus.day_started / night_started em todas as máquinas.
##
## Rede: o servidor manda no relógio e envia a hora a cada SYNC_INTERVAL segundos
## (e na hora para quem entra); os clientes avançam sozinhos entre um envio e outro.
## F8 (só no servidor) adianta 1 hora, para testes.

signal time_changed(day: int, hour: float)

const DAY_START := 6.0
const NIGHT_START := 20.0
const SYNC_INTERVAL := 5.0

## Duração de um dia inteiro de jogo, em segundos reais (24 min = 1 h de jogo por minuto).
@export var day_length_seconds := 1440.0
@export var start_hour := 8.0
@export var sun_path: NodePath = ^"../Sun"
@export var environment_path: NodePath = ^"../WorldEnvironment"

var day := 1
var hour := 8.0

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _was_night := false
## Céu avermelhado da horda (0 a 1), definido pela Horde em todas as máquinas.
var red_sky := 0.0
var _sync_timer := 0.0


func _ready() -> void:
	add_to_group("day_night")
	hour = start_hour
	_sun = get_node_or_null(sun_path)
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	if world_env:
		_env = world_env.environment
		if _env.sky:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
			# O céu muda a cada minuto do jogo: recalcular a luz do céu aos poucos, em vários
			# quadros (de uma vez dava um soluço de ~20 ms por segundo).
			_env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			_env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.55, 0.65, 1.0)
	_moon.shadow_enabled = true
	add_child(_moon)
	_was_night = is_night()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _sync.rpc_id(id, day, hour))
	_apply_visuals()


## O DayNight do nível atual (ou null).
static func find(tree: SceneTree) -> DayNight:
	return tree.get_first_node_in_group("day_night") as DayNight


func is_night() -> bool:
	return hour >= NIGHT_START or hour < DAY_START


## "08:30"
func clock_text() -> String:
	var minutes := int(hour * 60.0) % 60
	return "%02d:%02d" % [int(hour), minutes]


func _process(delta: float) -> void:
	_advance(delta * 24.0 / day_length_seconds)
	if multiplayer.is_server() and Network.is_online():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			_sync.rpc(day, hour)


func _unhandled_key_input(event: InputEvent) -> void:
	if multiplayer.is_server() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F8:
		_advance(1.0)
		if Network.is_online():
			_sync.rpc(day, hour)


func _advance(hours: float) -> void:
	hour += hours
	while hour >= 24.0:
		hour -= 24.0
		day += 1
	_check_transitions()
	_apply_visuals()
	time_changed.emit(day, hour)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(server_day: int, server_hour: float) -> void:
	day = server_day
	hour = server_hour
	_check_transitions()
	_apply_visuals()
	time_changed.emit(day, hour)


func _check_transitions() -> void:
	var night := is_night()
	if night == _was_night:
		return
	_was_night = night
	if night:
		EventBus.night_started.emit(day)
	else:
		EventBus.day_started.emit(day)


# --- Visual -----------------------------------------------------------------------------

func _apply_visuals() -> void:
	# Sol: nasce às 06h (0°), alto às 13h (90°), se põe às 20h (180°) — o dia do jogo.
	# Lua: o mesmo arco de 20h a 06h. Fora do seu período, cada um fica abaixo do horizonte.
	var day_span := NIGHT_START - DAY_START
	var night_progress := fposmod(hour - NIGHT_START, 24.0) / (24.0 - day_span)
	var sun_elev := (hour - DAY_START) / day_span * 180.0 if not is_night() else -night_progress * 180.0
	var sun_height := sin(deg_to_rad(sun_elev))  # 1 ao meio-dia, <0 à noite
	var daylight := clampf(sun_height * 1.6 + 0.15, 0.0, 1.0)  # 0 noite, 1 dia (com crepúsculo)

	if _sun:
		_sun.rotation = Vector3(deg_to_rad(-sun_elev), deg_to_rad(-30.0), 0.0)
		_sun.light_energy = clampf(sun_height * 1.4, 0.0, 1.0)
		_sun.visible = sun_height > -0.05
		# Alaranjado perto do horizonte, branco no alto.
		var low := 1.0 - clampf(sun_height * 2.5, 0.0, 1.0)
		_sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.6, 0.35), low)

	# Lua: fraca e azulada, com um mínimo garantido para a noite não ser breu total.
	var moon_elev := night_progress * 180.0
	_moon.rotation = Vector3(deg_to_rad(-clampf(moon_elev, 15.0, 165.0)), deg_to_rad(150.0), 0.0)
	_moon.light_energy = 0.1 + 0.12 * sin(deg_to_rad(moon_elev)) if is_night() else 0.0
	_moon.visible = is_night()

	if _sky:
		_sky.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.38, 0.45, 0.6), daylight)
		var dusk := clampf(1.0 - absf(sun_height) * 4.0, 0.0, 1.0)  # forte no nascer/pôr do sol
		var horizon := Color(0.05, 0.06, 0.1).lerp(Color(0.65, 0.67, 0.7), daylight)
		_sky.sky_horizon_color = horizon.lerp(Color(0.85, 0.5, 0.3), dusk * 0.6)
		_sky.ground_horizon_color = _sky.sky_horizon_color
		_sky.ground_bottom_color = Color(0.03, 0.03, 0.04).lerp(Color(0.2, 0.17, 0.13), daylight)
		if red_sky > 0.0:
			_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(Color(0.6, 0.08, 0.05), red_sky * 0.75)
			_sky.ground_horizon_color = _sky.sky_horizon_color
			_sky.sky_top_color = _sky.sky_top_color.lerp(Color(0.18, 0.02, 0.03), red_sky * 0.5)
	if _moon.visible and red_sky > 0.0:
		_moon.light_color = Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.35, 0.3), red_sky)
	if _env:
		_env.ambient_light_energy = lerpf(0.25, 1.0, daylight)
		_env.background_energy_multiplier = lerpf(0.35, 1.0, daylight)
