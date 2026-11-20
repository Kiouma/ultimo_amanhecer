class_name ResourceOrb
extends Control
## Esfera de recurso da HUD (vida à esquerda, mana à direita), enchendo de baixo para
## cima. Mostra o valor em números, a parte reservada por auras (faixa escura em cima)
## e, na vida, o escudo de energia como um anel azul claro que sobe pelos lados.

var fill_color := Color(0.75, 0.13, 0.12)
var value := 1.0
var maximum := 1.0
## Fração reservada (0 a 1), desenhada de cima para baixo.
var reserved := 0.0
var shield := 0.0
var shield_max := 0.0

const SHIELD_COLOR := Color(0.55, 0.85, 1.0, 0.9)
const SEGMENTS := 48


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: float, m: float, res := 0.0, sh := 0.0, sh_max := 0.0) -> void:
	if v == value and m == maximum and res == reserved and sh == shield and sh_max == shield_max:
		return
	value = v
	maximum = m
	reserved = res
	shield = sh
	shield_max = sh_max
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var c := size * 0.5
	if r <= 4.0:
		return
	# Fundo e vidro.
	draw_circle(c, r + 3.0, Color(0.05, 0.05, 0.06, 0.85))
	draw_circle(c, r, Color(0.1, 0.1, 0.12, 0.9))
	var f := clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	_draw_segment(c, r, f, false, fill_color)
	# Brilho da superfície do líquido.
	if f > 0.02 and f < 0.98:
		var y := c.y + r - 2.0 * r * f
		var half := sqrt(maxf(r * r - (y - c.y) * (y - c.y), 0.0))
		draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), fill_color.lightened(0.45), 2.0, true)
	if reserved > 0.005:
		_draw_segment(c, r, clampf(reserved, 0.0, 1.0), true, Color(0.18, 0.18, 0.2, 0.92))
	# Reflexo.
	draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.18, Color(1, 1, 1, 0.08))
	draw_arc(c, r, 0, TAU, SEGMENTS, Color(0.55, 0.5, 0.4, 0.9), 2.0, true)
	# Escudo de energia: anel azul claro subindo pelos dois lados a partir de baixo.
	if shield_max > 0.0 and shield > 0.0:
		var a := PI * clampf(shield / shield_max, 0.0, 1.0)
		draw_arc(c, r + 3.5, PI * 0.5 - a, PI * 0.5 + a, SEGMENTS, SHIELD_COLOR, 4.0, true)
	# Números.
	var font := get_theme_default_font()
	var font_size := clampi(int(r * 0.32), 10, 20)
	_text(font, c + Vector2(0, font_size * 0.35), "%d / %d" % [ceili(value), ceili(maximum)], font_size, Color.WHITE)
	if shield_max > 0.0:
		_text(font, c + Vector2(0, font_size * 1.45), "%d" % ceili(shield), maxi(font_size - 3, 9), SHIELD_COLOR)


## Segmento do círculo cheio até a fração f (de baixo, ou de cima se from_top).
func _draw_segment(c: Vector2, r: float, f: float, from_top: bool, color: Color) -> void:
	if f <= 0.003:
		return
	if f >= 0.997:
		draw_circle(c, r, color)
		return
	var level := r - 2.0 * r * f  # y do nível em relação ao centro (de baixo)
	var a1 := asin(clampf(level / r, -1.0, 1.0))
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var a := lerpf(a1, PI - a1, float(i) / SEGMENTS)
		var p := Vector2(cos(a), sin(a)) * r
		if from_top:
			p.y = -p.y
		points.append(c + p)
	draw_colored_polygon(points, color)


func _text(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := at - Vector2(w * 0.5, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
