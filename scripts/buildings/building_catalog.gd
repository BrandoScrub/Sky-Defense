## Every building the player can place. Numbers are first guesses from the
## design doc and are meant to be tuned in playtests.
class_name BuildingCatalog
extends RefCounted

## Fraction of the cost (scrap and crystals) returned when a building is
## demolished. Half, so every build is a commitment.
const REFUND_RATIO := 0.5

## short: optional shorter name for the build menu button.
## crystals: optional crystal price on top of the scrap cost (advanced gear).
## power: positive supplies electricity, negative draws it.
## tiles: tile types the building may stand on.
## role: "ground", "flak" or "hangar" for defenses (see ROLES); none for
## economy buildings.
## Defense roles, for the build menu and info card.
const ROLES := {
	"ground": "Ground defense: can't hit aircraft, strengthens your units nearby",
	"flak": "Flak: shoots only aircraft and airships",
	"hangar": "Hangar: launches defensive drones and builds patrol airships",
}

const BUILDINGS := {
	"dynamo": {
		"name": "Dynamo Generator", "short": "Dynamo", "cost": 40, "power": 8, "weight": 3,
		"tiles": ["deck", "generator_socket"], "shape": "generator",
		"color": Color(0.95, 0.78, 0.25),
		# Generators on a generator socket produce more.
		"power_on_socket": 15,
		"hp": 120.0,
	},
	"harvester": {
		"name": "Cloud Harvester", "short": "Harvester", "cost": 80, "power": 15, "weight": 2,
		"tiles": ["harvester_anchor"], "shape": "harvester",
		"color": Color(0.35, 0.6, 1.0),
		"hp": 80.0,
	},
	# Extra lift under a platform: it can carry more weight ("capacity").
	"lift_engine": {
		"name": "Lift Engine", "cost": 60, "power": -3, "weight": 0,
		"tiles": ["deck"], "shape": "lift",
		"color": Color(0.45, 0.6, 0.7),
		"hp": 120.0,
		"capacity": 10,
	},
	# --- Ground defenses: modest guns that can't hit aircraft, but make your
	# own ground units nearby stronger. "aura" lists what they give allies
	# within "radius": damage_mult (more damage), cooldown_mult (below 1 =
	# faster fire), armor (fraction of damage blocked) and heal (hp/second).
	"rivet_turret": {
		"name": "Rivet Turret", "cost": 50, "power": -3, "weight": 2,
		"tiles": ["deck"], "shape": "turret", "role": "ground",
		"color": Color(0.6, 0.62, 0.66),
		"hp": 150.0,
		"attack": {"damage": 13.0, "range": 10.0, "cooldown": 0.8},
		# Its plating gives cover to units fighting beside it.
		"aura": {"radius": 5.0, "armor": 0.15},
	},
	"arc_coil": {
		"name": "Arc Coil", "cost": 70, "crystals": 10, "power": -8, "weight": 4,
		"tiles": ["deck"], "shape": "coil", "role": "ground",
		"color": Color(0.55, 0.45, 0.95),
		"hp": 130.0,
		# Chain lightning: hits up to 3 enemies near the first target.
		"attack": {"damage": 16.0, "range": 8.0, "cooldown": 1.5, "chain": 3},
	},
	"rally_horn": {
		"name": "Rally Horn", "cost": 45, "power": -3, "weight": 2,
		"tiles": ["deck"], "shape": "horn", "role": "ground",
		"color": Color(0.85, 0.6, 0.25),
		"hp": 110.0,
		"attack": {"damage": 4.0, "range": 7.0, "cooldown": 1.0},
		"aura": {"radius": 7.0, "damage_mult": 1.35, "cooldown_mult": 0.8},
	},
	# --- Flak: anti-air only. "air_only" towers ignore walkers and buildings;
	# "air" is their damage against aircraft and airships.
	"flak_battery": {
		"name": "Flak Battery", "cost": 50, "power": -3, "weight": 3,
		"tiles": ["deck"], "shape": "flak", "role": "flak",
		"color": Color(0.45, 0.55, 0.4),
		"hp": 150.0,
		# Bursting shells: other aircraft within "splash" of the hit take part
		# of it too. Shreds light craft and tight formations; heavy hulls
		# shrug off some of it.
		"attack": {"damage": 0.0, "range": 12.0, "cooldown": 0.35, "air": 22.0, "air_only": true,
			"splash": 2.5, "vs_heavy": 0.85},
	},
	"skyhook_cannon": {
		"name": "Skyhook Gun", "cost": 75, "crystals": 10, "power": -6, "weight": 4,
		"tiles": ["deck"], "shape": "skyhook", "role": "flak",
		"color": Color(0.5, 0.42, 0.35),
		"hp": 140.0,
		# Slow, long-range harpoon gun for big airships: double damage to heavy
		# hulls, but it struggles to track small, light craft.
		"attack": {"damage": 0.0, "range": 16.0, "cooldown": 2.8, "air": 70.0, "air_only": true,
			"vs_heavy": 2.0, "vs_light": 0.5},
	},
	# --- Industry: engines that let you move a turbine island (IslandSteering).
	"turbine_engine": {
		"name": "Turbine Engine", "short": "Turbine", "cost": 60, "power": -3, "weight": 3,
		"tiles": ["deck"], "shape": "engine",
		"color": Color(0.72, 0.52, 0.26),
		"hp": 140.0,
		# Only fits on turbine islands; 4 of them let you steer the island.
		"island_style": "turbine",
	},
	# The Airship Hangar keeps a few defensive drones in the air ("hangar":
	# they fly out to anything that comes within "leash", then return, and
	# lost drones are rebuilt) and builds your patrol airships (AirPatrols),
	# which fly a loop of Mooring Masts.
	"airship_hangar": {
		"name": "Airship Hangar", "short": "Hangar", "cost": 100, "crystals": 15, "power": -8, "weight": 5,
		"tiles": ["deck"], "shape": "airship_hangar", "role": "hangar",
		"color": Color(0.5, 0.42, 0.33),
		"hp": 220.0,
		"hangar": {"drones": 2, "rebuild": 8.0, "leash": 13.0},
	},
	# A patrol point: airships refuel and spot twice as far near it, and it
	# sees far through the storm clouds. Ships only hunt within reach of a
	# hangar or a mast, so where you put masts is where the sky is covered.
	"mooring_mast": {
		"name": "Mooring Mast", "cost": 45, "power": -2, "weight": 2,
		"tiles": ["deck"], "shape": "mast",
		"color": Color(0.7, 0.62, 0.4),
		"hp": 100.0,
	},
}


static func get_data(type_id: String) -> Dictionary:
	return BUILDINGS[type_id]


static func refund_for(type_id: String) -> int:
	return int(floor(BUILDINGS[type_id].cost * REFUND_RATIO))


static func crystals_of(type_id: String) -> int:
	return BUILDINGS[type_id].get("crystals", 0)


static func crystal_refund_for(type_id: String) -> int:
	return int(floor(crystals_of(type_id) * REFUND_RATIO))


## Power a building of this type gives (+) or takes (-) on a given tile type.
static func power_for(type_id: String, tile_type: String) -> int:
	var data: Dictionary = BUILDINGS[type_id]
	if tile_type == "generator_socket" and data.has("power_on_socket"):
		return data.power_on_socket
	return data.power


## The building's defense role ("ground", "flak", "hangar"), or "".
static func role_of(type_id: String) -> String:
	return BUILDINGS[type_id].get("role", "")
