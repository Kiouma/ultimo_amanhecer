class_name ResourceArc
extends Control
## Barra em arco perto da mira: "(" à esquerda (side = -1) ou ")" à direita (side = 1),
## enchendo de baixo para cima. Usada pela stamina (sempre) e, se o jogador escolher,
## pela vida e pela mana no lugar das esferas. Ocupa a tela toda (centro = mira).

var side := -1
var radius := 46.0
var thickness := 5.0
## Abertura do arco, em graus.
var span := 90.0
var fill_color := Color(0.9, 0.78, 0.25)
var value := 1.0
var maximum := 1.0
var reserved := 0.0
var shield := 0.0
var shield_max := 0.0
## Some devagar quando fica cheio por um tempo (stamina).
var fade_when_full := false
var show_number := true

var _full_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_values(v: float, m: float, res := 0.0, sh := 0.0, sh_max := 0.0) -> void:
	value = v
	maximum = m
	reserved = res
	shield = sh
	shield_max = sh_max
	queue_redraw()


func _process(delta: float) -> void:
	if not fade_when_full:
		modulate.a = 1.0
		return
	if value >= maximum - 0.01:
		_full_time += delta
	else:
		_full_time = 0.0
	var target := 0.0 if _full_time > 1.5 else 1.0
	modulate.a = move_toward(modulate.a, target, delta * 3.0)


## Ângulo (rad) do ponto a uma fração t do arco, de baixo (0) para cima (1).
func _angle(t: float) -> float:
	var half := deg_to_rad(span) * 0.5
	if side < 0:
		return PI - half + 2.0 * half * t  # de baixo-esquerda subindo
	return half - 2.0 * half * t  # de baixo-direita subindo


func _draw() -> void:
	var c := size * 0.5
	var f := clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	var steps := 32
	draw_arc(c, radius, _angle(0.0), _angle(1.0), steps, Color(0.05, 0.05, 0.06, 0.55), thickness + 2.0, true)
	if f > 0.0:
		draw_arc(c, radius, _angle(0.0), _angle(f), steps, fill_color, thickness, true)
	if reserved > 0.005:
		draw_arc(c, radius, _angle(1.0 - clampf(reserved, 0.0, 1.0)), _angle(1.0), steps, Color(0.25, 0.25, 0.28, 0.9), thickness, true)
	if shield_max > 0.0 and shield > 0.0:
		var s := clampf(shield / shield_max, 0.0, 1.0)
		draw_arc(c, radius + thickness + 1.5, _angle(0.0), _angle(s), steps, ResourceOrb.SHIELD_COLOR, 2.5, true)
	if show_number:
		var font := get_theme_default_font()
		var text := "%d" % ceili(value)
		var bottom := c + Vector2(cos(_angle(0.0)), sin(_angle(0.0))) * radius
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var at := bottom + Vector2(-w - 4.0 if side < 0 else 4.0, 12.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, fill_color.lightened(0.3))
