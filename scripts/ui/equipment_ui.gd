class_name EquipmentUI
extends Control
## Tela de equipamentos (tecla V): as peças vestidas, arrumadas como um corpo, e o
## painel de status (EquipmentPanel). Separada do inventário (B) desde a virada para
## RPG. Vestir: clique duplo no item do inventário, ou clique no slot daqui.

var player: Player
var _panel: EquipmentPanel


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func bind(p: Player) -> void:
	player = p
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.08, 0.95)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	frame.add_theme_stylebox_override("panel", style)
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)
	_panel = EquipmentPanel.new()
	box.add_child(_panel)
	_panel.setup(player, true)
	var hint := Label.new()
	hint.text = "Clique no slot para vestir/tirar · clique duplo no item do inventário (B) veste · [V] fecha"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.65, 0.65, 0.6)
	box.add_child(hint)
	UITabs.attach(self, "equipment", frame)
	player.equipment.changed.connect(func() -> void:
		if visible:
			_panel.refresh())
	player.progression.changed.connect(func() -> void:
		if visible:
			_panel.refresh())


func refresh() -> void:
	if _panel:
		_panel.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("equipment"):
		if not visible and get_parent().has_method(&"open_panel"):
			get_parent().open_panel("equipment")
		else:
			toggle()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and not player.health.is_dead
	MouseMode.refresh()
	if visible:
		_panel.refresh()
