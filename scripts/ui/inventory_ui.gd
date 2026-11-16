class_name InventoryUI
extends Control
## Tela de inventário (Tab): mochila, hotbar, peso e fabricação (GDD 8 e 13.2).
## Aberta com E numa estação (fogueira, bancada), mostra também as receitas dela.
## Fabricar entra na fila (CraftQueue), que aparece embaixo com progresso e cancelar.
## Arrastar entre slots move/junta; botão direito divide a pilha;
## soltar fora da janela joga o item no chão, na frente do jogador.

const COLUMNS := 8

var player: Player
var _slots: Array[InventorySlotUI] = []
var _weight_label: Label
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _built := false
var _craft_list: VBoxContainer
var _craft_title: Label
var _queue_box: VBoxContainer
## Estação aberta (null = só mãos).
var _station: CraftingStation


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # o fundo recebe o "soltar no chão"
	visible = false


func bind(p: Player) -> void:
	player = p
	if not _built:
		_build()
	player.inventory.changed.connect(_refresh)
	player.craft_queue.changed.connect(_refresh_queue)
	EventBus.station_opened.connect(_on_station_opened)
	_refresh()


func _on_station_opened(station: Node, who: Node) -> void:
	if who != player:
		return
	_station = station
	if not visible:
		toggle()
	else:
		_refresh()


func _process(_delta: float) -> void:
	# Afastou da estação: volta a mostrar só as receitas das mãos.
	if _station and (not is_instance_valid(_station) \
			or _station.global_position.distance_to(player.global_position) > CraftingStation.USE_RANGE + 1.0):
		_station = null
		if visible:
			_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and not player.health.is_dead
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()
	else:
		_station = null


# Soltar fora dos slots (no fundo escuro) = jogar no chão.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("slot_from")


func _drop_data(_at: Vector2, data: Variant) -> void:
	var from := int(data.slot_from)
	var s := player.inventory.get_slot(from)
	if s.is_empty():
		return
	var taken := player.inventory.take_from_slot(from, int(s.count))
	var ahead := -player.global_basis.z * 1.8 + Vector3.UP * 0.3  # fora do raio da coleta automática
	WorldItems.drop(taken.id, taken.count, player.global_position + ahead, player, Inventory.extra_of(taken))


func _refresh() -> void:
	for slot in _slots:
		slot.refresh()
	var inv := player.inventory
	var weight := inv.total_weight()
	_weight_label.text = "Peso: %.1f / %.0f kg%s" % [weight, inv.max_weight, "  (sobrecarregado: lento)" if inv.is_overloaded() else ""]
	_weight_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if inv.is_overloaded() else Color(0.85, 0.85, 0.8))
	_weight_bar.max_value = inv.max_weight
	_weight_bar.value = minf(weight, inv.max_weight)
	_weight_fill.bg_color = Color(0.85, 0.35, 0.3) if inv.is_overloaded() else Color(0.55, 0.75, 0.45)
	_refresh_crafting()
	_refresh_queue()


## Receitas da estação aberta (se houver) e das mãos. Fabricar (1), ×5 e Tudo entram na fila.
func _refresh_crafting() -> void:
	for child in _craft_list.get_children():
		child.queue_free()
	var stations: Array[String] = ["hands"]
	if _station:
		stations.push_front(_station.station)
	_craft_title.text = "Fabricar (%s)" % (_station.display_name().to_lower() + " + mãos" if _station else "mãos")
	for station in stations:
		if stations.size() > 1:
			var header := Label.new()
			header.text = Crafting.station_name(station).capitalize()
			header.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
			_craft_list.add_child(header)
		for recipe in Crafting.recipes_for(station):
			_craft_list.add_child(_recipe_row(recipe))
	if _station and _station.station == "workbench":
		_add_repair_section()


func _recipe_row(recipe: Dictionary) -> Control:
	var possible := Crafting.max_times(player.inventory, recipe)
	var result := GameData.get_item(str(recipe.result))
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "%s ×%d" % [result.get("name", recipe.result), int(recipe.get("amount", 1))]
	title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88) if possible > 0 else Color(0.55, 0.55, 0.52))
	info.add_child(title)
	var needs := Label.new()
	needs.text = "%s · %ss" % [Crafting.describe_ingredients(recipe), str(recipe.get("time", 2))]
	needs.add_theme_font_size_override("font_size", 12)
	needs.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	info.add_child(needs)
	row.add_child(info)
	row.add_child(_craft_button("Fabricar", recipe, 1, possible >= 1))
	row.add_child(_craft_button("×5", recipe, 5, possible >= 5))
	row.add_child(_craft_button("Tudo (%d)" % possible, recipe, -1, possible >= 2))
	return row


## times = -1: quantas der na hora do clique.
func _craft_button(text: String, recipe: Dictionary, times: int, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.pressed.connect(_enqueue.bind(recipe, times))
	return button


func _enqueue(recipe: Dictionary, times: int) -> void:
	var n := Crafting.max_times(player.inventory, recipe) if times < 0 else times
	player.craft_queue.enqueue(recipe, n)


## Bancada: reparar (durabilidade cheia) e desmontar (recupera materiais) itens do inventário.
func _add_repair_section() -> void:
	var header := Label.new()
	header.text = "Reparar, refinar e desmontar"
	header.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	_craft_list.add_child(header)
	var inv := player.inventory
	var any := false
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not (Repair.is_repairable(s) or Repair.is_salvageable(s) or Refine.can_be_refined(s)):
			continue
		any = true
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Label.new()
		var max_dur := Inventory.max_durability_of(s)
		title.text = Inventory.display_name_of(s)
		if max_dur > 0.0:
			title.text += "  %d/%d" % [roundi(Inventory.durability_of(s)), roundi(max_dur)]
		title.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if Inventory.is_broken(s) else Color(0.92, 0.92, 0.88))
		info.add_child(title)
		var cost := Repair.repair_cost(s)
		var details := Label.new()
		var refine_text := "máximo" if Refine.is_maxed(s) else "+%d por %d pedra(s) de refino" % [Inventory.refine_of(s) + 1, Refine.cost(s)]
		details.text = "reparo: %s · refino: %s · desmontar dá: %s" % [Repair.describe(cost) if not cost.is_empty() else "—", refine_text if Refine.can_be_refined(s) else "—", Repair.describe(Repair.salvage_result(s))]
		details.add_theme_font_size_override("font_size", 12)
		details.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(details)
		row.add_child(info)
		var repair_button := Button.new()
		repair_button.text = "Reparar"
		repair_button.disabled = not Repair.can_repair(inv, s)
		repair_button.pressed.connect(func() -> void: Repair.repair(player.inventory, s))
		row.add_child(repair_button)
		var refine_button := Button.new()
		refine_button.text = "Refinar"
		refine_button.tooltip_text = "+5% de dano/eficiência por nível (até +12). Pedra de refino cai de inimigos."
		refine_button.disabled = not Refine.can_refine(inv, s)
		refine_button.pressed.connect(func() -> void: Refine.refine(player.inventory, s))
		row.add_child(refine_button)
		var salvage_button := Button.new()
		salvage_button.text = "Desmontar"
		salvage_button.disabled = Repair.salvage_result(s).is_empty()
		salvage_button.pressed.connect(func() -> void: Repair.salvage(player.inventory, i))
		row.add_child(salvage_button)
		_craft_list.add_child(row)
	if not any:
		var none := Label.new()
		none.text = "nada para reparar ou desmontar"
		none.add_theme_color_override("font_color", Color(0.5, 0.5, 0.48))
		_craft_list.add_child(none)


## Fila: uma linha por trabalho, com progresso, pausa (longe da estação) e cancelar.
func _refresh_queue() -> void:
	if _queue_box == null:
		return
	for child in _queue_box.get_children():
		child.queue_free()
	var queue := player.craft_queue
	if queue.jobs.is_empty():
		var empty := Label.new()
		empty.text = "vazia"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.48))
		_queue_box.add_child(empty)
	for i in queue.jobs.size():
		var job: Dictionary = queue.jobs[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		var item_name := str(GameData.get_item(str(job.recipe.result)).get("name", job.recipe.result))
		var paused := i == 0 and not queue.is_station_ok(job.recipe)
		var note := "  (pausado: longe da %s)" % Crafting.station_name(str(job.recipe.station)) if paused else ""
		label.text = "%s · faltam %d%s" % [item_name, int(job.left), note]
		row.add_child(label)
		if i == 0:
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(80, 10)
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.value = float(job.progress)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bar)
		var cancel := Button.new()
		cancel.text = "×"
		cancel.tooltip_text = "Cancelar (devolve os ingredientes)"
		cancel.pressed.connect(queue.cancel.bind(i))
		row.add_child(cancel)
		_queue_box.add_child(row)


func _build() -> void:
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.08, 0.95)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	columns.add_child(vbox)

	var craft := VBoxContainer.new()
	craft.custom_minimum_size = Vector2(400, 0)
	craft.add_theme_constant_override("separation", 8)
	columns.add_child(craft)
	_craft_title = Label.new()
	_craft_title.text = "Fabricar (mãos)"
	_craft_title.add_theme_font_size_override("font_size", 22)
	craft.add_child(_craft_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	craft.add_child(scroll)
	_craft_list = VBoxContainer.new()
	_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_craft_list)
	var queue_title := Label.new()
	queue_title.text = "Fila de fabricação"
	queue_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	craft.add_child(queue_title)
	_queue_box = VBoxContainer.new()
	craft.add_child(_queue_box)

	var title := Label.new()
	title.text = "Inventário"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_weight_label = Label.new()
	vbox.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.2)
	_weight_fill = StyleBoxFlat.new()
	_weight_fill.bg_color = Color(0.55, 0.75, 0.45)
	_weight_bar.add_theme_stylebox_override("background", bg)
	_weight_bar.add_theme_stylebox_override("fill", _weight_fill)
	vbox.add_child(_weight_bar)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	vbox.add_child(grid)
	var inv := player.inventory
	for i in range(Inventory.HOTBAR_SIZE, inv.slots.size()):
		grid.add_child(_new_slot(i))

	var hotbar_title := Label.new()
	hotbar_title.text = "Hotbar (teclas 1 a 9)"
	hotbar_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	vbox.add_child(hotbar_title)
	var hotbar := HBoxContainer.new()
	vbox.add_child(hotbar)
	for i in Inventory.HOTBAR_SIZE:
		hotbar.add_child(_new_slot(i))

	var help := Label.new()
	help.text = "Arraste para mover · botão direito divide · solte fora da janela para jogar no chão · Tab fecha"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vbox.add_child(help)


func _new_slot(i: int) -> InventorySlotUI:
	var slot := InventorySlotUI.new()
	slot.setup(player.inventory, i)
	_slots.append(slot)
	return slot
