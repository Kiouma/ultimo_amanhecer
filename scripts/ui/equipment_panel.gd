class_name EquipmentPanel
extends VBoxContainer
## Coluna da esquerda do inventário (Tab): equipamento vestido, arrumado como um corpo
## (capacete em cima, colar ao lado, anéis dos lados da armadura, luvas e botas embaixo)
## e, colado embaixo, o painel de status com duas abas:
## - Primários: vida, stamina, mana (e regenerações), redução de recarga, velocidade,
##   resistências, velocidade de ataque, dano por tipo...
## - Secundários: bônus de conjuntos e efeitos como aumento de loot e capacidade de carga.
## Arraste um item do inventário para um slot para vestir; clique num slot cheio para tirar.

const BODY_SIZE := Vector2(260, 300)
## slot → [posição, tamanho] dentro do corpo.
const LAYOUT := {
	"head": [Vector2(98, 0), Vector2(64, 64)],
	"neck": [Vector2(172, 10), Vector2(58, 58)],
	"chest": [Vector2(90, 72), Vector2(80, 104)],
	"ring1": [Vector2(28, 108), Vector2(58, 58)],
	"ring2": [Vector2(174, 108), Vector2(58, 58)],
	"hands": [Vector2(8, 186), Vector2(64, 64)],
	"legs": [Vector2(98, 184), Vector2(64, 108)],
	"feet": [Vector2(188, 186), Vector2(64, 64)],
}

var player: Player
var _slots := {}
var _stats_box: VBoxContainer
var _tab := "primary"
var _tab_buttons := {}
var _menu: PopupMenu
var _menu_slot := ""
var _menu_indexes: Array = []


func setup(p: Player) -> void:
	player = p
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Equipamento"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var body := _Body.new()
	body.custom_minimum_size = BODY_SIZE
	add_child(body)
	for slot: String in Equipment.SLOTS:
		var s := EquipSlot.new()
		s.panel = self
		s.slot = slot
		s.position = LAYOUT[slot][0]
		s.custom_minimum_size = LAYOUT[slot][1]
		s.size = LAYOUT[slot][1]
		body.add_child(s)
		_slots[slot] = s
	_build_stats()
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	player.equipment.changed.connect(refresh)
	player.progression.changed.connect(refresh)
	player.inventory.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if player == null or not is_visible_in_tree():
		return
	for slot: String in _slots:
		_slots[slot].refresh()
	_refresh_stats()


# --- Slots -------------------------------------------------------------------------------

func slot_clicked(slot: String, right: bool) -> void:
	var eq := player.equipment
	if not eq.get_item(slot).is_empty():
		eq.unequip(slot)
		return
	if right:
		return
	_menu.clear()
	_menu_indexes.clear()
	_menu_slot = slot
	var inv := player.inventory
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not s.is_empty() and Equipment.fits(s.id, slot):
			_menu.add_item(Inventory.display_name_of(s), _menu_indexes.size())
			_menu_indexes.append(i)
	if _menu_indexes.is_empty():
		player.notify(tr("Nada para %s no inventário") % tr(str(Equipment.SLOT_NAMES[slot])).to_lower())
		return
	_menu.position = Vector2i(get_global_mouse_position())
	_menu.popup()


func _on_menu(id: int) -> void:
	player.equipment.equip_from_inventory(int(_menu_indexes[id]), _menu_slot)


# --- Status ------------------------------------------------------------------------------

func _build_stats() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	for t: Array in [["primary", "Primários"], ["secondary", "Secundários"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_tab = t[0]
			_refresh_stats())
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.12, 0.9)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BODY_SIZE.x, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_stats_box = VBoxContainer.new()
	_stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_stats_box)


func _refresh_stats() -> void:
	for t: String in _tab_buttons:
		_tab_buttons[t].button_pressed = t == _tab
	for c in _stats_box.get_children():
		_stats_box.remove_child(c)
		c.queue_free()
	if _tab == "primary":
		for row: Array in primary_stats(player):
			_row(row[0], row[1], row[2] if row.size() > 2 else "")
	else:
		_secondary()


## [nome, valor, dica] dos status primários (também usado em testes).
static func primary_stats(p: Player) -> Array:
	var prog := p.progression
	var stamina := p.stamina
	var mana := p.mana
	var out: Array = []
	out.append([tr_static(TranslationServer.translate("Vida")), "%d" % ceili(p.health.max_health)])
	out.append([tr_static(TranslationServer.translate("Regeneração de vida")), "%.2f/s" % p.survival.regen_per_second,
		tr_static(TranslationServer.translate("Só com fome e sede acima de %d%%")) % int(p.survival.well_fed_threshold)])
	out.append([tr_static(TranslationServer.translate("Stamina")), "%d" % roundi(stamina.max_value)])
	out.append([tr_static(TranslationServer.translate("Regeneração de stamina")), "%.1f/s" % stamina.regen_per_second])
	out.append([tr_static(TranslationServer.translate("Mana")), "%d" % roundi(mana.max_value)])
	out.append([tr_static(TranslationServer.translate("Regeneração de mana")), "%.1f/s" % mana.regen_per_second,
		tr_static(TranslationServer.translate("%.1f/s depois de %d s sem conjurar nem atacar")) % [mana.regen_per_second * mana.out_of_action_factor, int(StatPool.OUT_OF_ACTION)]])
	out.append([tr_static(TranslationServer.translate("Redução de recarga")), "%d%%" % roundi(Progression.cooldown_reduction(p) * 100.0), tr_static(TranslationServer.translate("Vem de itens. Máximo 50%."))])
	out.append([tr_static(TranslationServer.translate("Velocidade de movimento")), "%.1f m/s (%+d%%)" % [p.walk_speed * prog.mult("move_speed"), roundi((prog.mult("move_speed") - 1.0) * 100.0)]])
	out.append([tr_static(TranslationServer.translate("Velocidade de ataque")), "%+d%%" % roundi(Progression.attack_speed(p) * 100.0),
		tr_static(TranslationServer.translate("Corpo a corpo e arremesso: 100% do valor. Puxada do arco: 20%."))])
	var armor := p.equipment.armor_total()
	out.append([tr_static(TranslationServer.translate("Proteção (armadura)")), "%d" % roundi(armor)])
	out.append([tr_static(TranslationServer.translate("Resistência a dano")), "%d%%" % roundi((1.0 - prog.mult("damage_taken")) * 100.0), tr_static(TranslationServer.translate("Armadura, Resistência e habilidades."))])
	out.append([tr_static(TranslationServer.translate("Resistência a magia")), "%d%%" % roundi(Progression.spell_resist(p) * 100.0), tr_static(TranslationServer.translate("Vem de itens. Reduz ácido e feitiços. Máximo 75%."))])
	out.append([tr_static(TranslationServer.translate("Dano corpo a corpo")), "%+d%%" % roundi((prog.mult("melee.damage") - 1.0) * 100.0)])
	out.append([tr_static(TranslationServer.translate("Dano à distância")), "%+d%%" % roundi((prog.mult("ranged.damage") - 1.0) * 100.0)])
	out.append([tr_static(TranslationServer.translate("Dano mágico")), "%+d%%" % roundi((prog.mult("magic.damage") - 1.0) * 100.0)])
	out.append([tr_static(TranslationServer.translate("Dano de arremesso")), "%+d%%" % roundi((prog.mult("thrown.damage") - 1.0) * 100.0)])
	out.append([tr_static(TranslationServer.translate("Custo de mana")), "%+d%%" % roundi((prog.mult("magic.mana") - 1.0) * 100.0)])
	return out


## [nome, valor, dica] dos efeitos secundários.
static func secondary_stats(p: Player) -> Array:
	var prog := p.progression
	var pct := func(key: String) -> String: return "%+d%%" % roundi((prog.mult(key) - 1.0) * 100.0)
	return [
		[tr_static(TranslationServer.translate("Aumento de loot")), "%+d%%" % roundi(clampf(prog.add("loot_bonus"), 0.0, 2.0) * 100.0), tr_static(TranslationServer.translate("Chance e quantidade dos itens que inimigos derrubam."))],
		[tr_static(TranslationServer.translate("Capacidade de carga")), TranslationServer.translate("%.0f kg") % p.inventory.max_weight, tr_static(TranslationServer.translate("Acima disso fica lento."))],
		[tr_static(TranslationServer.translate("Coleta de recursos")), pct.call("gather_yield")],
		[tr_static(TranslationServer.translate("Comida e bebida rendem")), pct.call("food")],
		[tr_static(TranslationServer.translate("Cura de bandagens e kits")), pct.call("heal")],
		[tr_static(TranslationServer.translate("Tempo de fabricação")), pct.call("craft_time")],
		[tr_static(TranslationServer.translate("Barulho")), pct.call("noise")],
		[tr_static(TranslationServer.translate("Stamina gasta correndo")), pct.call("sprint_stamina")],
		[tr_static(TranslationServer.translate("Dano de ataque surpresa")), pct.call("sneak_damage")],
		[tr_static(TranslationServer.translate("Dano na cabeça")), pct.call("headshot_damage")],
		[tr_static(TranslationServer.translate("Recuperar flechas")), pct.call("ranged.recover_chance")],
		[tr_static(TranslationServer.translate("Força da canalização")), pct.call("magic.channel")],
		[tr_static(TranslationServer.translate("Carga do golpe")), pct.call("melee.channel")],
	]


static func tr_static(text: String) -> String:
	return TranslationServer.translate(text)


func _secondary() -> void:
	var counts := player.equipment.set_counts()
	_header(tr("Conjuntos"))
	if counts.is_empty():
		_line(tr("Nenhuma peça de conjunto vestida."), Color(0.6, 0.6, 0.58))
	for set_id: String in counts:
		var data := GameData.get_entry("sets", set_id)
		_line("%s (%s): %d %s" % [data.get("name", set_id), data.get("style", ""), int(counts[set_id]), tr("peças")], Color(1.0, 0.85, 0.55))
		var desc: Dictionary = data.get("desc", {})
		for need: String in desc:
			var on := int(counts[set_id]) >= int(need)
			_line("  %s %s: %s" % ["✓" if on else "·", tr("%s peças") % need, desc[need]], Color(0.6, 1.0, 0.6) if on else Color(0.6, 0.6, 0.58))
	_header(tr("Efeitos secundários"))
	for row: Array in secondary_stats(player):
		_row(row[0], row[1], row[2] if row.size() > 2 else "")


func _header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	_stats_box.add_child(l)


func _line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	_stats_box.add_child(l)


func _row(label: String, value: String, hint := "") -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = hint
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.76))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = hint
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	row.add_child(v)
	_stats_box.add_child(row)


## Fundo do corpo: silhueta clara atrás dos slots.
class _Body extends Control:
	func _draw() -> void:
		var c := Color(1, 1, 1, 0.05)
		draw_circle(Vector2(130, 32), 30.0, c)
		draw_rect(Rect2(84, 68, 92, 112), c)
		draw_line(Vector2(84, 80), Vector2(40, 200), Color(1, 1, 1, 0.06), 14.0)
		draw_line(Vector2(176, 80), Vector2(220, 200), Color(1, 1, 1, 0.06), 14.0)
		draw_rect(Rect2(98, 180, 64, 112), c)


## Um slot de equipamento: mostra a peça, aceita arrastar do inventário.
class EquipSlot extends PanelContainer:
	var panel: EquipmentPanel
	var slot := ""
	var _label: Label
	var _style := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		_style.set_corner_radius_all(4)
		_style.set_border_width_all(2)
		_style.border_color = Color(0.3, 0.3, 0.3)
		_style.set_content_margin_all(3)
		add_theme_stylebox_override("panel", _style)
		_label = Label.new()
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 10)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func refresh() -> void:
		var item := panel.player.equipment.get_item(slot)
		if item.is_empty():
			_label.text = str(Equipment.SLOT_NAMES[slot])
			_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.43))
			_style.border_color = Color(0.3, 0.3, 0.3)
			_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			tooltip_text = tr("%s (vazio)\nArraste uma peça do inventário ou clique para escolher.") % tr(str(Equipment.SLOT_NAMES[slot]))
			return
		var data := GameData.get_item(item.id)
		_label.text = Inventory.display_name_of(item)
		var broken := Inventory.is_broken(item)
		_label.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if broken else Color(0.95, 0.95, 0.9))
		var tier: Color = Inventory.TIER_COLORS[clampi(int(item.get("q", 1)) - 1, 0, Inventory.TIER_COLORS.size() - 1)]
		_style.border_color = tier
		_style.bg_color = Color(tier.r * 0.25, tier.g * 0.25, tier.b * 0.25, 0.9)
		var lines: PackedStringArray = [Inventory.display_name_of(item)]
		if float(data.get("armor", 0.0)) > 0.0:
			lines.append(tr("Proteção: %d") % roundi(float(data.armor) * Inventory.quality_multiplier(item) * Inventory.refine_multiplier(item)))
		var bonus := ProgressionUI.bonus_text(data.get("bonus", {}))
		if bonus != "":
			lines.append(bonus)
		if Inventory.max_durability(item.id) > 0.0:
			lines.append(tr("Durabilidade: %d/%d") % [ceili(Inventory.durability_of(item)), int(Inventory.max_durability_of(item))])
		if str(data.get("set", "")) != "":
			lines.append(tr("Conjunto: %s") % GameData.get_entry("sets", str(data.set)).get("name", data.set))
		lines.append(tr("Clique para tirar."))
		tooltip_text = "\n".join(lines)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				panel.slot_clicked(slot, false)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				panel.slot_clicked(slot, true)
			accept_event()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and data.has("slot_from")):
			return false
		var s := panel.player.inventory.get_slot(int(data.slot_from))
		return not s.is_empty() and Equipment.fits(s.id, slot)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.player.equipment.equip_from_inventory(int(data.slot_from), slot)
