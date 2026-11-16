extends Node
## Salvamento (GDD 17, Fase 8), autoload "SaveGame".
## - Mundo (user://save/world.json), salvo pelo host: semente, dia/hora, clima,
##   construções, estações, armadilhas e itens/bags no chão. Recursos e zumbis voltam
##   pela semente e pela população.
## - Personagem (user://save/character.json), salvo por cada jogador na própria
##   máquina (inventário e progressão são do dono): dá para levar o personagem para o
##   mundo de um amigo. A posição só volta se for o mesmo mundo (mesma semente).
## Salva sozinho a cada AUTOSAVE_SECONDS, ao fechar a janela e pelo menu de pausa.

const DIR := "user://save"
const WORLD_PATH := "user://save/world.json"
const CHARACTER_PATH := "user://save/character.json"
const VERSION := 1
const AUTOSAVE_SECONDS := 120.0

## Escolhas do menu: carregar o mundo / o personagem salvos.
var load_world := false
var load_character := false

var _timer := AUTOSAVE_SECONDS


func _ready() -> void:
	get_tree().auto_accept_quit = false


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


func has_world() -> bool:
	return FileAccess.file_exists(WORLD_PATH)


func has_character() -> bool:
	return FileAccess.file_exists(CHARACTER_PATH)


## Resumo para o menu ("Dia 9", "Nível 4 · Enfermeiro").
func world_summary() -> String:
	var data := _read(WORLD_PATH)
	return "Dia %d" % int(data.get("day", 1)) if not data.is_empty() else ""


func character_summary() -> String:
	var data := _read(CHARACTER_PATH)
	if data.is_empty():
		return ""
	var bg := str(GameData.get_entry("backgrounds", str(data.get("background", ""))).get("name", ""))
	return "Nível %d%s" % [int(data.get("progression", {}).get("char_level", 1)), " · " + bg if bg != "" else ""]


## Salva o que esta máquina pode: o mundo (se for o servidor) e o personagem local.
func save_all() -> void:
	var level := _world()
	if level == null:
		return
	if multiplayer.is_server():
		_write(WORLD_PATH, _capture_world(level))
	var me := _local_player()
	if me:
		_write(CHARACTER_PATH, _capture_character(me, level))


# --- Mundo ------------------------------------------------------------------------------

## Semente salva (0 = nenhuma), para gerar o mesmo terreno antes do _ready do nível.
func saved_seed() -> int:
	return int(_read(WORLD_PATH).get("seed", 0)) if load_world else 0


func _capture_world(level: Node) -> Dictionary:
	var data := {"version": VERSION, "seed": int(level.get("world_seed")) if "world_seed" in level else 0}
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
				"contents": s.contents, "water": s.water})
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
	var data := _read(WORLD_PATH)
	if data.is_empty():
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
		var node := Structures._spawn(str(s.id), _vec(s.pos), float(s.rot), float(s.get("dur", -1.0)))
		if node is BaseUtility:
			for stack: Dictionary in s.get("contents", []):
				if not GameData.get_item(str(stack.get("id", ""))).is_empty():
					stack.count = int(stack.count)
					node.contents.append(stack)
			node.water = int(s.get("water", 0))
	for it: Dictionary in data.get("items", []):
		if it.get("bag", false):
			WorldItems.drop_bag(it.contents, _vec(it.pos), str(it.owner))
		else:
			WorldItems.spawn(str(it.id), int(it.count), _vec(it.pos) + Vector3.UP * 0.3, 0, it.get("extra", {}))


# --- Personagem -----------------------------------------------------------------------

func _capture_character(p: Player, level: Node) -> Dictionary:
	var prog := p.progression
	return {
		"version": VERSION, "background": Network.background,
		"seed": int(level.get("world_seed")) if "world_seed" in level else 0,
		"pos": _v(p.global_position), "rot": p.rotation.y,
		"bed": _v(p._spawn_point) if p.has_bed else [],
		"inventory": p.inventory.slots,
		"equipment": p.equipment.to_save(),
		"exploration": (p.get_node(^"Exploration") as Exploration).to_save() if p.has_node(^"Exploration") else {},
		"health": p.health.current, "hunger": p.survival.hunger, "thirst": p.survival.thirst,
		"weakness": {"level": p.death_penalty.level, "time_left": p.death_penalty.time_left},
		"progression": {"levels": prog.levels, "xp": prog.xp, "char_level": prog.char_level, "char_xp": prog.char_xp,
			"skill_points": prog.skill_points, "skills": prog.skills, "mastery_uses": prog.mastery_uses,
			"spells": prog.spells, "last_spell": prog.last_spell},
	}


## Jogador local, no _ready: troca o kit inicial pelo personagem salvo. Retorna true se carregou.
func apply_character(p: Player) -> bool:
	if not load_character:
		return false
	var data := _read(CHARACTER_PATH)
	if data.is_empty():
		return false
	Network.background = str(data.get("background", Network.background))
	var slots: Array = data.get("inventory", [])
	for i in mini(slots.size(), p.inventory.slots.size()):
		var s: Dictionary = slots[i] if slots[i] is Dictionary else {}
		if not s.is_empty() and GameData.get_item(str(s.get("id", ""))).is_empty():
			s = {}  # item que não existe mais
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
	prog.skill_points = int(pd.get("skill_points", 0))
	prog.skills = pd.get("skills", {})
	for key: String in pd.get("spells", {}):
		prog.spells[key] = int(pd.spells[key])
	prog.last_spell = str(pd.get("last_spell", prog.last_spell))
	for key: String in pd.get("mastery_uses", {}):
		prog.mastery_uses[key] = int(pd.mastery_uses[key])
	prog._rebuild()
	prog.changed.emit()
	if p.has_node(^"Exploration") and data.has("exploration"):
		(p.get_node(^"Exploration") as Exploration).from_save(data.exploration)
	p.equipment.from_save(data.get("equipment", {}))
	p.survival.hunger = float(data.get("hunger", 100.0))
	p.survival.thirst = float(data.get("thirst", 100.0))
	var weak: Dictionary = data.get("weakness", {})
	p.death_penalty.level = int(weak.get("level", 0))
	p.death_penalty.time_left = float(weak.get("time_left", 0.0))
	var level := _world()
	if level and "world_seed" in level and int(data.get("seed", -1)) == int(level.world_seed):
		p.global_position = _vec(data.pos) + Vector3.UP * 0.3
		p.rotation.y = float(data.get("rot", 0.0))
		if data.get("bed", []).size() == 3:
			p._spawn_point = _vec(data.bed)
			p._spawn_point_set = true
			p.has_bed = true
	# Vida: o servidor manda; pede um ajuste depois que tudo estiver de pé.
	var hp := float(data.get("health", 100.0))
	if hp < p.health.max_health and hp > 0.0:
		p.health.take_damage.call_deferred(p.health.max_health - hp, p)
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


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
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
