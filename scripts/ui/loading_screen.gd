class_name LoadingScreen
extends CanvasLayer
## Tela de carregamento ao entrar num mundo: cobre tudo enquanto o terreno, os recursos e
## a navegação em volta de onde você vai aparecer ficam prontos (pré-carregamento). Barra
## de progresso, o que está acontecendo e uma dica.

const TIPS := [
	"Dica: pedras soltas e galhos perto do começo dão para o machado e a picareta de pedra.",
	"Dica: à noite os monstros ficam mais ferozes; uma fogueira e uma tocha ajudam.",
	"Dica: clique duplo num equipamento para vestir; numa arma, para pôr na mão.",
	"Dica: interaja com a bancada para ver só as receitas dela.",
	"Dica: a roda do mouse dá zoom no mapa (M); o botão direito marca um ponto.",
	"Dica: cada vocação tem um conjunto inicial feito na bancada com drops de monstros.",
	"Dica: água do lago é suja; ferva na fogueira antes de beber.",
]

var _bar: ProgressBar
var _status: Label
var _tip: Label


func _init() -> void:
	layer = 50
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # nada atrás recebe clique
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Último Amanhecer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.66))
	box.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.8, 0.82, 0.78))
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.max_value = 1.0
	_bar.show_percentage = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.65, 0.35)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.16, 0.16)
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 13)
	_tip.add_theme_color_override("font_color", Color(0.6, 0.62, 0.58))
	box.add_child(_tip)


func open(status: String) -> void:
	_status.text = status
	_bar.value = 0.0
	_tip.text = tr(TIPS[randi() % TIPS.size()])
	visible = true


func set_progress(value: float, status := "") -> void:
	_bar.value = maxf(_bar.value, clampf(value, 0.0, 1.0))  # nunca volta
	if status != "":
		_status.text = status


func close() -> void:
	visible = false
