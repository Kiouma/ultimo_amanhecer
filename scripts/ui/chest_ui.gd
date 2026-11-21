class_name ChestUI
extends Control
## Tela do baú: à esquerda o que está no baú (clique pega), à direita o seu
## inventário (clique guarda a pilha inteira). Fecha com E, B, Esc ou ao se afastar.

var player: Player
var _chest: BaseUtility
var _left: GridContainer
var _right: GridContainer
var _title: Label


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	box.add_child(cols)
	_left = _column(cols, tr("Baú (clique para pegar)"))
	_right = _column(cols, tr("Seu inventário (clique para guardar)"))
	var hint := Label.new()
	hint.text = "E, B ou Esc fecha"
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)
	EventBus.chest_opened.connect(_on_opened)
	EventBus.chest_changed.connect(func(c: Node) -> void:
		if visible and c == _chest:
			_refresh())


func bind(p: Player) -> void:
	player = p
	player.inventory.changed.connect(func() -> void:
		if visible:
			_refresh())


func _column(parent: Control, text: String) -> GridContainer:
	var col := VBoxContainer.new()
	parent.add_child(col)
	var label := Label.new()
	label.text = text
	col.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 380)
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	scroll.add_child(grid)
	return grid


func _on_opened(chest: Node, who: Node) -> void:
	if who != player:
		return
	_chest = chest
	visible = true
	MouseMode.refresh()
	_refresh()


func close() -> void:
	visible = false
	_chest = null
	MouseMode.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(_chest) or _chest.global_position.distance_to(player.global_position) > CraftingStation.USE_RANGE + 1.0):
		close()


func _refresh() -> void:
	if not is_instance_valid(_chest):
		return
	_title.text = tr("Baú · %d/%d pilhas") % [_chest.contents.size(), BaseUtility.MAX_STACKS]
	for c in _left.get_children():
		c.queue_free()
	for c in _right.get_children():
		c.queue_free()
	for i in _chest.contents.size():
		var s: Dictionary = _chest.contents[i]
		_left.add_child(_button(s, func() -> void: _chest.take(i)))
	var inv := player.inventory
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if s.is_empty():
			continue
		_right.add_child(_button(s, func() -> void:
			var stack := inv.get_slot(i)
			if stack.is_empty():
				return
			var moved := {"id": stack.id, "count": int(stack.count)}
			moved.merge(Inventory.extra_of(stack))
			inv.take_from_slot(i, int(stack.count))
			_chest.put(moved)))


func _button(s: Dictionary, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(138, 40)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 11)
	b.text = "%s%s" % [Inventory.display_name_of(s), " ×%d" % int(s.count) if int(s.count) > 1 else ""]
	b.pressed.connect(action)
	return b
