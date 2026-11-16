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
var _style := StyleBoxFlat.new()


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

	# Durabilidade: faixa fina embaixo (verde → vermelho).
	_dur_bar = ColorRect.new()
	_dur_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dur_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dur_bar.size = Vector2(0, 3)
	box.add_child(_dur_bar)


## compact: versão menor da hotbar do HUD (fonte menor para o nome caber).
func setup(inv: Inventory, slot_index: int, is_interactive := true, compact := false) -> void:
	if compact:
		custom_minimum_size = Vector2(60, 60)
		_name_label.add_theme_font_size_override("font_size", 9)
	inventory = inv
	index = slot_index
	interactive = is_interactive
	if index < Inventory.HOTBAR_SIZE:
		_key_label.text = str(index + 1)
	refresh()


func refresh() -> void:
	var s := inventory.get_slot(index)
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
		var max_dur := Inventory.max_durability(s.id)
		if max_dur > 0.0:
			tooltip_text += "
Durabilidade %d / %d" % [roundi(Inventory.durability_of(s)), roundi(max_dur)] if interactive else ""
			if Inventory.is_broken(s):
				_name_label.text += "
(quebrado)"
		var weight := float(data.get("weight", 0.0))
		tooltip_text = "%s\n%s · %.2f kg cada · %.1f kg" % [item_name, str(data.get("type", "")), weight, weight * count] \
			if interactive else ""
	_update_dur_bar()
	_update_style()


func _update_dur_bar() -> void:
	var s := inventory.get_slot(index)
	var max_dur := Inventory.max_durability(s.id) if not s.is_empty() else 0.0
	_dur_bar.visible = max_dur > 0.0
	if not _dur_bar.visible:
		return
	var frac := clampf(Inventory.durability_of(s) / max_dur, 0.0, 1.0)
	var full := maxf(custom_minimum_size.x - 8.0, 1.0)
	_dur_bar.position = Vector2(0, custom_minimum_size.y - 11.0)
	_dur_bar.size = Vector2(maxf(full * frac, 2.0), 3)
	_dur_bar.color = Color(0.85, 0.25, 0.2).lerp(Color(0.4, 0.8, 0.35), frac) if frac > 0.0 else Color(0.6, 0.1, 0.1)


func _update_style() -> void:
	_style.border_color = Color(0.95, 0.8, 0.35) if selected else Color(0.3, 0.3, 0.3, 0.9)


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


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
