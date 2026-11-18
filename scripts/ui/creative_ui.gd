class_name CreativeUI
extends Control
## Aba Criativo (só no modo criativo, ligado no Esc): atalhos do personagem (nível,
## proficiências, habilidades, voo, encher barras) e o catálogo com todos os itens do jogo.
## Catálogo: clique esquerdo dá 1, direito dá uma pilha cheia. Qualidade e refino
## escolhidos valem para armas, ferramentas e equipamentos.

const TYPE_ORDER := ["melee", "thrown", "bow", "tool", "focus", "armor", "ammo", "consumable", "grimoire", "resource", "station", "trap"]

var player: Player
var _grid: GridContainer
var _search: LineEdit
var _type_filter: OptionButton
var _quality: OptionButton
var _refine: SpinBox
var _level_label: Label
var _fly: CheckButton
var _types: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "creative")


func bind(p: Player) -> void:
	player = p
	player.progression.changed.connect(func() -> void:
		if visible:
			_refresh_info())
	EventBus.creative_changed.connect(func(on: bool) -> void:
		if not on and visible:
			toggle())


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and player.creative and not player.health.is_dead
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh_info()
		_refresh_catalog()


func _process(_delta: float) -> void:
	if visible and _fly.button_pressed != player.flying:
		_fly.set_pressed_no_signal(player.flying)


# --- Montagem -----------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	# Esquerda: personagem.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var title := Label.new()
	title.text = "Criativo"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	_level_label = Label.new()
	left.add_child(_level_label)
	_button(left, "+1 nível de personagem", func() -> void: _add_levels(1))
	_button(left, "+10 níveis de personagem", func() -> void: _add_levels(10))
	_button(left, "+10 em todas as proficiências", _boost_proficiencies)
	_button(left, "Todas as habilidades no nível máximo", _learn_all_spells)
	_button(left, "Encher vida, fome, sede, stamina e mana", _refill)
	_fly = CheckButton.new()
	_fly.text = "Voar (ou Espaço duas vezes)"
	_fly.toggled.connect(func(on: bool) -> void: player.flying = on)
	left.add_child(_fly)
	var note := Label.new()
	note.text = "Você está invencível.
No criativo nada se gasta: comida, munição,\nmateriais de construção e fabricação, pedras\nde refino e durabilidade. Basta ter 1 unidade."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	left.add_child(note)

	# Direita: catálogo.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	var cat_title := Label.new()
	cat_title.text = "Todos os itens (esquerdo: 1 · direito: pilha cheia)"
	cat_title.add_theme_font_size_override("font_size", 18)
	right.add_child(cat_title)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	right.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar..."
	_search.custom_minimum_size = Vector2(180, 0)
	_search.text_changed.connect(func(_t: String) -> void: _refresh_catalog())
	filters.add_child(_search)
	_type_filter = OptionButton.new()
	_type_filter.add_item("Todos os tipos")
	_types.append("")
	for t: String in TYPE_ORDER:
		_type_filter.add_item(_type_name(t))
		_types.append(t)
	_type_filter.item_selected.connect(func(_i: int) -> void: _refresh_catalog())
	filters.add_child(_type_filter)
	_quality = OptionButton.new()
	for q in range(1, Inventory.MAX_QUALITY + 1):
		_quality.add_item("Q%d" % q)
	_quality.tooltip_text = "Qualidade das armas, ferramentas e equipamentos dados"
	_quality.item_selected.connect(func(_i: int) -> void: _refresh_catalog())
	filters.add_child(_quality)
	var refine_label := Label.new()
	refine_label.text = "Refino +"
	filters.add_child(refine_label)
	_refine = SpinBox.new()
	_refine.max_value = Inventory.MAX_REFINE
	filters.add_child(_refine)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


static func _type_name(t: String) -> String:
	return {"melee": TranslationServer.translate("Corpo a corpo"), "thrown": TranslationServer.translate("Arremesso"), "bow": TranslationServer.translate("Arcos e bestas"), "tool": TranslationServer.translate("Ferramentas"), "focus": TranslationServer.translate("Cajados"), "armor": TranslationServer.translate("Equipamentos"),
		"ammo": TranslationServer.translate("Munição"), "consumable": TranslationServer.translate("Consumíveis"), "grimoire": TranslationServer.translate("Grimórios"), "resource": TranslationServer.translate("Recursos"),
		"station": TranslationServer.translate("Estações e base"), "trap": TranslationServer.translate("Armadilhas")}.get(t, t)


# --- Atualização --------------------------------------------------------------------------

func _refresh_info() -> void:
	var prog := player.progression
	_level_label.text = tr("Nível %d · %d ponto(s) de habilidade") % [prog.char_level, prog.skill_points]
	_fly.set_pressed_no_signal(player.flying)


## Itens do jogo em ordem: por tipo (TYPE_ORDER) e nome.
func _all_items() -> Array:
	var list := []
	for id: String in GameData.get_all("items"):
		var data := GameData.get_item(id)
		var t := str(data.get("type", ""))
		if t == "spell":
			continue
		list.append(data)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := TYPE_ORDER.find(str(a.get("type", "")))
		var tb := TYPE_ORDER.find(str(b.get("type", "")))
		ta = TYPE_ORDER.size() if ta < 0 else ta
		tb = TYPE_ORDER.size() if tb < 0 else tb
		if ta != tb:
			return ta < tb
		return str(a.get("name", "")) < str(b.get("name", "")))
	return list


func _refresh_catalog() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var type_id := _types[_type_filter.selected] if _type_filter.selected >= 0 else ""
	for data: Dictionary in _all_items():
		var item_name := str(data.get("name", data.id))
		if query != "" and not item_name.to_lower().contains(query) and not str(data.id).contains(query):
			continue
		if type_id != "" and str(data.get("type", "")) != type_id:
			continue
		_grid.add_child(_item_button(data))


func _item_button(data: Dictionary) -> Button:
	var id := str(data.id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(146, 44)
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.text = str(data.get("name", id))
	b.tooltip_text = tr("%s\n%s · pilha de %d") % [b.text, _type_name(str(data.get("type", ""))), GameData.max_stack(id)]
	var tier := clampi(int(data.get("tier", 0)), 0, Inventory.MAX_QUALITY)
	if Inventory.max_durability(id) > 0.0:
		tier = _quality.selected + 1
	var color: Color = Inventory.TIER_COLORS[tier - 1] if tier > 0 else Color(0.3, 0.3, 0.3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.darkened(0.55), 0.9) if tier > 0 else Color(0.14, 0.14, 0.13, 0.9)
	sb.border_color = color.darkened(0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(color.darkened(0.35), 0.95)
	b.add_theme_stylebox_override("hover", hover)
	b.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_give(id, 1)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_give(id, GameData.max_stack(id))
			b.accept_event())
	return b


func _give(id: String, count: int) -> void:
	var extra := {}
	if Inventory.max_durability(id) > 0.0:
		extra = {"q": _quality.selected + 1, "r": int(_refine.value)}
	var left := player.inventory.add_item(id, count, extra)
	var item_name := str(GameData.get_item(id).get("name", id))
	if left >= count:
		player.notify(tr("Inventário cheio"))
	else:
		player.notify("+%d %s" % [count - left, item_name])


# --- Personagem ---------------------------------------------------------------------------

func _add_levels(n: int) -> void:
	var prog := player.progression
	for i in n:
		prog.gain_character(Progression.char_xp_to_next(prog.char_level) - prog.char_xp + 0.01, false)
	prog.changed.emit()


func _boost_proficiencies() -> void:
	var prog := player.progression
	for prof: String in prog.levels:
		prog.levels[prof] = mini(int(prog.levels[prof]) + 10, Progression.MAX_LEVEL)
		prog.xp[prof] = 0.0
	prog._rebuild()
	prog.changed.emit()
	player.notify(tr("Proficiências +10"))


func _learn_all_spells() -> void:
	var prog := player.progression
	for id: String in GameData.get_all("items"):
		var data := GameData.get_item(id)
		if str(data.get("type", "")) != "grimoire":
			continue
		for spell_id: String in data.get("teaches", []):
			prog.spells[spell_id] = Progression.MAX_SPELL_LEVEL
	for spell_id: String in prog.spells:
		prog.spells[spell_id] = Progression.MAX_SPELL_LEVEL
	prog.changed.emit()
	player.notify(tr("Todas as habilidades no nível %d (roda do Q)") % Progression.MAX_SPELL_LEVEL)


func _refill() -> void:
	player.health.heal(player.health.max_health)
	player.survival.refill()
	player.stamina.refill()
	player.mana.refill()
	player.notify(tr("Tudo cheio"))
