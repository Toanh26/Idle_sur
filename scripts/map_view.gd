extends Node2D
## Vẽ bản đồ lục giác góc nhìn 3/4 và xử lý chạm / kéo / thu phóng.
## Hình tạm được vẽ bằng code. Nếu có file res://assets/tiles/<loại>.png thì dùng ảnh đó thay thế
## (loại: village, forest, rock, field, grass, water, camp).

signal tile_tapped(key: String)

const Hex = preload("res://scripts/hex.gd")
const ZOOM_MIN := 0.55
const ZOOM_MAX := 2.2
const PAN_LIMIT := 800.0

var cam: Camera2D
var selected := ""
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _touches := {}
var _pinch_dist := 0.0
var _tex_cache := {}
var _time := 0.0
var _font: Font


func _ready() -> void:
	cam = Camera2D.new()
	add_child(cam)
	cam.position = Vector2(0, 170)
	cam.zoom = Vector2(1.15, 1.15)
	cam.make_current()
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func focus(key: String) -> void:
	if not Game.tiles.has(key):
		return
	var t: Dictionary = Game.tiles[key]
	cam.position = Hex.to_pixel(int(t["q"]), int(t["r"])) + Vector2(0, 170) / cam.zoom.x


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			_pinch_dist = _two_finger_dist()
			_dragging = true
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 2:
			var d := _two_finger_dist()
			if _pinch_dist > 1.0:
				_zoom_by(d / _pinch_dist)
			_pinch_dist = d
			_dragging = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
			else:
				if _pressed and not _dragging and _touches.size() <= 1:
					_tap(mb.position)
				_pressed = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.1)
	elif event is InputEventMouseMotion and _pressed:
		if _touches.size() >= 2:
			return
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 14.0:
			_dragging = true
		if _dragging:
			cam.position -= mm.relative / cam.zoom.x
			cam.position = cam.position.clamp(Vector2(-PAN_LIMIT, -PAN_LIMIT), Vector2(PAN_LIMIT, PAN_LIMIT))


func _two_finger_dist() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _zoom_by(f: float) -> void:
	var z := clampf(cam.zoom.x * f, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)


func _tap(screen_pos: Vector2) -> void:
	var world := get_canvas_transform().affine_inverse() * screen_pos
	var order: Array = Game.draw_order
	for i in range(order.size() - 1, -1, -1):
		var key: String = order[i]
		var t: Dictionary = Game.tiles[key]
		if not t["revealed"] and not Game.is_fog_edge(key):
			continue
		var top := Hex.corners(_tile_center(t))
		if Geometry2D.is_point_in_polygon(world, top):
			selected = key
			tile_tapped.emit(key)
			return


# ---------------------------------------------------------------- vẽ
func _tile_center(t: Dictionary) -> Vector2:
	var elev := int(t["elev"]) if t["revealed"] else 0
	return Hex.to_pixel(int(t["q"]), int(t["r"])) + Vector2(0, -elev * Hex.ELEV_PX)


func _tex(type: String) -> Texture2D:
	if _tex_cache.has(type):
		return _tex_cache[type]
	var path := "res://assets/tiles/%s.png" % type
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[type] = tex
	return tex


func _draw() -> void:
	for key in Game.draw_order:
		var t: Dictionary = Game.tiles[key]
		if t["revealed"]:
			_draw_tile(key, t)
		elif Game.is_fog_edge(key):
			_draw_fog(t)


func _draw_fog(t: Dictionary) -> void:
	var c := _tile_center(t)
	var top := Hex.corners(c)
	_draw_sides(top, 8.0, Color(0.16, 0.18, 0.19))
	draw_colored_polygon(top, Color(0.25, 0.28, 0.3))
	draw_string(_font, c + Vector2(-6, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.55, 0.6, 0.62))


func _draw_sides(top: PackedVector2Array, depth: float, col: Color) -> void:
	## Vẽ 2 mặt hông nhìn thấy được (cạnh dưới-phải và dưới-trái) thành 2 tứ giác lồi riêng.
	if depth <= 0.5:
		return
	var d := Vector2(0, depth)
	var right := PackedVector2Array([top[1], top[2], top[2] + d, top[1] + d])
	var left := PackedVector2Array([top[2], top[3], top[3] + d, top[2] + d])
	draw_colored_polygon(right, col)
	draw_colored_polygon(left, col.darkened(0.15))


func _draw_tile(key: String, t: Dictionary) -> void:
	var type: String = t["type"]
	var c := _tile_center(t)
	var top := Hex.corners(c)
	var col: Color = Data.TILES[type]["color"]
	if not t["owned"]:
		col = col.darkened(0.35)
	_draw_sides(top, int(t["elev"]) * Hex.ELEV_PX + 8.0, col.darkened(0.45))
	draw_colored_polygon(top, col)
	var outline := top.duplicate()
	outline.append(top[0])
	draw_polyline(outline, col.darkened(0.3), 2.0)

	var tex := _tex(type)
	if tex:
		draw_texture_rect(tex, Rect2(c.x - 42, c.y - 62, 84, 84), false)
	else:
		_draw_decor(type, c, t)

	_draw_buildings(t, c)

	# Lãnh thổ chưa sở hữu: viền tối
	if t["owned"] and type != "camp":
		draw_polyline(outline, Color(1, 0.95, 0.7, 0.25), 1.0)

	# Bãi chứa
	var stock := float(t["stock"])
	if stock >= 1.0:
		var full := stock >= Data.STOCK_CAP - 0.5
		var col_s := Color(1, 0.45, 0.35) if full else Color(1, 0.95, 0.75)
		draw_string(_font, c + Vector2(-22, 26), "%d" % int(stock), HORIZONTAL_ALIGNMENT_CENTER, 44, 15, col_s)

	# Thao tác tay đang chạy
	var p := Game.manual_progress(key)
	if p > 0.0:
		draw_arc(c + Vector2(0, -34), 13, -PI / 2, -PI / 2 + TAU * p, 24, Color(1, 0.9, 0.4), 4.0)

	if key == selected:
		draw_polyline(outline, Color(1, 1, 1, 0.9), 3.5)


func _draw_decor(type: String, c: Vector2, t: Dictionary) -> void:
	match type:
		"forest":
			for o in [Vector2(-18, -2), Vector2(12, -10), Vector2(2, 8), Vector2(22, 6)]:
				var p: Vector2 = c + o
				draw_rect(Rect2(p.x - 2, p.y - 2, 4, 8), Color("5a3b22"))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(-11, 0), p + Vector2(11, 0)]), Color("2f5e2a"))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -28), p + Vector2(-8, -10), p + Vector2(8, -10)]), Color("3d7535"))
		"rock":
			draw_circle(c + Vector2(-12, 2), 11, Color("6e6c63"))
			draw_circle(c + Vector2(8, -4), 14, Color("8a877b"))
			draw_circle(c + Vector2(14, 8), 8, Color("77746a"))
			draw_circle(c + Vector2(4, -8), 5, Color("a5a295"))
		"field":
			for i in 4:
				var y := -12.0 + i * 7.0
				draw_line(c + Vector2(-26 + i * 3, y), c + Vector2(26 - i * 3, y), Color("d8c24a"), 3.0)
			for i in 6:
				var x := -20.0 + i * 8.0
				var sway := sin(_time * 2.0 + i) * 1.5
				draw_line(c + Vector2(x, 10), c + Vector2(x + sway, -2), Color("e9d36a"), 2.0)
		"grass":
			if t["structure"] == "":
				for o in [Vector2(-14, -4), Vector2(10, 6), Vector2(16, -8), Vector2(-4, 10)]:
					draw_line(c + o, c + o + Vector2(-2, -6), Color("5d8f40"), 2.0)
					draw_line(c + o, c + o + Vector2(2, -6), Color("6ea34b"), 2.0)
		"water":
			for i in 3:
				var y := -8.0 + i * 8.0
				var off := sin(_time * 1.5 + i) * 4.0
				draw_line(c + Vector2(-20 + off, y), c + Vector2(-4 + off, y), Color("9fd0ec"), 2.0)
				draw_line(c + Vector2(4 + off, y + 3), c + Vector2(18 + off, y + 3), Color("9fd0ec"), 2.0)
		"village":
			_draw_house(c + Vector2(-14, 4), 1.0)
			_draw_house(c + Vector2(12, -6), 0.85)
			_draw_house(c + Vector2(10, 12), 0.7)
			draw_string(_font, c + Vector2(-40, -30), "Làng", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1, 0.97, 0.85))
		"camp":
			var p := c + Vector2(0, 6)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -26), p + Vector2(-20, 4), p + Vector2(20, 4)]), Color("8f2f22"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -26), p + Vector2(-5, 4), p + Vector2(5, 4)]), Color("3a1712"))
			draw_line(p + Vector2(16, -2), p + Vector2(16, -34), Color("3a2a1a"), 2.0)
			var wave := sin(_time * 4.0) * 2.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(16, -34), p + Vector2(30, -30 + wave), p + Vector2(16, -26)]), Color("d23c2c"))
			var idx := int(t["camp"])
			draw_string(_font, c + Vector2(-40, 30), "Sức mạnh %d" % Data.camp_power(idx), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(1, 0.75, 0.7))


func _draw_house(p: Vector2, s: float) -> void:
	draw_rect(Rect2(p.x - 10 * s, p.y - 10 * s, 20 * s, 14 * s), Color("e6d3ad"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-13, -10) * s, p + Vector2(13, -10) * s, p + Vector2(0, -22) * s]), Color("a2452f"))
	draw_rect(Rect2(p.x - 3 * s, p.y - 4 * s, 6 * s, 8 * s), Color("6b4a2c"))


func _draw_buildings(t: Dictionary, c: Vector2) -> void:
	var npcs := int(t["npcs"])
	if npcs > 0:
		var p := c + Vector2(-30, -16)
		draw_rect(Rect2(p.x - 8, p.y - 6, 16, 12), Color("8a6a3f"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-10, -6), p + Vector2(10, -6), p + Vector2(0, -14)]), Color("5e4326"))
		draw_string(_font, p + Vector2(-8, 22), "x%d" % npcs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	if int(t["machine"]) > 0:
		var g := c + Vector2(28, -14)
		var a := _time * 2.5
		draw_circle(g, 9, Color("55595e"))
		for i in 6:
			var ang := a + i * TAU / 6.0
			draw_line(g, g + Vector2(cos(ang), sin(ang)) * 12.0, Color("7d838a"), 3.0)
		draw_circle(g, 4, Color("c9a24a"))
		var puff := fmod(_time, 1.5) / 1.5
		draw_circle(g + Vector2(4, -14 - puff * 14), 4 + puff * 4, Color(0.85, 0.85, 0.85, 0.6 * (1.0 - puff)))
	if t["crane"]:
		var b := c + Vector2(-26, 14)
		draw_line(b, b + Vector2(0, -40), Color("d9a43a"), 3.0)
		draw_line(b + Vector2(-6, -40), b + Vector2(26, -40), Color("d9a43a"), 3.0)
		var hook := 8.0 + (sin(_time * 1.6) * 0.5 + 0.5) * 18.0
		draw_line(b + Vector2(22, -40), b + Vector2(22, -40 + hook), Color("444444"), 1.5)
		draw_rect(Rect2(b.x + 18, b.y - 40 + hook, 8, 6), Color("8a6a3f"))
	if int(t["porters"]) > 0:
		# chấm nhỏ chạy qua lại tượng trưng khuân vác
		var dir := Hex.to_pixel(0, 0) - Hex.to_pixel(int(t["q"]), int(t["r"]))
		var k := fmod(_time * 0.4, 1.0)
		var along := c + dir.normalized() * minf(dir.length(), 40.0) * (k if k < 0.5 else 1.0 - k) * 2.0
		draw_circle(along + Vector2(0, 10), 3.5, Color("f0d9a0"))
	var st: String = t["structure"]
	if st == "rao":
		for i in 5:
			var x := -24.0 + i * 12.0
			draw_line(c + Vector2(x, 10), c + Vector2(x, -6), Color("b39a5a"), 3.0)
		draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color("9a8248"), 2.0)
	elif st == "thap_cung":
		draw_rect(Rect2(c.x - 9, c.y - 34, 18, 40), Color("8a6a3f"))
		draw_rect(Rect2(c.x - 13, c.y - 40, 26, 8), Color("6b4f2a"))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -40), c + Vector2(14, -40), c + Vector2(0, -54)]), Color("a2452f"))
