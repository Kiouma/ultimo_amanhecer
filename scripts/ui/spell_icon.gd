class_name SpellIcon
extends Control
## Ícone da última habilidade (Q), à esquerda da hotbar: cor da escola, sigla,
## nível e recarga escurecendo por cima.

var player: Player


static func school_color(spell_id: String) -> Color:
	match str(GameData.get_item(spell_id).get("school", "")):
		"fire": return Color(1.0, 0.45, 0.1)
		"ice": return Color(0.5, 0.8, 1.0)
		"lightning": return Color(0.8, 0.8, 1.0)
		"life": return Color(0.4, 1.0, 0.5)
		"earth": return Color(0.75, 0.55, 0.3)
	return Color(0.9, 0.6, 1.0)


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var font := get_theme_default_font()
	var id := player.progression.last_spell
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12, 0.85))
	if id == "":
		draw_string(font, Vector2(6, 38), "sem\nmagia", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		return
	var color := school_color(id)
	draw_circle(c, 22.0, Color(color, 0.85))
	var spell_name := str(GameData.get_item(id).get("name", id))
	var initials := ""
	for word in spell_name.split(" "):
		if word.length() > 2:
			initials += word.left(1).to_upper()
	draw_string(font, c + Vector2(-9.0 * initials.length() * 0.5 - 2, 6), initials.left(2), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	# Recarga.
	var caster: SpellCaster = player.weapons.caster_for(id) if player.weapons else null
	if caster and caster.cooldown > 0.0:
		var total := maxf(caster.stat("cooldown", 1.0) + caster.stat("cast_time", 0.4), 0.1)
		var frac := clampf(caster.cooldown / total, 0.0, 1.0)
		draw_rect(Rect2(0, size.y * (1.0 - frac), size.x, size.y * frac), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(3, 13), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.5))
	draw_string(font, Vector2(size.x - 26, size.y - 4), "Nv%d" % int(player.progression.spells.get(id, 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
