extends Node
## Banco de dados do jogo (autoload "GameData").
## Carrega itens, receitas, zumbis, feitiços etc. dos arquivos JSON em res://data.
## Regra do GDD (16.2): conteúdo fica em arquivos de dados, não no código.
##
## Cada arquivo .json de uma categoria contém uma lista de objetos com "id".
## Uso: GameData.get_entry("items", "machado_de_pedra")

const DATA_ROOT := "res://data"
const CATEGORIES: Array[String] = [
	"items", "recipes", "zombies", "skills", "proficiencies", "backgrounds", "nodes", "buildings", "passives", "ascendancies", "auras", "effects", "loot", "sets", "affixes",
]

var _db: Dictionary = {}
## Textos originais (português) dos campos traduzíveis: "categoria/id/campo" -> texto.
var _sources: Dictionary = {}
## Campos de texto mostrados ao jogador (traduzidos no lugar ao trocar de idioma).
const TRANSLATED_FIELDS := ["name", "desc", "summary", "raised_by", "style", "verb"]


func _ready() -> void:
	reload()


func reload() -> void:
	_db.clear()
	_sources.clear()
	for category in CATEGORIES:
		_db[category] = _load_category(category)
	retranslate()


## Troca os textos dos dados (nomes, descrições...) para o idioma atual. Chamado pelo
## Settings ao mudar de idioma. O original em português fica guardado em _sources.
func retranslate() -> void:
	for category: String in _db:
		for id: String in _db[category]:
			var entry: Dictionary = _db[category][id]
			for field: String in TRANSLATED_FIELDS:
				if not entry.has(field):
					continue
				var key := "%s/%s/%s" % [category, id, field]
				if not _sources.has(key):
					_sources[key] = entry[field].duplicate() if entry[field] is Dictionary else entry[field]
				var source: Variant = _sources[key]
				if source is String:
					entry[field] = tr(source)
				elif source is Dictionary:
					var out := {}
					for k: String in source:
						out[k] = tr(str(source[k])) if source[k] is String else source[k]
					entry[field] = out


func get_entry(category: String, id: String) -> Dictionary:
	return _db.get(category, {}).get(id, {})


func get_all(category: String) -> Dictionary:
	return _db.get(category, {})


## Qualquer coisa que pode ocupar um slot de inventário (items/*.json). Retorna {} se o
## id não existir.
func get_item(id: String) -> Dictionary:
	return get_entry("items", id)


## Quantos cabem num slot (campo "stack"; armas e ferramentas = 1).
func max_stack(id: String) -> int:
	return maxi(int(get_item(id).get("stack", 1)), 1)


func _load_category(category: String) -> Dictionary:
	var entries := {}
	var dir_path := DATA_ROOT.path_join(category)
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.get_extension() != "json":
			continue
		var path := dir_path.path_join(file_name)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_ARRAY:
			push_error("GameData: %s deve conter uma lista de objetos JSON." % path)
			continue
		for entry: Variant in parsed:
			if entry is Dictionary and entry.has("id"):
				if entries.has(entry["id"]):
					push_warning("GameData: id duplicado '%s' em %s." % [entry["id"], path])
				entries[entry["id"]] = entry
			else:
				push_error("GameData: entrada sem 'id' em %s." % path)
	return entries
