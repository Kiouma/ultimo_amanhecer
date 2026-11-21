class_name TradeUI
extends Control
## Janela de troca (etapa 9). À esquerda, o que você oferece (clique num item do seu
## inventário embaixo para pôr/tirar; ouro no campo); à direita, o que o outro oferece.
## Confirmar dos dois lados faz a troca. Mudar qualquer oferta tira as confirmações.
## Também mostra o convite ("X quer trocar itens") com Aceitar/Recusar.

var player: Player

var _panel: PanelContainer
var _title: Label
var _mine: VBoxContainer
var _theirs: VBoxContainer
var _gold: SpinBox
var _their_gold: Label
var _status: Label
var _confirm: Button
var _grid: GridContainer
var _invite: ConfirmationDialog
var _updating := false


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func bind(p: Player) -> void:
	player = p
	var t := player.trade
	t.invited.connect(_on_invited)
	t.opened.connect(func(_partner: Player) -> void:
		visible = true
		MouseMode.refresh()
		_refresh())
	t.changed.connect(_refresh)
	t.closed.connect(func(_reason: String) -> void:
		visible = false
		MouseMode.refresh())
	player.inventory.changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		player.trade.cancel()
		get_viewport().set_input_as_handled()


func _on_invited(from: Player) -> void:
	_invite.dialog_text = tr("%s quer trocar itens com você.") % from.display_name()
	_invite.popup_centered()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(640, 520)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.position = -_panel.custom_minimum_size * 0.5
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	root.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lt := Label.new()
	lt.text = "Você oferece"
	left.add_child(lt)
	_mine = VBoxContainer.new()
	_mine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_mine)
	var gold_row := HBoxContainer.new()
	var gl := Label.new()
	gl.text = "Ouro:"
	gold_row.add_child(gl)
	_gold = SpinBox.new()
	_gold.step = 1
	_gold.value_changed.connect(func(v: float) -> void:
		if not _updating:
			player.trade.set_gold(int(v)))
	gold_row.add_child(_gold)
	left.add_child(gold_row)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rt := Label.new()
	rt.text = "O outro oferece"
	right.add_child(rt)
	_theirs = VBoxContainer.new()
	_theirs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_theirs)
	_their_gold = Label.new()
	right.add_child(_their_gold)
	var hint := Label.new()
	hint.text = "Clique num item do seu inventário para pôr ou tirar da oferta:"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	root.add_child(hint)
	_grid = GridContainer.new()
	_grid.columns = 10
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	root.add_child(_grid)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	root.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(func() -> void: player.trade.cancel())
	buttons.add_child(cancel)
	_confirm = Button.new()
	_confirm.text = "Confirmar"
	_confirm.pressed.connect(func() -> void: player.trade.confirm())
	buttons.add_child(_confirm)
	_invite = ConfirmationDialog.new()
	_invite.title = "Troca"
	_invite.ok_button_text = "Aceitar"
	_invite.cancel_button_text = "Recusar"
	_invite.confirmed.connect(func() -> void: player.trade.accept_invite())
	_invite.canceled.connect(func() -> void: player.trade.decline_invite())
	add_child(_invite)


func _refresh() -> void:
	var t := player.trade
	if not t.is_open():
		return
	_title.text = tr("Troca com %s") % t.partner.display_name()
	for c in _mine.get_children() + _theirs.get_children() + _grid.get_children():
		c.queue_free()
	for e: Dictionary in t.my_items:
		_mine.add_child(_line(str(e.id), int(e.count)))
	for e: Dictionary in t.their_items:
		_theirs.add_child(_line(str(e.get("id", "")), int(e.get("count", 1))))
	_updating = true
	_gold.max_value = player.inventory.gold
	_gold.value = t.my_gold
	_updating = false
	_their_gold.text = tr("Ouro: %d") % t.their_gold
	var offered := {}
	for e: Dictionary in t.my_items:
		offered[int(e.index)] = true
	var inv := player.inventory
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if s.is_empty():
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 40)
		b.text = "%s\n×%d" % [Inventory.display_name_of(s).left(9), int(s.count)]
		b.add_theme_font_size_override("font_size", 10)
		b.toggle_mode = true
		b.button_pressed = offered.has(i)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = Inventory.display_name_of(s)
		var index := i
		b.pressed.connect(func() -> void: player.trade.toggle_item(index))
		_grid.add_child(b)
	_status.text = "%s · %s" % [tr("Você confirmou") if t.my_ok else tr("Você não confirmou"), tr("o outro confirmou") if t.their_ok else tr("o outro ainda não confirmou")]
	_confirm.disabled = t.my_ok


func _line(id: String, count: int) -> Label:
	var l := Label.new()
	l.text = "%s ×%d" % [tr(str(GameData.get_item(id).get("name", id))), count]
	return l
