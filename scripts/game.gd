extends Node
## Trạng thái và mô phỏng game (autoload "Game").
## Mô phỏng chạy theo bước cố định Data.TICK; cùng một hàm simulate() dùng cho lúc chơi và lúc offline.

signal structure_changed      # có gì đó thay đổi cần dựng lại giao diện / bản đồ
signal logged(msg: String)
signal offline_ready          # vừa tính xong phần thưởng AFK (khi mở lại app)

const Hex = preload("res://scripts/hex.gd")

var res := {}
var warehouse_lvl := 0
var xp := {}
var tool_lvl := {}
var tiles := {}
var draw_order: Array = []
var army := {}
var train_queue: Array = []
var porters_total := 0
var camps_taken := 0
var raid_timer := 0.0
var manual := {}
var auto_repeat := false
var log_lines: Array = []
var play_time := 0.0
var world_speed := 1.0
var starving := false
var offline_report := ""

var _acc := 0.0
var _save_acc := 0.0
var _last_levels := {}
var _paused_at := 0.0


func _ready() -> void:
	if not load_game():
		new_game()
	for s in Data.SKILL_ORDER:
		_last_levels[s] = skill_level(s)


# =====================================================================
#  Khởi tạo
# =====================================================================
func new_game() -> void:
	res = {"lua": 30.0, "go": 0.0, "da": 0.0, "vang": 40.0}
	warehouse_lvl = 0
	xp = {}
	tool_lvl = {}
	for s in Data.SKILL_ORDER:
		xp[s] = 0.0
		tool_lvl[s] = 0
	army = {}
	for u in Data.UNIT_ORDER:
		army[u] = 0
	train_queue = []
	porters_total = Data.START_PORTERS
	camps_taken = 0
	raid_timer = Data.RAID_INTERVAL
	manual = {}
	auto_repeat = false
	log_lines = []
	play_time = 0.0
	starving = false
	offline_report = ""
	_gen_map()
	add_log("Một làng quê yên bình bên sông. Hãy bắt đầu bằng đôi tay: chạm vào Rừng, Mỏ đá hoặc Ruộng lúa.")


func _gen_map() -> void:
	tiles = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = Data.MAP_SEED
	var R: int = Data.MAP_RADIUS
	for c in Hex.coords_in_radius(Vector2i.ZERO, R):
		var d := Hex.distance(c, Vector2i.ZERO)
		var type := _rand_type(rng)
		var elev := 0
		if type == "rock":
			elev = rng.randi_range(1, 2)
		elif (type == "forest" or type == "grass") and rng.randf() < 0.15:
			elev = 1
		tiles[Hex.key(c.x, c.y)] = {
			"q": c.x, "r": c.y, "type": type, "elev": elev,
			"owned": d <= Data.START_OWNED_RADIUS, "revealed": d <= Data.START_REVEAL_RADIUS,
			"npcs": 0, "porters": 0, "machine": 0, "crane": false, "stock": 0.0,
			"structure": "", "camp": -1,
		}
	# Làng ở giữa và vòng đầu cố định để khởi đầu luôn có đủ loại tài nguyên.
	var fixed := {
		Vector2i(0, 0): ["village", 0], Vector2i(1, 0): ["forest", 0], Vector2i(1, -1): ["rock", 1],
		Vector2i(0, -1): ["field", 0], Vector2i(-1, 0): ["grass", 0], Vector2i(-1, 1): ["forest", 0],
		Vector2i(0, 1): ["field", 0],
	}
	for c in fixed:
		var t: Dictionary = tiles[Hex.key(c.x, c.y)]
		t["type"] = fixed[c][0]
		t["elev"] = fixed[c][1]
	for i in Data.CAMPS.size():
		var cp: Vector2i = Data.CAMPS[i]
		var t: Dictionary = tiles[Hex.key(cp.x, cp.y)]
		t["type"] = "camp"
		t["camp"] = i
		t["elev"] = 0
		t["owned"] = false
	_build_draw_order()


func _rand_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in Data.TILE_WEIGHTS:
		total += int(Data.TILE_WEIGHTS[k])
	var roll := rng.randi_range(1, total)
	for k in Data.TILE_WEIGHTS:
		roll -= int(Data.TILE_WEIGHTS[k])
		if roll <= 0:
			return k
	return "grass"


func _build_draw_order() -> void:
	## Vẽ từ xa tới gần: ô có toạ độ màn hình y nhỏ hơn vẽ trước.
	draw_order = tiles.keys()
	draw_order.sort_custom(func(a, b):
		var ta: Dictionary = tiles[a]
		var tb: Dictionary = tiles[b]
		var ya := 2 * int(ta["r"]) + int(ta["q"])
		var yb := 2 * int(tb["r"]) + int(tb["q"])
		if ya != yb:
			return ya < yb
		return int(ta["q"]) < int(tb["q"]))


# =====================================================================
#  Vòng lặp
# =====================================================================
func _process(delta: float) -> void:
	_acc += delta * world_speed
	var steps := 0
	while _acc >= Data.TICK and steps < 400:
		_acc -= Data.TICK
		steps += 1
		simulate(Data.TICK, false)
		_tick_manual(Data.TICK)
	_check_levels()
	_save_acc += delta
	if _save_acc >= Data.AUTOSAVE_SEC:
		_save_acc = 0.0
		save_game()


func simulate(dt: float, offline: bool) -> void:
	play_time += dt
	# --- Lương thực cho thợ và quân ---
	var food_need := (total_npcs() * Data.NPC_FOOD + army_upkeep()) * dt
	if float(res["lua"]) >= food_need:
		res["lua"] = float(res["lua"]) - food_need
		starving = false
	else:
		res["lua"] = 0.0
		starving = food_need > 0.0

	# --- Sản xuất tại từng ô + vận chuyển về kho ---
	for key in tiles:
		var t: Dictionary = tiles[key]
		if not t["owned"]:
			continue
		var s := tile_skill(t)
		if s == "":
			continue
		var prod := tile_rate(t, offline) * dt
		var stock_before: float = t["stock"]
		var available := stock_before + prod
		var moved := 0.0
		if available > 0.0:
			var res_id: String = Data.SKILLS[s]["res"]
			moved = add_res(res_id, minf(available, transport_rate(key) * dt))
		var new_stock := minf(Data.STOCK_CAP, available - moved)
		var produced := new_stock + moved - stock_before
		if produced > 0.0:
			xp[s] = float(xp[s]) + produced * Data.AUTO_XP
		t["stock"] = new_stock

	# --- Huấn luyện ---
	var left := dt
	while left > 0.0 and train_queue.size() > 0:
		var job: Dictionary = train_queue[0]
		var use := minf(left, float(job["t"]))
		job["t"] = float(job["t"]) - use
		left -= use
		if float(job["t"]) <= 0.0:
			var u: String = job["unit"]
			army[u] = int(army[u]) + 1
			train_queue.pop_front()
			if not offline:
				structure_changed.emit()

	# --- Đợt cướp ---
	raid_timer -= dt
	if raid_timer <= 0.0:
		raid_timer += Data.RAID_INTERVAL
		_resolve_raid()


func _tick_manual(dt: float) -> void:
	if manual.is_empty():
		return
	manual["t"] = float(manual["t"]) + dt
	if float(manual["t"]) < float(manual["dur"]):
		return
	var key: String = manual["key"]
	var t: Dictionary = tiles[key]
	var s := tile_skill(t)
	var res_id: String = Data.SKILLS[s]["res"]
	add_res(res_id, manual_yield(s))
	xp[s] = float(xp[s]) + Data.MANUAL_XP
	if auto_repeat and skill_level(s) >= Data.AUTO_REPEAT_UNLOCK:
		manual["t"] = 0.0
		manual["dur"] = manual_duration(s)
	else:
		manual = {}


func _check_levels() -> void:
	for s in Data.SKILL_ORDER:
		var lvl := skill_level(s)
		var old: int = _last_levels.get(s, lvl)
		if lvl > old:
			_last_levels[s] = lvl
			var sname: String = Data.SKILLS[s]["name"]
			var msg := "%s lên cấp %d." % [sname, lvl]
			if old < Data.HUT_UNLOCK and lvl >= Data.HUT_UNLOCK:
				msg += " Đã mở thuê thợ!"
			if old < Data.AUTO_REPEAT_UNLOCK and lvl >= Data.AUTO_REPEAT_UNLOCK:
				msg += " Đã mở tự lặp thao tác tay!"
			if s == "dap_da" and old < Data.CRANE_UNLOCK and lvl >= Data.CRANE_UNLOCK:
				msg += " Đã mở cần cẩu!"
			if old < Data.MACHINE_UNLOCK and lvl >= Data.MACHINE_UNLOCK:
				msg += " Đã mở máy móc!"
			add_log(msg)
			structure_changed.emit()


# =====================================================================
#  Tính toán
# =====================================================================
func skill_level(s: String) -> int:
	var lvl := 1
	var v: float = xp[s]
	while lvl < Data.MAX_LEVEL and v >= Data.xp_for_level(lvl):
		lvl += 1
	return lvl


func level_progress(s: String) -> float:
	var lvl := skill_level(s)
	if lvl >= Data.MAX_LEVEL:
		return 1.0
	var lo := 0.0 if lvl == 1 else Data.xp_for_level(lvl - 1)
	var hi := Data.xp_for_level(lvl)
	return clampf((float(xp[s]) - lo) / (hi - lo), 0.0, 1.0)


func mastery_mult(s: String) -> float:
	var l := skill_level(s)
	var m := 1.0 + 0.01 * l
	if l >= 50:
		m *= 1.25
	if l >= 99:
		m *= 2.0
	return m


func manual_duration(s: String) -> float:
	return maxf(0.2, float(Data.SKILLS[s]["t0"]) * pow(0.97, skill_level(s) - 1))


func manual_yield(s: String) -> float:
	return 1.0 + 0.5 * int(tool_lvl[s])


func manual_progress(key: String) -> float:
	if manual.is_empty() or manual["key"] != key:
		return 0.0
	return clampf(float(manual["t"]) / float(manual["dur"]), 0.0, 1.0)


func tile_skill(t: Dictionary) -> String:
	return String(Data.TILES[t["type"]].get("skill", ""))


func tile_coord(t: Dictionary) -> Vector2i:
	return Vector2i(int(t["q"]), int(t["r"]))


func tile_rate(t: Dictionary, offline := false) -> float:
	var s := tile_skill(t)
	if s == "":
		return 0.0
	var npc_r := int(t["npcs"]) * Data.NPC_RATE
	if offline:
		npc_r *= Data.OFFLINE_NPC_EFF
	if starving:
		npc_r *= 0.25
	var mach := 0.0
	var ml := int(t["machine"])
	if ml > 0:
		mach = Data.MACHINE_BASE * (1.0 + 0.5 * (ml - 1))
	return (npc_r + mach) * mastery_mult(s)


func transport_rate(key: String) -> float:
	var t: Dictionary = tiles[key]
	var d := maxi(1, Hex.distance(tile_coord(t), Vector2i.ZERO))
	var trip := Data.PORTER_TRIP_PER_HEX * d
	if not t["crane"]:
		trip *= 1.0 + Data.ELEV_PENALTY * int(t["elev"])
	var r := int(t["porters"]) * Data.PORTER_CARRY / trip
	if t["crane"]:
		r += Data.CRANE_BONUS
	return r


func cap() -> float:
	return Data.WAREHOUSE_BASE * pow(Data.WAREHOUSE_GROWTH, warehouse_lvl)


func add_res(id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if id == "vang":
		res[id] = float(res[id]) + amount
		return amount
	var space := maxf(0.0, cap() - float(res[id]))
	var added := minf(space, amount)
	res[id] = float(res[id]) + added
	return added


func total_npcs() -> int:
	var n := 0
	for key in tiles:
		n += int(tiles[key]["npcs"])
	return n


func porters_assigned() -> int:
	var n := 0
	for key in tiles:
		n += int(tiles[key]["porters"])
	return n


func porters_free() -> int:
	return porters_total - porters_assigned()


func army_power() -> int:
	var p := 0
	for u in Data.UNIT_ORDER:
		p += int(army[u]) * int(Data.UNITS[u]["power"])
	return p


func army_count() -> int:
	var n := 0
	for u in Data.UNIT_ORDER:
		n += int(army[u])
	return n


func army_upkeep() -> float:
	var f := 0.0
	for u in Data.UNIT_ORDER:
		f += int(army[u]) * float(Data.UNITS[u]["upkeep"])
	return f


func defense_power() -> int:
	var d := Data.VILLAGE_BASE_DEF
	for key in tiles:
		var st: String = tiles[key]["structure"]
		if st != "":
			d += int(Data.STRUCTURES[st]["def"])
	return d + int(army_power() * Data.GARRISON_SHARE)


func food_rate() -> float:
	## Lúa vào kho mỗi giây trừ đi lúa ăn mỗi giây (ước tính).
	var income := 0.0
	for key in tiles:
		var t: Dictionary = tiles[key]
		if t["owned"] and tile_skill(t) == "trong_lua":
			income += minf(tile_rate(t), transport_rate(key))
	return income - (total_npcs() * Data.NPC_FOOD + army_upkeep())


func bottleneck_text(key: String) -> String:
	var t: Dictionary = tiles[key]
	var s := tile_skill(t)
	if s == "":
		return ""
	var prod := tile_rate(t)
	var tr := transport_rate(key)
	var res_id: String = Data.SKILLS[s]["res"]
	if prod <= 0.0:
		return "Chưa có thợ hay máy: chỉ khai thác bằng tay."
	if tr <= 0.0:
		return "Nút thắt: chưa có khuân vác, hàng nằm ở bãi."
	if float(res[res_id]) >= cap() - 0.5:
		return "Nút thắt: kho đầy. Nâng cấp kho hoặc bán bớt."
	if tr < prod:
		return "Nút thắt: vận chuyển (chở %.2f < làm ra %.2f/giây)." % [tr, prod]
	return "Ổn định: vận chuyển theo kịp sản xuất."


func is_attackable(key: String) -> bool:
	var t: Dictionary = tiles[key]
	if t["type"] != "camp" or not t["revealed"]:
		return false
	for n in Hex.neighbors(int(t["q"]), int(t["r"])):
		var nk := Hex.key(n.x, n.y)
		if tiles.has(nk) and tiles[nk]["owned"]:
			return true
	return false


func is_fog_edge(key: String) -> bool:
	var t: Dictionary = tiles[key]
	if t["revealed"]:
		return false
	for n in Hex.neighbors(int(t["q"]), int(t["r"])):
		var nk := Hex.key(n.x, n.y)
		if tiles.has(nk) and tiles[nk]["revealed"]:
			return true
	return false


# =====================================================================
#  Chi phí
# =====================================================================
func cost_npc() -> Dictionary:
	return {"vang": int(15.0 * pow(1.15, total_npcs())), "lua": 10}


func cost_porter() -> Dictionary:
	return {"vang": int(10.0 * pow(1.12, porters_total - Data.START_PORTERS))}


func cost_tool(s: String) -> Dictionary:
	var n := int(tool_lvl[s])
	return {"go": int(15.0 * pow(1.25, n)), "da": int(10.0 * pow(1.25, n))}


func cost_machine(t: Dictionary) -> Dictionary:
	var n := int(t["machine"])
	return {"go": int(150.0 * pow(1.3, n)), "da": int(150.0 * pow(1.3, n)), "vang": int(80.0 * pow(1.3, n))}


func cost_crane() -> Dictionary:
	return {"go": 80, "da": 60}


func cost_warehouse() -> Dictionary:
	return {"go": int(100.0 * pow(1.6, warehouse_lvl)), "da": int(80.0 * pow(1.6, warehouse_lvl))}


func cost_clear_field() -> Dictionary:
	return {"go": 20}


func can_afford(c: Dictionary) -> bool:
	for id in c:
		if float(res.get(id, 0.0)) < float(c[id]):
			return false
	return true


func pay(c: Dictionary) -> bool:
	if not can_afford(c):
		return false
	for id in c:
		res[id] = float(res[id]) - float(c[id])
	return true


func cost_text(c: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in Data.RES_ORDER:
		if c.has(id):
			parts.append("%d %s" % [int(c[id]), Data.RES[id]["name"]])
	return ", ".join(parts)


# =====================================================================
#  Hành động của người chơi
# =====================================================================
func start_manual(key: String) -> void:
	if not manual.is_empty() or not tiles.has(key):
		return
	var t: Dictionary = tiles[key]
	var s := tile_skill(t)
	if s == "" or not t["owned"]:
		return
	manual = {"key": key, "t": 0.0, "dur": manual_duration(s)}


func stop_manual() -> void:
	manual = {}


func can_hire_npc(key: String) -> bool:
	var t: Dictionary = tiles[key]
	var s := tile_skill(t)
	return s != "" and t["owned"] and skill_level(s) >= Data.HUT_UNLOCK \
		and int(t["npcs"]) < Data.MAX_NPC_PER_TILE and can_afford(cost_npc())


func hire_npc(key: String) -> void:
	if not can_hire_npc(key):
		return
	pay(cost_npc())
	tiles[key]["npcs"] = int(tiles[key]["npcs"]) + 1
	if int(tiles[key]["npcs"]) == 1:
		add_log("Thợ đầu tiên đã đến làm việc. Đừng quên giao khuân vác cho ô này!")
	structure_changed.emit()


func hire_porter() -> void:
	if pay(cost_porter()):
		porters_total += 1
		structure_changed.emit()


func assign_porter(key: String, delta: int) -> void:
	var t: Dictionary = tiles[key]
	var cur := int(t["porters"])
	if delta > 0 and (porters_free() <= 0 or cur >= Data.MAX_PORTERS_PER_TILE):
		return
	if delta < 0 and cur <= 0:
		return
	t["porters"] = cur + delta
	structure_changed.emit()


func can_buy_machine(key: String) -> bool:
	var t: Dictionary = tiles[key]
	var s := tile_skill(t)
	return s != "" and t["owned"] and skill_level(s) >= Data.MACHINE_UNLOCK and can_afford(cost_machine(t))


func buy_machine(key: String) -> void:
	if not can_buy_machine(key):
		return
	var t: Dictionary = tiles[key]
	pay(cost_machine(t))
	t["machine"] = int(t["machine"]) + 1
	add_log("Máy móc cấp %d bắt đầu chạy." % int(t["machine"]))
	structure_changed.emit()


func can_build_crane(key: String) -> bool:
	var t: Dictionary = tiles[key]
	return t["owned"] and int(t["elev"]) > 0 and not t["crane"] \
		and skill_level("dap_da") >= Data.CRANE_UNLOCK and can_afford(cost_crane())


func build_crane(key: String) -> void:
	if not can_build_crane(key):
		return
	pay(cost_crane())
	tiles[key]["crane"] = true
	add_log("Cần cẩu đầu tiên kéo hàng lên dốc. Phạt độ cao đã hết!")
	structure_changed.emit()


func upgrade_tool(s: String) -> void:
	if pay(cost_tool(s)):
		tool_lvl[s] = int(tool_lvl[s]) + 1
		structure_changed.emit()


func upgrade_warehouse() -> void:
	if pay(cost_warehouse()):
		warehouse_lvl += 1
		add_log("Kho lên cấp %d, sức chứa %d." % [warehouse_lvl, int(cap())])
		structure_changed.emit()


func sell(id: String, amount: float) -> void:
	var a := minf(amount, float(res[id]))
	if a <= 0.0:
		return
	res[id] = float(res[id]) - a
	res["vang"] = float(res["vang"]) + a * float(Data.RES[id]["price"])


func can_build_structure(key: String, sid: String) -> bool:
	var t: Dictionary = tiles[key]
	return t["owned"] and t["type"] == "grass" and t["structure"] == "" \
		and can_afford(Data.STRUCTURES[sid]["cost"])


func build_structure(key: String, sid: String) -> void:
	if not can_build_structure(key, sid):
		return
	pay(Data.STRUCTURES[sid]["cost"])
	tiles[key]["structure"] = sid
	structure_changed.emit()


func clear_field(key: String) -> void:
	var t: Dictionary = tiles[key]
	if t["owned"] and t["type"] == "grass" and t["structure"] == "" and pay(cost_clear_field()):
		t["type"] = "field"
		structure_changed.emit()


func can_train(u: String, n: int = 1) -> bool:
	var c: Dictionary = Data.UNITS[u]["cost"]
	var total := {}
	for id in c:
		total[id] = int(c[id]) * n
	return can_afford(total)


func train(u: String, n: int = 1) -> void:
	for i in n:
		if not pay(Data.UNITS[u]["cost"]):
			break
		train_queue.append({"unit": u, "t": float(Data.UNITS[u]["time"])})
	structure_changed.emit()


func apply_battle_losses(losses: Dictionary) -> void:
	for u in losses:
		army[u] = maxi(0, int(army[u]) - int(losses[u]))
	structure_changed.emit()


func capture_camp(key: String) -> void:
	var t: Dictionary = tiles[key]
	var idx := int(t["camp"])
	var loot := 30 * (idx + 1)
	res["vang"] = float(res["vang"]) + loot
	add_res("go", 20.0 * (idx + 1))
	add_res("da", 15.0 * (idx + 1))
	t["type"] = "grass"
	t["camp"] = -1
	camps_taken += 1
	var c := tile_coord(t)
	for n in Hex.coords_in_radius(c, 2):
		var nk := Hex.key(n.x, n.y)
		if not tiles.has(nk):
			continue
		var nt: Dictionary = tiles[nk]
		nt["revealed"] = true
		if Hex.distance(n, c) <= 1 and nt["type"] != "camp":
			nt["owned"] = true
	for n in Hex.coords_in_radius(c, 3):
		var nk := Hex.key(n.x, n.y)
		if tiles.has(nk):
			tiles[nk]["revealed"] = true
	if idx == Data.CAMPS.size() - 1:
		add_log("Sào huyệt thủ lĩnh đã thất thủ! Thung lũng hoàn toàn thuộc về bạn. (Hết nội dung prototype)")
	else:
		add_log("Chiếm được %s! +%d Vàng, lãnh thổ mở rộng." % [Data.camp_name(idx), loot])
	structure_changed.emit()


func _resolve_raid() -> void:
	var atk := Data.raid_power(camps_taken)
	var def := defense_power()
	if def >= atk:
		var loot := int(atk * 0.3)
		res["vang"] = float(res["vang"]) + loot
		add_log("Đánh lui đợt cướp (địch %d / phòng thủ %d). +%d Vàng." % [atk, def, loot])
	else:
		for id in ["lua", "go", "da"]:
			res[id] = float(res[id]) * (1.0 - Data.RAID_LOSS)
		add_log("Thổ phỉ cướp làng! Mất 15%% lúa, gỗ, đá (địch %d / phòng thủ %d). Xây tháp, hàng rào hoặc thêm quân." % [atk, def])


func add_log(msg: String) -> void:
	var stamp := Time.get_time_string_from_system().substr(0, 5)
	log_lines.push_front("[%s] %s" % [stamp, msg])
	if log_lines.size() > 40:
		log_lines.resize(40)
	logged.emit(msg)


# =====================================================================
#  Lưu / tải / offline
# =====================================================================
func save_game() -> void:
	var data := {
		"v": 1, "time": Time.get_unix_time_from_system(),
		"res": res, "warehouse": warehouse_lvl, "xp": xp, "tool": tool_lvl, "tiles": tiles,
		"army": army, "queue": train_queue, "porters": porters_total, "camps": camps_taken,
		"raid": raid_timer, "log": log_lines, "repeat": auto_repeat, "play": play_time,
	}
	var f := FileAccess.open(Data.SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(Data.SAVE_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Data.SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	res = d.get("res", {})
	for id in Data.RES_ORDER:
		res[id] = float(res.get(id, 0.0))
	warehouse_lvl = int(d.get("warehouse", 0))
	xp = d.get("xp", {})
	tool_lvl = d.get("tool", {})
	for s in Data.SKILL_ORDER:
		xp[s] = float(xp.get(s, 0.0))
		tool_lvl[s] = int(tool_lvl.get(s, 0))
	army = d.get("army", {})
	for u in Data.UNIT_ORDER:
		army[u] = int(army.get(u, 0))
	tiles = d.get("tiles", {})
	if tiles.is_empty():
		return false
	for key in tiles:
		var t: Dictionary = tiles[key]
		for f in ["q", "r", "elev", "npcs", "porters", "machine", "camp"]:
			t[f] = int(t.get(f, 0))
		t["stock"] = float(t.get("stock", 0.0))
	train_queue = d.get("queue", [])
	porters_total = int(d.get("porters", Data.START_PORTERS))
	camps_taken = int(d.get("camps", 0))
	raid_timer = float(d.get("raid", Data.RAID_INTERVAL))
	log_lines = d.get("log", [])
	auto_repeat = bool(d.get("repeat", false))
	play_time = float(d.get("play", 0.0))
	manual = {}
	_build_draw_order()
	var elapsed := Time.get_unix_time_from_system() - float(d.get("time", Time.get_unix_time_from_system()))
	if elapsed > 60.0:
		_run_offline(elapsed)
	return true


func _run_offline(elapsed: float) -> void:
	var secs := minf(elapsed, Data.OFFLINE_CAP)
	var before := res.duplicate()
	var remaining := secs
	while remaining > 0.0:
		var step := minf(Data.OFFLINE_STEP, remaining)
		simulate(step, true)
		remaining -= step
	var lines := PackedStringArray()
	lines.append("Bạn đã vắng mặt %s%s." % [_fmt_duration(elapsed), " (tính tối đa 12 giờ)" if elapsed > Data.OFFLINE_CAP else ""])
	var gains := PackedStringArray()
	for id in Data.RES_ORDER:
		var g := float(res[id]) - float(before[id])
		if absf(g) >= 1.0:
			gains.append("%+d %s" % [int(g), Data.RES[id]["name"]])
	lines.append("Thu được: " + (", ".join(gains) if gains.size() > 0 else "không có gì (chưa có thợ hoặc máy)."))
	var hints := PackedStringArray()
	for key in tiles:
		var t: Dictionary = tiles[key]
		if t["owned"] and float(t["stock"]) >= Data.STOCK_CAP * 0.95:
			hints.append("Bãi chứa ở %s đầy: cần thêm khuân vác hoặc cần cẩu." % Data.TILES[t["type"]]["name"])
			break
	for id in ["lua", "go", "da"]:
		if float(res[id]) >= cap() - 0.5:
			hints.append("Kho %s đã đầy: nâng cấp kho." % Data.RES[id]["name"])
			break
	if starving:
		hints.append("Hết lúa: thợ làm việc rất chậm. Cần thêm ruộng hoặc thợ trồng lúa.")
	if hints.size() > 0:
		lines.append("Nút thắt: " + " ".join(hints))
	offline_report = "\n".join(lines)
	add_log("Thu hoạch AFK sau %s." % _fmt_duration(elapsed))


func _fmt_duration(s: float) -> String:
	var h := int(s) / 3600
	var m := (int(s) % 3600) / 60
	if h > 0:
		return "%d giờ %d phút" % [h, m]
	return "%d phút" % m


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
		_paused_at = Time.get_unix_time_from_system()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _paused_at > 0.0:
			var elapsed := Time.get_unix_time_from_system() - _paused_at
			_paused_at = 0.0
			if elapsed > 60.0:
				_run_offline(elapsed)
				offline_ready.emit()
				structure_changed.emit()


func reset_game() -> void:
	if FileAccess.file_exists(Data.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Data.SAVE_PATH))
	new_game()
	for s in Data.SKILL_ORDER:
		_last_levels[s] = skill_level(s)
	structure_changed.emit()
