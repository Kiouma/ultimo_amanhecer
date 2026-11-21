class_name InventoryUI
extends Control
## Tela de inventário (B): mochila, peso e fabricação nas mãos (GDD 8 e 13.2).
## Equipamento e status ficam na tela própria (V, EquipmentUI).
## As estações (fogueira, bancada) têm a própria tela de fabricação (CraftingUI).
## Fabricar entra na fila (CraftQueue), que aparece embaixo com progresso e cancelar.
## Arrastar entre slots move/junta; botão direito divide a pilha;
## soltar fora da janela joga o item no chão, na frente do jogador.

const COLUMNS := 8
## Tela compacta: mochila + fabricação ocupam pouco mais da metade da largura em 1280 px.
const SLOT_SIZE := Vector2(46, 46)

var player: Player
var _slots: Array[InventorySlotUI] = []
var _weight_label: Label
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _built := false
var _craft_list: VBoxContainer
var _craft_title: Label
var _queue_box: VBoxContainer
## Slot sob o mouse (-1 = nenhum).
var _hovered := -1


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # o fundo recebe o tr("soltar no chão")
	visible = false


func bind(p: Player) -> void:
	player = p
	if not _built:
		_build()
	player.inventory.changed.connect(_refresh)
	player.inventory.gold_changed.connect(func(_g: int, _d: int) -> void:
		if visible:
			_refresh())
	player.craft_queue.changed.connect(_refresh_queue)
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
	MouseMode.refresh()
	_hovered = -1
	if visible:
		_refresh()


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
	_weight_label.text = tr("Ouro: %d   ·   Peso: %.1f / %.0f kg%s") % [inv.gold, weight, inv.max_weight, tr("  (sobrecarregado: lento)") if inv.is_overloaded() else ""]
	_weight_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if inv.is_overloaded() else Color(0.85, 0.85, 0.8))
	_weight_bar.max_value = inv.max_weight
	_weight_bar.value = minf(weight, inv.max_weight)
	_weight_fill.bg_color = Color(0.85, 0.35, 0.3) if inv.is_overloaded() else Color(0.55, 0.75, 0.45)
	_refresh_crafting()
	_refresh_queue()


## Receitas feitas nas mãos (as das estações ficam na tela de cada estação, CraftingUI).
func _refresh_crafting() -> void:
	for child in _craft_list.get_children():
		child.queue_free()
	_craft_title.text = tr("Fabricar (%s)") % tr("mãos")
	for recipe in Crafting.recipes_for("hands"):
		_craft_list.add_child(RecipeCard.build(player, recipe, _enqueue))


func _enqueue(recipe: Dictionary, times: int) -> void:
	var n := Crafting.max_times(player.inventory, recipe) if times < 0 else times
	player.craft_queue.enqueue(recipe, n)


## Bancada: reparar (durabilidade cheia) e desmontar (recupera materiais) itens do inventário.
func add_repair_section(target: Control) -> void:
	var header := Label.new()
	header.text = "Reparar e desmontar (refino: Upgrading Machine)"
	header.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	target.add_child(header)
	var inv := player.inventory
	var any := false
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not (Repair.is_repairable(s) or Repair.is_salvageable(s)):
			continue
		any = true
		var row := VBoxContainer.new()
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_END
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
		details.text = "reparo: %s · desmontar dá: %s" % [Repair.describe(cost) if not cost.is_empty() else "—", Repair.describe(Repair.salvage_result(s))]
		details.add_theme_font_size_override("font_size", 12)
		details.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(details)
		row.add_child(info)
		var repair_button := Button.new()
		repair_button.text = "Reparar"
		repair_button.disabled = not Repair.can_repair(inv, s)
		repair_button.pressed.connect(func() -> void: Repair.repair(player.inventory, s))
		actions.add_child(repair_button)
		var salvage_button := Button.new()
		salvage_button.text = "Desmontar"
		salvage_button.disabled = Repair.salvage_result(s).is_empty()
		salvage_button.pressed.connect(func() -> void: Repair.salvage(player.inventory, i))
		actions.add_child(salvage_button)
		row.add_child(actions)
		target.add_child(row)
	if not any:
		var none := Label.new()
		none.text = "nada para reparar ou desmontar"
		none.add_theme_color_override("font_color", Color(0.5, 0.5, 0.48))
		target.add_child(none)


## Fila: uma linha por trabalho, com progresso, pausa (longe da estação) e cancelar.
func _refresh_queue() -> void:
	fill_queue(_queue_box)


## Fila de fabricação em `box` (também usada pela tela das estações).
func fill_queue(box: Control) -> void:
	if box == null:
		return
	for child in box.get_children():
		child.queue_free()
	var queue := player.craft_queue
	if queue.jobs.is_empty():
		var empty := Label.new()
		empty.text = "vazia"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.48))
		box.add_child(empty)
	for i in queue.jobs.size():
		var job: Dictionary = queue.jobs[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		var item_name := str(GameData.get_item(str(job.recipe.result)).get("name", job.recipe.result))
		var paused := i == 0 and not queue.is_station_ok(job.recipe)
		var note := tr("  (pausado: longe da %s)") % Crafting.station_name(str(job.recipe.station)) if paused else ""
		label.text = tr("%s · faltam %d%s") % [item_name, int(job.left), note]
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
		box.add_child(row)


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
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	UITabs.attach(self, "inventory", panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	panel.add_child(columns)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	columns.add_child(vbox)

	var craft := VBoxContainer.new()
	craft.custom_minimum_size = Vector2(290, 0)
	craft.add_theme_constant_override("separation", 8)
	columns.add_child(craft)
	_craft_title = Label.new()
	_craft_title.text = "Fabricar (mãos)"
	_craft_title.add_theme_font_size_override("font_size", 18)
	craft.add_child(_craft_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290, 340)
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
	title.add_theme_font_size_override("font_size", 18)
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

	var help := Label.new()
	help.text = "Arraste para mover · botão direito divide · solte fora da janela para jogar no chão\nclique duplo: equipa, usa, lê ou coloca · B fecha"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vbox.add_child(help)


func _new_slot(i: int) -> InventorySlotUI:
	var slot := InventorySlotUI.new()
	slot.setup(player.inventory, i)
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_entered.connect(func() -> void: _hovered = i)
	slot.mouse_exited.connect(func() -> void:
		if _hovered == i:
			_hovered = -1)
	_slots.append(slot)
	return slot
