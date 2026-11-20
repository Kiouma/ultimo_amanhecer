class_name HudEditor
extends Control
## Editor da HUD (engrenagem ao lado da hotbar). Arrastar move as esferas de vida e mana
## e a barra de buffs; a roda do mouse em cima de uma esfera muda o tamanho. No painel:
## vida e mana em esferas (canto da tela) ou em arcos "(" e ")" perto da mira, raio dos
## arcos, restaurar o padrão. Salvo nas Configurações (por máquina).

## Posições padrão: centro (fração da tela) e tamanho em pixels (0 = não muda).
const DEFAULTS := {
	"life_orb": [0.075, 0.855, 118.0],
	"mana_orb": [0.925, 0.855, 118.0],
	"buffs": [0.5, 0.79, 0.0],
}
const DEFAULT_ARC_RADIUS := 62.0
const NAMES := {"life_orb": "Vida", "mana_orb": "Mana", "buffs": "Buffs"}

## O HUD (DebugHUD): hud_items() e apply_hud_layout().
var hud: Node

var _drag := ""
var _drag_offset := Vector2.ZERO
var _orbs_button: Button
var _arcs_button: Button
var _radius: HSlider


static func layout() -> Dictionary:
	var out := {}
	for key: String in DEFAULTS:
		var saved: Variant = Settings.hud_layout.get(key)
		out[key] = saved if saved is Array and saved.size() == 3 else DEFAULTS[key].duplicate()
	return out


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open() -> void:
	visible = true
	_sync_buttons()
	MouseMode.refresh()
	queue_redraw()


func close() -> void:
	visible = false
	_drag = ""
	Settings.remember("hud_layout", Settings.hud_layout)
	Settings.remember("hud_style", Settings.hud_style)
	Settings.remember("hud_arc_radius", Settings.hud_arc_radius)
	MouseMode.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _set_item(key: String, value: Array) -> void:
	var l := Settings.hud_layout.duplicate(true)
	l[key] = value
	Settings.hud_layout = l
	hud.apply_hud_layout()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var items: Dictionary = hud.hud_items()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = _item_at(items, mb.position)
				if _drag != "":
					var rect: Rect2 = (items[_drag] as Control).get_global_rect()
					_drag_offset = rect.get_center() - mb.position
			else:
				_drag = ""
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var key := _item_at(items, mb.position)
			if key.ends_with("_orb"):
				var l := layout()
				var entry: Array = l[key]
				entry[2] = clampf(float(entry[2]) + (8.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -8.0), 60.0, 220.0)
				_set_item(key, entry)
			accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		var vp := get_viewport_rect().size
		var center := ((event as InputEventMouseMotion).position + _drag_offset).clamp(Vector2.ZERO, vp)
		var entry: Array = layout()[_drag]
		entry[0] = center.x / vp.x
		entry[1] = center.y / vp.y
		_set_item(_drag, entry)


func _item_at(items: Dictionary, at: Vector2) -> String:
	for key: String in items:
		var c := items[key] as Control
		if c.visible and c.get_global_rect().grow(6.0).has_point(at):
			return key
	return ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	if hud == null:
		return
	var font := get_theme_default_font()
	var items: Dictionary = hud.hud_items()
	for key: String in items:
		var c := items[key] as Control
		if not c.visible:
			continue
		var rect := c.get_global_rect().grow(4.0)
		if rect.size.x < 20.0:
			rect = Rect2(rect.position - Vector2(60, 16), Vector2(120, 32))  # barra de buffs vazia
		var color := Color(1.0, 0.85, 0.3) if key == _drag else Color(1.0, 0.85, 0.3, 0.6)
		draw_rect(rect, color, false, 2.0)
		draw_string_outline(font, rect.position + Vector2(4, -4), tr(str(NAMES[key])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(font, rect.position + Vector2(4, -4), tr(str(NAMES[key])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _sync_buttons() -> void:
	_orbs_button.button_pressed = Settings.hud_style != "arcs"
	_arcs_button.button_pressed = Settings.hud_style == "arcs"
	_radius.set_value_no_signal(Settings.hud_arc_radius)
	_radius.editable = Settings.hud_style == "arcs"


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 60)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Editar HUD"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Arraste para mover · roda do mouse numa esfera muda o tamanho"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.75, 0.75, 0.7)
	box.add_child(hint)
	var style_row := HBoxContainer.new()
	style_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(style_row)
	var style_label := Label.new()
	style_label.text = "Vida e mana:"
	style_row.add_child(style_label)
	var group := ButtonGroup.new()
	_orbs_button = Button.new()
	_orbs_button.text = "Esferas"
	_arcs_button = Button.new()
	_arcs_button.text = "Arcos perto da mira"
	for b: Button in [_orbs_button, _arcs_button]:
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		style_row.add_child(b)
	_orbs_button.pressed.connect(func() -> void:
		Settings.hud_style = "orbs"
		_sync_buttons()
		hud.apply_hud_layout()
		queue_redraw())
	_arcs_button.pressed.connect(func() -> void:
		Settings.hud_style = "arcs"
		_sync_buttons()
		hud.apply_hud_layout()
		queue_redraw())
	var radius_row := HBoxContainer.new()
	box.add_child(radius_row)
	var radius_label := Label.new()
	radius_label.text = "Raio dos arcos"
	radius_row.add_child(radius_label)
	_radius = HSlider.new()
	_radius.min_value = 50
	_radius.max_value = 160
	_radius.step = 2
	_radius.custom_minimum_size = Vector2(180, 20)
	_radius.focus_mode = Control.FOCUS_NONE
	_radius.value_changed.connect(func(v: float) -> void:
		Settings.hud_arc_radius = v
		hud.apply_hud_layout())
	radius_row.add_child(_radius)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var reset := Button.new()
	reset.text = "Restaurar padrão"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		Settings.hud_layout = {}
		Settings.hud_style = "orbs"
		Settings.hud_arc_radius = DEFAULT_ARC_RADIUS
		_sync_buttons()
		hud.apply_hud_layout()
		queue_redraw())
	buttons.add_child(reset)
	var done := Button.new()
	done.text = "Concluir"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	buttons.add_child(done)
