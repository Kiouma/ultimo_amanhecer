class_name Gathering
extends Node3D
## Coleta com tempo e pesca (nó "Gathering" do Player, etapa 7). Roda no dono.
##
## Coleta: E numa árvore/rocha com a ferramenta certa no slot (machado/picareta)
## começa a coleta. Barra de progresso (ChannelBar). Andar, atacar, se afastar ou
## morrer cancela; levar dano não cancela. Tempo = tempo base do recurso ÷ velocidade
## (ferramenta × qualidade × Sobrevivência). No fim, o recurso dá tudo de uma vez ×
## rendimento (ferramenta × refino × "gather_yield").
##
## Pesca: com a vara no slot, olhando para um lago (água a até 5 m à frente), E lança.
## Espera alguns segundos (menos com mais força de pesca); quando o peixe fisga, E (ou
## clique) em até BITE_WINDOW segundos pega. Força de pesca = vara + isca (a melhor
## isca do inventário é gasta a cada lançada). Força maior = peixes mais raros.
## Este nó também é o "ponto de pesca" do foco de interação (fica na água).

signal changed

enum Mode { NONE, GATHER, FISH_WAIT, FISH_BITE }

const BITE_WINDOW := 1.4
const WATER_DEPTH := 0.3
## Nível da água dos lagos (igual a World.WATER_LEVEL).
const WATER_LEVEL := 0.0
## Peso base por raridade e força mínima para aparecer (raridade 3 = 2, 4 = 3).
const RARITY_WEIGHT := {1: 50.0, 2: 22.0, 3: 6.0, 4: 2.0}
const RARITY_MIN_POWER := {1: 0, 2: 1, 3: 2, 4: 3}

var mode := Mode.NONE

var _player: Player
var _target: ResourceNode
var _tool: Dictionary = {}
var _time := 0.0
var _total := 1.0
var _bite_timer := 0.0
var _cast_power := 0
var _anim_timer := 0.0
var _water_timer := 0.0
var _has_water := false
var _bobber: MeshInstance3D


func _ready() -> void:
	_player = get_parent() as Player
	top_level = true


# --- Números ----------------------------------------------------------------------------

## Velocidade de coleta da ferramenta (tipo × qualidade × Sobrevivência).
func gather_speed(tool: Dictionary) -> float:
	if tool.is_empty():
		return 1.0
	var survival := _player.progression.get_level("survival") if _player else 1
	return float(GameData.get_item(tool.id).get("gather_speed", 1.0)) * Inventory.quality_multiplier(tool) \
		* (1.0 + 0.01 * (survival - 1))


## Rendimento (quanto sai): tipo × refino × "gather_yield" (árvore, itens).
func gather_yield(tool: Dictionary) -> float:
	return float(GameData.get_item(tool.id).get("gather_yield", 1.0)) * Inventory.refine_multiplier(tool) \
		* _player.progression.mult("gather_yield")


func gather_time(node: ResourceNode) -> float:
	return node.base_gather_time() / gather_speed(_player.equipment.tool_item(node.tool_slot()))


## Força de pesca: vara + melhor isca do inventário (ou a isca já gasta nesta lançada).
func fishing_power() -> int:
	var rod := _player.equipment.tool_item("rod")
	if rod.is_empty():
		return 0
	var bait := _cast_power if mode in [Mode.FISH_WAIT, Mode.FISH_BITE] else int(_best_bait()[1])
	return int(GameData.get_item(rod.id).get("fishing_power", 1)) + bait


## [id, força] da melhor isca no inventário (["", 0] se não tem).
func _best_bait() -> Array:
	var best := ["", 0]
	for id: String in GameData.get_all("items"):
		var d := GameData.get_item(id)
		if str(d.get("type", "")) == "bait" and _player.inventory.count_of(id) > 0 and int(d.get("bait_power", 0)) > int(best[1]):
			best = [id, int(d.bait_power)]
	return best


# --- Coleta -------------------------------------------------------------------------------

func start_gather(node: ResourceNode) -> void:
	if not _can_start():
		return
	cancel()
	var tool := _player.equipment.tool_item(node.tool_slot())
	if tool.is_empty():
		_player.notify(tr("Equipe %s no slot de ferramenta (V)") % (tr("um machado") if node.tool_slot() == "axe" else tr("uma picareta")))
		return
	_target = node
	_tool = tool
	_time = 0.0
	_total = gather_time(node)
	_anim_timer = 0.0
	mode = Mode.GATHER
	# Ferramenta na mão enquanto coleta (todos veem); a arma volta no fim (_end).
	_player.net_held = "%s|%s" % [str(tool.id), str(_player.equipment.get_item("offhand").get("id", ""))]
	_player.face_point(node.global_position)
	changed.emit()


## 0 a 1 durante a coleta (barra de progresso); -1 fora dela. Na fisgada, o tempo que sobra.
func channel_fraction() -> float:
	match mode:
		Mode.GATHER: return clampf(_time / _total, 0.0, 1.0)
		Mode.FISH_BITE: return clampf(_bite_timer / BITE_WINDOW, 0.0, 1.0)
	return -1.0


func channel_label() -> String:
	match mode:
		Mode.GATHER:
			var verb := tr("Cortando") if _target and _target.gather_kind() == "tree" else tr("Minerando")
			return "%s %s · %.1f s" % [verb, str(_target.data.get("name", "")).to_lower() if _target else "", maxf(_total - _time, 0.0)]
		Mode.FISH_BITE:
			return tr("Fisgou! Aperte E ou clique")
	return ""


func _finish_gather() -> void:
	var node := _target
	var tool := _tool
	_end()
	if not is_instance_valid(node):
		return
	node.request_harvest(_player, str(tool.id), gather_yield(tool))
	_player.inventory.wear(tool, 1.0)
	_player.progression.gain("survival", 3.0)
	Sfx.play("swing", node.global_position + Vector3.UP, -4.0)


# --- Pesca ----------------------------------------------------------------------------------

## O personagem está de frente para água, com a vara no slot.
func can_fish() -> bool:
	return _has_water and not _player.equipment.tool_item("rod").is_empty()


## Aviso de interação (este nó é o "ponto de pesca").
func get_prompt() -> String:
	match mode:
		Mode.FISH_WAIT: return tr("Esperando o peixe... [E] recolhe a linha")
		Mode.FISH_BITE: return tr("[E] Fisgou! Puxe agora!")
	var bait := _best_bait()
	var bait_text := (" · " + tr("isca: %s") % GameData.get_item(bait[0]).get("name", "")) if bait[0] != "" else ""
	return tr("[E] Pescar (força de pesca %d%s)") % [fishing_power(), bait_text]


func has_prompt() -> bool:
	return true


func interact(_who: Node3D) -> void:
	match mode:
		Mode.NONE: start_fishing()
		Mode.FISH_WAIT:
			_player.notify(tr("Recolheu a linha"))
			cancel()
		Mode.FISH_BITE: _catch()


func start_fishing() -> void:
	if not _can_start() or not can_fish():
		return
	var rod := _player.equipment.tool_item("rod")
	var bait := _best_bait()
	_cast_power = 0
	if bait[0] != "" and _player.inventory.remove_item(str(bait[0]), 1):
		_cast_power = int(bait[1])
	mode = Mode.FISH_WAIT
	var power := fishing_power()
	_bite_timer = randf_range(4.0, 10.0) / (1.0 + 0.15 * power)
	_tool = rod
	_player.face_point(global_position)
	_player.play_action_synced(&"Fishing_Idle")
	_show_bobber(true)
	changed.emit()
	_player.notify(tr("Lançou a linha (força de pesca %d)") % power)


func _catch() -> void:
	var fish := _pick_fish(fishing_power())
	var rod := _tool
	_end()
	_player.play_action_synced(&"Fishing_Reeling", 0.8)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(_player) and mode == Mode.NONE:
			_player.stop_action_synced())
	if fish == "":
		return
	var left := _player.inventory.add_item(fish, 1)
	if left > 0:
		WorldItems.drop(fish, left, _player.global_position + Vector3.UP * 0.3, _player)
	_player.inventory.received.emit(fish, 1)
	_player.notify(tr("Pescou: %s!") % GameData.get_item(fish).get("name", fish))
	_player.inventory.wear(rod, 1.0)
	_player.progression.gain("survival", 4.0)
	Sfx.play("pickup", _player.global_position + Vector3.UP, 0.0)


## Sorteia um peixe pela força de pesca: raros só a partir de certa força e com mais peso
## quanto maior a força.
static func _pick_fish(power: int) -> String:
	var table := {}
	var total := 0.0
	for id: String in GameData.get_all("items"):
		var d := GameData.get_item(id)
		if not d.get("fish", false):
			continue
		var rarity := int(d.get("rarity", 1))
		if power < int(RARITY_MIN_POWER.get(rarity, 0)):
			continue
		var w := float(RARITY_WEIGHT.get(rarity, 1.0)) * (1.0 + 0.5 * power * (rarity - 1))
		table[id] = w
		total += w
	var roll := randf() * total
	for id: String in table:
		roll -= float(table[id])
		if roll <= 0.0:
			return id
	return table.keys()[0] if not table.is_empty() else ""


# --- Andamento --------------------------------------------------------------------------

func is_busy() -> bool:
	return mode != Mode.NONE


func cancel(message := "") -> void:
	if mode == Mode.NONE:
		return
	_end()
	if message != "":
		_player.notify(message)


func _end() -> void:
	var was := mode
	mode = Mode.NONE
	_target = null
	_show_bobber(false)
	if was != Mode.NONE:
		_player.stop_action_synced()
		_player._update_held()
	changed.emit()


func _can_start() -> bool:
	return _player and _player.is_local() and not _player.health.is_dead and MouseMode.playing()


func _process(delta: float) -> void:
	if _player == null or not _player.is_local():
		return
	_update_water(delta)
	if mode == Mode.NONE:
		return
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1 \
		or Input.is_action_pressed("jump")
	if _player.health.is_dead:
		cancel()
		return
	match mode:
		Mode.GATHER:
			if moving or (Input.is_action_just_pressed("attack") and MouseMode.can_attack(get_viewport())):
				cancel(tr("Coleta cancelada"))
				return
			if not is_instance_valid(_target) or _target.global_position.distance_to(_player.global_position) > ResourceNode.MAX_REACH:
				cancel()
				return
			_anim_timer -= delta
			if _anim_timer <= 0.0:
				_anim_timer = 0.9
				_player.play_action_synced(&"Chopping" if _target.gather_kind() == "tree" else &"Pickaxing", 0.9)
			_time += delta
			if _time >= _total:
				_finish_gather()
		Mode.FISH_WAIT:
			if moving:
				cancel(tr("A linha soltou (você se mexeu)"))
				return
			_bite_timer -= delta
			if _bite_timer <= 0.0:
				mode = Mode.FISH_BITE
				_bite_timer = BITE_WINDOW
				_player.notify(tr("Fisgou! Aperte E"))
				Sfx.play("hit", global_position, -6.0)
				changed.emit()
		Mode.FISH_BITE:
			if moving:
				cancel(tr("O peixe escapou"))
				return
			_bite_timer -= delta
			if _bite_timer <= 0.0:
				cancel(tr("O peixe escapou"))
	if _bobber and _bobber.visible:
		_bobber.position.y = WATER_LEVEL + 0.05 + (sin(Time.get_ticks_msec() * 0.008) * 0.04 if mode == Mode.FISH_WAIT else -0.12)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not _player.is_local() or mode != Mode.FISH_BITE:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("attack"):
		_catch()
		get_viewport().set_input_as_handled()


## Água a até 5 m à frente do personagem? Guarda o ponto (este nó vai para lá).
func _update_water(delta: float) -> void:
	if mode in [Mode.FISH_WAIT, Mode.FISH_BITE]:
		return
	_water_timer -= delta
	if _water_timer > 0.0:
		return
	_water_timer = 0.3
	_has_water = false
	if _player.equipment.tool_item("rod").is_empty():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method(&"ground_height"):
		return
	var forward := -_player.global_basis.z
	for dist: float in [2.0, 3.0, 4.0, 5.0]:
		var p := _player.global_position + forward * dist
		if world.ground_height(p.x, p.z) < WATER_LEVEL - WATER_DEPTH:
			global_position = Vector3(p.x, WATER_LEVEL, p.z)
			_has_water = true
			return


func _show_bobber(on: bool) -> void:
	if on and _bobber == null:
		_bobber = Weapon.sphere(0.07, Color(0.9, 0.2, 0.15))
		_bobber.top_level = true
		add_child(_bobber)
	if _bobber:
		_bobber.visible = on
		if on:
			_bobber.global_position = global_position + Vector3.UP * 0.05
