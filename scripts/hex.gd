extends RefCounted
## Hàm hỗ trợ lưới lục giác đỉnh phẳng (flat-top, toạ độ axial q,r) — khớp với bộ asset ô đất.
## Trục Y bị ép lại (SQUASH) để tạo góc nhìn 3/4 từ trên cao.

const SIZE := 48.0
const SQUASH := 0.67
const ELEV_PX := 14.0
const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]


static func to_pixel(q: int, r: int) -> Vector2:
	var x := SIZE * 1.5 * float(q)
	var y := SIZE * sqrt(3.0) * (float(r) + float(q) / 2.0) * SQUASH
	return Vector2(x, y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2


static func corners(center: Vector2, size: float = SIZE) -> PackedVector2Array:
	## Thứ tự: 0 phải, 1 dưới-phải, 2 dưới-trái, 3 trái, 4 trên-trái, 5 trên-phải.
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
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
