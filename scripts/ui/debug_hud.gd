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
var _aura_ui: AuraUI
var _equipment_ui: EquipmentUI
## Telas cheias (inventário, bancada, personagem, auras, mapa, criativo, baú, pausa):
## com alguma aberta, o minimapa some.
var _screens: Array[Control] = []
# HUD de recursos (etapa 4): esferas ou arcos de vida/mana, arco de stamina, buffs e
# o editor da engrenagem. As barras antigas da cena ficam escondidas.
var _player: Player
var _life_orb: ResourceOrb
var _mana_orb: ResourceOrb
var _life_arc: ResourceArc
var _mana_arc: ResourceArc
var _stamina_arc: ResourceArc
var _buff_bar: BuffBar
var _hud_editor: HudEditor
## Centro da barra de buffs (pixels): ela muda de largura conforme os ícones.
var _buff_center := Vector2.ZERO
var _health: Health
var _shield_bar: ProgressBar
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
	_health = health
	if health and _shield_bar == null:
		# Escudo de energia: faixa azul clara por cima da barra de vida.
		_shield_bar = ProgressBar.new()
		_shield_bar.show_percentage = false
		_shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shield_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var clear := StyleBoxEmpty.new()
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.55, 0.85, 1.0, 0.75)
		fill.set_corner_radius_all(3)
		_shield_bar.add_theme_stylebox_override("background", clear)
		_shield_bar.add_theme_stylebox_override("fill", fill)
		_shield_bar.visible = false
		health_bar.add_child(_shield_bar)
		health.shield_changed.connect(func(_c: float, _m: float) -> void:
			_on_health_changed(health.current, health.max_health))
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
	_bind_death_penalty(player)
	_bind_overload(player)
	_bind_network()
	_bind_pickup_feed(player)
	_bind_minimap(player)
	_bind_fps()
	# Idioma trocado (Esc > Configurações): textos montados no código se refazem.
	_bus(Settings.changed, func() -> void:
		_update_hotbar()
		_update_weapon()
		if _inventory_ui and _inventory_ui.visible:
			_inventory_ui._refresh()
		if _equipment_ui and _equipment_ui.visible:
			_equipment_ui.refresh()
		if _progression_ui and _progression_ui.visible:
			_progression_ui._refresh()
		if _aura_ui and _aura_ui.visible:
			_aura_ui._refresh())
	_bind_notifications(player)
	_build_resource_hud(player)
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
		crosshair.visible = false  # 3ª pessoa com cursor: sem mira no centro
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
		# Clicável com o mouse livre (Alt): escolhe o slot.
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_weapons.select(i)
				slot.accept_event())
		slot.setup(player.inventory, i, false, true)
		strip.add_child(slot)
		_hotbar_slots.append(slot)
	# Engrenagem: editor da HUD (clicável com o mouse livre).
	var gear_gap := Control.new()
	gear_gap.custom_minimum_size = Vector2(6, 0)
	strip.add_child(gear_gap)
	var gear := GearButton.new()
	gear.size_flags_vertical = Control.SIZE_SHRINK_END
	gear.pressed.connect(open_hud_editor)
	strip.add_child(gear)
	# Âncora depois dos slots, para usar o tamanho real da faixa.
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	player.inventory.changed.connect(_update_hotbar)
	_weapons.changed.connect(_update_hotbar)
	_update_hotbar()

	# Aviso de interação, logo abaixo da mira.
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 150  # abaixo do personagem (3ª pessoa)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 5)
	add_child(_prompt)
	player.interaction_prompt_changed.connect(func(text: String) -> void: _prompt.text = text)

	_inventory_ui = InventoryUI.new()
	add_child(_inventory_ui)
	_inventory_ui.bind(player)

	var crafting_ui := CraftingUI.new()
	add_child(crafting_ui)
	crafting_ui.bind(player, _inventory_ui)

	_progression_ui = ProgressionUI.new()
	add_child(_progression_ui)
	_progression_ui.bind(player)

	_equipment_ui = EquipmentUI.new()
	add_child(_equipment_ui)
	_equipment_ui.bind(player)

	_aura_ui = AuraUI.new()
	add_child(_aura_ui)
	_aura_ui.bind(player)

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
	_screens = [_inventory_ui, _equipment_ui, crafting_ui, _progression_ui, _aura_ui, _map_ui, _creative_ui, chest_ui, pause_menu]


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


## FPS (Esc > Configurações > Mostrar FPS), no canto superior esquerdo; o aviso de rede
## fica logo abaixo.
var _fps_label: Label
var _fps_timer := 0.0


func _bind_fps() -> void:
	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)
	_bus(Settings.changed, _apply_fps_setting)
	_apply_fps_setting()


func _apply_fps_setting() -> void:
	_fps_label.visible = Settings.show_fps
	if _net_label:
		_net_label.position.y = 34.0 if Settings.show_fps else 12.0


## Minimapa (canto superior direito, Esc > Configurações liga/desliga). O relógio fica
## logo abaixo dele.
const MINIMAP_SIZE := 190.0
var _clock: Label
var _minimap_frame: PanelContainer
var _minimap: MapView
var _minimap_timer := 0.0


func _bind_minimap(player: Player) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not "CHUNK" in world:
		return  # arena de teste: sem mapa
	_minimap_frame = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.9)
	style.border_color = Color(0.85, 0.78, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	_minimap_frame.add_theme_stylebox_override("panel", style)
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_minimap_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_minimap_frame)
	_minimap = MapView.new()
	_minimap.custom_minimum_size = Vector2.ONE * MINIMAP_SIZE
	_minimap.player = player
	_minimap.world = world
	_minimap.zoom = clampf(Settings.minimap_zoom, MapView.MIN_ZOOM, MapView.MAX_ZOOM)
	_minimap.show_labels = false
	_minimap.round_dots = 0.8
	var minimap_box := VBoxContainer.new()
	minimap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_box.add_theme_constant_override("separation", 3)
	_minimap_frame.add_child(minimap_box)
	minimap_box.add_child(_minimap)
	# Zoom do minimapa: botões +/- embaixo dele (clicáveis com o mouse livre).
	var zoom_row := HBoxContainer.new()
	zoom_row.alignment = BoxContainer.ALIGNMENT_END
	zoom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_box.add_child(zoom_row)
	for z: Array in [["−", 1.0 / 1.25], ["+", 1.25]]:
		var b := Button.new()
		b.text = z[0]
		b.custom_minimum_size = Vector2(26, 22)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var factor: float = z[1]
		b.pressed.connect(func() -> void:
			_minimap.zoom_at(_minimap.size * 0.5, factor)
			Settings.remember("minimap_zoom", _minimap.zoom))
		zoom_row.add_child(b)
	_minimap_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	var exploration := player.get_node_or_null(^"Exploration") as Exploration
	if exploration:
		if not exploration.revealed.is_connected(MapTiles.invalidate_fog):
			exploration.revealed.connect(MapTiles.invalidate_fog)
	_bus(Settings.changed, _apply_minimap_setting)
	_apply_minimap_setting()


func _apply_minimap_setting() -> void:
	if _minimap_frame == null:
		return
	_minimap_frame.visible = Settings.show_minimap
	if _clock:
		_clock.offset_top = (MINIMAP_SIZE + 58.0) if Settings.show_minimap else 20.0
		_clock.offset_bottom = _clock.offset_top + 50.0


## Itens recebidos (coleta, chão, recompensas): "+1 Madeira" à direita da tela. O mesmo
## item pego de novo logo em seguida soma na mesma linha ("+3 Madeira").
const FEED_SECONDS := 3.0
const FEED_MAX := 6
var _feed: VBoxContainer
var _feed_rows := {}  # id → [Label, quantidade, Tween]


func _bind_pickup_feed(player: Player) -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.grow_vertical = Control.GROW_DIRECTION_BOTH
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	player.inventory.received.connect(_on_item_received)


func _on_item_received(id: String, count: int) -> void:
	var row: Array = _feed_rows.get(id, [])
	if row.is_empty() or not is_instance_valid(row[0]):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.85))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		_feed.add_child(label)
		row = [label, 0, null]
		while _feed.get_child_count() > FEED_MAX:
			_feed.get_child(0).free()
	row[1] = int(row[1]) + count
	var l: Label = row[0]
	l.text = "+%d  %s" % [int(row[1]), str(GameData.get_item(id).get("name", id))]
	l.modulate.a = 1.0
	if row[2] and (row[2] as Tween).is_valid():
		(row[2] as Tween).kill()
	var tw := l.create_tween()
	tw.tween_interval(FEED_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void:
		_feed_rows.erase(id)
		l.queue_free())
	row[2] = tw
	_feed_rows[id] = row


## Rede (canto superior esquerdo): quem entrou vê o ping até o host; o host vê quantos
## jogadores há e, por um tempo depois de hospedar, como os amigos entram (IP e porta).
var _net_label: Label
var _net_timer := 0.0
var _share_until := 0.0


func _bind_network() -> void:
	_net_label = Label.new()
	_net_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_net_label.add_theme_font_size_override("font_size", 13)
	_net_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_net_label.add_theme_constant_override("outline_size", 4)
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.custom_minimum_size = Vector2(420, 0)
	add_child(_net_label)
	_share_until = Time.get_ticks_msec() / 1000.0 + 25.0
	_bus(Network.upnp_finished, func(_info: Dictionary) -> void:
		_share_until = Time.get_ticks_msec() / 1000.0 + 25.0
		_update_network())
	_update_network()


func _update_network() -> void:
	if _net_label == null:
		return
	if not Network.is_online():
		_net_label.text = ""
		return
	if multiplayer.is_server():
		var count := multiplayer.get_peers().size() + 1
		var text := tr("Hospedando · %d/%d jogadores") % [count, Network.MAX_PLAYERS]
		if Time.get_ticks_msec() / 1000.0 < _share_until:
			text += "\n" + Network.share_text()
		_net_label.text = text
		_net_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	else:
		var ping := Network.ping_ms()
		_net_label.text = tr("Ping: %d ms") % ping
		var color := Color(0.75, 0.95, 0.75) if ping < 120 else (Color(1.0, 0.85, 0.4) if ping < 250 else Color(1.0, 0.45, 0.4))
		_net_label.add_theme_color_override("font_color", color)


## Peso acima da capacidade: aviso acima da vida (fica lento, inclusive correndo).
func _bind_overload(player: Player) -> void:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	# Quebra linha em vez de alargar a coluna (senão as barras esticam junto com o texto).
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	var box := health_bar.get_parent()
	box.add_child(label)
	box.move_child(label, 0)
	var update := func() -> void:
		var inv := player.inventory
		label.visible = inv.is_overloaded()
		if label.visible:
			label.text = tr("Sobrecarregado: %.0f / %.0f kg (lento)") % [inv.total_weight(), inv.max_weight]
	player.inventory.changed.connect(update)
	player.progression.changed.connect(update)
	update.call()


## Fraqueza pós-morte: rótulo acima da vida com nível, tempo e efeitos.
func _bind_death_penalty(player: Player) -> void:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.95))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	# Quebra linha em vez de alargar a coluna (senão as barras esticam junto com o texto).
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
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
	_weakness_label.text = tr("Fraqueza %d · %d:%02d  (−%d%% vel. · −%d%% dano · stamina lenta)") % [
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
	_queue_label.text = tr("Fabricando %s (faltam %d) %s") % [item_name, int(job.left),
		tr("· pausado: volte à %s") % Crafting.station_name(str(job.recipe.station)) if paused else "%d%%" % int(float(job.progress) * 100)]
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
	_clock = clock

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
		show_banner.call(tr("Noite %d\nos monstros ficam mais ferozes") % d, Color(0.75, 0.8, 1.0)))
	_bus(EventBus.day_started, func(d: int) -> void:
		show_banner.call(tr("Dia %d") % d, Color(1.0, 0.9, 0.6)))
	_bus(EventBus.weather_changed, func(state: String) -> void:
		var texts := {"rain": tr("Começou a chover\nos sons ficam abafados"), "fog": tr("A neblina baixou\nninguém enxerga longe"),
			"storm": tr("Tempestade!\nraios por toda parte"), "cold": tr("Frio extremo\nfique perto de uma fogueira")}
		if texts.has(state):
			show_banner.call(texts[state], Color(0.8, 0.88, 1.0)))

	var day_night := DayNight.find(get_tree())
	if day_night == null:
		return
	var update := func(d: int, _h: float) -> void:
		clock.text = "%s %d · %s" % [tr("Noite") if day_night.is_night() else tr("Dia"), d, day_night.clock_text()]
		var color := Color(0.75, 0.8, 1.0) if day_night.is_night() else Color(1.0, 0.95, 0.85)
		var weather := Weather.find(get_tree())
		if weather and weather.state != "clear":
			clock.text += " · " + weather.display_name()
		clock.add_theme_color_override("font_color", color)
	day_night.time_changed.connect(update)
	update.call(day_night.day, day_night.hour)


## Troca de tela pelas abas (Inventário / Personagem / Mapa).
func open_panel(which: String) -> void:
	var panels := {"inventory": _inventory_ui, "equipment": _equipment_ui, "character": _progression_ui, "auras": _aura_ui, "map": _map_ui, "creative": _creative_ui}
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
	_update_resource_hud()
	# Recarga de feitiço muda a cada frame; o resto atualiza por sinal.
	if _weapons and _weapons.current() is SpellCaster:
		_update_weapon()
	_boss_timer -= delta
	if _boss_timer <= 0.0:
		_boss_timer = 0.25
		_update_boss_bar()
	_minimap_timer -= delta
	if _minimap:
		# Telas cheias abertas escondem o minimapa; só o mouse solto não (dá para clicar
		# nos botões de zoom dele).
		_minimap_frame.visible = Settings.show_minimap and not _screens.any(func(s: Control) -> bool: return is_instance_valid(s) and s.visible)
	if _minimap and _minimap_frame.visible and _minimap_timer <= 0.0:
		_minimap_timer = 0.15
		_minimap.queue_redraw()
	if _fps_label and _fps_label.visible:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.5
			var fps := Engine.get_frames_per_second()
			_fps_label.text = "%d FPS" % fps
			_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if fps >= 55 else (Color(1.0, 0.85, 0.4) if fps >= 30 else Color(1.0, 0.45, 0.4)))
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = 1.0
		_update_network()


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
		_boss_label.text = str(boss.stats.get("name", tr("Chefe")))
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
	health_label.text = tr("Vida %d / %d") % [ceili(current), ceili(maximum)]
	if _health and _health.reserved > 0.0:
		health_label.text += "  " + tr("(%d reservada)") % roundi(maximum * _health.reserved)
	if _shield_bar and _health:
		_shield_bar.visible = _health.max_shield > 0.0
		_shield_bar.max_value = maxf(maximum, _health.max_shield)
		_shield_bar.value = _health.shield
		if _health.max_shield > 0.0:
			health_label.text += "  ·  " + tr("Escudo %d / %d") % [ceili(_health.shield), ceili(_health.max_shield)]
	if current > 0.0:
		death_label.visible = false


# --- HUD de recursos (etapa 4) ------------------------------------------------------------

func _build_resource_hud(player: Player) -> void:
	_player = player
	# Barras antigas: escondidas (continuam recebendo valores). A caixa fica para os
	# avisos de Fraqueza e sobrecarga, agora acima da esfera de vida.
	for n: Control in [health_label, health_bar, stamina_bar, mana_bar]:
		n.visible = false
	var box := health_bar.get_parent() as Control
	box.offset_top = -330.0
	box.offset_bottom = -170.0
	weapon_label.offset_left = -520.0
	weapon_label.offset_right = -170.0
	_life_orb = ResourceOrb.new()
	_life_orb.fill_color = Color(0.72, 0.12, 0.12)
	add_child(_life_orb)
	_mana_orb = ResourceOrb.new()
	_mana_orb.fill_color = Color(0.2, 0.36, 0.85)
	add_child(_mana_orb)
	_life_arc = ResourceArc.new()
	_life_arc.side = -1
	_life_arc.thickness = 7.0
	_life_arc.fill_color = Color(0.85, 0.2, 0.2)
	add_child(_life_arc)
	_mana_arc = ResourceArc.new()
	_mana_arc.side = 1
	_mana_arc.thickness = 7.0
	_mana_arc.fill_color = Color(0.3, 0.5, 1.0)
	add_child(_mana_arc)
	_stamina_arc = ResourceArc.new()
	_stamina_arc.side = -1
	_stamina_arc.radius = 44.0
	_stamina_arc.thickness = 4.0
	_stamina_arc.span = 80.0
	_stamina_arc.fade_when_full = true
	_stamina_arc.fill_color = Color(0.92, 0.8, 0.28)
	add_child(_stamina_arc)
	_buff_bar = BuffBar.new()
	_buff_bar.player = player
	add_child(_buff_bar)
	_hud_editor = HudEditor.new()
	_hud_editor.hud = self
	add_child(_hud_editor)
	_screens.append(_hud_editor)
	get_viewport().size_changed.connect(apply_hud_layout)
	apply_hud_layout()


## O que o editor da HUD pode mover: nome → controle.
func hud_items() -> Dictionary:
	return {"life_orb": _life_orb, "mana_orb": _mana_orb, "buffs": _buff_bar}


## Posições, tamanhos e estilo (esferas ou arcos) salvos nas Configurações.
func apply_hud_layout() -> void:
	if _life_orb == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var layout := HudEditor.layout()
	for key: String in ["life_orb", "mana_orb"]:
		var entry: Array = layout[key]
		var orb := hud_items()[key] as Control
		var s := float(entry[2])
		orb.size = Vector2(s, s)
		orb.position = Vector2(float(entry[0]) * vp.x, float(entry[1]) * vp.y) - orb.size * 0.5
	var arcs := Settings.hud_style == "arcs"
	_life_orb.visible = not arcs
	_mana_orb.visible = not arcs
	_life_arc.visible = arcs
	_mana_arc.visible = arcs
	_life_arc.radius = Settings.hud_arc_radius
	_mana_arc.radius = Settings.hud_arc_radius
	# Stamina por dentro dos arcos de vida/mana (ou perto da mira).
	_stamina_arc.radius = clampf(Settings.hud_arc_radius - 16.0, 34.0, 200.0) if arcs else 44.0
	var buffs: Array = layout["buffs"]
	_buff_center = Vector2(float(buffs[0]) * vp.x, float(buffs[1]) * vp.y)
	_center_buffs()


func _center_buffs() -> void:
	_buff_bar.reset_size()
	_buff_bar.position = _buff_center - _buff_bar.get_combined_minimum_size() * 0.5


func open_hud_editor() -> void:
	for s: Control in _screens:
		if s != _hud_editor and is_instance_valid(s) and s.visible and s.has_method(&"toggle"):
			s.toggle()
	_hud_editor.open()


func _update_resource_hud() -> void:
	if _player == null or not is_instance_valid(_player) or _life_orb == null:
		return
	var h := _player.health
	var life := [h.current, h.max_health, h.reserved, h.shield, h.max_shield]
	var mana := [_player.mana.current, _player.mana.max_value, _player.mana.reserved]
	if _life_orb.visible:
		_life_orb.set_values(life[0], life[1], life[2], life[3], life[4])
		_mana_orb.set_values(mana[0], mana[1], mana[2])
	else:
		_life_arc.set_values(life[0], life[1], life[2], life[3], life[4])
		_mana_arc.set_values(mana[0], mana[1], mana[2])
	_stamina_arc.set_values(_player.stamina.current, _player.stamina.max_value)
	_center_buffs()
	# Telas cheias abertas: a HUD de recursos some junto com o minimapa.
	var playing := MouseMode.playing() or _hud_editor.visible
	for n: Control in [_stamina_arc, _buff_bar]:
		n.visible = playing
	if Settings.hud_style == "arcs":
		_life_arc.visible = playing
		_mana_arc.visible = playing
