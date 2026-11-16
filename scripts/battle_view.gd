extends CanvasLayer
## Màn hình trận đánh tự động trên bàn lục giác.
## Người chơi không điều khiển từng lính; chỉ có nút Rút quân và tăng tốc.

signal finished(win: bool)

const Hex = preload("res://scripts/hex.gd")

var arena: Control
var title_label: Label
var result_panel: PanelContainer
var result_label: Label
var speed_button: Button
var retreat_button: Button

var units: Array = []
var shots: Array = []
var camp_key := ""
var selection := {}
var time := 0.0
var running := false
var speed := 1
var _font: Font


func _ready() -> void:
	layer = 10
	visible = false
	_font = ThemeDB.fallback_font
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.08, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	arena = Control.new()
	arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.draw.connect(_draw_arena)
	add_child(arena)

	title_label = Label.new()
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 30
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26)
	add_child(title_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -110
	bar.offset_bottom = -30
	bar.offset_left = 30
	bar.offset_right = -30
	bar.add_theme_constant_override("separation", 20)
	add_child(bar)
	retreat_button = Button.new()
	retreat_button.text = "Rút quân"
	retreat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retreat_button.add_theme_font_size_override("font_size", 26)
	retreat_button.pressed.connect(_on_retreat)
	bar.add_child(retreat_button)
	speed_button = Button.new()
	speed_button.text = "x1"
	speed_button.custom_minimum_size = Vector2(140, 0)
	speed_button.add_theme_font_size_override("font_size", 26)
	speed_button.pressed.connect(_toggle_speed)
	bar.add_child(speed_button)

	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.custom_minimum_size = Vector2(560, 300)
	result_panel.offset_left = -280
	result_panel.offset_right = 280
	result_panel.offset_top = -150
	result_panel.offset_bottom = 150
	result_panel.visible = false
	add_child(result_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	result_panel.add_child(vb)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_label.add_theme_font_size_override("font_size", 24)
	vb.add_child(result_label)
	var close := Button.new()
	close.text = "Về làng"
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(_close)
	vb.add_child(close)


func set_theme_from(th: Theme) -> void:
	for c in get_children():
		if c is Control:
			(c as Control).theme = th


# ---------------------------------------------------------------- bắt đầu
func start(key: String, pick: Dictionary) -> void:
	camp_key = key
	selection = pick.duplicate()
	units.clear()
	shots.clear()
	time = 0.0
	speed = 1
	speed_button.text = "x1"
	result_panel.visible = false
	retreat_button.disabled = false

	var size := get_viewport().get_visible_rect().size
	var cx := size.x / 2.0
	var base_y := size.y * 0.62

	# --- quân mình: hàng trước (khiên) gần giữa, cung thủ phía sau ---
	var rows := {0: [], 1: [], 2: []}
	for u in Data.UNIT_ORDER:
		for i in int(selection.get(u, 0)):
			rows[int(Data.UNITS[u]["row"])].append(u)
	var y := base_y
	for r in [0, 1, 2]:
		var list: Array = rows[r]
		y = _place_rows(list, cx, y, 1, true)

	# --- quân địch ---
	var t: Dictionary = Game.tiles[key]
	var idx := int(t["camp"])
	var power := Data.camp_power(idx)
	var raw := maxi(3, int(power / 7.0))
	var n := mini(raw, Data.BATTLE_MAX_PER_SIDE)
	var mult := float(raw) / float(n)
	var n_archer := int(n * 0.3)
	var enemy_rows := {0: [], 2: []}
	for i in n - n_archer:
		enemy_rows[0].append("tho_phi")
	for i in n_archer:
		enemy_rows[2].append("cung_phi")
	y = size.y * 0.38
	for r in [0, 2]:
		var list: Array = enemy_rows[r]
		y = _place_rows(list, cx, y, -1, false, mult)

	title_label.text = "%s — 0 giây" % Data.camp_name(idx)
	visible = true
	running = true


func _place_rows(list: Array, cx: float, y: float, dir: int, mine: bool, mult: float = 1.0) -> float:
	if list.is_empty():
		return y
	var per_row := 10
	var spacing := 52.0
	var i := 0
	while i < list.size():
		var count := mini(per_row, list.size() - i)
		for j in count:
			var type: String = list[i + j]
			var def: Dictionary = Data.UNITS[type] if mine else Data.ENEMIES[type]
			var x := cx + (j - (count - 1) / 2.0) * spacing
			units.append({
				"mine": mine, "type": type,
				"hp": float(def["hp"]) * mult, "max": float(def["hp"]) * mult,
				"atk": float(def["atk"]) * mult, "range": float(def["range"]),
				"speed": float(def["speed"]), "pos": Vector2(x, y), "cd": randf() * 0.6,
			})
		i += count
		y += 46.0 * dir
	return y + 20.0 * dir


# ---------------------------------------------------------------- mô phỏng
func _process(delta: float) -> void:
	if not visible:
		return
	if running:
		for i in speed:
			_step(minf(delta, 0.05))
			if not running:
				break
		var idx := int(Game.tiles[camp_key]["camp"]) if Game.tiles.has(camp_key) else 0
		title_label.text = "%s — %d giây" % [Data.camp_name(maxi(0, idx)), int(time)]
	for s in shots:
		s["ttl"] = float(s["ttl"]) - delta
	shots = shots.filter(func(s): return float(s["ttl"]) > 0.0)
	arena.queue_redraw()


func _step(dt: float) -> void:
	time += dt
	var mine_alive := 0
	var enemy_alive := 0
	for u in units:
		if float(u["hp"]) <= 0.0:
			continue
		var target = _nearest_enemy(u)
		if target == null:
			continue
		var pos: Vector2 = u["pos"]
		var tpos: Vector2 = target["pos"]
		var dist := pos.distance_to(tpos)
		if dist > float(u["range"]):
			u["pos"] = pos + (tpos - pos).normalized() * float(u["speed"]) * dt
		else:
			u["cd"] = float(u["cd"]) - dt
			if float(u["cd"]) <= 0.0:
				u["cd"] = 1.0
				target["hp"] = float(target["hp"]) - float(u["atk"])
				if float(u["range"]) > 60.0:
					shots.append({"a": pos, "b": tpos, "ttl": 0.15, "mine": u["mine"]})
	# tách nhau một chút cho đỡ chồng hình
	for a in units:
		if float(a["hp"]) <= 0.0:
			continue
		for b in units:
			if is_same(a, b) or float(b["hp"]) <= 0.0:
				continue
			var pa: Vector2 = a["pos"]
			var pb: Vector2 = b["pos"]
			var d := pa.distance_to(pb)
			if d < 22.0 and d > 0.01:
				a["pos"] = pa + (pa - pb).normalized() * (22.0 - d) * 0.5
	for u in units:
		if float(u["hp"]) > 0.0:
			if u["mine"]:
				mine_alive += 1
			else:
				enemy_alive += 1
	if enemy_alive == 0:
		_finish(true, false)
	elif mine_alive == 0 or time >= Data.BATTLE_TIME_LIMIT:
		_finish(false, false)


func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d := INF
	var pos: Vector2 = u["pos"]
	for o in units:
		if o["mine"] == u["mine"] or float(o["hp"]) <= 0.0:
			continue
		var d := pos.distance_squared_to(o["pos"])
		if d < best_d:
			best_d = d
			best = o
	return best


func _finish(win: bool, retreated: bool) -> void:
	running = false
	retreat_button.disabled = true
	var alive := {}
	for u in Data.UNIT_ORDER:
		alive[u] = 0
	for u in units:
		if u["mine"] and float(u["hp"]) > 0.0:
			alive[u["type"]] = int(alive[u["type"]]) + 1
	var losses := {}
	var lost_total := 0
	for u in Data.UNIT_ORDER:
		var l := int(selection.get(u, 0)) - int(alive[u])
		losses[u] = l
		lost_total += l
	Game.apply_battle_losses(losses)
	var text := ""
	if win:
		text = "Chiến thắng!\nĐồn địch đã bị chiếm, lãnh thổ mở rộng.\nTổn thất: %d lính." % lost_total
		Game.capture_camp(camp_key)
	elif retreated:
		text = "Đã rút quân.\nTổn thất: %d lính." % lost_total
	else:
		text = "Thất bại.\nTổn thất: %d lính.\nHãy luyện thêm quân hoặc dùng lính khiên ở hàng trước." % lost_total
	result_label.text = text
	result_panel.visible = true
	_last_win = win


var _last_win := false


func _close() -> void:
	visible = false
	result_panel.visible = false
	finished.emit(_last_win)


func _on_retreat() -> void:
	if running:
		_finish(false, true)


func _toggle_speed() -> void:
	speed = 2 if speed == 1 else (4 if speed == 2 else 1)
	speed_button.text = "x%d" % speed


# ---------------------------------------------------------------- vẽ
func _draw_arena() -> void:
	var size := arena.size
	# bàn lục giác
	var hs := 34.0
	var w := hs * sqrt(3.0)
	var h := hs * 1.5 * Hex.SQUASH * 1.25
	var rows := int(size.y * 0.62 / h)
	var start_y := size.y * 0.16
	for r in rows:
		var off := (w / 2.0) if r % 2 == 1 else 0.0
		var cols := int(size.x / w) + 2
		for q in cols:
			var c := Vector2(q * w + off - w / 2.0, start_y + r * h)
			var pts := Hex.corners(c, hs - 2.0)
			var shade := 0.04 * ((q + r) % 2)
			draw_hex(pts, Color(0.30 + shade, 0.36 + shade, 0.24))
	# đạn
	for s in shots:
		var col := Color(0.6, 0.85, 1.0) if s["mine"] else Color(1.0, 0.6, 0.45)
		arena.draw_line(s["a"], s["b"], col, 2.0)
	# lính
	for u in units:
		if float(u["hp"]) <= 0.0:
			continue
		var p: Vector2 = u["pos"]
		var mine: bool = u["mine"]
		var body := Color("4a7fc1") if mine else Color("b8483a")
		var type: String = u["type"]
		arena.draw_circle(p + Vector2(0, 8), 11, Color(0, 0, 0, 0.25))
		match type:
			"linh_khien":
				arena.draw_rect(Rect2(p.x - 11, p.y - 12, 22, 22), body)
				arena.draw_rect(Rect2(p.x - 11, p.y - 12, 22, 22), Color(0.9, 0.9, 0.9), false, 2.0)
			"cung_thu", "cung_phi":
				arena.draw_circle(p, 9, body)
				arena.draw_arc(p + Vector2(8, 0), 8, -PI / 2, PI / 2, 8, Color("d9c08a"), 2.0)
			_:
				arena.draw_circle(p, 10, body)
				arena.draw_line(p + Vector2(6, 6), p + Vector2(14, -12), Color("cfcfcf"), 2.0)
		var ratio := clampf(float(u["hp"]) / float(u["max"]), 0.0, 1.0)
		arena.draw_rect(Rect2(p.x - 13, p.y - 22, 26, 4), Color(0, 0, 0, 0.6))
		arena.draw_rect(Rect2(p.x - 13, p.y - 22, 26 * ratio, 4), Color("6cd36c") if mine else Color("e86a5a"))
	# chú thích
	arena.draw_string(_font, Vector2(20, size.y * 0.17), "Địch", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.7, 0.65))
	arena.draw_string(_font, Vector2(20, size.y * 0.78), "Quân ta", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.85, 1))


func draw_hex(pts: PackedVector2Array, col: Color) -> void:
	arena.draw_colored_polygon(pts, col)
