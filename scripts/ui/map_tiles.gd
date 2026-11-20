class_name MapTiles
## Imagens do mapa por bloco do mundo (mapa do M e minimapa): o terreno (cor do bioma,
## sombra do relevo, água) e a névoa (o que o jogador ainda não viu).
## O terreno de cada bloco é calculado numa thread (antes, gerar na hora dava soluços ao
## andar, porque o minimapa pedia vários blocos novos por quadro); enquanto não fica
## pronto, o bloco aparece em cinza. A névoa é barata e refaz só o bloco revelado.

const PIXELS := 32  # por lado de bloco (2 m por pixel)

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


## Paleta do mapa (estilo mapa pintado: mais saturada que as cores dos biomas no chão).
const PLAINS := Color(0.5, 0.58, 0.34)
const FOREST := Color(0.31, 0.47, 0.27)
const SWAMP := Color(0.36, 0.4, 0.27)
const TUNDRA := Color(0.88, 0.9, 0.94)
const CORRUPT := Color(0.42, 0.32, 0.48)
const ROCK := Color(0.52, 0.5, 0.47)
const SNOW := Color(0.94, 0.95, 0.97)
const SAND := Color(0.82, 0.76, 0.56)
const SHALLOW := Color(0.36, 0.6, 0.72)
const DEEP := Color(0.13, 0.28, 0.45)
## Curvas de nível a cada CONTOUR metros.
const CONTOUR := 4.0


## Amostras de ruído por lado do bloco (a cada 4 m); os pixels interpolam entre elas.
## Assim o mapa tem 32 px por bloco gastando menos ruído que antes (16 px, 1 amostra/px).
const GRID := 16


## Thread: cores do bloco (só usa o ruído do mundo). Mistura suave dos biomas (em vez de
## pixels de uma cor só), sombra do relevo (luz vinda do noroeste), curvas de nível,
## água mais escura no fundo, areia e contorno na margem.
static func _render(world: Node, c: Vector2i) -> Image:
	var img := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	var chunk_size: float = world.CHUNK
	var cell := chunk_size / GRID
	var origin := Vector2(c) * chunk_size
	var water: float = world.WATER_LEVEL
	# Grade grossa: alturas com 1 de borda (relevo nas beiradas) e cores da terra.
	var side := GRID + 3  # índices -1 .. GRID+1
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for j in side:
		for i in side:
			heights[j * side + i] = world._raw_height(origin.x + (i - 1) * cell, origin.y + (j - 1) * cell)
	var land: Array[Color] = []
	var shades := PackedFloat32Array()
	var light := Vector2(-1.0, -1.0).normalized()
	for j in GRID + 1:
		for i in GRID + 1:
			var k := (j + 1) * side + (i + 1)
			land.append(_land_color(world, origin.x + i * cell, origin.y + j * cell, heights[k]))
			var grad := Vector2(heights[k + 1] - heights[k - 1], heights[k + side] - heights[k - side]) / (2.0 * cell)
			shades.append(clampf(-grad.dot(light) * 0.9, -0.35, 0.35))
	# Pixels: interpolação bilinear da grade.
	var hp := PackedFloat32Array()
	hp.resize(PIXELS * PIXELS)
	var scale := float(GRID) / PIXELS
	for j in PIXELS:
		for i in PIXELS:
			var gx := (i + 0.5) * scale
			var gz := (j + 0.5) * scale
			var i0 := mini(int(gx), GRID - 1)
			var j0 := mini(int(gz), GRID - 1)
			var fx := gx - i0
			var fz := gz - j0
			var k := (j0 + 1) * side + (i0 + 1)
			var h := lerpf(lerpf(heights[k], heights[k + 1], fx), lerpf(heights[k + side], heights[k + side + 1], fx), fz)
			hp[j * PIXELS + i] = h
			var g := j0 * (GRID + 1) + i0
			var color: Color
			if h < water:
				color = SHALLOW.lerp(DEEP, clampf(-h / 1.8, 0.0, 1.0)).lightened(clampf(0.25 + h * 0.4, 0.0, 0.25))
			else:
				color = land[g].lerp(land[g + 1], fx).lerp(land[g + GRID + 1].lerp(land[g + GRID + 2], fx), fz)
				var shade := lerpf(lerpf(shades[g], shades[g + 1], fx), lerpf(shades[g + GRID + 1], shades[g + GRID + 2], fx), fz)
				color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
			img.set_pixel(i, j, color)
	# Curvas de nível e contorno da margem (comparando com os vizinhos do pixel).
	for j in PIXELS:
		for i in PIXELS:
			var h := hp[j * PIXELS + i]
			var right := hp[j * PIXELS + mini(i + 1, PIXELS - 1)]
			var down := hp[mini(j + 1, PIXELS - 1) * PIXELS + i]
			var wet := h < water
			if wet != (right < water) or wet != (down < water):
				img.set_pixel(i, j, img.get_pixel(i, j).darkened(0.3) if not wet else img.get_pixel(i, j).lightened(0.2))
			elif not wet and h > water + 1.0 and (floorf(h / CONTOUR) != floorf(right / CONTOUR) or floorf(h / CONTOUR) != floorf(down / CONTOUR)):
				img.set_pixel(i, j, img.get_pixel(i, j).darkened(0.1))
	return img


## Cor da terra num ponto, misturando os biomas pelas mesmas fronteiras do mundo
## (world._biome_raw), mas com transição suave.
static func _land_color(world: Node, x: float, z: float, h: float) -> Color:
	var color := PLAINS
	var d := Vector2(x, z).length()
	if d >= world.SPAWN_BLEND:
		color = color.lerp(FOREST, smoothstep(-0.3, 0.2, world._n("forest", x, z)))
		color = color.lerp(SWAMP, smoothstep(0.24, 0.4, world._n("swamp", x, z)))
		color = color.lerp(TUNDRA, smoothstep(-0.3, -0.46, world._n("temp", x, z)))
		if d > 160.0:
			color = color.lerp(CORRUPT, smoothstep(0.48, 0.62, world._n("corrupt", x, z)))
	# Montanha: rocha, e neve no alto.
	var m: float = world._mountain_factor(x, z)
	color = color.lerp(ROCK, smoothstep(0.3, 0.55, m))
	color = color.lerp(SNOW, smoothstep(world.MOUNTAIN_HEIGHT * 0.75, world.MOUNTAIN_HEIGHT + 6.0, h) * smoothstep(0.4, 0.6, m))
	# Areia na margem.
	color = color.lerp(SAND, 1.0 - smoothstep(world.WATER_LEVEL + 0.2, world.WATER_LEVEL + 0.9, h))
	return color


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
