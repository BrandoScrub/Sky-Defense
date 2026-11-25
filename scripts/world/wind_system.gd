## The wind over the sky region. It blows from one of the 8 compass
## directions and turns every `shift_every` waves, at the start of a build
## phase so the player sees the new airship routes before the next attack.
## Enemy airships plan their routes with it (see AirNav): they make their
## bombing runs downwind, so when the wind turns they attack from a new side.
class_name WindSystem
extends Node

## `from_index` is the compass index the wind blows from (0 = east,
## 2 = north; see LevelLayout.COMPASS). `first` is true for the opening wind.
signal wind_changed(from_index: int, first: bool)

@export var waves: WaveManager
@export var shift_every := 3

## Compass index the wind blows from.
var from_index := 0
## Wave number when the wind last turned (or the game began).
var since_wave := 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(["wind", SkyRegion.seed_override])
	if SkyRegion.seed_override < 0:
		_rng.randomize()
	from_index = _rng.randi_range(0, 7)
	if waves:
		waves.phase_changed.connect(_on_phase_changed)
	wind_changed.emit.call_deferred(from_index, true)


## "North", "Southwest" and so on.
func from_name() -> String:
	return LevelLayout.COMPASS[from_index]


## Unit vector the wind blows toward, on the XZ plane.
func blowing() -> Vector3:
	return -LevelLayout.compass_vector(from_index)


## Waves still to come before the wind turns, counting the next one.
func waves_until_shift(wave: int) -> int:
	return shift_every - (wave - since_wave)


## Turns the wind to a new direction at least 90 degrees away. Public so
## tests can drive it.
func shift(wave: int) -> void:
	var choices := []
	for d in 8:
		if LevelLayout.compass_gap(d, from_index) >= 2:
			choices.append(d)
	from_index = choices[_rng.randi_range(0, choices.size() - 1)]
	since_wave = wave
	wind_changed.emit(from_index, false)


func _on_phase_changed(phase: String, wave: int) -> void:
	if phase == WaveManager.BUILD and wave - since_wave >= shift_every:
		shift(wave)
