class_name InventoryUI
extends Control
## Tela de inventário (Tab): mochila, hotbar, peso e fabricação nas mãos (GDD 8 e 13.2).
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # o fundo recebe o "soltar no chão"
	visible = false


func bind(p: Player) -> void:
	player = p
	if not _built:
		_build()
	player.inventory.changed.connect(_refresh)
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


# Soltar fora dos slots (no fundo escuro) = jogar no chão.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("slot_from")


func _drop_data(_at: Vector2, data: Variant) -> void:
	var from := int(data.slot_from)
	var s := player.inventory.get_slot(from)
	if s.is_empty():
		return
	var taken := player.inventory.take_from_slot(from, int(s.count))
	var ahead := -player.global_basis.z * 1.2 + Vector3.UP * 0.3
	WorldItems.drop(taken.id, taken.count, player.global_position + ahead, player)


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


## Lista de receitas "nas mãos": cada uma com Fabricar (1x) e Tudo (quantas der).
func _refresh_crafting() -> void:
	for child in _craft_list.get_children():
		child.queue_free()
	var inv := player.inventory
	for recipe in Crafting.recipes_for("hands"):
		var result := GameData.get_item(str(recipe.result))
		var possible := Crafting.max_times(inv, recipe)
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Label.new()
		title.text = "%s ×%d" % [result.get("name", recipe.result), int(recipe.get("amount", 1))]
		title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88) if possible > 0 else Color(0.55, 0.55, 0.52))
		info.add_child(title)
		var needs := Label.new()
		needs.text = Crafting.describe_ingredients(recipe)
		needs.add_theme_font_size_override("font_size", 12)
		needs.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
		info.add_child(needs)
		row.add_child(info)
		var one := Button.new()
		one.text = "Fabricar"
		one.disabled = possible < 1
		one.pressed.connect(func() -> void: Crafting.craft(player.inventory, recipe, 1))
		row.add_child(one)
		var all := Button.new()
		all.text = "Tudo (%d)" % possible
		all.disabled = possible < 2
		all.pressed.connect(func() -> void: Crafting.craft(player.inventory, recipe, Crafting.max_times(player.inventory, recipe)))
		row.add_child(all)
		_craft_list.add_child(row)


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
	craft.custom_minimum_size = Vector2(300, 0)
	craft.add_theme_constant_override("separation", 8)
	columns.add_child(craft)
	var craft_title := Label.new()
	craft_title.text = "Fabricar (mãos)"
	craft_title.add_theme_font_size_override("font_size", 22)
	craft.add_child(craft_title)
	_craft_list = VBoxContainer.new()
	_craft_list.add_theme_constant_override("separation", 8)
	craft.add_child(_craft_list)

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
