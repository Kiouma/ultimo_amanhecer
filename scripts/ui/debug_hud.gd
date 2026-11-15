extends CanvasLayer
## HUD provisório da Fase 1: barra de vida e aviso de morte.
## O HUD de verdade (GDD 13.1) entra na Fase 2.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var death_label: Label = %DeathLabel


func _ready() -> void:
	death_label.visible = false
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_died.connect(func(_p: Node) -> void: death_label.visible = true)
	# O player pode ter nascido antes do HUD.
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_on_player_spawned(player)


func _on_player_spawned(player: Node) -> void:
	var health := Health.find_in(player)
	if health and not health.changed.is_connected(_on_health_changed):
		health.changed.connect(_on_health_changed)
		_on_health_changed(health.current, health.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "Vida %d / %d" % [ceili(current), ceili(maximum)]
	if current > 0.0:
		death_label.visible = false
