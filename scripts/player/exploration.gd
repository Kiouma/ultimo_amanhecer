class_name Exploration
extends Node
## O que este jogador já viu do mapa (névoa do mapa, GDD 10) e as marcações que fez.
## Fica no jogador local (nó "Exploration"). Mundo infinito: guardado por bloco de
## CHUNK metros (uma grade de CELL metros por bloco), só dos blocos visitados. Tudo num
## raio de REVEAL_RADIUS em volta do jogador vai sendo revelado. Salvo com o personagem.

## Revelou algo; chunks: blocos que mudaram (Array de Vector2i).
signal revealed(chunks: Array)
signal markers_changed

const CELL := 4.0
const CHUNK := 64.0
const PER_SIDE := 16  # CHUNK / CELL
const REVEAL_RADIUS := 40.0
const MAX_MARKERS := 8

## Mundo a que a exploração pertence (outra semente = começa do zero).
var world_seed := 0
## Vector2i (bloco) → PackedByteArray(PER_SIDE²): 1 = visto.
var chunks := {}
## Marcações do mapa: posições no plano (x, z).
var markers: Array[Vector2] = []

var _timer := 0.0


## Prepara para o mundo atual (outra semente: recomeça).
func setup(seed_value: int) -> void:
	if seed_value == world_seed:
		return
	world_seed = seed_value
	chunks.clear()
	markers.clear()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not "world_seed" in world:
		return
	setup(int(world.world_seed))
	_reveal((get_parent() as Node3D).global_position)


func _reveal(at: Vector3) -> void:
	var changed := {}
	var r := int(ceil(REVEAL_RADIUS / CELL))
	var ci := floori(at.x / CELL)
	var cj := floori(at.z / CELL)
	for j in range(cj - r, cj + r + 1):
		for i in range(ci - r, ci + r + 1):
			if Vector2(i - ci, j - cj).length() * CELL > REVEAL_RADIUS:
				continue
			var c := Vector2i(floori(float(i) / PER_SIDE), floori(float(j) / PER_SIDE))
			var mask: PackedByteArray = chunks.get(c, PackedByteArray())
			if mask.is_empty():
				mask.resize(PER_SIDE * PER_SIDE)
			var k := posmod(j, PER_SIDE) * PER_SIDE + posmod(i, PER_SIDE)
			if mask[k] == 0:
				mask[k] = 1
				changed[c] = true
			chunks[c] = mask
	if not changed.is_empty():
		revealed.emit(changed.keys())


func is_explored(x: float, z: float) -> bool:
	var i := floori(x / CELL)
	var j := floori(z / CELL)
	var mask: PackedByteArray = chunks.get(Vector2i(floori(float(i) / PER_SIDE), floori(float(j) / PER_SIDE)), PackedByteArray())
	return not mask.is_empty() and mask[posmod(j, PER_SIDE) * PER_SIDE + posmod(i, PER_SIDE)] == 1


## Máscara do bloco (vazia = nada visto).
func chunk_mask(c: Vector2i) -> PackedByteArray:
	return chunks.get(c, PackedByteArray())


## Botão direito no mapa: marca, ou desmarca se já tem uma perto.
func toggle_marker(at: Vector2, near := 8.0) -> void:
	for k in markers.size():
		if markers[k].distance_to(at) < near:
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
	var packed := {}
	for c: Vector2i in chunks:
		packed["%d:%d" % [c.x, c.y]] = Marshalls.raw_to_base64(chunks[c])
	return {"seed": world_seed, "chunks": packed, "markers": list}


func from_save(data: Dictionary) -> void:
	world_seed = int(data.get("seed", 0))
	chunks.clear()
	var packed: Dictionary = data.get("chunks", {})  # saves antigos (mapa fixo) não têm: recomeça
	for key: String in packed:
		var parts := key.split(":")
		var mask := Marshalls.base64_to_raw(str(packed[key]))
		if parts.size() == 2 and mask.size() == PER_SIDE * PER_SIDE:
			chunks[Vector2i(int(parts[0]), int(parts[1]))] = mask
	markers.clear()
	for m: Array in data.get("markers", []):
		markers.append(Vector2(float(m[0]), float(m[1])))
