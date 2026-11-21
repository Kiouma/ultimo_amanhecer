class_name InventorySlotUI
extends PanelContainer
## Um quadrado de slot do inventário. Mostra nome curto e quantidade.
## Na tela de inventário: arrastar move/junta pilhas, botão direito divide ao meio.
## Na hotbar do HUD: só mostra (interactive = false).

const SIZE := Vector2(68, 68)

var inventory: Inventory
var index := 0
var interactive := true
var selected := false:
	set(value):
		selected = value
		_update_style()

var _name_label: Label
var _count_label: Label
var _key_label: Label
var _dur_bar: ColorRect
var _quality_label: Label
## Cor da borda e do fundo por qualidade/raridade (Q1..Q5: cinza, verde, azul, roxo, laranja).
const QUALITY_COLORS := Inventory.TIER_COLORS
const EMPTY_BG := Color(0.1, 0.1, 0.1, 0.75)
var _quality_color := Color(0.3, 0.3, 0.3, 0.9)
var _bg_color := EMPTY_BG
var _style := StyleBoxFlat.new()
## Brilho do item refinado (a cada 3 níveis muda a cor).
var _sparkles: CPUParticles2D


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.bg_color = Color(0.1, 0.1, 0.1, 0.75)
	_style.set_corner_radius_all(4)
	_style.set_border_width_all(2)
	_style.border_color = Color(0.3, 0.3, 0.3, 0.9)
	_style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", _style)

	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_name_label = _make_label(11, Color(0.92, 0.92, 0.88))
	_name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name_label)

	_count_label = _make_label(13, Color(1, 0.95, 0.7))
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_child(_count_label)

	_key_label = _make_label(10, Color(0.6, 0.6, 0.6))
	_key_label.position = Vector2(0, -2)
	box.add_child(_key_label)

	_quality_label = _make_label(10, Color.WHITE)
	_quality_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quality_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_child(_quality_label)

	# Durabilidade: faixa fina embaixo (verde → vermelho).
	_dur_bar = ColorRect.new()
	_dur_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dur_bar.size = Vector2(0, 3)
	box.add_child(_dur_bar)

	_sparkles = CPUParticles2D.new()
	_sparkles.emitting = false
	_sparkles.amount = 10
	_sparkles.lifetime = 1.0
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.emission_rect_extents = Vector2(26, 26)
	_sparkles.position = SIZE * 0.5 - Vector2(4, 4)
	_sparkles.direction = Vector2.UP
	_sparkles.spread = 30.0
	_sparkles.gravity = Vector2(0, -12)
	_sparkles.initial_velocity_min = 4.0
	_sparkles.initial_velocity_max = 12.0
	_sparkles.scale_amount_min = 2.0
	_sparkles.scale_amount_max = 3.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	_sparkles.color_ramp = fade
	box.add_child(_sparkles)


## compact: versão menor da hotbar do HUD (fonte menor para o nome caber).
func setup(inv: Inventory, slot_index: int, is_interactive := true, compact := false) -> void:
	if compact:
		custom_minimum_size = Vector2(60, 60)
		_name_label.add_theme_font_size_override("font_size", 9)
		_sparkles.position = Vector2(26, 26)
		_sparkles.emission_rect_extents = Vector2(22, 22)
	inventory = inv
	index = slot_index
	interactive = is_interactive
	if index < Inventory.HOTBAR_SIZE:
		_key_label.text = str(index + 1)
	refresh()


func refresh() -> void:
	var s := inventory.get_slot(index)
	_quality_label.text = ""
	_quality_color = Color(0.3, 0.3, 0.3, 0.9)
	_bg_color = EMPTY_BG
	var tier := Inventory.tier_of(s)
	if tier > 0:
		_quality_color = QUALITY_COLORS[tier - 1]
		_bg_color = Color(_quality_color.darkened(0.55), 0.85)
	var fx := Inventory.refine_fx_tier(s)
	_sparkles.emitting = fx > 0
	if fx > 0:
		_sparkles.color = Inventory.REFINE_FX_COLORS[mini(fx, Inventory.REFINE_FX_COLORS.size()) - 1]
		_sparkles.amount = 6 + 3 * fx
	if s.is_empty():
		_name_label.text = ""
		_count_label.text = ""
		tooltip_text = ""
	else:
		var data := GameData.get_item(s.id)
		var item_name := str(data.get("name", s.id))
		_name_label.text = item_name
		var count := int(s.count)
		_count_label.text = str(count) if count > 1 else ""
		if s.has("mag"):
			_count_label.text = "%d" % int(s.mag)
		var max_dur := Inventory.max_durability_of(s)
		if max_dur > 0.0:
			var q := Inventory.quality_of(s)
			_quality_label.text = "Q%d" % q
			_quality_label.add_theme_color_override("font_color", _quality_color)
			var refine := Inventory.refine_of(s)
			if refine > 0:
				_name_label.text += " +%d" % refine
			if Inventory.is_broken(s):
				_name_label.text += "\n" + tr("(quebrado)")
		# O texto só liga a dica; o conteúdo é o painel de _make_custom_tooltip.
		tooltip_text = item_name if interactive else ""
	_update_dur_bar()
	_update_style()


## Dica com as informações do item (efeitos, números, Material/Consumível).
func _make_custom_tooltip(_for_text: String) -> Object:
	var s := inventory.get_slot(index) if inventory else {}
	return ItemTooltip.build(s) if not s.is_empty() else null


func _update_dur_bar() -> void:
	var s := inventory.get_slot(index)
	var max_dur := Inventory.max_durability_of(s)
	_dur_bar.visible = max_dur > 0.0
	if not _dur_bar.visible:
		return
	var frac := clampf(Inventory.durability_of(s) / max_dur, 0.0, 1.0)
	var full := maxf(custom_minimum_size.x - 8.0, 1.0)
	_dur_bar.position = Vector2(0, custom_minimum_size.y - 11.0)
	_dur_bar.size = Vector2(maxf(full * frac, 2.0), 3)
	_dur_bar.color = Color(0.85, 0.25, 0.2).lerp(Color(0.4, 0.8, 0.35), frac) if frac > 0.0 else Color(0.6, 0.1, 0.1)


func _update_style() -> void:
	_style.border_color = Color(0.95, 0.8, 0.35) if selected else _quality_color.darkened(0.25)
	_style.bg_color = _bg_color


# --- Arrastar e soltar ---------------------------------------------------------------------

func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or inventory.get_slot(index).is_empty():
		return null
	var preview := _make_label(14, Color.WHITE)
	preview.text = _name_label.text
	set_drag_preview(preview)
	return {"slot_from": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return interactive and data is Dictionary and data.has("slot_from")


func _drop_data(_at: Vector2, data: Variant) -> void:
	inventory.move_slot(int(data.slot_from), index)


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		inventory.split_slot(index)
		accept_event()
	elif interactive and event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		equip_from_slot()
		accept_event()


## Clique duplo: usa o item. Equipamento e armas vão para o corpo/mão (o que estava lá
## volta para o inventário); consumível é usado; livro de habilidade é lido; estação e
## armadilha são colocadas à frente (WeaponHolder.use_item).
func equip_from_slot() -> void:
	var player := inventory.get_parent() as Player
	if inventory.get_slot(index).is_empty() or player == null:
		return
	player.weapons.use_item(index)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
