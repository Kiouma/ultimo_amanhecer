class_name CraftingUI
extends Control
## Tela de uma estação de fabricação (E na fogueira, bancada...): só as receitas daquela
## estação, em cartões (RecipeCard), a fila de fabricação e, na bancada, reparar,
## refinar e desmontar. Fecha com E, Tab, Esc ou ao se afastar da estação.
## As receitas das mãos ficam no inventário (Tab).

const PANEL_SIZE := Vector2(660, 580)

var player: Player
var inventory_ui: InventoryUI
var station: CraftingStation

var _title: Label
var _list: VBoxContainer
var _queue_box: VBoxContainer
var _dirty := false
var _opened_frame := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.08, 0.96)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var queue_title := Label.new()
	queue_title.text = "Fila de fabricação"
	queue_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	box.add_child(queue_title)
	_queue_box = VBoxContainer.new()
	box.add_child(_queue_box)
	var hint := Label.new()
	hint.text = "E, Tab ou Esc fecha"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.65, 0.65, 0.6)
	box.add_child(hint)


func bind(p: Player, inv_ui: InventoryUI) -> void:
	player = p
	inventory_ui = inv_ui
	EventBus.station_opened.connect(_on_station_opened)
	player.inventory.changed.connect(func() -> void: _dirty = true)
	player.craft_queue.changed.connect(func() -> void:
		if visible:
			inventory_ui.fill_queue(_queue_box))


func _exit_tree() -> void:
	if EventBus.station_opened.is_connected(_on_station_opened):
		EventBus.station_opened.disconnect(_on_station_opened)


func _on_station_opened(s: Node, who: Node) -> void:
	if who != player or not s is CraftingStation:
		return
	station = s
	if inventory_ui.visible:
		inventory_ui.toggle()
	visible = true
	_opened_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	visible = false
	station = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return  # o mesmo E que abriu não fecha
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if station == null or not is_instance_valid(station) or player.health.is_dead \
			or station.global_position.distance_to(player.global_position) > CraftingStation.USE_RANGE + 1.0:
		close()
		return
	if _dirty:
		_refresh()


func _refresh() -> void:
	_dirty = false
	_title.text = station.display_name()
	for c in _list.get_children():
		c.queue_free()
	var recipes := Crafting.recipes_for(station.station)
	if recipes.is_empty():
		var none := Label.new()
		none.text = "Nada para fabricar aqui"
		none.modulate = Color(0.6, 0.6, 0.58)
		_list.add_child(none)
	for recipe in recipes:
		_list.add_child(RecipeCard.build(player, recipe, func(r: Dictionary, n: int) -> void: player.craft_queue.enqueue(r, n)))
	if station.station == "workbench":
		inventory_ui.add_repair_section(_list)
	inventory_ui.fill_queue(_queue_box)
