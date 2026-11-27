## The player's stockpiled resources. Electricity isn't stockpiled: it's the
## grid total of the player's buildings, which SkyRegion works out.
class_name PlayerResources
extends Node

signal changed

@export var scrap := 300
## Energized crystals, from Cloud Harvesters and crystal seams. Spent on
## advanced gear (see a catalog entry's "crystals") and company powers.
@export var crystals := 10


func can_afford(amount: int) -> bool:
	return scrap >= amount


## Takes scrap if there's enough. Returns false and changes nothing otherwise.
func spend_scrap(amount: int) -> bool:
	if not can_afford(amount):
		return false
	scrap -= amount
	changed.emit()
	return true


## True if there's enough of both.
func can_pay(scrap_cost: int, crystal_cost := 0) -> bool:
	return scrap >= scrap_cost and crystals >= crystal_cost


## Why a price can't be paid right now, or "".
func shortfall(scrap_cost: int, crystal_cost := 0) -> String:
	if scrap < scrap_cost:
		return "Not enough scrap (%d needed)" % scrap_cost
	if crystals < crystal_cost:
		return "Not enough crystals (%d needed). Harvesters and seams pay them" % crystal_cost
	return ""


## Takes scrap and crystals together, or nothing if either falls short.
func pay(scrap_cost: int, crystal_cost := 0) -> bool:
	if not can_pay(scrap_cost, crystal_cost):
		return false
	scrap -= scrap_cost
	crystals -= crystal_cost
	changed.emit()
	return true


func add_scrap(amount: int) -> void:
	scrap += amount
	changed.emit()


## Takes crystals if there are enough. Returns false and changes nothing otherwise.
func spend_crystals(amount: int) -> bool:
	if crystals < amount:
		return false
	crystals -= amount
	changed.emit()
	return true


func add_crystals(amount: int) -> void:
	crystals += amount
	changed.emit()
