class_name SkillsUI
extends Control
## Tela de Habilidades (tecla K, etapa 6). Uma linha por habilidade da classe (pela ordem
## de desbloqueio) e, embaixo, as habilidades únicas aprendidas com livros. Cada linha:
## ícone, nome e nível, descrição curta, o próximo marco (5/10/15/20), o botão de
## desbloquear/evoluir (com o custo em ouro e Essência de chefe) e os botões 1 a 5 que
## põem a habilidade naquele slot da barra.

var player: Player

var _list: VBoxContainer
var _gold_label: Label
var _footer: Label


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "skills")


func bind(p: Player) -> void:
	player = p
	var again := func() -> void:
		if visible:
			_refresh()
	player.skills.changed.connect(again)
	player.progression.changed.connect(again)
	player.inventory.gold_changed.connect(func(_g: int, _d: int) -> void: again.call())
	player.inventory.changed.connect(again)


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("skills"):
		if not visible and get_parent().has_method(&"open_panel"):
			get_parent().open_panel("skills")
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
		_footer.text = ""
		_refresh()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(820, 640)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	var title := Label.new()
	title.text = "Habilidades"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 13)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root.add_child(_gold_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	root.add_child(_footer)
	var help := Label.new()
	help.text = "Teclas 1 a 5 usam a barra · habilidades de área: a tecla mostra o círculo, o clique solta, Esc cancela\nEvoluir até o nível 20 custa ouro; os níveis 5, 10, 15 e 20 pedem Essência de chefe e dão um efeito extra · K fecha"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	root.add_child(help)


func _refresh() -> void:
	if player == null:
		return
	var skills := player.skills
	_gold_label.text = tr("Ouro: %d  ·  Essência de chefe: %d  ·  Nível do personagem: %d") % [
		player.inventory.gold, player.inventory.count_of(Skills.ESSENCE), player.progression.char_level]
	for c in _list.get_children():
		c.queue_free()
	var class_ids := skills.class_skills()
	if class_ids.is_empty():
		var none := Label.new()
		none.text = tr("Este personagem não tem classe com habilidades.")
		_list.add_child(none)
	for id: String in class_ids:
		_list.add_child(_row(id))
	var books := skills.book_skills()
	var header := Label.new()
	header.text = tr("Habilidades únicas (livros de habilidade, caem de chefes)")
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	_list.add_child(header)
	if books.is_empty():
		var none := Label.new()
		none.text = tr("Nenhuma ainda.")
		none.add_theme_color_override("font_color", Color(0.55, 0.55, 0.5))
		_list.add_child(none)
	for id: String in books:
		_list.add_child(_row(id))


func _row(id: String) -> Control:
	var skills := player.skills
	var d := Skills.data(id)
	var level := skills.level_of(id)
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.9) if level > 0 else Color(0.08, 0.08, 0.09, 0.9)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", style)
	box.tooltip_text = SkillBar.skill_tooltip(skills, id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(_icon(id))
	# Texto.
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	row.add_child(text)
	var name_label := Label.new()
	var head := str(d.get("name", id))
	if level > 0:
		head += "  ·  " + tr("Nível %d") % level
	elif not bool(d.get("book", false)):
		head += "  ·  " + tr("abre no nível %d") % int(d.get("unlock", 1))
	name_label.text = head
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1) if level > 0 else Color(0.65, 0.65, 0.62))
	text.add_child(name_label)
	var desc := Label.new()
	desc.text = str(d.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	text.add_child(desc)
	var next_mark := 0
	for m: int in Skills.MILESTONES:
		if level < m:
			next_mark = m
			break
	if next_mark > 0:
		var mark := Label.new()
		mark.text = tr("Nível %d: %s") % [next_mark, str(d.get("milestone_text", {}).get(str(next_mark), ""))]
		mark.add_theme_font_size_override("font_size", 11)
		mark.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		text.add_child(mark)
	# Ações.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	row.add_child(actions)
	var main := Button.new()
	main.focus_mode = Control.FOCUS_NONE
	main.custom_minimum_size = Vector2(200, 0)
	if level <= 0:
		var reason := skills.unlock_block_reason(id)
		main.text = tr("Desbloquear (%d de ouro)") % Skills.unlock_cost(id)
		main.disabled = reason != ""
		main.tooltip_text = reason
		main.pressed.connect(func() -> void: skills.unlock(id))
	elif level < Skills.MAX_LEVEL:
		var next := level + 1
		var cost := tr("%d de ouro") % Skills.level_cost(next)
		if Skills.essence_cost(next) > 0:
			cost += tr(" + %d Essência") % Skills.essence_cost(next)
		var reason := skills.level_block_reason(id)
		main.text = tr("Evoluir para %d (%s)") % [next, cost]
		main.disabled = reason != ""
		main.tooltip_text = reason
		main.pressed.connect(func() -> void: skills.level_up(id))
	else:
		main.text = tr("Nível máximo")
		main.disabled = true
	actions.add_child(main)
	if level > 0:
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 3)
		actions.add_child(slots)
		for i in Skills.BAR_SIZE:
			var b := Button.new()
			b.text = str(i + 1)
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(36, 0)
			b.toggle_mode = true
			b.button_pressed = str(skills.bar[i]) == id
			b.tooltip_text = tr("Pôr no slot %d da barra") % (i + 1)
			b.pressed.connect(func() -> void:
				if str(skills.bar[i]) == id:
					skills.assign("", i)
				else:
					skills.assign(id, i))
			slots.add_child(b)
	return box


## Ícone simples (iniciais na cor da escola).
func _icon(id: String) -> Control:
	var d := Skills.data(id)
	var c := player.skills.caster(id)
	var color := c.color() if c else Color.WHITE
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(48, 48)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55) if player.skills.level_of(id) > 0 else Color(0.15, 0.15, 0.16)
	style.border_color = color.lightened(0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var initials := ""
	for word: String in str(d.get("name", id)).split(" ", false):
		if word.length() > 2:
			initials += word.left(1).to_upper()
	label.text = initials.left(2)
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)
	return panel
