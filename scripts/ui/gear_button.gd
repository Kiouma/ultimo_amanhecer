class_name GearButton
extends Control
## Botão pequeno de engrenagem (desenhado, sem depender de ícone na fonte). Ao lado da
## hotbar: abre o editor da HUD. Clicável com o mouse livre (Alt).

signal pressed

var _hover := false


func _ready() -> void:
	custom_minimum_size = Vector2(26, 26)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Editar HUD (posição, tamanho, esferas ou arcos)"
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var color := Color(0.95, 0.88, 0.65) if _hover else Color(0.75, 0.72, 0.62)
	draw_circle(c, r + 1.5, Color(0.08, 0.08, 0.09, 0.85))
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * r * 0.45, c + dir * r * 0.95, color, 3.5)
	draw_circle(c, r * 0.62, color)
	draw_circle(c, r * 0.28, Color(0.08, 0.08, 0.09))
