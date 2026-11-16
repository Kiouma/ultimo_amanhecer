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
var _progression_ui: ProgressionUI
var _map_ui: MapUI
var _creative_ui: CreativeUI
var _weakness_label: Label
var _queue_label: Label
var _build_label: Label
var _boss_bar: ProgressBar
var _boss_label: Label
var _boss_timer := 0.0


func _ready() -> void:
	death_label.visible = false
	EventBus.player_spawned.connect(_on_player_spawned)
	_bus(EventBus.player_died, func(p: Node) -> void:
		if p.is_multiplayer_authority():
			death_label.visible = true)
	_build_clock()
	_build_boss_bar()
	# O player pode ter nascido antes do HUD.
	for player in get_tree().get_nodes_in_group("player"):
		_on_player_spawned(player)


## Liga um sinal global a uma função anônima e lembra, para desligar ao sair
## (voltar ao menu): lambdas não se desligam sozinhas quando o HUD é liberado.
var _bus_links: Array = []


func _bus(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_bus_links.append([sig, callable])


func _exit_tree() -> void:
	for link: Array in _bus_links:
		if (link[0] as Signal).is_connected(link[1]):
			(link[0] as Signal).disconnect(link[1])
	_bus_links.clear()


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
	_bind_survival(player)
	_bind_death_penalty(player)
	_bind_notifications(player)
	var channel := ChannelBar.new()
	channel.player = player
	add_child(channel)
	var wheel := SkillWheel.new()
	wheel.player = player
	add_child(wheel)
	player.skill_wheel = wheel
	var compass := CompassBar.new()
	compass.player = player
	add_child(compass)
	# Marca de acerto: a mira pisca (amarela em ataque surpresa).
	var crosshair := get_node_or_null(^"Crosshair") as Label
	if crosshair:
		player.progression.hit_confirmed.connect(func(surprise: bool) -> void:
			crosshair.text = "×"
			crosshair.modulate = Color(1.0, 0.85, 0.2) if surprise else Color(1.0, 0.35, 0.3)
			var tw := crosshair.create_tween()
			tw.tween_interval(0.12)
			tw.tween_callback(func() -> void:
				crosshair.text = "+"
				crosshair.modulate = Color.WHITE))


func _bind_inventory(player: Player) -> void:
	# Hotbar fixa embaixo, no centro.
	var strip := HBoxContainer.new()
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	# Ícone da última habilidade (Q), à esquerda das teclas.
	var spell_icon := SpellIcon.new()
	spell_icon.player = player
	strip.add_child(spell_icon)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	strip.add_child(gap)
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

	_progression_ui = ProgressionUI.new()
	add_child(_progression_ui)
	_progression_ui.bind(player)

	_map_ui = MapUI.new()
	add_child(_map_ui)
	_map_ui.bind(player)

	_creative_ui = CreativeUI.new()
	add_child(_creative_ui)
	_creative_ui.bind(player)

	var chest_ui := ChestUI.new()
	add_child(chest_ui)
	chest_ui.bind(player)

	var pause_menu := PauseMenu.new()
	add_child(pause_menu)
	pause_menu.bind(player)


## Fome e sede: duas meias-barras com rótulo, embaixo de vida/stamina/mana.
func _bind_survival(player: Player) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	health_bar.get_parent().add_child(row)
	var hunger := _labeled_bar(row, "Fome", Color(0.85, 0.55, 0.2))
	var thirst := _labeled_bar(row, "Sede", Color(0.3, 0.75, 0.9))
	var update := func(h: float, t: float) -> void:
		hunger.value = h
		thirst.value = t
		# Pisca o rótulo em vermelho quando está acabando.
		hunger.get_parent().get_child(0).modulate = Color(1, 0.35, 0.3) if h < 20.0 else Color.WHITE
		thirst.get_parent().get_child(0).modulate = Color(1, 0.35, 0.3) if t < 20.0 else Color.WHITE
	player.survival.changed.connect(update)
	update.call(player.survival.hunger, player.survival.thirst)


func _labeled_bar(parent: Control, text: String, color: Color) -> ProgressBar:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	return bar


## Fraqueza pós-morte: rótulo acima da vida com nível, tempo e efeitos.
func _bind_death_penalty(player: Player) -> void:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.95))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	var box := health_bar.get_parent()
	box.add_child(label)
	box.move_child(label, 0)
	label.visible = false
	_weakness_label = label
	player.death_penalty.changed.connect(_on_weakness_changed.bind(player.death_penalty))


func _on_weakness_changed(level: int, time_left: float, penalty: DeathPenalty) -> void:
	_weakness_label.visible = level > 0
	if level <= 0:
		return
	_weakness_label.text = "Fraqueza %d · %d:%02d  (−%d%% vel. · −%d%% dano · stamina lenta)" % [
		level, int(time_left) / 60, int(time_left) % 60,
		roundi((1.0 - penalty.speed_factor()) * 100), roundi((1.0 - penalty.damage_factor()) * 100)]


## Avisos curtos (player.notify) e linha da fila de fabricação, acima da hotbar.
func _bind_notifications(player: Player) -> void:
	var toast := Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 206)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 5)
	toast.modulate.a = 0.0
	add_child(toast)
	player.notified.connect(_on_notified.bind(toast))

	_queue_label = Label.new()
	_queue_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 184)
	_queue_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_label.add_theme_font_size_override("font_size", 13)
	_queue_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_queue_label.add_theme_constant_override("outline_size", 4)
	add_child(_queue_label)
	player.craft_queue.changed.connect(_on_queue_changed.bind(player.craft_queue))

	# Painel do modo construção (B), à esquerda da mira.
	_build_label = Label.new()
	_build_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	_build_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_label.add_theme_font_size_override("font_size", 14)
	_build_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	_build_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_build_label.add_theme_constant_override("outline_size", 5)
	add_child(_build_label)
	if player.build:
		player.build.changed.connect(func() -> void: _build_label.text = player.build.status_text())


func _on_notified(text: String, toast: Label) -> void:
	toast.text = text
	var tw := toast.create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)


func _on_queue_changed(queue: CraftQueue) -> void:
	if queue.jobs.is_empty():
		_queue_label.text = ""
		return
	var job: Dictionary = queue.jobs[0]
	var item_name := str(GameData.get_item(str(job.recipe.result)).get("name", ""))
	var paused := not queue.is_station_ok(job.recipe)
	_queue_label.text = "Fabricando %s (faltam %d) %s" % [item_name, int(job.left),
		"· pausado: volte à %s" % Crafting.station_name(str(job.recipe.station)) if paused else "%d%%" % int(float(job.progress) * 100)]
	_queue_label.modulate = Color(1, 0.6, 0.5) if paused else Color(0.85, 0.85, 0.8)


## Relógio (canto superior direito) e aviso grande quando a noite/o dia começa.
func _build_clock() -> void:
	var clock := Label.new()
	clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_theme_font_size_override("font_size", 20)
	clock.add_theme_color_override("font_outline_color", Color.BLACK)
	clock.add_theme_constant_override("outline_size", 5)
	add_child(clock)

	var banner := Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 34)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.modulate.a = 0.0
	add_child(banner)
	var show_banner := func(text: String, color: Color) -> void:
		banner.text = text
		banner.add_theme_color_override("font_color", color)
		var tw := banner.create_tween()
		tw.tween_property(banner, "modulate:a", 1.0, 0.6)
		tw.tween_interval(3.0)
		tw.tween_property(banner, "modulate:a", 0.0, 1.2)
	_bus(EventBus.night_started, func(d: int) -> void:
		var h := Horde.find(get_tree())
		if h and h.is_horde_day(d):
			return  # a faixa da horda ocupa o lugar
		show_banner.call("Noite %d\nos mortos estão mais rápidos" % d, Color(0.75, 0.8, 1.0)))
	_bus(EventBus.day_started, func(d: int) -> void:
		var h := Horde.find(get_tree())
		if h and h.is_horde_day(d):
			show_banner.call("Dia %d\na horda vem esta noite: preparem a base" % d, Color(1.0, 0.55, 0.4))
		else:
			show_banner.call("Dia %d" % d, Color(1.0, 0.9, 0.6)))
	_bus(EventBus.weather_changed, func(state: String) -> void:
		var texts := {"rain": "Começou a chover\nos sons ficam abafados", "fog": "A neblina baixou\nninguém enxerga longe",
			"storm": "Tempestade!\nraios por toda parte", "cold": "Frio extremo\nfique perto de uma fogueira"}
		if texts.has(state):
			show_banner.call(texts[state], Color(0.8, 0.88, 1.0)))
	_bus(EventBus.horde_started, func(n: int) -> void:
		show_banner.call("A HORDA %d CHEGOU" % n, Color(1.0, 0.3, 0.25)))
	_bus(EventBus.horde_ended, func(n: int, survived: bool) -> void:
		show_banner.call("Horda %d vencida!\nrecompensa no inventário" % n if survived else "A horda %d passou" % n,
			Color(0.6, 1.0, 0.6)))

	var day_night := DayNight.find(get_tree())
	if day_night == null:
		return
	var update := func(d: int, h: float) -> void:
		clock.text = "%s %d · %s" % ["Noite" if day_night.is_night() else "Dia", d, day_night.clock_text()]
		var color := Color(0.75, 0.8, 1.0) if day_night.is_night() else Color(1.0, 0.95, 0.85)
		var weather := Weather.find(get_tree())
		if weather and weather.state != "clear":
			clock.text += " · " + weather.display_name()
		var horde := Horde.find(get_tree())
		if horde:
			clock.text += "\n" + horde.status_text(d, h)
			if horde.active or horde.days_until(d) == 0:
				color = Color(1.0, 0.45, 0.4)
		clock.add_theme_color_override("font_color", color)
	day_night.time_changed.connect(update)
	update.call(day_night.day, day_night.hour)


## Troca de tela pelas abas (Inventário / Personagem / Mapa).
func open_panel(which: String) -> void:
	var panels := {"inventory": _inventory_ui, "character": _progression_ui, "map": _map_ui, "creative": _creative_ui}
	var target: Control = panels.get(which)
	if target == null:
		return
	for p: Control in panels.values():
		if p != target and p.visible:
			p.visible = false
	if not target.visible:
		target.toggle()


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


func _process(delta: float) -> void:
	# Recarga de feitiço muda a cada frame; o resto atualiza por sinal.
	if _weapons and _weapons.current() is SpellCaster:
		_update_weapon()
	_boss_timer -= delta
	if _boss_timer <= 0.0:
		_boss_timer = 0.25
		_update_boss_bar()


## Barra do chefe (Colosso...) no topo, quando algum está vivo a até 60 m.
func _build_boss_bar() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 56)  # abaixo da bússola
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_boss_label = Label.new()
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 18)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
	_boss_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_label.add_theme_constant_override("outline_size", 5)
	box.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(420, 14)
	_boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.15, 0.12)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_boss_bar)
	box.visible = false


func _update_boss_bar() -> void:
	var box := _boss_bar.get_parent() as Control
	var me: Node3D = null
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			me = p
	var boss: Node3D = null
	if me:
		for z: Node3D in get_tree().get_nodes_in_group("boss"):
			var h := Health.find_in(z)
			if h and not h.is_dead and z.global_position.distance_to(me.global_position) < 60.0:
				boss = z
	box.visible = boss != null
	if boss:
		var h := Health.find_in(boss)
		_boss_label.text = str(boss.stats.get("name", "Chefe"))
		_boss_bar.max_value = h.max_health
		_boss_bar.value = h.current


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
