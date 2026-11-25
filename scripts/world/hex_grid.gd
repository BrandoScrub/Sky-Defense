## Pointy-top hex grid math in axial coordinates (q, r), stored as Vector2i.
## World space is the XZ plane; see https://www.redblobgames.com/grids/hexagons/
class_name HexGrid
extends RefCounted

const SQRT3 := 1.7320508075688772

## Neighbour offsets, starting east and going counter-clockwise when seen from above.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


## Centre of a hex on the XZ plane. `size` is the centre-to-corner radius.
static func to_world(hex: Vector2i, size: float) -> Vector3:
	return Vector3(size * SQRT3 * (hex.x + hex.y / 2.0), 0.0, size * 1.5 * hex.y)


## The hex containing a world point.
static func from_world(point: Vector3, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * point.x - point.z / 3.0) / size
	var r := (2.0 / 3.0 * point.z) / size
	return round_axial(q, r)


static func round_axial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(hex + d)
	return out


## Every hex within `radius` steps of `center` (a hexagon of 1 + 3r(r+1) tiles).
static func disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(center + Vector2i(q, r))
	return out


## Hexes exactly `radius` steps from `center`.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var out: Array[Vector2i] = []
	var hex := center + DIRECTIONS[4] * radius
	for side in 6:
		for step in radius:
			out.append(hex)
			hex += DIRECTIONS[side]
	return out


## Hexes on a straight line from a to b, both included.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		return [a]
	# A tiny nudge keeps the line from landing exactly on hex edges.
	var aq := a.x + 1e-6
	var ar := a.y + 2e-6
	for i in n + 1:
		var t := float(i) / n
		out.append(round_axial(lerpf(aq, b.x + 1e-6, t), lerpf(ar, b.y + 2e-6, t)))
	return out
