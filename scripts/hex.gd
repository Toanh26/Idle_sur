extends RefCounted
## Hàm hỗ trợ lưới lục giác (pointy-top, toạ độ axial q,r).
## Trục Y bị ép lại (SQUASH) để tạo cảm giác nhìn 3/4 từ trên cao.

const SIZE := 48.0
const SQUASH := 0.62
const ELEV_PX := 14.0
const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]


static func to_pixel(q: int, r: int) -> Vector2:
	var x := SIZE * sqrt(3.0) * (float(q) + float(r) / 2.0)
	var y := SIZE * 1.5 * float(r) * SQUASH
	return Vector2(x, y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2


static func corners(center: Vector2, size: float = SIZE) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(size * cos(ang), size * sin(ang) * SQUASH))
	return pts


static func key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


static func neighbors(q: int, r: int) -> Array:
	var out := []
	for d in DIRS:
		out.append(Vector2i(q + d.x, r + d.y))
	return out


static func coords_in_radius(center: Vector2i, radius: int) -> Array:
	var out := []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			out.append(Vector2i(center.x + dq, center.y + dr))
	return out
