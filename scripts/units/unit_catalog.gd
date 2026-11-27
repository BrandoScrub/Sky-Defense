## Stats for every kind of ground unit, in one place. Every faction can field
## the same base units; a faction only changes the colour (and later, its own
## upgrades). Build one with UnitCatalog.make("rifleman", "rival").
##
## The roster, kept small so each unit has one clear job:
##   Riveteer     - cheap all-rounder. Claims platforms, fights at short range.
##   Shieldbearer - riot shield. Tough melee brawler; its shield soaks up enemy
##                  shots aimed at it or at allies standing behind it.
##   Rifleman     - bolt gun. Long range and hard-hitting, but fragile.
##   Lancer       - anti-armor. Slow, heavy arc-lance shots that punch through
##                  walkers, shields and buildings.
##   Engineer     - support. Patches up wounded allies, repairs your
##                  buildings and wrecks enemy ones.
class_name UnitCatalog
extends RefCounted

## Stats a unit doesn't set fall back to these (they match Unit's defaults).
const DEFAULTS := {
	"name": "Unit",
	"cost": 30,
	"train_seconds": 5.0,
	"hp": 60.0,
	"damage": 8.0,
	"range": 4.0,
	"cooldown": 1.0,
	"aggro": 9.0,
	"speed": 6.0,
	"weight": 1,
	"footprint": 0.6,
	"bounty": 15,
	"armored": false,
	# Share of a projectile's damage a shield stops (0 = no shield).
	"shield": 0.0,
	# Damage multipliers against armored units and against buildings / HQs.
	"vs_armor": 1.0,
	"vs_buildings": 1.0,
	# Engineer: hit points restored per second to one wounded ally in range.
	"heal": 0.0,
	# Engineer: hit points restored per second to one damaged building in range.
	"repair": 0.0,
	"hits_air": false,
	# Heavy hits shove the target back and delay its next attack.
	"heavy": false,
	# How fast its shots fly, units per second.
	"shell_speed": 50.0,
	"color": Color(0.42, 0.5, 0.6),
	"blurb": "",
}

const UNITS := {
	"riveteer": {
		"name": "Riveteer",
		"cost": 30,
		"hp": 75.0,
		"damage": 9.0,
		"blurb": "Your basic soldier. Cheap, and good at claiming platforms by standing on them. Fights at short range. Can't hit aircraft.",
	},
	"shieldbearer": {
		"name": "Shieldbearer",
		"cost": 50,
		"train_seconds": 6.0,
		"hp": 140.0,
		"damage": 9.0,
		"range": 1.8,
		"cooldown": 1.0,
		"speed": 4.8,
		"weight": 2,
		"footprint": 0.7,
		"shield": 0.75,
		"color": Color(0.32, 0.36, 0.44),
		"blurb": "Riot trooper with a riveted tower shield. Strong in melee. The shield faces forward: it stops most of any shot from the front, and catches shots flying past at allies behind. Braced, it doesn't flinch from heavy hits. Shots from the side or back get through, so watch the flanks.",
	},
	"rifleman": {
		"name": "Rifleman",
		"cost": 40,
		"hp": 45.0,
		"damage": 13.0,
		"range": 7.5,
		"cooldown": 1.4,
		"aggro": 11.0,
		"shell_speed": 70.0,
		"color": Color(0.45, 0.42, 0.3),
		# The only ground troop that can shoot at aircraft, so a wave of
		# airships can't drag on forever with no flak around.
		"hits_air": true,
		"blurb": "Carries a bolt gun. Outranges walkers and hits hard, and can take shots at airships, but goes down fast. Keep them behind Shieldbearers.",
	},
	"lancer": {
		"name": "Lancer",
		"cost": 60,
		# Its arc lance is Hum-charged: costs crystals as well as scrap.
		"crystals": 5,
		"train_seconds": 8.0,
		"hp": 80.0,
		"damage": 30.0,
		"range": 5.5,
		"cooldown": 2.6,
		"speed": 4.5,
		"weight": 2,
		"vs_armor": 2.5,
		"vs_buildings": 1.5,
		"heavy": true,
		"shell_speed": 26.0,
		"color": Color(0.35, 0.45, 0.55),
		"blurb": "Anti-armor trooper with a Hum-charged arc lance. Slow, heavy bolts that do over double damage to armored walkers and knock them back. Its bolts burn through shields too.",
	},
	"engineer": {
		"name": "Engineer",
		"cost": 40,
		"train_seconds": 6.0,
		"hp": 65.0,
		"damage": 6.0,
		"range": 4.0,
		"cooldown": 1.0,
		"vs_buildings": 4.0,
		"heal": 6.0,
		"repair": 8.0,
		"color": Color(0.55, 0.4, 0.25),
		"blurb": "Field engineer with a wrench, a tonic tank and a satchel of charges. Patches up the most wounded ally nearby first, repairs your buildings when nobody needs patching, and does four times damage to enemy buildings.",
	},
	# Ironbell's heavy walker: an armored rival-only unit.
	"walker": {
		"name": "Ironbell Walker",
		"cost": 0,
		"hp": 90.0,
		"damage": 10.0,
		# Stomps and swings at close range, so riot shields don't stop it.
		"range": 2.2,
		"cooldown": 1.2,
		"speed": 4.0,
		"weight": 3,
		"footprint": 0.75,
		"armored": true,
		"heavy": true,
		"color": Color(0.55, 0.18, 0.15),
		"blurb": "Ironbell's armored walker. Marches down walkways toward your Hub, claiming platforms and smashing buildings on the way. Its stomps knock light troops back; braced Shieldbearers hold it, and Lancers make short work of it.",
	},
}

## Units the player can train, in Army tab order.
const TRAINABLE := ["riveteer", "shieldbearer", "rifleman", "lancer", "engineer"]

## Rival faction colours, mixed into a unit's own colour so you can tell sides apart.
const FACTION_TINT := {
	"rival": Color(0.6, 0.15, 0.12),
}


## A unit's full stats, with defaults filled in.
static func get_data(type_id: String) -> Dictionary:
	var data := DEFAULTS.duplicate()
	data.merge(UNITS.get(type_id, {}), true)
	data["id"] = type_id
	return data


static func has_unit(type_id: String) -> bool:
	return UNITS.has(type_id)


## Makes a unit of a type for a faction ("player" or "rival"). Add it to the
## scene tree yourself.
static func make(type_id: String, faction := "player") -> Unit:
	var u := Unit.new()
	apply(u, type_id, faction)
	return u


## Sets a unit's stats from the catalog. Call before adding it to the tree.
static func apply(u: Unit, type_id: String, faction := "player") -> void:
	var d := get_data(type_id)
	u.unit_type = type_id
	u.faction = faction
	u.display_name = d.name
	u.max_hp = d.hp
	u.hp = d.hp
	u.damage = d.damage
	u.attack_range = d.range
	u.attack_cooldown = d.cooldown
	u.aggro_range = maxf(d.aggro, d.range + 2.0)
	u.move_speed = d.speed
	u.weight = d.weight
	u.footprint = d.footprint
	u.bounty = d.bounty if faction == "rival" else 0
	u.armored = d.armored
	u.shield = d.shield
	u.vs_armor = d.vs_armor
	u.vs_buildings = d.vs_buildings
	u.heal_power = d.heal
	u.repair_power = d.repair
	u.hits_air = d.hits_air
	u.heavy_hits = d.heavy
	u.shell_speed = d.shell_speed
	var color: Color = d.color
	if FACTION_TINT.has(faction) and type_id != "walker":
		color = color.lerp(FACTION_TINT[faction], 0.55)
	u.body_color = color
