class_name Exploration
extends Node
## O que este jogador já viu do mapa (névoa do mapa, GDD 10) e as marcações que fez.
## Fica no jogador local (nó "Exploration"). Grade de CELL metros; tudo num raio de
## REVEAL_RADIUS em volta dele vai sendo revelado. Salvo junto do personagem.

signal revealed
signal markers_changed

const CELL := 5.0
const REVEAL_RADIUS := 40.0
const MAX_MARKERS := 8

## Mundo a que a exploração pertence (outra semente = começa do zero).
var world_seed := 0
var size := 0  # células por lado
var explored := PackedByteArray()
## Marcações do mapa: posições no plano (x, z).
var markers: Array[Vector2] = []

var _half := 0.0
var _timer := 0.0


## Prepara para o mundo atual (chamado quando o mundo existe).
func setup(seed_value: int, world_size: float) -> void:
	if seed_value == world_seed and size > 0:
		return
	world_seed = seed_value
	size = int(ceil(world_size / CELL))
	_half = world_size * 0.5
	explored = PackedByteArray()
	explored.resize(size * size)
	markers.clear()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	setup(int(world.world_seed), float(world.SIZE))  # outro mundo: recomeça
	_half = float(world.SIZE) * 0.5
	_reveal((get_parent() as Node3D).global_position)


func _reveal(at: Vector3) -> void:
	var changed := false
	var r := int(ceil(REVEAL_RADIUS / CELL))
	var ci := int((at.x + _half) / CELL)
	var cj := int((at.z + _half) / CELL)
	for j in range(cj - r, cj + r + 1):
		for i in range(ci - r, ci + r + 1):
			if i < 0 or j < 0 or i >= size or j >= size:
				continue
			if Vector2(i - ci, j - cj).length() * CELL > REVEAL_RADIUS:
				continue
			var k := j * size + i
			if explored[k] == 0:
				explored[k] = 1
				changed = true
	if changed:
		revealed.emit()


func is_explored(x: float, z: float) -> bool:
	if size == 0:
		return false
	var i := int((x + _half) / CELL)
	var j := int((z + _half) / CELL)
	return i >= 0 and j >= 0 and i < size and j < size and explored[j * size + i] == 1


## Botão direito no mapa: marca, ou desmarca se já tem uma perto.
func toggle_marker(at: Vector2) -> void:
	for k in markers.size():
		if markers[k].distance_to(at) < 8.0:
			markers.remove_at(k)
			markers_changed.emit()
			return
	if markers.size() >= MAX_MARKERS:
		markers.remove_at(0)
	markers.append(at)
	markers_changed.emit()


func to_save() -> Dictionary:
	var list: Array = []
	for m in markers:
		list.append([m.x, m.y])
	return {"seed": world_seed, "size": size, "explored": Marshalls.raw_to_base64(explored), "markers": list}


func from_save(data: Dictionary) -> void:
	world_seed = int(data.get("seed", 0))
	size = int(data.get("size", 0))
	explored = Marshalls.base64_to_raw(str(data.get("explored", "")))
	if explored.size() != size * size:
		size = 0
		world_seed = 0
		explored = PackedByteArray()
	markers.clear()
	for m: Array in data.get("markers", []):
		markers.append(Vector2(float(m[0]), float(m[1])))
