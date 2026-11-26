## Build phase, then wave phase, like the reference game. Each build phase
## runs on a timer (Space ends it early). Each wave sends a bigger Ironbell party
## and, from wave 3, a flight of Vesper bombers; once every attacker is
## destroyed the next build phase starts. A rival whose headquarters falls
## stops attacking. Destroying both wins; losing the Hub's headquarters loses.
class_name WaveManager
extends Node

signal phase_changed(phase: String, wave: int)
signal game_over(won: bool)
signal rival_defeated(platform: String)

const BUILD := "build"
const WAVE := "wave"
const OVER := "over"

@export var first_build_seconds := 45.0
@export var build_seconds := 25.0
@export var base_party := 2
@export var max_party := 10
## Walkers in later waves get this much extra health per wave.
@export var hp_growth_per_wave := 0.08

@export var first_air_wave := 3
@export var max_flight := 4
## Ironbell troop carriers: from this wave, one more every 3 waves.
@export var first_carrier_wave := 5
@export var max_carriers := 3
## Vesper gunships escort the bombers: from this wave, one more every 3 waves.
@export var first_gunship_wave := 7
@export var max_gunships := 3

@export var raids: RivalRaids
## Optional: Vesper's bombers join waves when set.
@export var fleet: VesperFleet
@export var combat: CombatSystem

var phase := BUILD
## Number of the next (or current) wave, from 1.
var wave := 1
var time_left := 0.0
var won := false
var _wave_units: Array[Unit] = []
## corp -> the units it sent in the current wave.
var _wave_units_by_corp := {}


func _ready() -> void:
	time_left = first_build_seconds
	combat.headquarters_destroyed.connect(_on_headquarters_destroyed)
	if fleet:
		fleet.troops_dropped.connect(func(c, _p, units): add_wave_units(units, c))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_wave_early") and phase == BUILD:
		start_wave()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	match phase:
		BUILD:
			time_left -= delta
			if time_left <= 0.0:
				start_wave()
		WAVE:
			if remaining() == 0:
				wave += 1
				phase = BUILD
				time_left = build_seconds
				phase_changed.emit(phase, wave)


## Extra walker toughness, e.g. from storms Ironbell controls (StormSystem).
var hp_bonus := 0.0


func party_size_for(n: int) -> int:
	return mini(base_party + n, max_party)


## Vesper bombers in wave `n`: none before `first_air_wave`, then one more
## every two waves.
func flight_size_for(n: int) -> int:
	if n < first_air_wave:
		return 0
	return mini(1 + (n - first_air_wave) / 2, max_flight)


## Ironbell troop carriers in wave `n`.
func carriers_for(n: int) -> int:
	if n < first_carrier_wave:
		return 0
	return mini(1 + (n - first_carrier_wave) / 3, max_carriers)


## Vesper gunships in wave `n`.
func gunships_for(n: int) -> int:
	if n < first_gunship_wave:
		return 0
	return mini(1 + (n - first_gunship_wave) / 3, max_gunships)


## What wave `n` sends, for the wave preview and for start_wave. One entry
## per kind of unit: {corp, hq, unit (UnitCatalog or airship kind), name,
## count, air}. A troop carrier entry also has `carries`: the unit types of
## the squad each one drops. Rivals whose headquarters has fallen send nothing.
func composition_for(n: int) -> Array:
	var out := []
	if raids and _hq_alive(raids.rival_platform):
		var by_type := {}
		var order := []
		for i in party_size_for(n):
			var t := raids.unit_for_slot(i)
			if not by_type.has(t):
				by_type[t] = 0
				order.append(t)
			by_type[t] += 1
		for t in order:
			out.append({"corp": raids.corp, "hq": raids.rival_platform, "unit": t,
				"name": UnitCatalog.get_data(t).name, "count": by_type[t], "air": false})
		if fleet and carriers_for(n) > 0:
			out.append({"corp": raids.corp, "hq": raids.rival_platform, "unit": "carrier",
				"name": VesperFleet.name_of("carrier"), "count": carriers_for(n), "air": true,
				"carries": VesperFleet.AIRSHIPS.carrier.troops.duplicate()})
	if fleet and _hq_alive(fleet.home):
		for kind in ["bomber", "gunship"]:
			var count := flight_size_for(n) if kind == "bomber" else gunships_for(n)
			if count > 0:
				out.append({"corp": "Vesper", "hq": fleet.home, "unit": kind,
					"name": VesperFleet.name_of(kind), "count": count, "air": true})
	return out


func _hq_alive(platform: String) -> bool:
	return combat == null or combat.headquarters_on(platform) != null


func start_wave() -> void:
	if phase != BUILD:
		return
	phase = WAVE
	_wave_units = []
	_wave_units_by_corp = {}
	var ground := 0
	for entry in composition_for(wave):
		var sent: Array[Unit] = []
		if not entry.air:
			ground += entry.count
		elif entry.unit == "bomber":
			sent = fleet.send_flight(entry.count)
		else:
			sent = fleet.launch(entry.unit, entry.count)
		_track(entry.corp, sent)
	if ground > 0:
		_track(raids.corp, raids.send_party(ground))
	for u in _wave_units:
		_toughen(u)
	phase_changed.emit(phase, wave)


## Troops dropped by a carrier join the wave (and must be beaten to end it).
func add_wave_units(units: Array, corp := "Ironbell") -> void:
	for u in units:
		_toughen(u)
	_track(corp, units)


func _track(corp: String, units: Array) -> void:
	_wave_units.append_array(units)
	if not _wave_units_by_corp.has(corp):
		_wave_units_by_corp[corp] = []
	_wave_units_by_corp[corp].append_array(units)


func _toughen(u: Unit) -> void:
	u.max_hp *= (1.0 + hp_growth_per_wave * (wave - 1)) * (1.0 + hp_bonus)
	u.hp = u.max_hp


## Walkers from the current wave still alive.
func remaining() -> int:
	return _alive(_wave_units)


## Attackers a rival sent in the current wave that are still alive.
func remaining_for(corp: String) -> int:
	return _alive(_wave_units_by_corp.get(corp, []))


func _alive(units: Array) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.hp > 0.0:
			n += 1
	return n


## What each rival sends in wave `n` (default: the next or current wave).
## The HUD reads this, so keep it in step with start_wave(). One entry per
## rival: {corp, hq, defeated, units: [[unit name, count], ...]}.
func wave_plan(n := -1) -> Array:
	if n < 0:
		n = wave
	var counts := {raids.corp: {}}
	var hqs := {raids.corp: raids.rival_platform}
	if fleet:
		counts["Vesper"] = {}
		hqs["Vesper"] = fleet.home
	for entry in composition_for(n):
		var unit_name: String = entry.name
		if entry.has("carries"):
			unit_name += " (drops %d troops each)" % entry.carries.size()
		counts[entry.corp][unit_name] = counts[entry.corp].get(unit_name, 0) + entry.count
	var plan := []
	for corp in counts:
		plan.append(_plan_entry(corp, hqs[corp], counts[corp]))
	return plan


func _plan_entry(corp: String, hq: String, counts: Dictionary) -> Dictionary:
	var units := []
	for unit_name in counts:
		units.append([unit_name, counts[unit_name]])
	return {"corp": corp, "hq": hq, "defeated": combat.headquarters_on(hq) == null, "units": units}


## How much tougher than normal this wave's attackers are, e.g. 0.16 = +16%.
func health_bonus(n := -1) -> float:
	if n < 0:
		n = wave
	return (1.0 + hp_growth_per_wave * (n - 1)) * (1.0 + hp_bonus) - 1.0


func _on_headquarters_destroyed(faction: String, platform: String) -> void:
	if phase == OVER:
		return
	if faction == "rival":
		for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
			if hq.faction == "rival" and hq.is_alive():
				rival_defeated.emit(platform)
				return
	phase = OVER
	won = faction == "rival"
	phase_changed.emit(phase, wave)
	game_over.emit(won)
