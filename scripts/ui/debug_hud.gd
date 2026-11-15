extends CanvasLayer
## HUD provisório da Fase 1: vida, stamina, mana, arma atual e aviso de morte.
## O HUD de verdade (GDD 13.1) entra na Fase 2.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var death_label: Label = %DeathLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var weapon_label: Label = %WeaponLabel

var _weapons: WeaponHolder


func _ready() -> void:
	death_label.visible = false
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_died.connect(func(p: Node) -> void:
		if p.is_multiplayer_authority():
			death_label.visible = true)
	# O player pode ter nascido antes do HUD.
	for player in get_tree().get_nodes_in_group("player"):
		_on_player_spawned(player)


func _on_player_spawned(player: Node) -> void:
	# Na rede existem vários personagens; o HUD mostra só o desta máquina.
	if not player.is_multiplayer_authority():
		return
	var health := Health.find_in(player)
	if health and not health.changed.is_connected(_on_health_changed):
		health.changed.connect(_on_health_changed)
		_on_health_changed(health.current, health.max_health)
	_bind_pool(player.get_node_or_null(^"Stamina"), stamina_bar)
	_bind_pool(player.get_node_or_null(^"Mana"), mana_bar)
	_weapons = player.get(&"weapons")
	if _weapons and not _weapons.changed.is_connected(_update_weapon):
		_weapons.changed.connect(_update_weapon)
	_update_weapon()


func _bind_pool(pool: StatPool, bar: ProgressBar) -> void:
	if pool == null:
		return
	var update := func(current: float, maximum: float) -> void:
		bar.max_value = maximum
		bar.value = current
	pool.changed.connect(update)
	update.call(pool.current, pool.max_value)


func _process(_delta: float) -> void:
	# Recarga de feitiço muda a cada frame; o resto atualiza por sinal.
	if _weapons and _weapons.current() is SpellCaster:
		_update_weapon()


func _update_weapon() -> void:
	var weapon := _weapons.current() if _weapons else null
	if weapon == null:
		weapon_label.text = ""
		return
	var extra := weapon.hud_text()
	weapon_label.text = "[%d] %s" % [_weapons.current_index + 1, weapon.display_name()]
	if extra != "":
		weapon_label.text += "\n" + extra


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "Vida %d / %d" % [ceili(current), ceili(maximum)]
	if current > 0.0:
		death_label.visible = false
