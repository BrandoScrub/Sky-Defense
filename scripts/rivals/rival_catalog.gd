## Every rival corporation as data: where its headquarters is, how it looks,
## whether it bridges, and what it sends each wave. WaveManager, RivalRaids,
## RivalBridges, VesperFleet, the level layout, the top bar and the fog all
## read this, so a new rival is a new entry here rather than edits across
## the game.
##
## A wave entry: {unit, first, base, every, max}. From wave `first` the rival
## sends `base` of that unit, one more every `every` waves, up to `max`.
## `unit` is "ground" for a raiding party (its unit types follow party_mix),
## or an airship kind from VesperFleet.AIRSHIPS.
##
## span_seconds: how long a bridging rival takes per walkway span (30 is
## Ironbell's pace). Extra rivals bridge slower so their raids don't all
## reach you in the same wave.
##
## Nimbus and Aurum are stand-ins: they reuse today's units so that 3 and 4
## rival maps play, until their own storms, buildings and boss ship are
## designed. Only Ironbell and Vesper are on by default.
class_name RivalCatalog
extends RefCounted

## In the order rivals are added to a map (SkyRegion.rival_count picks the
## first N).
const ORDER := ["Ironbell", "Vesper", "Nimbus", "Aurum"]

const RIVALS := {
	"Ironbell": {
		"name": "Ironbell Consolidated", "hq": "Ironbell HQ", "first": "Midway",
		# Colour key in SkyRegion.COLORS for its platforms and top bar card.
		"tile": "rival",
		"glow": [Color(1.0, 0.35, 0.15), "Furnace glare"],
		"bridges": true, "air_lanes": false, "span_seconds": 30,
		"party_mix": ["walker", "walker", "walker", "shieldbearer", "rifleman"],
		"waves": [
			# Walkers creep island by island along the bridge...
			{"unit": "ground", "first": 1, "base": 2, "every": 2, "max": 8},
			# ...while troop carriers fly squads straight at you every wave.
			{"unit": "carrier", "first": 1, "base": 1, "every": 4, "max": 2},
		],
	},
	"Vesper": {
		"name": "Vesper Aeronautics", "hq": "Vesper Aerodrome", "first": "Outpost",
		"tile": "vesper",
		"glow": [Color(0.8, 0.4, 1.0), "Signal lamps"],
		"bridges": false, "air_lanes": true,
		"party_mix": [],
		"waves": [
			{"unit": "bomber", "first": 3, "base": 1, "every": 2, "max": 4},
			{"unit": "gunship", "first": 7, "base": 1, "every": 3, "max": 3},
		],
	},
	"Nimbus": {
		"name": "Nimbus Weatherworks", "hq": "Nimbus Station", "first": "Squall Reach",
		"placeholder": true,
		"tile": "rival",
		"glow": [Color(0.5, 0.75, 1.0), "Thunder rumble"],
		"bridges": true, "air_lanes": false, "span_seconds": 40,
		"party_mix": ["riveteer", "rifleman", "riveteer", "medic"],
		"waves": [
			{"unit": "ground", "first": 2, "base": 2, "every": 2, "max": 7},
		],
	},
	"Aurum": {
		"name": "Aurum Crystalworks", "hq": "Aurum Bastion", "first": "Gilt Reach",
		"placeholder": true,
		"tile": "rival",
		"glow": [Color(1.0, 0.85, 0.35), "Gilded gleam"],
		"bridges": true, "air_lanes": false, "span_seconds": 50,
		"party_mix": ["shieldbearer", "lancer", "shieldbearer", "medic"],
		"waves": [
			{"unit": "ground", "first": 4, "base": 2, "every": 3, "max": 5},
		],
	},
}


static func has(corp: String) -> bool:
	return RIVALS.has(corp)


static func get_data(corp: String) -> Dictionary:
	return RIVALS.get(corp, {})


## How many of `unit` a rival sends in wave `n` (0 if none).
static func count_for(corp: String, unit: String, n: int) -> int:
	for w in get_data(corp).get("waves", []):
		if w.unit == unit:
			if n < w.first:
				return 0
			return mini(w.base + (n - w.first) / w.every, w.max)
	return 0


## The most of `unit` a rival will ever send in one wave.
static func max_for(corp: String, unit: String) -> int:
	for w in get_data(corp).get("waves", []):
		if w.unit == unit:
			return w.max
	return 0


## The first wave a rival sends `unit` in, or -1.
static func first_wave(corp: String, unit: String) -> int:
	for w in get_data(corp).get("waves", []):
		if w.unit == unit:
			return w.first
	return -1


static func hq_of(corp: String) -> String:
	return get_data(corp).get("hq", "")


## The corporation whose headquarters is on `platform_name`, or "".
static func corp_at(platform_name: String) -> String:
	for corp in RIVALS:
		if RIVALS[corp].hq == platform_name:
			return corp
	return ""


static func bridges(corp: String) -> bool:
	return get_data(corp).get("bridges", false)


## The first `count` rivals, as LevelLayout wants them: {corp, hq, first}.
static func layout_rivals(count: int) -> Array:
	var out := []
	for corp in ORDER.slice(0, clampi(count, 1, ORDER.size())):
		out.append({"corp": corp, "hq": RIVALS[corp].hq, "first": RIVALS[corp].first})
	return out
