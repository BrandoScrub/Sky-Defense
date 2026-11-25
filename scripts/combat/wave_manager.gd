## Build phase, then wave phase, like the reference game. Each build phase
## runs on a timer (G ends it early). Each wave sends a bigger Ironbell party;
## once every walker in it is destroyed the next build phase starts.
## Destroying Ironbell HQ wins; losing the Hub's headquarters loses.
class_name WaveManager
extends Node

signal phase_changed(phase: String, wave: int)
signal game_over(won: bool)

const BUILD := "build"
const WAVE := "wave"
const OVER := "over"

@export var first_build_seconds := 45.0
@export var build_seconds := 25.0
@export var base_party := 2
@export var max_party := 10
## Walkers in later waves get this much extra health per wave.
@export var hp_growth_per_wave := 0.08

@export var raids: RivalRaids
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


func start_wave() -> void:
	if phase != BUILD:
		return
	phase = WAVE
	_wave_units = raids.send_party(party_size_for(wave))
	for u in _wave_units:
		u.max_hp *= (1.0 + hp_growth_per_wave * (wave - 1)) * (1.0 + hp_bonus)
		u.hp = u.max_hp
	phase_changed.emit(phase, wave)


## Walkers from the current wave still alive.
func remaining() -> int:
	var n := 0
	for u in _wave_units:
		if is_instance_valid(u) and u.hp > 0.0:
			n += 1
	return n


func _on_headquarters_destroyed(faction: String) -> void:
	if phase == OVER:
		return
	phase = OVER
	won = faction == "rival"
	phase_changed.emit(phase, wave)
	game_over.emit(won)
