class_name SkillBar
extends HBoxContainer
## Barra de habilidades da HUD (etapa 6): 5 slots, teclas 1 a 5. Mostra a habilidade
## (iniciais na cor da escola), o nível, a recarga (escurece de cima para baixo e conta
## os segundos) e o custo. Clicável com o mouse: usa a habilidade. A tela de
## Habilidades (K) escolhe o que vai em cada slot.

const SLOT_SIZE := Vector2(56, 56)

var player: Player
var _slots: Array[SkillSlot] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p: Player) -> void:
	player = p
	for i in Skills.BAR_SIZE:
		var slot := SkillSlot.new()
		slot.bar = self
		slot.index = i
		slot.custom_minimum_size = SLOT_SIZE
		add_child(slot)
		_slots.append(slot)
	player.skills.changed.connect(refresh)
	refresh()


func refresh() -> void:
	for slot in _slots:
		slot.queue_redraw()
		slot.update_tooltip()


func _process(_delta: float) -> void:
	for slot in _slots:
		slot.queue_redraw()


## Texto de dica de uma habilidade (barra e tela de Habilidades).
static func skill_tooltip(skills: Skills, id: String) -> String:
	var d := Skills.data(id)
	if d.is_empty():
		return ""
	var level := skills.level_of(id)
	var lines: PackedStringArray = ["%s (%s)" % [TranslationServer.translate(str(d.get("name", id))), TranslationServer.translate("Nível %d") % level if level > 0 else TranslationServer.translate("bloqueada")]]
	lines.append(TranslationServer.translate(str(d.get("desc", ""))))
	var c := skills.caster(id) if level > 0 else null
	var cost := c.stat("cost", 0.0) if c else float(d.get("cost", 0.0))
	var cd := c.stat("cooldown", 0.0) if c else float(d.get("cooldown", 0.0))
	lines.append(TranslationServer.translate("Custo: %d de %s · recarga %.1f s") % [roundi(cost), TranslationServer.translate("mana") if str(d.get("cost_type", "")) == "mana" else TranslationServer.translate("stamina"), cd])
	var marks: Dictionary = d.get("milestone_text", {})
	for m: int in Skills.MILESTONES:
		var text := str(marks.get(str(m), ""))
		if text != "":
			lines.append(("✔ " if level >= m else "· ") + TranslationServer.translate("Nível %d: %s") % [m, text])
	return "\n".join(lines)


## Um slot da barra.
class SkillSlot extends Control:
	var bar: SkillBar
	var index := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func skill_id() -> String:
		return str(bar.player.skills.bar[index]) if bar and bar.player else ""

	func update_tooltip() -> void:
		var id := skill_id()
		tooltip_text = SkillBar.skill_tooltip(bar.player.skills, id) if id != "" else tr("Slot vazio: escolha uma habilidade na tela Habilidades (K)")

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bar.player.skills.use_slot(index)
			accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var id := skill_id()
		var font := get_theme_default_font()
		draw_rect(rect, Color(0.08, 0.08, 0.09, 0.85))
		if id == "":
			draw_rect(rect, Color(0.35, 0.35, 0.35), false, 2.0)
		else:
			var skills := bar.player.skills
			var d := Skills.data(id)
			var c := skills.caster(id)
			var col := c.color() if c else Color.WHITE
			draw_rect(rect.grow(-3), Color(col.darkened(0.55), 0.95))
			draw_rect(rect, col.lightened(0.2), false, 2.0)
			var initials := ""
			for word: String in tr(str(d.get("name", id))).split(" ", false):
				if word.length() > 2:
					initials += word.left(1).to_upper()
			var on_cooldown := c != null and c.cooldown > 0.0
			if not on_cooldown:
				draw_string(font, Vector2(0, size.y * 0.5 + 8), initials.left(2), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.95))
			draw_string(font, Vector2(size.x - 12, size.y - 4), str(skills.level_of(id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.6))
			# Recarga: escurece a parte que falta e mostra os segundos no lugar das iniciais.
			if on_cooldown:
				var frac := clampf(c.cooldown / maxf(c.stat("cooldown", 1.0), 0.01), 0.0, 1.0)
				draw_rect(Rect2(0, 0, size.x, size.y * frac), Color(0, 0, 0, 0.6))
				draw_string(font, Vector2(0, size.y * 0.5 + 7), "%.1f" % c.cooldown if c.cooldown < 10.0 else "%d" % ceili(c.cooldown), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)
			elif c and c.block_reason() != "" and not c.casting:
				draw_rect(rect, Color(0.3, 0.0, 0.0, 0.35))  # sem mana/stamina, sem arco...
			if skills.is_aiming() and skills._aiming == id:
				draw_rect(rect.grow(2), Color(1.0, 0.85, 0.3), false, 3.0)
		draw_string(font, Vector2(4, 13), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.8))
