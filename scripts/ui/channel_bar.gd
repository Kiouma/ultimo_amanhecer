class_name ChannelBar
extends Control
## Barra de carga logo acima da hotbar: puxada do arco, golpe carregado, canalização
## do cajado e força do arremesso. A arma na mão diz quanto (channel_fraction, 0 a 1;
## -1 = escondida) e o texto (channel_label).

const WIDTH := 260.0

var player: Player


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 26)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 104)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player) or player.weapons == null:
		return
	var weapon := player.weapons.current()
	if weapon == null or not weapon.has_method(&"channel_fraction"):
		return
	var f: float = weapon.channel_fraction()
	if f < 0.0:
		return
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 11), str(weapon.channel_label()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(0, 14, WIDTH, 10), Color(0, 0, 0, 0.6))
	var color := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.35, 0.2), f)
	draw_rect(Rect2(1, 15, (WIDTH - 2) * f, 8), color)
	if f >= 0.999:
		draw_rect(Rect2(0, 14, WIDTH, 10), Color.WHITE, false, 1.5)
