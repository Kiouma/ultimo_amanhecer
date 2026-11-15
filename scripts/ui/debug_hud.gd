extends CanvasLayer
## HUD provisório: vida, stamina, mana, item na mão, hotbar, aviso de interação,
## tela de inventário (Tab) e aviso de morte. Visual final do HUD (GDD 13.1) fica para o polimento.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var death_label: Label = %DeathLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var weapon_label: Label = %WeaponLabel

var _weapons: WeaponHolder
var _hotbar_slots: Array[InventorySlotUI] = []
var _prompt: Label
var _inventory_ui: InventoryUI


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
	_bind_inventory(player)


func _bind_inventory(player: Player) -> void:
	# Hotbar fixa embaixo, no centro.
	var strip := HBoxContainer.new()
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	for i in Inventory.HOTBAR_SIZE:
		var slot := InventorySlotUI.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.setup(player.inventory, i, false, true)
		strip.add_child(slot)
		_hotbar_slots.append(slot)
	# Âncora depois dos slots, para usar o tamanho real da faixa.
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	player.inventory.changed.connect(_update_hotbar)
	_weapons.changed.connect(_update_hotbar)
	_update_hotbar()

	# Aviso de interação, logo abaixo da mira.
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 28
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 5)
	add_child(_prompt)
	player.interaction_prompt_changed.connect(func(text: String) -> void: _prompt.text = text)

	_inventory_ui = InventoryUI.new()
	add_child(_inventory_ui)
	_inventory_ui.bind(player)


func _update_hotbar() -> void:
	for i in _hotbar_slots.size():
		_hotbar_slots[i].refresh()
		_hotbar_slots[i].selected = i == _weapons.selected


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
	if _weapons == null:
		weapon_label.text = ""
		return
	var extra := _weapons.hud_text()
	weapon_label.text = "[%d] %s" % [_weapons.selected + 1, _weapons.display_name()]
	if extra != "":
		weapon_label.text += "\n" + extra


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "Vida %d / %d" % [ceili(current), ceili(maximum)]
	if current > 0.0:
		death_label.visible = false
