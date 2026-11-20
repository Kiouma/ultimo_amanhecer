extends Node
## Salvamento (GDD 17), autoload "SaveGame". Vários personagens e vários mundos:
## - Mundos (user://worlds/<id>.json), salvos pelo host: nome, semente, dia/hora, clima,
##   construções, estações, armadilhas e itens/bags no chão. Recursos e zumbis voltam
##   pela semente e pela população.
## - Personagens (user://characters/<id>.json), salvos por cada jogador na própria
##   máquina: nome, passado, inventário, equipamento, níveis, habilidades, auras...
##   O mesmo personagem entra em qualquer mundo (inclusive no de um amigo); a posição
##   é guardada por mundo (semente).
## O menu escolhe o mundo (current_world_id, só solo/host) e o personagem
## (current_character_id) antes de começar. Salva sozinho a cada AUTOSAVE_SECONDS, ao
## fechar a janela e pelo menu de pausa.
##
## Saves da versão antiga (user://save/world.json e character.json) viram "Mundo 1" e
## "Personagem 1" na primeira vez.

const VERSION := 2
const AUTOSAVE_SECONDS := 120.0

## Pasta raiz dos saves (testes: --save-root=user://test_saves).
var root := "user://"
var current_world_id := ""
var current_character_id := ""

var _timer := AUTOSAVE_SECONDS


func _ready() -> void:
	get_tree().auto_accept_quit = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-root="):
			root = arg.get_slice("=", 1).trim_suffix("/") + "/"
	_migrate_legacy()
	EventBus.player_spawned.connect(_on_player_spawned)


## Personagem local saindo do mundo (host caiu, conexão perdida, voltou ao menu): salva
## na hora, para quem joga no mundo de um amigo não perder o que fez desde o último save.
func _on_player_spawned(p: Node) -> void:
	if p is Player and p.is_multiplayer_authority():
		p.tree_exiting.connect(func() -> void: _save_character_of(p))


func _save_character_of(p: Player) -> void:
	var level := _world()
	if level == null or current_character_id == "" or not p.is_inside_tree() or p.progression == null:
		return
	_write(_character_path(current_character_id), _capture_character(p, level, _read(_character_path(current_character_id))))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_all()
		get_tree().quit()


func _process(delta: float) -> void:
	if _world() == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = AUTOSAVE_SECONDS
		save_all()


func characters_dir() -> String:
	return root + "characters"


func worlds_dir() -> String:
	return root + "worlds"


func _character_path(id: String) -> String:
	return characters_dir().path_join(id + ".json")


func _world_path(id: String) -> String:
	return worlds_dir().path_join(id + ".json")


# --- Listas, criar e excluir (menu) ---------------------------------------------------

## Personagens: [{id, name, background, level, updated}], o mais recente primeiro.
func list_characters() -> Array:
	var out: Array = []
	for id in _ids_in(characters_dir()):
		var data := _read(_character_path(id))
		if data.is_empty():
			continue
		out.append({"id": id, "name": str(data.get("name", id)), "background": str(data.get("background", "survivor")),
			"level": int(data.get("progression", {}).get("char_level", 1)), "updated": int(data.get("updated", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated) > int(b.updated))
	return out


## Mundos: [{id, name, day, updated}], o mais recente primeiro.
func list_worlds() -> Array:
	var out: Array = []
	for id in _ids_in(worlds_dir()):
		var data := _read(_world_path(id))
		if data.is_empty():
			continue
		out.append({"id": id, "name": str(data.get("name", id)), "day": int(data.get("day", 1)),
			"started": int(data.get("seed", 0)) != 0, "updated": int(data.get("updated", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated) > int(b.updated))
	return out


func create_character(char_name: String, background: String) -> String:
	var id := _new_id("char")
	_write(_character_path(id), {"version": VERSION, "name": char_name.strip_edges().left(24), "background": background,
		"updated": int(Time.get_unix_time_from_system())})
	return id


func create_world(world_name: String) -> String:
	var id := _new_id("world")
	_write(_world_path(id), {"version": VERSION, "name": world_name.strip_edges().left(32), "seed": 0,
		"updated": int(Time.get_unix_time_from_system())})
	return id


func delete_character(id: String) -> void:
	DirAccess.remove_absolute(_character_path(id))
	if current_character_id == id:
		current_character_id = ""


func delete_world(id: String) -> void:
	DirAccess.remove_absolute(_world_path(id))
	if current_world_id == id:
		current_world_id = ""


func character_name() -> String:
	return str(_read(_character_path(current_character_id)).get("name", "")) if current_character_id != "" else ""


func character_background() -> String:
	return str(_read(_character_path(current_character_id)).get("background", "survivor")) if current_character_id != "" else "survivor"


func world_name() -> String:
	return str(_read(_world_path(current_world_id)).get("name", "")) if current_world_id != "" else ""


## Salva o que esta máquina pode: o mundo (se for o servidor) e o personagem local.
func save_all() -> void:
	var level := _world()
	if level == null:
		return
	if multiplayer.is_server() and current_world_id != "":
		var data := _capture_world(level)
		var old := _read(_world_path(current_world_id))
		data.name = str(old.get("name", tr("Mundo")))
		_write(_world_path(current_world_id), data)
	var me := _local_player()
	if me and current_character_id != "":
		var old := _read(_character_path(current_character_id))
		_write(_character_path(current_character_id), _capture_character(me, level, old))


# --- Mundo ------------------------------------------------------------------------------

## Regiões cujos lugares já foram montados (para não montar de novo ao voltar).
func saved_regions() -> Dictionary:
	var out := {}
	for key: Variant in _read(_world_path(current_world_id)).get("built_regions", []):
		out[str(key)] = true
	return out


## Semente do mundo escolhido (0 = mundo novo, ainda sem semente).
func saved_seed() -> int:
	return int(_read(_world_path(current_world_id)).get("seed", 0)) if current_world_id != "" else 0


func _capture_world(level: Node) -> Dictionary:
	var data := {"version": VERSION, "seed": int(level.get("world_seed")) if "world_seed" in level else 0,
		"updated": int(Time.get_unix_time_from_system())}
	if "built_regions" in level:
		data.built_regions = (level.built_regions as Dictionary).keys()
	data.gen = 2  # mundo infinito com relevo
	var dn := DayNight.find(get_tree())
	if dn:
		data.day = dn.day
		data.hour = dn.hour
	var weather := Weather.find(get_tree())
	if weather:
		data.weather = weather.state
	var pieces: Array = []
	for piece in Structures.pieces():
		if piece.piece_id == "earth_wall":
			continue  # temporário
		pieces.append({"id": piece.piece_id, "tier": piece.tier, "slot": piece.slot_key, "rot": piece.rot,
			"hp": piece.health.current, "open": piece.open})
	data.pieces = pieces
	var placed: Array = []
	for s in level.get_node("Structures").get_children():
		if s is BaseUtility:
			placed.append({"id": s.item_id, "pos": _v(s.global_position), "rot": s.rotation.y, "dur": -1.0,
				"contents": s.contents})
		elif s is CraftingStation:
			placed.append({"id": s.item_id, "pos": _v(s.global_position), "rot": s.rotation.y, "dur": -1.0})
		elif s is Trap:
			placed.append({"id": s.item_id, "pos": _v(s.global_position), "rot": s.rotation.y, "dur": s.uses})
	data.placed = placed
	var items: Array = []
	for it in level.get_node("Items").get_children():
		if it.is_queued_for_deletion():
			continue
		if it is DeathBag:
			items.append({"bag": true, "contents": it.contents, "owner": it.owner_name, "pos": _v(it.global_position)})
		else:
			items.append({"id": it.item_id, "count": it.count, "extra": it.extra, "pos": _v(it.global_position)})
	data.items = items
	return data


## Servidor, depois que o nível montou: recoloca o que foi salvo.
func apply_world(level: Node) -> void:
	var data := _read(_world_path(current_world_id))
	if data.is_empty() or int(data.get("seed", 0)) == 0:
		return
	var dn := DayNight.find(get_tree())
	if dn:
		dn.day = int(data.get("day", 1))
		dn.hour = float(data.get("hour", 8.0))
		dn._was_night = dn.is_night()
		dn._advance(0.0)
	var weather := Weather.find(get_tree())
	if weather and data.has("weather"):
		weather.set_state(str(data.weather))
	for p: Dictionary in data.get("pieces", []):
		Structures._spawn_piece(str(p.id), str(p.tier), str(p.slot), int(p.rot))
		var piece := Structures.piece_at(str(p.slot))
		if piece:
			piece.health._set_state(minf(float(p.get("hp", piece.health.max_health)), piece.health.max_health), false, 0.0, null)
			if p.get("open", false):
				piece._set_open(true)
	for s: Dictionary in data.get("placed", []):
		if GameData.get_item(str(s.get("id", ""))).is_empty():
			continue
		var node := Structures._spawn(str(s.id), _vec(s.pos), float(s.rot), float(s.get("dur", -1.0)))
		if node is BaseUtility:
			node.contents.append_array(_valid_stacks(s.get("contents", [])))
	for it: Dictionary in data.get("items", []):
		if it.get("bag", false):
			WorldItems.drop_bag(_valid_stacks(it.get("contents", [])), _vec(it.pos), str(it.owner))
		elif not GameData.get_item(str(it.get("id", ""))).is_empty():
			WorldItems.spawn(str(it.id), int(it.count), _vec(it.pos) + Vector3.UP * 0.3, 0, it.get("extra", {}))


## Pilhas de itens que ainda existem no jogo (itens removidos, como armas de fogo, somem).
static func _valid_stacks(stacks: Array) -> Array:
	var out: Array = []
	for stack: Variant in stacks:
		if stack is Dictionary and not GameData.get_item(str(stack.get("id", ""))).is_empty():
			stack.count = int(stack.get("count", 1))
			out.append(stack)
	return out


# --- Personagem -----------------------------------------------------------------------

func _capture_character(p: Player, level: Node, old: Dictionary) -> Dictionary:
	var prog := p.progression
	var seed_key := str(int(level.get("world_seed")) if "world_seed" in level else 0)
	var positions: Dictionary = old.get("positions", {})
	positions[seed_key] = {"pos": _v(p.global_position), "rot": p.rotation.y, "bed": _v(p._spawn_point) if p.has_bed else []}
	return {
		"version": VERSION, "name": str(old.get("name", tr("Sobrevivente"))), "background": str(old.get("background", "survivor")),
		"updated": int(Time.get_unix_time_from_system()),
		"positions": positions,
		"creative": p.creative,
		"inventory": p.inventory.slots,
		"equipment": p.equipment.to_save(),
		"exploration": (p.get_node(^"Exploration") as Exploration).to_save() if p.has_node(^"Exploration") else {},
		"health": p.health.current,
		"weakness": {"level": p.death_penalty.level, "time_left": p.death_penalty.time_left},
		"progression": {"levels": prog.levels, "xp": prog.xp, "char_level": prog.char_level, "char_xp": prog.char_xp,
			"class": prog.char_class, "passives": prog.passives.keys(), "ascendancy": prog.ascendancy,
			"asc_nodes": prog.asc_nodes.keys(), "mastery_uses": prog.mastery_uses,
			"spells": prog.spells, "last_spell": prog.last_spell},
		"auras": p.auras.to_save() if p.auras else {},
	}


## Jogador local, no _ready: aplica o personagem escolhido. Retorna false se ele é novo
## (nunca jogou): aí o Player dá o kit inicial e o bônus do passado.
func apply_character(p: Player) -> bool:
	if current_character_id == "":
		return false
	var data := _read(_character_path(current_character_id))
	if data.is_empty() or not data.has("inventory"):
		return false
	var slots: Array = data.get("inventory", [])
	for i in mini(slots.size(), p.inventory.slots.size()):
		var s: Dictionary = slots[i] if slots[i] is Dictionary else {}
		if not s.is_empty() and GameData.get_item(str(s.get("id", ""))).is_empty():
			s = {}  # item que não existe mais (ex.: armas de fogo)
		elif not s.is_empty() and GameData.get_item(str(s.id)).get("type", "") == "spell":
			p.progression.spells[str(s.id)] = maxi(int(p.progression.spells.get(str(s.id), 0)), 1)
			s = {}  # feitiço como item (versão antiga): vira habilidade aprendida
		if s.has("count"):
			s.count = int(s.count)
		p.inventory.slots[i] = s
	p.inventory.changed.emit()
	var prog := p.progression
	var pd: Dictionary = data.get("progression", {})
	for key: String in pd.get("levels", {}):
		prog.levels[key] = int(pd.levels[key])
	for key: String in pd.get("xp", {}):
		prog.xp[key] = float(pd.xp[key])
	prog.char_level = int(pd.get("char_level", 1))
	prog.char_xp = float(pd.get("char_xp", 0.0))
	# Classe: a salva ou a vocação do personagem. Saves antigos (trilhas de habilidades)
	# não têm "passives": os pontos voltam todos livres para a árvore.
	prog.char_class = str(pd.get("class", data.get("background", "")))
	prog.passives = {}
	for id: Variant in pd.get("passives", []):
		prog.passives[str(id)] = true
	prog.validate_passives()
	prog.ascendancy = str(pd.get("ascendancy", ""))
	if GameData.get_entry("ascendancies", prog.ascendancy).is_empty():
		prog.ascendancy = ""
	prog.asc_nodes = {}
	for id: Variant in pd.get("asc_nodes", []):
		if not prog.ascendancy_node(str(id)).is_empty():
			prog.asc_nodes[str(id)] = true
	for key: String in pd.get("spells", {}):
		prog.spells[key] = int(pd.spells[key])
	prog.last_spell = str(pd.get("last_spell", prog.last_spell))
	for key: String in pd.get("mastery_uses", {}):
		prog.mastery_uses[key] = int(pd.mastery_uses[key])
	prog._rebuild()
	prog.changed.emit()
	if p.auras:
		p.auras.from_save(data.get("auras", {}))
	if p.has_node(^"Exploration") and data.has("exploration"):
		(p.get_node(^"Exploration") as Exploration).from_save(data.exploration)
	p.equipment.from_save(data.get("equipment", {}))
	p.creative = bool(data.get("creative", false))
	var weak: Dictionary = data.get("weakness", {})
	p.death_penalty.level = int(weak.get("level", 0))
	p.death_penalty.time_left = float(weak.get("time_left", 0.0))
	var level := _world()
	if level and "world_seed" in level:
		var here: Dictionary = data.get("positions", {}).get(str(int(level.world_seed)), {})
		if here.is_empty() and int(data.get("seed", -1)) == int(level.world_seed):
			here = {"pos": data.get("pos", []), "rot": data.get("rot", 0.0), "bed": data.get("bed", [])}  # versão 1
		if not here.is_empty():
			p.global_position = _vec(here.get("pos", [])) + Vector3.UP * 0.3
			p.rotation.y = float(here.get("rot", 0.0))
			if here.get("bed", []).size() == 3:
				p._spawn_point = _vec(here.bed)
				p._spawn_point_set = true
				p.has_bed = true
	# Vida: o servidor manda; pede um ajuste depois que tudo estiver de pé.
	var hp := float(data.get("health", 100.0))
	if hp < p.health.cap() and hp > 0.0:
		p.health.take_damage.call_deferred(p.health.cap() - hp, p)
	return true


# --- Arquivos ---------------------------------------------------------------------------

func _world() -> Node:
	var main := get_tree().current_scene
	var level_root := main.get_node_or_null(^"Level") if main else null
	if level_root == null or level_root.get_child_count() == 0:
		return null
	return level_root.get_child(0)


func _local_player() -> Player:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null


func _ids_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "json":
			out.append(file_name.get_basename())
	return out


func _new_id(prefix: String) -> String:
	return "%s_%d_%d" % [prefix, int(Time.get_unix_time_from_system()), randi() % 100000]


## Saves da versão 1 (um mundo e um personagem só) viram o primeiro de cada lista.
func _migrate_legacy() -> void:
	var legacy_world := root + "save/world.json"
	var legacy_char := root + "save/character.json"
	if FileAccess.file_exists(legacy_world) and _ids_in(worlds_dir()).is_empty():
		var data := _read(legacy_world)
		if not data.is_empty():
			data.name = "Mundo 1"
			data.updated = int(FileAccess.get_modified_time(legacy_world))
			_write(_world_path("world_legacy"), data)
			DirAccess.rename_absolute(legacy_world, legacy_world + ".migrated")
	if FileAccess.file_exists(legacy_char) and _ids_in(characters_dir()).is_empty():
		var data := _read(legacy_char)
		if not data.is_empty():
			data.name = "Personagem 1"
			data.updated = int(FileAccess.get_modified_time(legacy_char))
			_write(_character_path("char_legacy"), data)
			DirAccess.rename_absolute(legacy_char, legacy_char + ".migrated")


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: não deu para gravar %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)  # troca de uma vez: não corrompe se cair no meio


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO
