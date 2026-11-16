class_name ProgressionUI
extends Control
## Painel do personagem (tecla P): nível, XP, proficiências, maestria de armas e,
## na coluna da direita, as trilhas de habilidades (GDD 4.1, 4.2 e 12).

var player: Player

var _title: Label
var _xp_bar: ProgressBar
var _profs: VBoxContainer
var _mastery: Label
var _skills: VBoxContainer
var _points: Label
var _gear_buttons := {}
var _gear_info: Label
var _gear_menu: PopupMenu
var _gear_menu_slot := ""
var _gear_menu_indexes: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "character")


func bind(p: Player) -> void:
	player = p
	player.progression.changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("progression"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and not player.health.is_dead
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()


func _refresh() -> void:
	_refresh_gear()
	var prog := player.progression
	_title.text = "Nível %d" % prog.char_level
	_xp_bar.max_value = Progression.char_xp_to_next(prog.char_level)
	_xp_bar.value = prog.char_xp
	_xp_bar.tooltip_text = "%d / %d XP" % [int(prog.char_xp), int(_xp_bar.max_value)]
	for c in _profs.get_children():
		c.queue_free()
	for id: String in GameData.get_all("proficiencies"):
		var data := GameData.get_entry("proficiencies", id)
		var level := prog.get_level(id)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var head := Label.new()
		head.text = "%s · nível %d" % [data.get("name", id), level]
		head.add_theme_font_size_override("font_size", 14)
		row.add_child(head)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		bar.max_value = Progression.xp_to_next(level)
		bar.value = float(prog.xp.get(id, 0.0))
		row.add_child(bar)
		var info := Label.new()
		info.text = "%s · sobe: %s" % [data.get("summary", ""), str(data.get("raised_by", "")).to_lower()]
		info.add_theme_font_size_override("font_size", 11)
		info.modulate = Color(0.75, 0.75, 0.72)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		_profs.add_child(row)
	var parts: PackedStringArray = []
	for t in ["bow", "firearm", "melee", "spell"]:
		parts.append("%s %d" % [Progression.mastery_name(t).capitalize(), prog.mastery_level(t)])
	_mastery.text = "Maestria (até +10% de dano): " + " · ".join(parts)
	_refresh_skills()


## Coluna de habilidades, agrupadas por trilha.
func _refresh_skills() -> void:
	var prog := player.progression
	_points.text = "Pontos de habilidade: %d (1 por nível do personagem)" % prog.skill_points
	for c in _skills.get_children():
		c.queue_free()
	var by_trail := {}
	for id: String in GameData.get_all("skills"):
		var trail := str(GameData.get_entry("skills", id).get("trail", ""))
		if not by_trail.has(trail):
			by_trail[trail] = []
		by_trail[trail].append(id)
	for trail: String in by_trail:
		var title := Label.new()
		title.text = "Trilha do " + str(Progression.TRAIL_NAMES.get(trail, trail))
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		_skills.add_child(title)
		for id: String in by_trail[trail]:
			_skills.add_child(_skill_row(id))


func _skill_row(id: String) -> Control:
	var prog := player.progression
	var data := GameData.get_entry("skills", id)
	var row := HBoxContainer.new()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	var learned := prog.skills.has(id)
	name_label.text = "%s%s (%d pt)" % ["✓ " if learned else "", data.get("name", id), int(data.get("cost", 1))]
	name_label.add_theme_font_size_override("font_size", 13)
	if learned:
		name_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	text.add_child(name_label)
	var desc := Label.new()
	var req: Dictionary = data.get("requires", {})
	var req_parts: PackedStringArray = []
	for prof: String in req:
		req_parts.append("%s %d" % [GameData.get_entry("proficiencies", prof).get("name", prof), int(req[prof])])
	desc.text = "%s · requer %s" % [data.get("desc", ""), ", ".join(req_parts)]
	desc.add_theme_font_size_override("font_size", 11)
	desc.modulate = Color(0.75, 0.75, 0.72)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	row.add_child(text)
	if not learned:
		var button := Button.new()
		var reason := prog.learn_block_reason(id)
		button.text = "Aprender"
		button.disabled = reason != ""
		button.tooltip_text = reason
		button.pressed.connect(func() -> void:
			prog.learn(id))
		row.add_child(button)
	return row


# --- Equipamento ----------------------------------------------------------------------

func _build_gear(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(290, 0)
	parent.add_child(col)
	var title := Label.new()
	title.text = "Equipamento"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for slot: String in Equipment.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 52)
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_gear_pressed.bind(slot))
		grid.add_child(b)
		_gear_buttons[slot] = b
	_gear_info = Label.new()
	_gear_info.add_theme_font_size_override("font_size", 11)
	_gear_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gear_info.custom_minimum_size = Vector2(290, 0)
	col.add_child(_gear_info)
	var hint := Label.new()
	hint.text = "Clique num slot vazio para vestir algo do inventário; num cheio, para tirar."
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.7, 0.7, 0.68)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	_gear_menu = PopupMenu.new()
	_gear_menu.id_pressed.connect(_on_gear_menu)
	add_child(_gear_menu)


func _refresh_gear() -> void:
	var eq := player.equipment
	for slot: String in Equipment.SLOTS:
		var item := eq.get_item(slot)
		var b: Button = _gear_buttons[slot]
		if item.is_empty():
			b.text = "%s\n(vazio)" % Equipment.SLOT_NAMES[slot]
			b.modulate = Color(0.75, 0.75, 0.75)
		else:
			var data := GameData.get_item(item.id)
			var extra := ""
			if Inventory.max_durability(item.id) > 0.0:
				extra = " · %d/%d" % [ceili(Inventory.durability_of(item)), int(Inventory.max_durability_of(item))]
			b.text = "%s\n%s%s" % [Equipment.SLOT_NAMES[slot], Inventory.display_name_of(item), extra]
			b.modulate = Color(1, 0.55, 0.5) if Inventory.is_broken(item) else Color.WHITE
			b.tooltip_text = _bonus_text(data.get("bonus", {}))
	var lines: PackedStringArray = []
	var armor := eq.armor_total()
	lines.append("Proteção: %d (−%d%% de dano)" % [roundi(armor), roundi(100.0 * armor / (armor + 100.0))])
	var counts := eq.set_counts()
	for set_id: String in counts:
		var data := GameData.get_entry("sets", set_id)
		lines.append("Conjunto %s (%s): %d peças" % [data.get("name", set_id), data.get("style", ""), int(counts[set_id])])
		var desc: Dictionary = data.get("desc", {})
		for need: String in desc:
			lines.append("   %s %s peças: %s" % ["✓" if int(counts[set_id]) >= int(need) else "·", need, desc[need]])
	_gear_info.text = "\n".join(lines)


func _on_gear_pressed(slot: String) -> void:
	var eq := player.equipment
	if not eq.get_item(slot).is_empty():
		eq.unequip(slot)
		_refresh()
		return
	_gear_menu.clear()
	_gear_menu_indexes.clear()
	_gear_menu_slot = slot
	var inv := player.inventory
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not s.is_empty() and Equipment.fits(s.id, slot):
			_gear_menu.add_item(Inventory.display_name_of(s), _gear_menu_indexes.size())
			_gear_menu_indexes.append(i)
	if _gear_menu_indexes.is_empty():
		player.notify("Nada para %s no inventário" % str(Equipment.SLOT_NAMES[slot]).to_lower())
		return
	_gear_menu.position = Vector2i(get_global_mouse_position())
	_gear_menu.popup()


func _on_gear_menu(id: int) -> void:
	player.equipment.equip_from_inventory(int(_gear_menu_indexes[id]), _gear_menu_slot)
	_refresh()


static func _bonus_text(bonus: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in bonus:
		var v := float(bonus[key])
		parts.append("%s %s" % [key, ("%+d" % roundi(v)) if key.ends_with("_add") else ("%+d%%" % roundi(v * 100.0))])
	return ", ".join(parts)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1240, 600)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)

	_build_gear(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	columns.add_child(left)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	left.add_child(_title)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 12)
	_xp_bar.show_percentage = false
	left.add_child(_xp_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_profs = VBoxContainer.new()
	_profs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profs.add_theme_constant_override("separation", 6)
	scroll.add_child(_profs)
	_mastery = Label.new()
	_mastery.add_theme_font_size_override("font_size", 12)
	_mastery.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_mastery)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var skills_title := Label.new()
	skills_title.text = "Habilidades"
	skills_title.add_theme_font_size_override("font_size", 22)
	right.add_child(skills_title)
	_points = Label.new()
	right.add_child(_points)
	var skill_scroll := ScrollContainer.new()
	skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(skill_scroll)
	_skills = VBoxContainer.new()
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(_skills)
	var hint := Label.new()
	hint.text = "[P] fechar"
	hint.modulate = Color(0.7, 0.7, 0.7)
	right.add_child(hint)
