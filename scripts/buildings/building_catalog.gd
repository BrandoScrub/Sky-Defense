## Every building the player can place. Numbers are first guesses from the
## design doc and are meant to be tuned in playtests.
class_name BuildingCatalog
extends RefCounted

## Fraction of the cost returned when a building is demolished.
const REFUND_RATIO := 0.75

## power: positive supplies electricity, negative draws it.
## tiles: tile types the building may stand on.
## role: "ground", "flak" or "hangar" for defenses (see ROLES); none for
## economy buildings.
## Defense roles, for the build menu and info card.
const ROLES := {
	"ground": "Ground defense: can't hit aircraft, strengthens your units nearby",
	"flak": "Flak: shoots only aircraft and airships",
	"hangar": "Hangar: launches defensive drones",
}

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
	# --- Ground defenses: modest guns that can't hit aircraft, but make your
	# own ground units nearby stronger. "aura" lists what they give allies
	# within "radius": damage_mult (more damage), cooldown_mult (below 1 =
	# faster fire), armor (fraction of damage blocked) and heal (hp/second).
	"rivet_turret": {
		"name": "Rivet Turret", "cost": 30, "power": -2, "weight": 2,
		"tiles": ["deck"], "shape": "turret", "role": "ground",
		"color": Color(0.6, 0.62, 0.66),
		"hp": 150.0,
		"attack": {"damage": 13.0, "range": 10.0, "cooldown": 0.8},
		# Its plating gives cover to units fighting beside it.
		"aura": {"radius": 5.0, "armor": 0.15},
	},
	"arc_coil": {
		"name": "Arc Coil", "cost": 70, "power": -8, "weight": 4,
		"tiles": ["deck"], "shape": "coil", "role": "ground",
		"color": Color(0.55, 0.45, 0.95),
		"hp": 130.0,
		# Chain lightning: hits up to 3 enemies near the first target.
		"attack": {"damage": 16.0, "range": 8.0, "cooldown": 1.5, "chain": 3},
	},
	"rally_horn": {
		"name": "Rally Horn", "cost": 45, "power": -2, "weight": 2,
		"tiles": ["deck"], "shape": "horn", "role": "ground",
		"color": Color(0.85, 0.6, 0.25),
		"hp": 110.0,
		"attack": {"damage": 4.0, "range": 7.0, "cooldown": 1.0},
		"aura": {"radius": 7.0, "damage_mult": 1.35, "cooldown_mult": 0.8},
	},
	"mending_post": {
		"name": "Mending Post", "cost": 55, "power": -4, "weight": 3,
		"tiles": ["deck"], "shape": "mender", "role": "ground",
		"color": Color(0.4, 0.75, 0.55),
		"hp": 110.0,
		"attack": {"damage": 4.0, "range": 6.0, "cooldown": 1.2},
		"aura": {"radius": 6.0, "heal": 5.0, "armor": 0.1},
	},
	# --- Flak: anti-air only. "air_only" towers ignore walkers and buildings;
	# "air" is their damage against aircraft and airships.
	"flak_battery": {
		"name": "Flak Battery", "cost": 50, "power": -3, "weight": 3,
		"tiles": ["deck"], "shape": "flak", "role": "flak",
		"color": Color(0.45, 0.55, 0.4),
		"hp": 150.0,
		"attack": {"damage": 0.0, "range": 12.0, "cooldown": 0.35, "air": 22.0, "air_only": true},
	},
	"skyhook_cannon": {
		"name": "Skyhook Gun", "cost": 75, "power": -5, "weight": 4,
		"tiles": ["deck"], "shape": "skyhook", "role": "flak",
		"color": Color(0.5, 0.42, 0.35),
		"hp": 140.0,
		# Slow, long-range harpoon gun for big airships.
		"attack": {"damage": 0.0, "range": 16.0, "cooldown": 2.8, "air": 70.0, "air_only": true},
	},
	# --- Hangars: launch defensive drones that fly out to anything that comes
	# within "leash" of the hangar, then return. Lost drones are rebuilt.
	# --- Ships: engines that let you move a turbine island (IslandSteering).
	"turbine_engine": {
		"name": "Turbine Engine", "cost": 60, "power": -3, "weight": 3,
		"tiles": ["deck"], "shape": "engine",
		"color": Color(0.72, 0.52, 0.26),
		"hp": 140.0,
		# Only fits on turbine islands; 4 of them let you steer the island.
		"island_style": "turbine",
	},
	"drone_hangar": {
		"name": "Drone Hangar", "cost": 90, "power": -6, "weight": 4,
		"tiles": ["deck"], "shape": "hangar", "role": "hangar",
		"color": Color(0.55, 0.5, 0.42),
		"hp": 170.0,
		"hangar": {"drones": 3, "rebuild": 8.0, "leash": 13.0},
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


## The building's defense role ("ground", "flak", "hangar"), or "".
static func role_of(type_id: String) -> String:
	return BUILDINGS[type_id].get("role", "")
