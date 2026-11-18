extends Node
## Configurações do jogador (autoload "Settings"), salvas em user://settings.cfg:
## idioma, sensibilidade do mouse, volume e o modo do Shift (correr) e do Ctrl (agachar):
## segurar ou alternar.
##
## Idiomas: o texto-fonte do jogo é o português. As traduções ficam em
## data/i18n/<código>.json ({"texto em português": "tradução"}) e viram objetos
## Translation na hora. Rótulos e botões traduzem sozinhos (auto_translate do Godot);
## textos montados no código usam tr(); nomes e descrições dos dados, GameData.retranslate().

signal changed

const PATH := "user://settings.cfg"
const I18N_DIR := "res://data/i18n"
## [código do Godot, nome no próprio idioma, bandeira (FlagIcons)].
const LANGUAGES := [
	["pt_BR", "Português", "br"],
	["en", "English", "us"],
	["zh_CN", "简体中文", "cn"],
	["ru", "Русский", "ru"],
]

var language := "pt_BR"
var mouse_sensitivity := 0.0025
var volume := 0.8
## true = Shift liga/desliga a corrida; false = corre enquanto segura.
var sprint_toggle := false
## true = Ctrl liga/desliga o agachar; false = agacha enquanto segura.
var crouch_toggle := true
## Minimapa no canto superior direito.
var show_minimap := true


func _ready() -> void:
	_load_translations()
	var cfg := ConfigFile.new()
	var first_run := cfg.load(PATH) != OK
	language = str(cfg.get_value("general", "language", _default_language() if first_run else "pt_BR"))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	sprint_toggle = bool(cfg.get_value("controls", "sprint_toggle", sprint_toggle))
	crouch_toggle = bool(cfg.get_value("controls", "crouch_toggle", crouch_toggle))
	show_minimap = bool(cfg.get_value("interface", "show_minimap", show_minimap))
	volume = float(cfg.get_value("audio", "volume", volume))
	Sfx.volume = volume
	_apply_language()


func set_language(code: String) -> void:
	if code == language:
		return
	language = code
	_apply_language()
	save()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	if key == "volume":
		Sfx.volume = float(value)
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("general", "language", language)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "sprint_toggle", sprint_toggle)
	cfg.set_value("controls", "crouch_toggle", crouch_toggle)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("interface", "show_minimap", show_minimap)
	cfg.save(PATH)
	changed.emit()


func language_index() -> int:
	for i in LANGUAGES.size():
		if LANGUAGES[i][0] == language:
			return i
	return 0


func _apply_language() -> void:
	TranslationServer.set_locale(language)
	GameData.retranslate()
	changed.emit()


## Primeira vez: usa o idioma do sistema, se for um dos suportados.
func _default_language() -> String:
	var sys := OS.get_locale()
	for lang: Array in LANGUAGES:
		if sys == lang[0] or sys.get_slice("_", 0) == str(lang[0]).get_slice("_", 0):
			return lang[0]
	return "pt_BR"


func _load_translations() -> void:
	for lang: Array in LANGUAGES:
		var code: String = lang[0]
		var path := I18N_DIR.path_join(code + ".json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("Settings: tradução inválida em %s" % path)
			continue
		var t := Translation.new()
		t.locale = code
		for src: String in parsed:
			if str(parsed[src]) != "":
				t.add_message(src, str(parsed[src]))
		TranslationServer.add_translation(t)
