## Easy, Normal or Hard. Picked on the opening build phase (before wave 1)
## and kept for "play again". Scales how many attackers each rival sends,
## their health, and the scrap you start with.
class_name Difficulty
extends RefCounted

const LEVELS := {
	"Easy": {"count": 0.7, "hp": 0.8, "scrap": 400},
	"Normal": {"count": 1.0, "hp": 1.0, "scrap": 300},
	"Hard": {"count": 1.3, "hp": 1.2, "scrap": 250},
}
const ORDER := ["Easy", "Normal", "Hard"]

static var level := "Normal"


static func get_data() -> Dictionary:
	return LEVELS.get(level, LEVELS.Normal)
