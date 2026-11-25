## Every building the player can place. Numbers are first guesses from the
## design doc and are meant to be tuned in playtests.
class_name BuildingCatalog
extends RefCounted

## Fraction of the cost returned when a building is demolished.
const REFUND_RATIO := 0.75

## power: positive supplies electricity, negative draws it.
## tiles: tile types the building may stand on.
const BUILDINGS := {
	"dynamo": {
		"name": "Dynamo Generator", "cost": 40, "power": 10, "weight": 3,
		"tiles": ["deck", "generator_socket"], "shape": "generator",
		"color": Color(0.95, 0.78, 0.25),
		# Generators on a generator socket produce more.
		"power_on_socket": 15,
		"hp": 120.0,
	},
	"harvester": {
		"name": "Cloud Harvester", "cost": 80, "power": 30, "weight": 2,
		"tiles": ["harvester_anchor"], "shape": "harvester",
		"color": Color(0.35, 0.6, 1.0),
		"hp": 80.0,
	},
	"rivet_turret": {
		"name": "Rivet Turret", "cost": 30, "power": -2, "weight": 2,
		"tiles": ["deck"], "shape": "turret",
		"color": Color(0.6, 0.62, 0.66),
		"hp": 150.0,
		# "air": damage against aircraft (no "air" key = can't hit aircraft).
		"attack": {"damage": 15.0, "range": 10.0, "cooldown": 0.8, "air": 7.0},
	},
	"flak_battery": {
		"name": "Flak Battery", "cost": 50, "power": -3, "weight": 3,
		"tiles": ["deck"], "shape": "flak",
		"color": Color(0.45, 0.55, 0.4),
		"hp": 150.0,
		# Built for aircraft; against ground units it fires fast but weak.
		"attack": {"damage": 5.0, "range": 12.0, "cooldown": 0.35, "air": 22.0},
	},
	"arc_coil": {
		"name": "Arc Coil", "cost": 70, "power": -8, "weight": 4,
		"tiles": ["deck"], "shape": "coil",
		"color": Color(0.55, 0.45, 0.95),
		"hp": 130.0,
		# Chain lightning: hits up to 3 enemies near the first target.
		"attack": {"damage": 16.0, "range": 8.0, "cooldown": 1.5, "chain": 3},
	},
}



static func get_data(type_id: String) -> Dictionary:
	return BUILDINGS[type_id]


static func refund_for(type_id: String) -> int:
	return int(floor(BUILDINGS[type_id].cost * REFUND_RATIO))


## Power a building of this type gives (+) or takes (-) on a given tile type.
static func power_for(type_id: String, tile_type: String) -> int:
	var data: Dictionary = BUILDINGS[type_id]
	if tile_type == "generator_socket" and data.has("power_on_socket"):
		return data.power_on_socket
	return data.power
