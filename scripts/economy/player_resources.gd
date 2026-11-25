## The player's stockpiled resources. Electricity isn't stockpiled: it's the
## grid total of the player's buildings, which SkyRegion works out.
class_name PlayerResources
extends Node

signal changed

@export var scrap := 200
## Formed by Cloud Harvesters; spent on advanced upgrades in a later milestone.
@export var crystals := 0


func can_afford(amount: int) -> bool:
	return scrap >= amount


## Takes scrap if there's enough. Returns false and changes nothing otherwise.
func spend_scrap(amount: int) -> bool:
	if not can_afford(amount):
		return false
	scrap -= amount
	changed.emit()
	return true


func add_scrap(amount: int) -> void:
	scrap += amount
	changed.emit()


func add_crystals(amount: int) -> void:
	crystals += amount
	changed.emit()
