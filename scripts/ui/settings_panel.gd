class_name SettingsPanel
extends VBoxContainer
## Tela de configurações (menu principal e Esc > Configurações): idioma (com bandeira),
## sensibilidade do mouse, volume e o modo do Shift/Ctrl (segurar ou alternar).
## Tudo vai direto para o autoload Settings, que salva e avisa quem precisa.

signal closed

var _language: OptionButton
var _sensitivity: HSlider
var _volume: HSlider
var _sprint: OptionButton
var _crouch: OptionButton
var _minimap: CheckButton


func _ready() -> void:
	custom_minimum_size = Vector2(380, 0)
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Configurações"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	_label("Idioma")
	_language = OptionButton.new()
	_language.expand_icon = false
	for i in Settings.LANGUAGES.size():
		var lang: Array = Settings.LANGUAGES[i]
		_language.add_icon_item(FlagIcons.texture(lang[2]), lang[1], i)
	_language.item_selected.connect(func(index: int) -> void:
		Settings.set_language(str(Settings.LANGUAGES[index][0])))
	add_child(_language)

	_label("Sensibilidade do mouse")
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.0005
	_sensitivity.max_value = 0.006
	_sensitivity.step = 0.0001
	_sensitivity.value_changed.connect(func(v: float) -> void: Settings.set_value("mouse_sensitivity", v))
	add_child(_sensitivity)

	_label("Volume")
	_volume = HSlider.new()
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.value_changed.connect(func(v: float) -> void: Settings.set_value("volume", v))
	add_child(_volume)

	_label("Correr (Shift)")
	_sprint = _mode_picker(func(index: int) -> void: Settings.set_value("sprint_toggle", index == 1))
	_label("Agachar (Ctrl)")
	_crouch = _mode_picker(func(index: int) -> void: Settings.set_value("crouch_toggle", index == 1))

	_minimap = CheckButton.new()
	_minimap.text = "Mostrar minimapa"
	_minimap.toggled.connect(func(on: bool) -> void: Settings.set_value("show_minimap", on))
	add_child(_minimap)

	var back := Button.new()
	back.text = "Voltar"
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(closed.emit)
	add_child(back)
	visibility_changed.connect(_sync)
	_sync()


## Mostra os valores atuais (sem disparar os sinais).
func _sync() -> void:
	if not is_visible_in_tree() and is_inside_tree():
		return
	_language.select(Settings.language_index())
	_sensitivity.set_value_no_signal(Settings.mouse_sensitivity)
	_volume.set_value_no_signal(Settings.volume)
	_sprint.select(1 if Settings.sprint_toggle else 0)
	_crouch.select(1 if Settings.crouch_toggle else 0)
	_minimap.set_pressed_no_signal(Settings.show_minimap)


func _label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.8, 0.82, 0.78))
	add_child(l)


func _mode_picker(on_select: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("Segurar", 0)
	picker.add_item("Alternar (aperta liga, aperta de novo desliga)", 1)
	picker.item_selected.connect(on_select)
	add_child(picker)
	return picker
