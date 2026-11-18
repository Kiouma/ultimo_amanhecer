class_name FlagIcons
## Bandeiras pequenas desenhadas pixel a pixel (sem arquivos de imagem), para a escolha
## de idioma: br (Brasil), us (EUA), cn (China) e ru (Rússia).

const SIZE := Vector2i(36, 24)

static var _cache := {}


static func texture(code: String) -> Texture2D:
	if not _cache.has(code):
		_cache[code] = ImageTexture.create_from_image(_draw(code))
	return _cache[code]


static func _draw(code: String) -> Image:
	var w := SIZE.x
	var h := SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, _pixel(code, (x + 0.5) / w, (y + 0.5) / h))
	return img


## Cor da bandeira no ponto (u, v) de 0 a 1.
static func _pixel(code: String, u: float, v: float) -> Color:
	match code:
		"br":
			# Verde, losango amarelo e círculo azul.
			var du := absf(u - 0.5) / 0.42
			var dv := absf(v - 0.5) / 0.4
			var circle := Vector2((u - 0.5) * 1.5, v - 0.5).length() < 0.2
			if circle:
				return Color(0.0, 0.15, 0.5)
			if du + dv < 1.0:
				return Color(1.0, 0.85, 0.0)
			return Color(0.0, 0.6, 0.25)
		"us":
			# Listras vermelhas e brancas; cantão azul com pontos brancos.
			if u < 0.42 and v < 0.54:
				var su := fmod(u * 12.0, 1.0)
				var sv := fmod(v * 10.0, 1.0)
				return Color.WHITE if su > 0.35 and su < 0.65 and sv > 0.35 and sv < 0.65 else Color(0.2, 0.22, 0.5)
			return Color(0.75, 0.13, 0.2) if int(v * 13.0) % 2 == 0 else Color.WHITE
		"cn":
			# Vermelho com uma estrela grande e quatro pequenas, amarelas.
			var p := Vector2(u * 1.5, v)
			if _in_star(p, Vector2(0.25, 0.27), 0.17, 0.0):
				return Color(1.0, 0.87, 0.0)
			for s: Array in [[Vector2(0.5, 0.1), 0.4], [Vector2(0.6, 0.2), 0.8], [Vector2(0.6, 0.35), 0.0], [Vector2(0.5, 0.45), 0.4]]:
				if _in_star(p, s[0], 0.055, s[1]):
					return Color(1.0, 0.87, 0.0)
			return Color(0.87, 0.16, 0.06)
		"ru":
			if v < 1.0 / 3.0:
				return Color.WHITE
			return Color(0.0, 0.22, 0.65) if v < 2.0 / 3.0 else Color(0.84, 0.15, 0.12)
	return Color(0.4, 0.4, 0.4)


## Ponto dentro de uma estrela de 5 pontas (centro c, raio r, giro em radianos).
static func _in_star(p: Vector2, c: Vector2, r: float, spin: float) -> bool:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + spin + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.4
		points.append(c + Vector2(cos(a), sin(a)) * rr)
	return Geometry2D.is_point_in_polygon(p, points)
