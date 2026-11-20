class_name PassiveTree
extends RefCounted
## Grafo da árvore passiva (data/passives, gerado por tools/gen_passive_tree.py).
## Nós: "start" (início de cada classe), "small", "notable" e "keystone"; as ligações
## do JSON valem nos dois sentidos. Só leitura: quem guarda o que foi alocado é o
## Progression do personagem.

static var _adjacency := {}
static var _count := -1


static func node(id: String) -> Dictionary:
	return GameData.get_entry("passives", id)


static func all() -> Dictionary:
	return GameData.get_all("passives")


## Vizinhos de um nó (ligações nos dois sentidos).
static func neighbors(id: String) -> Array:
	_ensure()
	return _adjacency.get(id, [])


static func _ensure() -> void:
	var nodes := all()
	if nodes.size() == _count:
		return
	_count = nodes.size()
	_adjacency.clear()
	for id: String in nodes:
		if not _adjacency.has(id):
			_adjacency[id] = []
		for other: String in nodes[id].get("links", []):
			if not nodes.has(other):
				continue
			if not _adjacency.has(other):
				_adjacency[other] = []
			if other not in _adjacency[id]:
				_adjacency[id].append(other)
			if id not in _adjacency[other]:
				_adjacency[other].append(id)


## Os nós de `allocated` (mais o início `start`) que continuam ligados ao início.
static func connected_from(start: String, allocated: Dictionary) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var current: String = queue.pop_back()
		for other: String in neighbors(current):
			if not seen.has(other) and allocated.has(other):
				seen[other] = true
				queue.append(other)
	return seen
