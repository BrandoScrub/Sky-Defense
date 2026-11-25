## The fight over storm clouds. Each cloud is tapped by Cloud Harvesters on
## the harvester anchors that face it. Whoever has more harvesters on a
## cloud's anchors controls it:
##
## - Player control: the storm feeds the grid (+`power_per_storm`).
## - Ironbell control: lightning strikes your buildings and units near the
##   cloud, and Ironbell's walkers come out tougher.
##
## Ironbell also builds its own harvesters on free anchors of platforms it
## owns, so leaving Midway to them hands them both storms.
class_name StormSystem
extends Node

signal control_changed(cloud: String, controller: String)
signal rival_harvester_built(platform_name: String)

@export var region: SkyRegion
@export var combat: CombatSystem
@export var waves: WaveManager

@export var power_per_storm := 15
@export var strike_interval := 7.0
@export var strike_damage := 35.0
@export var strike_range := 14.0
@export var wave_hp_per_storm := 0.15
## Ironbell waits this long before building its first harvester, then checks
## again on this interval.
@export var rival_first_build := 50.0
@export var rival_build_interval := 30.0

## cloud name -> "player", "rival" or ""
var control := {}
var _strike_timer := 0.0
var _build_timer := 0.0
var _labels := {}


func _ready() -> void:
	_strike_timer = strike_interval
	_build_timer = rival_first_build
	for cloud in region.clouds:
		control[cloud] = ""
		var label := Label3D.new()
		label.name = "StormLabel_" + cloud.replace(" ", "")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 52
		label.outline_size = 10
		label.pixel_size = 0.02
		label.position = region.hex_center(region.clouds[cloud].center) + Vector3.UP * (SkyRegion.CLOUD_HEIGHT + 3.0)
		region.add_child(label)
		_labels[cloud] = label
	refresh()


func _process(delta: float) -> void:
	step(delta)


## Advances storms by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	refresh()
	_build_timer -= delta
	if _build_timer <= 0.0:
		_build_timer = rival_build_interval
		rival_build()
	_strike_timer -= delta
	if _strike_timer <= 0.0:
		_strike_timer = strike_interval
		for cloud in control:
			if control[cloud] == "rival":
				strike(cloud)


## Harvesters by faction on the anchors facing a cloud.
func harvesters_on(cloud: String) -> Dictionary:
	var count := {"player": 0, "rival": 0}
	for b in region.buildings.values():
		if b.type_id == "harvester" and b.is_alive() and region.get_tile(b.hex).get("target", "") == cloud:
			count[b.faction] += 1
	return count


## Recounts control of every cloud and applies its effects.
func refresh() -> void:
	var player_storms := 0
	var rival_storms := 0
	for cloud in control:
		var count := harvesters_on(cloud)
		var now := ""
		if count.player > count.rival:
			now = "player"
		elif count.rival > count.player:
			now = "rival"
		if now == "player":
			player_storms += 1
		elif now == "rival":
			rival_storms += 1
		if now != control[cloud]:
			control[cloud] = now
			control_changed.emit(cloud, now)
		_label(cloud, now, count)
	region.storm_bonus = player_storms * power_per_storm
	if waves:
		waves.hp_bonus = rival_storms * wave_hp_per_storm


## Lightning from an Ironbell-held cloud hits the nearest player building or
## unit in range. Returns what it hit, or null.
func strike(cloud: String):
	var at := region.hex_center(region.clouds[cloud].center)
	var target = combat.nearest_enemy(at, "rival", strike_range) if combat else null
	if target == null:
		return null
	var bolt: Node3D = _labels[cloud]
	combat._hit(bolt, target, strike_damage, Color(0.75, 0.85, 1.0))
	return target


## Ironbell puts a harvester on one free anchor of a platform it owns.
## Returns the platform name, or "" if there was nowhere to build.
func rival_build() -> String:
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type != "harvester_anchor" or region.buildings.has(hex):
			continue
		if region.platform_owner(t.platform) != "rival":
			continue
		var b := Building.new().setup("harvester")
		region.place_building(b, hex)
		b.faction = "rival"
		for mat in b._materials:
			mat.albedo_color = mat.albedo_color.lerp(Color(0.75, 0.2, 0.15), 0.6)
		rival_harvester_built.emit(t.platform)
		return t.platform
	return ""


func _label(cloud: String, now: String, count: Dictionary) -> void:
	var label: Label3D = _labels[cloud]
	match now:
		"player":
			label.text = "%s\nYours: +%d power" % [cloud, power_per_storm]
			label.modulate = Color(0.55, 0.85, 1.0)
		"rival":
			label.text = "%s\nIronbell's: lightning!" % cloud
			label.modulate = Color(1.0, 0.45, 0.35)
		_:
			label.text = "%s\nHarvesters %d v %d" % [cloud, count.player, count.rival]
			label.modulate = Color(0.85, 0.85, 0.85)
