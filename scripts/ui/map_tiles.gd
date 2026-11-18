class_name MapTiles
## Imagens do mapa por bloco do mundo (mapa do M e minimapa): o terreno (cor do bioma,
## sombra do relevo, água) e a névoa (o que o jogador ainda não viu). Cada imagem é feita
## uma vez e guardada; a névoa refaz só o bloco que foi revelado.

const PIXELS := 16  # por lado de bloco (4 m por pixel)

static var _seed := 0
static var _terrain := {}  # Vector2i → ImageTexture
static var _fog := {}  # Vector2i → ImageTexture


static func _check_world(world: Node) -> void:
	if int(world.world_seed) != _seed:
		_seed = int(world.world_seed)
		_terrain.clear()
		_fog.clear()


static func has_terrain(world: Node, c: Vector2i) -> bool:
	_check_world(world)
	return _terrain.has(c)


static func terrain(world: Node, c: Vector2i) -> Texture2D:
	_check_world(world)
	if not _terrain.has(c):
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
		_terrain[c] = ImageTexture.create_from_image(img)
	return _terrain[c]


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
