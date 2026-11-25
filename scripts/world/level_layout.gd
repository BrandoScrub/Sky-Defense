## Layout of the prototype sky region, in hex coordinates.
##
## Everything here is placeholder data meant to give later systems (building,
## resources, weight, rivals, ferries) somewhere to live. Edit it freely: the
## region is rebuilt from these tables when the scene loads.
class_name LevelLayout
extends RefCounted

## Centre-to-corner size of one hex tile, in world units.
const TILE_SIZE := 2.0

## Platforms. `radius` is in hex rings (1 = 7 tiles, 2 = 19, 3 = 37).
## `capacity` is the weight limit for the weight system.
## Features are [type, where]: `where` is an offset from the centre (Vector2i),
## or the name of a platform or cloud to put it on the rim facing that thing.
const PLATFORMS := [
	{
		"name": "Hub", "kind": "hub", "center": Vector2i(0, 0), "radius": 3, "capacity": 40,
		"features": [
			["core", Vector2i(0, 0)],
			["generator_socket", Vector2i(-2, 1)],
			["generator_socket", Vector2i(2, -1)],
			["dock", "Crystal Spire"],
			["harvester_anchor", "North Storm"],
		],
	},
	{
		"name": "Foundry", "kind": "neutral", "center": Vector2i(-8, 3), "radius": 2, "capacity": 20,
		"features": [
			["scrap_heap", Vector2i(-1, 0)],
			["scrap_heap", Vector2i(0, 1)],
		],
	},
	{
		"name": "Generator Rig", "kind": "neutral", "center": Vector2i(5, 4), "radius": 1, "capacity": 10,
		"features": [
			["generator_socket", Vector2i(0, 0)],
		],
	},
	{
		"name": "Midway", "kind": "neutral", "center": Vector2i(6, -9), "radius": 2, "capacity": 20,
		"features": [
			["harvester_anchor", "North Storm"],
			["harvester_anchor", "East Storm"],
		],
	},
	{
		"name": "Outpost", "kind": "neutral", "center": Vector2i(12, -6), "radius": 1, "capacity": 10,
		"features": [],
	},
	{
		"name": "Crystal Spire", "kind": "neutral", "center": Vector2i(-11, -3), "radius": 2, "capacity": 20,
		"features": [
			["crystal_seam", Vector2i(0, 0)],
			["crystal_seam", Vector2i(-1, -1)],
			["dock", "Hub"],
		],
	},
	{
		"name": "Ironbell HQ", "kind": "rival", "corp": "Ironbell", "center": Vector2i(10, -17), "radius": 3, "capacity": 40,
		"features": [
			["rival_core", Vector2i(0, 0)],
			["spawn", "Midway"],
			["harvester_anchor", "East Storm"],
		],
	},
	{
		# Vesper Aeronautics' airfield. Its airships fly the air lanes; the only
		# way in on foot is the long walkway from the Outpost.
		"name": "Vesper Aerodrome", "kind": "rival", "corp": "Vesper", "center": Vector2i(17, -1), "radius": 2, "capacity": 30,
		"features": [
			["rival_core", Vector2i(0, 0)],
		],
	},
]

## Metal walkways, built as a line of hex plates from rim to rim.
const WALKWAYS := [
	["Hub", "Midway"],
	["Hub", "Foundry"],
	["Hub", "Generator Rig"],
	["Midway", "Ironbell HQ"],
	["Midway", "Outpost"],
	["Outpost", "Vesper Aerodrome"],
]

## Airship ferry routes between docks. Not walkable: units ride the ferry.
const FERRY_ROUTES := [
	["Hub", "Crystal Spire"],
]

## Storm clouds float above the deck and can be harvested from anchors.
const CLOUDS := [
	{"name": "North Storm", "center": Vector2i(-1, -6), "radius": 1},
	{"name": "East Storm", "center": Vector2i(3, -13), "radius": 1},
]

## Rival air routes, drawn high above the deck.
const AIR_LANES := [
	["Vesper Aerodrome", "Hub"],
	["Vesper Aerodrome", "Generator Rig"],
]
