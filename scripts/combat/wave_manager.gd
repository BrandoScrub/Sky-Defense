## Build phase, then wave phase, like the reference game. Each build phase
## runs on a timer (Space ends it early). What each rival sends in each wave
## comes from RivalCatalog: Ironbell's raiding parties grow every wave,
## Vesper's bombers join from wave 3, and so on. Once every attacker is
## destroyed the next build phase starts. A rival whose headquarters falls
## stops attacking. Losing the Hub's headquarters loses. You win by
## surviving `match_waves` waves, or sooner by destroying every rival HQ.
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
## Waves to survive to win. 0: no limit.
@export var match_waves := 10
## Walkers in later waves get this much extra health per wave.
@export var hp_growth_per_wave := 0.06

## The first ground rival's raids (Ironbell). Kept for older callers; every
## ground rival's raids are in raids_by_corp.
@export var raids: RivalRaids
## Optional: rival airships join waves when set.
@export var fleet: VesperFleet
@export var combat: CombatSystem

## Rivals on this map, in order (main sets it from the layout). Empty means
## whatever raids and fleet stand for: Ironbell and Vesper.
var corps: Array = []
## corp -> RivalRaids, for every rival that sends ground parties.
var raids_by_corp := {}

## Caps, from RivalCatalog (for the HUD and tests).
var max_party: int:
	get: return RivalCatalog.max_for("Ironbell", "ground")
var max_flight: int:
	get: return RivalCatalog.max_for("Vesper", "bomber")
var max_carriers: int:
	get: return RivalCatalog.max_for("Ironbell", "carrier")
var max_gunships: int:
	get: return RivalCatalog.max_for("Vesper", "gunship")

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
	_check_contact()
	match phase:
		BUILD:
			time_left -= delta
			if time_left <= 0.0:
				start_wave()
		WAVE:
			if remaining() == 0:
				if final_wave() > 0 and wave >= final_wave():
					_end(true)
					return
				wave += 1
				phase = BUILD
				time_left = build_seconds
				phase_changed.emit(phase, wave)


## Extra walker toughness, e.g. from storms Ironbell controls (StormSystem).
var hp_bonus := 0.0

## Optional: bridging rivals count their waves from first contact when set.
var bridges: RivalBridges
## corp -> the wave in which a bridging rival's bridge first reached you.
var contact_wave := {}


## The wave that ends the match if you survive it, or -1 with no limit.
## Counted from wave 1, so the clock runs even while you keep cutting a
## rival's bridge.
func final_wave() -> int:
	return match_waves if match_waves > 0 else -1


## Rival headquarters destroyed so far, and how many there were.
func rivals_grounded() -> Array:
	var down := 0
	var total := 0
	for corp in rival_corps():
		total += 1
		if not _hq_alive(RivalCatalog.hq_of(corp)):
			down += 1
	return [down, total]


func _end(win: bool) -> void:
	phase = OVER
	won = win
	phase_changed.emit(phase, wave)
	game_over.emit(won)


## True once a rival can reach you: its bridge is done, or it flies.
func has_contact(corp: String) -> bool:
	return not _counts_from_contact(corp) or contact_wave.has(corp)


func _counts_from_contact(corp: String) -> bool:
	return bridges != null and bridges.crews.has(corp)


## Notes the wave a bridging rival's bridge reaches you in. Called each step,
## so a bridge finished mid-wave counts for that wave.
func _check_contact() -> void:
	if bridges == null:
		return
	for corp in bridges.crews:
		if not contact_wave.has(corp) and bridges.is_done(corp):
			contact_wave[corp] = wave


## The wave number a rival's army size and health follow for global wave `n`.
## Flying rivals follow the match's waves. Bridging rivals count from first
## contact: their first party to reach you is their wave-1 party, however
## late the bridge lands, and it grows from there. Before contact their camp
## stays at that first size.
func rival_wave(corp: String, n := -1) -> int:
	if n < 0:
		n = wave
	if not _counts_from_contact(corp):
		return n
	var first := maxi(RivalCatalog.first_wave(corp, "ground"), 1)
	if not contact_wave.has(corp):
		return first
	# A rival that starts late (Aurum) still starts at its own first wave.
	return first + maxi(n - maxi(contact_wave[corp], first), 0)


## How many of `unit` a rival sends in global wave `n`. A bridging rival
## sends only its ground party (at its first size) until the bridge lands.
func count_for(corp: String, unit: String, n: int) -> int:
	if _counts_from_contact(corp):
		if n < RivalCatalog.first_wave(corp, "ground"):
			return 0
		if not contact_wave.has(corp) and unit != "ground":
			return 0
	return RivalCatalog.count_for(corp, unit, rival_wave(corp, n))


## Rivals taking part, in order.
func rival_corps() -> Array:
	if not corps.is_empty():
		return corps
	var out := []
	if raids:
		out.append(raids.corp)
	if fleet:
		out.append("Vesper")
	return out


func _raids_for(corp: String) -> RivalRaids:
	if raids_by_corp.has(corp):
		return raids_by_corp[corp]
	return raids if raids and raids.corp == corp else null


## Ironbell's raiding party size in wave `n`.
func party_size_for(n: int) -> int:
	return RivalCatalog.count_for("Ironbell", "ground", n)


## Vesper bombers in wave `n`.
func flight_size_for(n: int) -> int:
	return RivalCatalog.count_for("Vesper", "bomber", n)


## Ironbell troop carriers in wave `n`.
func carriers_for(n: int) -> int:
	return RivalCatalog.count_for("Ironbell", "carrier", n)


## Vesper gunships in wave `n`.
func gunships_for(n: int) -> int:
	return RivalCatalog.count_for("Vesper", "gunship", n)


## What wave `n` sends, for the wave preview and for start_wave. One entry
## per kind of unit: {corp, hq, unit (UnitCatalog or airship kind), name,
## count, air}. A troop carrier entry also has `carries`: the unit types of
## the squad each one drops. Rivals whose headquarters has fallen send nothing.
func composition_for(n: int) -> Array:
	var out := []
	for corp in rival_corps():
		var hq := RivalCatalog.hq_of(corp)
		if not _hq_alive(hq):
			continue
		for w in RivalCatalog.get_data(corp).get("waves", []):
			var count := count_for(corp, w.unit, n)
			if count <= 0:
				continue
			if w.unit == "ground":
				var party := _raids_for(corp)
				if party == null:
					continue
				var by_type := {}
				var order := []
				for i in count:
					var t := party.unit_for_slot(i)
					if not by_type.has(t):
						by_type[t] = 0
						order.append(t)
					by_type[t] += 1
				for t in order:
					out.append({"corp": corp, "hq": hq, "unit": t,
						"name": UnitCatalog.get_data(t).name, "count": by_type[t], "air": false})
			elif fleet:
				var entry := {"corp": corp, "hq": hq, "unit": w.unit,
					"name": VesperFleet.name_of(w.unit), "count": count, "air": true}
				if w.unit == "carrier":
					entry.carries = VesperFleet.AIRSHIPS.carrier.troops.duplicate()
				out.append(entry)
	return out


func _hq_alive(platform: String) -> bool:
	return combat == null or combat.headquarters_on(platform) != null


func start_wave() -> void:
	if phase != BUILD:
		return
	_check_contact()
	phase = WAVE
	_wave_units = []
	_wave_units_by_corp = {}
	# Raiders still camped at the end of a bridge from earlier waves join this
	# one, and their rival only tops the camp up to this wave's size (so a
	# late bridge doesn't bring every wave at once).
	var leftovers := {}
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		if not node.flying and node.hp > 0.0:
			var corp: String = node.get_meta("corp", raids.corp if raids else "")
			if not leftovers.has(corp):
				leftovers[corp] = []
			leftovers[corp].append(node)
	var ground := {}
	for entry in composition_for(wave):
		var sent: Array[Unit] = []
		if not entry.air:
			ground[entry.corp] = ground.get(entry.corp, 0) + entry.count
		elif entry.unit == "bomber":
			sent = fleet.send_flight(entry.count, entry.corp)
		else:
			sent = fleet.launch(entry.unit, entry.count, entry.corp)
		_track(entry.corp, sent)
	for corp in ground:
		var size: int = ground[corp] - leftovers.get(corp, []).size()
		if size > 0:
			_track(corp, _raids_for(corp).send_party(size))
	for corp in _wave_units_by_corp:
		for u in _wave_units_by_corp[corp]:
			_toughen(u, corp)
	# Already toughened in the wave they came with.
	for corp in leftovers:
		_track(corp, leftovers[corp])
	phase_changed.emit(phase, wave)


## Troops dropped by a carrier join the wave (and must be beaten to end it).
func add_wave_units(units: Array, corp := "Ironbell") -> void:
	for u in units:
		_toughen(u, corp)
	_track(corp, units)


func _track(corp: String, units: Array) -> void:
	_wave_units.append_array(units)
	if not _wave_units_by_corp.has(corp):
		_wave_units_by_corp[corp] = []
	_wave_units_by_corp[corp].append_array(units)


func _toughen(u: Unit, corp := "") -> void:
	var n := rival_wave(corp) if corp != "" else wave
	u.max_hp *= (1.0 + hp_growth_per_wave * (n - 1)) * (1.0 + hp_bonus)
	u.hp = u.max_hp


## Walkers from the current wave still alive.
func remaining() -> int:
	return _alive(_wave_units)


## Attackers a rival sent in the current wave that are still alive.
func remaining_for(corp: String) -> int:
	return _alive(_wave_units_by_corp.get(corp, []))


## Raiders waiting at the end of an unfinished bridge don't hold the wave
## open: they camp there and join the next wave.
func _alive(units: Array) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.hp > 0.0 and not _is_camped(u):
			n += 1
	return n


func _is_camped(u: Unit) -> bool:
	var bridges: RivalBridges = raids.bridges if raids else null
	if bridges == null or u.flying:
		return false
	return bridges.is_waiting_at_frontier(u.get_meta("corp", raids.corp), u)


## Raiders camped at the end of an unfinished bridge, waiting for it.
func camped() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		if node.hp > 0.0 and _is_camped(node):
			n += 1
	return n


## What each rival sends in wave `n` (default: the next or current wave).
## The HUD reads this, so keep it in step with start_wave(). One entry per
## rival: {corp, hq, defeated, units: [[unit name, count], ...]}.
func wave_plan(n := -1) -> Array:
	if n < 0:
		n = wave
	var counts := {}
	var hqs := {}
	for corp in rival_corps():
		counts[corp] = {}
		hqs[corp] = RivalCatalog.hq_of(corp)
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
func health_bonus(n := -1, corp := "") -> float:
	if n < 0:
		n = wave
	if corp != "":
		n = rival_wave(corp, n)
	return (1.0 + hp_growth_per_wave * (n - 1)) * (1.0 + hp_bonus) - 1.0


func _on_headquarters_destroyed(faction: String, platform: String) -> void:
	if phase == OVER:
		return
	if faction == "rival":
		for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
			if hq.faction == "rival" and hq.is_alive():
				rival_defeated.emit(platform)
				return
	_end(faction == "rival")
