extends Node
## Banco de dados do jogo (autoload "GameData").
## Carrega itens, receitas, zumbis, feitiços etc. dos arquivos JSON em res://data.
## Regra do GDD (16.2): conteúdo fica em arquivos de dados, não no código.
##
## Cada arquivo .json de uma categoria contém uma lista de objetos com "id".
## Uso: GameData.get_entry("items", "machado_de_pedra")

const DATA_ROOT := "res://data"
const CATEGORIES: Array[String] = [
	"items", "recipes", "zombies", "spells", "proficiencies", "backgrounds", "nodes", "buildings", "skills",
]

var _db: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_db.clear()
	for category in CATEGORIES:
		_db[category] = _load_category(category)


func get_entry(category: String, id: String) -> Dictionary:
	return _db.get(category, {}).get(id, {})


func get_all(category: String) -> Dictionary:
	return _db.get(category, {})


## Qualquer coisa que pode ocupar um slot de inventário: itens de items/*.json ou
## feitiços de spells/*.json (feitiço vira um "item" sem peso, do tipo "spell").
## Retorna {} se o id não existir.
func get_item(id: String) -> Dictionary:
	var item := get_entry("items", id)
	if not item.is_empty():
		return item
	var spell := get_entry("spells", id)
	if not spell.is_empty():
		var as_item := spell.duplicate()
		as_item["type"] = "spell"
		as_item["weight"] = 0.0
		return as_item
	return {}


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
