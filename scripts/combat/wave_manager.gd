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
## Ironbell troop carriers: from this wave, one more every 3 waves.
@export var first_carrier_wave := 3
@export var max_carriers := 3
## Vesper gunships escort the bombers: from this wave, one more every 3 waves.
@export var first_gunship_wave := 4
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


func _ready() -> void:
	time_left = first_build_seconds
	combat.headquarters_destroyed.connect(_on_headquarters_destroyed)
	if fleet:
		fleet.troops_dropped.connect(func(_c, _p, units): add_wave_units(units))


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
	var ground := 0
	for entry in composition_for(wave):
		if not entry.air:
			ground += entry.count
		elif entry.unit == "bomber":
			_wave_units.append_array(fleet.send_flight(entry.count))
		else:
			_wave_units.append_array(fleet.launch(entry.unit, entry.count))
	if ground > 0:
		_wave_units.append_array(raids.send_party(ground))
	for u in _wave_units:
		_toughen(u)
	phase_changed.emit(phase, wave)


## Troops dropped by a carrier join the wave (and must be beaten to end it).
func add_wave_units(units: Array) -> void:
	for u in units:
		_toughen(u)
		_wave_units.append(u)


func _toughen(u: Unit) -> void:
	u.max_hp *= (1.0 + hp_growth_per_wave * (wave - 1)) * (1.0 + hp_bonus)
	u.hp = u.max_hp


## Walkers from the current wave still alive.
func remaining() -> int:
	var n := 0
	for u in _wave_units:
		if is_instance_valid(u) and u.hp > 0.0:
			n += 1
	return n


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
