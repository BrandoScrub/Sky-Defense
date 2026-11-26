## Round income and the power grid's effect on buildings.
##
## Income pays out once per round, when a wave is cleared, based on what you
## hold at that moment (scrap from kills is the exception: it's paid on the
## spot by CombatSystem):
## - Each scrap heap on a platform you own pays scrap.
## - Each Cloud Harvester you own pays energized crystals.
## - Each crystal seam on a platform you own pays energized crystals.
## - Every platform you hold besides the Hub pays a little scrap, so
##   claiming islands is worth it even without a scrap heap.
## Power isn't banked: it's a live budget. When demand outstrips supply, the
## grid browns out and every power-hungry building runs at supply / demand
## efficiency.
class_name EconomySystem
extends Node

signal grid_changed(efficiency: float)
## Emitted after a round's income is paid: see round_income() for the shape.
signal paid_out(income: Dictionary)

@export var scrap_per_heap_per_round := 50
@export var crystals_per_harvester_per_round := 6
@export var scrap_per_island_per_round := 25
## Crystal seams on islands you hold pay this many crystals each.
@export var crystals_per_seam_per_round := 5

@export var region: SkyRegion
@export var resources: PlayerResources
## Pays out each time one of its waves is cleared. Set with watch().
var waves: WaveManager

var efficiency := 1.0
## The last payout, for the HUD.
var last_income := {}


func _process(delta: float) -> void:
	step(delta)


## Pays round income whenever `wave_manager` finishes a wave.
func watch(wave_manager: WaveManager) -> void:
	waves = wave_manager
	waves.phase_changed.connect(func(phase: String, wave: int):
		# A cleared wave starts the next build phase; wave is already the next one.
		if phase == WaveManager.BUILD:
			pay_round(wave - 1))


## What the next payout would be if the round ended now:
## {scrap, crystals, sources: [[what, amount text], ...]}.
func round_income() -> Dictionary:
	var heaps := 0
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "scrap_heap" and region.platform_owner(t.platform) == "player":
			heaps += 1
	var seams := 0
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "crystal_seam" and region.platform_owner(t.platform) == "player":
			seams += 1
	var harvesters := 0
	for b in region.buildings.values():
		if b.type_id == "harvester" and b.faction == "player" and region.platform_owner(b.platform) == "player":
			harvesters += 1
	var islands := islands_held()
	var income := {"scrap": heaps * scrap_per_heap_per_round + islands * scrap_per_island_per_round,
		"crystals": harvesters * crystals_per_harvester_per_round + seams * crystals_per_seam_per_round, "sources": []}
	if islands > 0:
		income.sources.append(["%d island%s held" % [islands, "" if islands == 1 else "s"], "+%d scrap" % (islands * scrap_per_island_per_round)])
	if heaps > 0:
		income.sources.append(["%d scrap heap%s" % [heaps, "" if heaps == 1 else "s"], "+%d scrap" % (heaps * scrap_per_heap_per_round)])
	if harvesters > 0:
		income.sources.append(["%d Cloud Harvester%s" % [harvesters, "" if harvesters == 1 else "s"], "+%d crystals" % (harvesters * crystals_per_harvester_per_round)])
	if seams > 0:
		income.sources.append(["%d crystal seam%s" % [seams, "" if seams == 1 else "s"], "+%d crystals" % (seams * crystals_per_seam_per_round)])
	return income


## Platforms you own besides the Hub.
func islands_held() -> int:
	var n := 0
	for platform_name in region.platforms:
		if platform_name != "Hub" and region.platform_owner(platform_name) == "player":
			n += 1
	return n


## Pays this round's income. Returns what was paid (also in last_income).
func pay_round(wave_cleared := 0) -> Dictionary:
	var income := round_income()
	income.wave = wave_cleared
	if income.scrap > 0:
		resources.add_scrap(income.scrap)
	if income.crystals > 0:
		resources.add_crystals(income.crystals)
	last_income = income
	paid_out.emit(income)
	return income


## Updates the power grid's effect on buildings. Public for tests.
func step(_delta: float) -> void:
	var now := region.grid_efficiency()
	for b in region.buildings.values():
		b.set_efficiency(now)
	if not is_equal_approx(now, efficiency):
		efficiency = now
		grid_changed.emit(efficiency)
