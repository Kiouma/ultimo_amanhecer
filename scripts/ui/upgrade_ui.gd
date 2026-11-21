class_name UpgradeUI
extends Control
## Tela da Upgrading Machine (etapa 10, GDD 8.4). À esquerda, os equipamentos (vestidos
## e no inventário); à direita, o item escolhido com os afixos e as ações:
## - Abrir slot: abre um slot de afixo fechado e sorteia o afixo (ouro + Pó arcano);
## - Re-sortear afixos: troca todos os afixos abertos (ouro + Cristal arcano);
## - Refinar: +1 de refino (Pedras de refino; pode falhar), o que antes era na bancada;
## - Qualidade: Q+1 até Q5 (ouro + 3 pedras de refino da raridade da qualidade atual);
## - Melhorar ferramenta: machado/picareta/vara para o próximo nível (receitas
##   "upgrading_machine"; a ferramenta precisa estar no inventário).
## Fecha com E, Esc ou ao se afastar.

var player: Player

var _station: Node3D
var _list: VBoxContainer
var _detail: VBoxContainer
var _status: Label
## Item escolhido: o dicionário do próprio slot (inventário ou equipamento).
var _item: Dictionary = {}
var _where := ""


func _ready() -> void:
	MouseMode.register(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func bind(p: Player) -> void:
	player = p
	EventBus.station_opened.connect(func(s: Node, who: Node) -> void:
		if who == player and s is CraftingStation and s.station == "upgrading_machine":
			_station = s
			visible = true
			MouseMode.refresh()
			_refresh())
	player.inventory.changed.connect(func() -> void:
		if visible:
			_refresh())
	player.equipment.changed.connect(func() -> void:
		if visible:
			_refresh())


func close() -> void:
	visible = false
	_station = null
	MouseMode.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(_station) or _station.global_position.distance_to(player.global_position) > 6.0):
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 600)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var title := Label.new()
	title.text = "Upgrading Machine"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(right)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	root.add_child(_status)
	var help := Label.new()
	help.text = "Escolha um equipamento à esquerda (vestido ou no inventário) · E ou Esc fecha"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	root.add_child(help)


## Equipamentos que dá para melhorar: [[texto, dicionário do item, onde]].
func _candidates() -> Array:
	var out: Array = []
	for slot: String in Equipment.SLOTS:
		var item := player.equipment.get_item(slot)
		if not item.is_empty() and (Affixes.can_have(item.id) or Refine.can_be_refined(item)):
			out.append([Inventory.display_name_of(item) + "  " + tr("(vestido)"), item, "eq"])
	var inv := player.inventory
	for i in inv.slots.size():
		var s := inv.get_slot(i)
		if not s.is_empty() and (Affixes.can_have(s.id) or Refine.can_be_refined(s)):
			out.append([Inventory.display_name_of(s), s, "inv"])
	return out


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var found := false
	for entry: Array in _candidates():
		var item: Dictionary = entry[1]
		var b := Button.new()
		b.text = str(entry[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = is_same(item, _item)
		if is_same(item, _item):
			found = true
		var where := str(entry[2])
		b.pressed.connect(func() -> void:
			_item = item
			_where = where
			_status.text = ""
			_refresh())
		_list.add_child(b)
	if not found:
		_item = {}
	_refresh_detail()


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _item.is_empty():
		_detail.add_child(_label(tr("Escolha um equipamento."), 14, Color(0.6, 0.6, 0.55)))
		return
	var inv := player.inventory
	_detail.add_child(_label(Inventory.display_name_of(_item), 18, Color.WHITE))
	_detail.add_child(_label(tr("Ouro: %d") % inv.gold, 12, Color(1.0, 0.85, 0.4)))
	# Afixos.
	if Affixes.can_have(_item.id):
		var aff: Array = _item.get("aff", [])
		if aff.is_empty():
			aff = [null, null, null, null, null, null]
		for i in Affixes.SLOTS:
			var group := tr("Prefixo") if i < 3 else tr("Sufixo")
			var text := Affixes.describe(aff[i]) if aff[i] != null else tr("— fechado —")
			_detail.add_child(_label("%s %d: %s" % [group, (i % 3) + 1, text], 13, Color(0.75, 0.85, 1.0) if aff[i] != null else Color(0.45, 0.45, 0.45)))
		var open := Affixes.open_count(_item)
		if open < Affixes.SLOTS:
			var cost := Affixes.unlock_cost(_item)
			_action(tr("Abrir slot (%s)") % Affixes.describe_cost(cost), Affixes.can_pay(inv, cost), func() -> void:
				Affixes.pay(player.inventory, cost)
				var got := Affixes.unlock_slot(_item)
				_done(tr("Slot aberto: %s") % got))
		if open > 0:
			var cost2 := Affixes.reroll_cost(_item)
			_action(tr("Re-sortear afixos (%s)") % Affixes.describe_cost(cost2), Affixes.can_pay(inv, cost2), func() -> void:
				Affixes.pay(player.inventory, cost2)
				Affixes.reroll(_item)
				_done(tr("Afixos re-sorteados")))
	# Refino.
	if Refine.can_be_refined(_item):
		if Refine.is_maxed(_item):
			_detail.add_child(_label(tr("Refino no máximo"), 12, Color(0.6, 0.6, 0.55)))
		else:
			var text := tr("Refinar para +%d (%d× %s, %d%% de chance)") % [Inventory.refine_of(_item) + 1, Refine.cost(_item), str(GameData.get_item(Refine.stone_for(_item)).get("name", "")), roundi(Refine.chance(_item) * 100.0)]
			_action(text, Refine.can_refine(inv, _item), func() -> void:
				var result := Refine.refine(player.inventory, _item)
				_done(tr("Refino deu certo!") if result == Refine.Result.SUCCESS else tr("O refino falhou (as pedras se perderam)")))
	# Qualidade.
	if Inventory.max_durability(_item.id) > 0.0:
		var q := int(_item.get("q", 1))
		if q < Inventory.MAX_QUALITY:
			var cost3 := Affixes.quality_cost(_item)
			_action(tr("Qualidade Q%d → Q%d (%s)") % [q, q + 1, Affixes.describe_cost(cost3)], Affixes.can_pay(inv, cost3), func() -> void:
				Affixes.pay(player.inventory, cost3)
				_item["q"] = q + 1
				_done(tr("Qualidade subiu para Q%d") % (q + 1)))
		else:
			_detail.add_child(_label(tr("Qualidade máxima (Q%d)") % q, 12, Color(0.6, 0.6, 0.55)))
	# Ferramenta: próximo nível.
	for rid: String in GameData.get_all("recipes"):
		var r := GameData.get_entry("recipes", rid)
		if str(r.get("station", "")) != "upgrading_machine" or not r.get("ingredients", {}).has(str(_item.id)):
			continue
		var ok := _where == "inv" and Crafting.can_craft(inv, r)
		var label := tr("Melhorar para %s (%s)") % [GameData.get_item(str(r.result)).get("name", r.result), Crafting.describe_ingredients(r)]
		if _where != "inv":
			label += "  · " + tr("tire do slot antes")
		_action(label, ok, func() -> void:
			Crafting.take_ingredients(player.inventory, r, 1)
			Crafting.give_result(player.inventory, r, 1)
			_item = {}
			_done(tr("Ferramenta melhorada: %s") % GameData.get_item(str(r.result)).get("name", r.result)))


func _action(text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_detail.add_child(b)


func _done(message: String) -> void:
	_status.text = message
	player.inventory.changed.emit()
	player.equipment._changed()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
