## Steady income and the power grid's effect on buildings.
##
## - Scrap heaps on platforms you own yield scrap over time (claim the Foundry).
## - Cloud Harvesters slowly form energized crystals.
## - When power demand outstrips supply, the grid browns out and every
##   power-hungry building runs at supply / demand efficiency.
class_name EconomySystem
extends Node

signal grid_changed(efficiency: float)

@export var scrap_per_heap_per_second := 0.5
@export var crystals_per_harvester_per_second := 0.1

@export var region: SkyRegion
@export var resources: PlayerResources

var efficiency := 1.0
var _scrap_carry := 0.0
var _crystal_carry := 0.0


func _process(delta: float) -> void:
	step(delta)


## Advances income and grid state by `delta` seconds. Public for tests.
func step(delta: float) -> void:
	var heaps := 0
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "scrap_heap" and region.platform_owner(t.platform) == "player":
			heaps += 1
	var harvesters := 0
	for b in region.buildings.values():
		if b.type_id == "harvester" and region.platform_owner(b.platform) == "player":
			harvesters += 1

	_scrap_carry += heaps * scrap_per_heap_per_second * delta
	_crystal_carry += harvesters * crystals_per_harvester_per_second * delta
	if _scrap_carry >= 1.0:
		var whole := int(_scrap_carry)
		_scrap_carry -= whole
		resources.add_scrap(whole)
	if _crystal_carry >= 1.0:
		var whole_c := int(_crystal_carry)
		_crystal_carry -= whole_c
		resources.add_crystals(whole_c)

	var now := region.grid_efficiency()
	for b in region.buildings.values():
		b.set_efficiency(now)
	if not is_equal_approx(now, efficiency):
		efficiency = now
		grid_changed.emit(efficiency)
