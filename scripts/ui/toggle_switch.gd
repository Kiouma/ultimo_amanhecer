class_name ToggleSwitch
extends Control
## Interruptor com bolinha (estilo celular): trilho verde e bolinha à direita quando
## ligado, trilho vermelho e bolinha à esquerda quando desligado, com o texto ao lado.
## Clicar emite `toggled_by_user`; quem usa decide se muda (on = ...).

signal toggled_by_user

const TRACK := Vector2(54, 26)
const ON_COLOR := Color(0.25, 0.72, 0.35)
const OFF_COLOR := Color(0.78, 0.25, 0.25)

var on := false:
	set(value):
		on = value
		queue_redraw()
var on_text := "Ativado"
var off_text := "Desativado"
var disabled := false:
	set(value):
		disabled = value
		mouse_default_cursor_shape = Control.CURSOR_ARROW if value else Control.CURSOR_POINTING_HAND
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(TRACK.x + 120, TRACK.y + 4)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggled_by_user.emit()
		accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	var text := tr(on_text) if on else tr(off_text)
	var font_size := 16
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var total := TRACK.x + 10.0 + text_w
	var x0 := (size.x - total) * 0.5
	var y0 := (size.y - TRACK.y) * 0.5
	var color := ON_COLOR if on else OFF_COLOR
	if disabled:
		color = Color(0.35, 0.35, 0.37)
	var r := TRACK.y * 0.5
	# Trilho arredondado: retângulo + dois semicírculos.
	draw_rect(Rect2(x0 + r, y0, TRACK.x - TRACK.y, TRACK.y), color)
	draw_circle(Vector2(x0 + r, y0 + r), r, color)
	draw_circle(Vector2(x0 + TRACK.x - r, y0 + r), r, color)
	# Bolinha.
	var knob_x := x0 + TRACK.x - r if on else x0 + r
	draw_circle(Vector2(knob_x, y0 + r), r - 3.0, Color(0.96, 0.96, 0.94) if not disabled else Color(0.6, 0.6, 0.6))
	var text_color := color.lightened(0.35) if not disabled else Color(0.55, 0.55, 0.55)
	draw_string(font, Vector2(x0 + TRACK.x + 10.0, y0 + r + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
