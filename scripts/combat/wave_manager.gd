## Build phase, then wave phase, like the reference game. Each build phase
## runs on a timer (Space ends it early). Each wave sends a bigger Ironbell party
## and, from wave 2, a flight of Vesper bombers; once every attacker is
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

@export var first_air_wave := 2
@export var max_flight := 4

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


func start_wave() -> void:
	if phase != BUILD:
		return
	phase = WAVE
	_wave_units = []
	_wave_units_by_corp = {}
	if combat.headquarters_on(raids.rival_platform):
		_wave_units_by_corp[raids.corp] = raids.send_party(party_size_for(wave))
	if fleet and combat.headquarters_on(fleet.home):
		_wave_units_by_corp["Vesper"] = fleet.send_flight(flight_size_for(wave))
	for corp in _wave_units_by_corp:
		_wave_units.append_array(_wave_units_by_corp[corp])
	for u in _wave_units:
		u.max_hp *= (1.0 + hp_growth_per_wave * (wave - 1)) * (1.0 + hp_bonus)
		u.hp = u.max_hp
	phase_changed.emit(phase, wave)


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
	var plan := []
	var ironbell := {}
	for i in party_size_for(n):
		var type_id := raids.unit_for_slot(i)
		var unit_name: String = UnitCatalog.get_data(type_id).name if UnitCatalog.has_unit(type_id) else type_id.capitalize()
		ironbell[unit_name] = ironbell.get(unit_name, 0) + 1
	plan.append(_plan_entry(raids.corp, raids.rival_platform, ironbell))
	if fleet:
		var flight := flight_size_for(n)
		plan.append(_plan_entry("Vesper", fleet.home, {"Vesper Bomber": flight} if flight > 0 else {}))
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
