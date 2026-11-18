class_name MapTiles
## Imagens do mapa por bloco do mundo (mapa do M e minimapa): o terreno (cor do bioma,
## sombra do relevo, água) e a névoa (o que o jogador ainda não viu).
## O terreno de cada bloco é calculado numa thread (antes, gerar na hora dava soluços ao
## andar, porque o minimapa pedia vários blocos novos por quadro); enquanto não fica
## pronto, o bloco aparece em cinza. A névoa é barata e refaz só o bloco revelado.

const PIXELS := 16  # por lado de bloco (4 m por pixel)

static var _seed := 0
static var _terrain := {}  # Vector2i → ImageTexture
static var _fog := {}  # Vector2i → ImageTexture
static var _pending := {}  # Vector2i → id da tarefa
static var _done := {}  # Vector2i → Image (pronta na thread)
static var _mutex := Mutex.new()
static var _world_ref: WeakRef


static func _check_world(world: Node) -> void:
	if int(world.world_seed) != _seed:
		_seed = int(world.world_seed)
		wait_all()
		_terrain.clear()
		_fog.clear()
		_done.clear()
	_world_ref = weakref(world)


## Espera as tarefas em andamento (troca de mundo, saída).
static func wait_all() -> void:
	for c: Vector2i in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[c])
	_pending.clear()


static func has_terrain(world: Node, c: Vector2i) -> bool:
	_check_world(world)
	_collect()
	return _terrain.has(c)


## Textura do terreno do bloco, ou null se ainda está sendo feita (já pedida).
static func terrain(world: Node, c: Vector2i) -> Texture2D:
	_check_world(world)
	_collect()
	if _terrain.has(c):
		return _terrain[c]
	if not _pending.has(c):
		_pending[c] = WorkerThreadPool.add_task(func() -> void:
			var img := _render(world, c)
			_mutex.lock()
			_done[c] = img
			_mutex.unlock())
	return null


## Prontas na thread: vira textura (rápido para 16 × 16).
static func _collect() -> void:
	_mutex.lock()
	var ready := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for c: Vector2i in ready:
		if _pending.has(c):
			WorkerThreadPool.wait_for_task_completion(_pending[c])
			_pending.erase(c)
		_terrain[c] = ImageTexture.create_from_image(ready[c])


## Thread: cores do bloco (só usa o ruído do mundo).
static func _render(world: Node, c: Vector2i) -> Image:
	var img := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	var chunk_size: float = world.CHUNK
	var step := chunk_size / PIXELS
	for j in PIXELS:
		for i in PIXELS:
			var x: float = c.x * chunk_size + (i + 0.5) * step
			var z: float = c.y * chunk_size + (j + 0.5) * step
			var h: float = world._raw_height(x, z)
			var biome: String = world._biome_raw(x, z, h)
			var color: Color = world.BIOME_COLORS.get(biome, Color.BLACK)
			if biome == "lake":
				color = Color(0.2, 0.36, 0.48).darkened(clampf(-h / 6.0, 0.0, 0.3))
			else:
				color = color.lightened(clampf(h / 50.0, 0.0, 0.35))
			img.set_pixel(i, j, color.lightened(0.1))
	return img


## Névoa do bloco (null = nada visto: o bloco todo fica escuro).
static func fog(world: Node, c: Vector2i, exploration: Exploration) -> Texture2D:
	_check_world(world)
	if exploration == null:
		return null
	if not _fog.has(c):
		var mask := exploration.chunk_mask(c)
		if mask.is_empty():
			return null
		var img := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
		for j in PIXELS:
			for i in PIXELS:
				img.set_pixel(i, j, Color(0.04, 0.05, 0.06, 0.0 if mask[j * PIXELS + i] == 1 else 0.96))
		_fog[c] = ImageTexture.create_from_image(img)
	return _fog[c]


## Bloco revelado: refaz a névoa dele na próxima vez que for desenhado.
static func invalidate_fog(chunks: Array) -> void:
	for c: Vector2i in chunks:
		_fog.erase(c)
