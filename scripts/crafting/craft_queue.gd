class_name CraftQueue
extends Node
## Fila de fabricação do jogador (GDD 8.3). Ao enfileirar, os ingredientes saem do
## inventário na hora; cada unidade leva o "time" da receita. Receitas de estação
## (fogueira, bancada...) só avançam com o jogador perto de uma estação daquele
## tipo; longe, a fila fica pausada. Cancelar devolve os ingredientes do que falta.
## Roda na máquina do dono do inventário (local, como o próprio inventário).

signal changed

const MAX_JOBS := 8

## [{ "recipe": Dictionary, "left": int, "progress": float }, ...]
var jobs: Array[Dictionary] = []

var _player: Node3D
var _inventory: Inventory


func _ready() -> void:
	_player = get_parent() as Node3D
	_inventory = _player.get_node(^"Inventory")


## Enfileira `times` unidades da receita. Retorna false se faltar ingrediente ou a fila estiver cheia.
func enqueue(recipe: Dictionary, times := 1) -> bool:
	if times <= 0 or jobs.size() >= MAX_JOBS or not Crafting.can_craft(_inventory, recipe, times):
		return false
	Crafting.take_ingredients(_inventory, recipe, times)
	jobs.append({"recipe": recipe, "left": times, "progress": 0.0})
	changed.emit()
	return true


func cancel(index: int) -> void:
	if index < 0 or index >= jobs.size():
		return
	var job := jobs[index]
	jobs.remove_at(index)
	Crafting.give_ingredients(_inventory, job.recipe, int(job.left))
	changed.emit()


## A receita da frente pode avançar agora? (estação por perto)
func is_station_ok(recipe: Dictionary) -> bool:
	var station := str(recipe.get("station", "hands"))
	return station == "hands" or not Structures.stations_near(station, _player.global_position, CraftingStation.USE_RANGE).is_empty()


func _process(delta: float) -> void:
	if jobs.is_empty():
		return
	var job := jobs[0]
	if not is_station_ok(job.recipe):
		return  # pausado: longe da estação
	var prog := Progression.of(get_parent())
	var unit_time := maxf(float(job.recipe.get("time", 2.0)) * (prog.mult("craft_time") if prog else 1.0), 0.1)
	job.progress = float(job.progress) + delta / unit_time
	if job.progress >= 1.0:
		job.progress = 0.0
		job.left = int(job.left) - 1
		Crafting.give_result(_inventory, job.recipe, 1)
		if prog:
			prog.gain("crafting", float(job.recipe.get("time", 2.0)))
		if int(job.left) <= 0:
			jobs.pop_front()
	changed.emit()
