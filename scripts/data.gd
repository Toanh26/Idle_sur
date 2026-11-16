extends Node
## Dữ liệu tĩnh của game (autoload "Data").
## Muốn cân bằng lại game thì chỉnh số ở file này.

# ---------- Hệ thống ----------
const TICK := 0.25                 # giây mô phỏng mỗi bước
const SAVE_PATH := "user://save.json"
const AUTOSAVE_SEC := 30.0
const OFFLINE_CAP := 12.0 * 3600.0 # tối đa 12 giờ AFK
const OFFLINE_STEP := 300.0        # mô phỏng offline theo bước 5 phút
const OFFLINE_NPC_EFF := 0.5       # NPC làm 50% khi vắng mặt
const MAP_RADIUS := 6
const START_OWNED_RADIUS := 2
const START_REVEAL_RADIUS := 3
const MAP_SEED := 20261116

# ---------- Tài nguyên ----------
const RES := {
	"lua": {"name": "Lúa", "color": Color("e3c84f"), "price": 0.4},
	"go": {"name": "Gỗ", "color": Color("b07a45"), "price": 0.5},
	"da": {"name": "Đá", "color": Color("b5b5ad"), "price": 0.6},
	"vang": {"name": "Vàng", "color": Color("f2b134"), "price": 0.0},
}
const RES_ORDER := ["lua", "go", "da", "vang"]
const WAREHOUSE_BASE := 200.0
const WAREHOUSE_GROWTH := 1.6

# ---------- Ngành nghề / thuần thục ----------
const SKILLS := {
	"don_go": {"name": "Đốn gỗ", "res": "go", "t0": 2.0, "tile": "forest", "verb": "Đốn gỗ"},
	"dap_da": {"name": "Đập đá", "res": "da", "t0": 2.5, "tile": "rock", "verb": "Đập đá"},
	"trong_lua": {"name": "Trồng lúa", "res": "lua", "t0": 3.0, "tile": "field", "verb": "Gặt lúa"},
}
const SKILL_ORDER := ["don_go", "dap_da", "trong_lua"]
const MANUAL_XP := 25.0
const AUTO_XP := 5.0               # XP mỗi đơn vị do thợ/máy làm ra
const MAX_LEVEL := 99
const HUT_UNLOCK := 10             # cấp mở thuê thợ
const AUTO_REPEAT_UNLOCK := 20     # cấp mở tự lặp thao tác tay
const CRANE_UNLOCK := 15           # cấp Đập đá mở cần cẩu
const MACHINE_UNLOCK := 30         # cấp mở máy móc

# ---------- Sản xuất & vận chuyển ----------
const NPC_RATE := 0.3              # đơn vị/giây mỗi thợ
const NPC_FOOD := 0.02             # lúa/giây mỗi thợ
const MAX_NPC_PER_TILE := 5
const MACHINE_BASE := 2.5          # đơn vị/giây của máy cấp 1
const STOCK_CAP := 60.0            # bãi chứa tại mỗi ô
const START_PORTERS := 2
const PORTER_CARRY := 5.0          # mỗi chuyến chở 5 đơn vị
const PORTER_TRIP_PER_HEX := 4.0   # giây đi-về cho mỗi ô khoảng cách
const ELEV_PENALTY := 0.75         # mỗi bậc độ cao làm chuyến đi lâu thêm 75%
const CRANE_BONUS := 1.5           # cần cẩu chở thêm 1.5 đơn vị/giây và bỏ phạt độ cao
const MAX_PORTERS_PER_TILE := 8

# ---------- Ô đất ----------
const TILES := {
	"village": {"name": "Làng", "color": Color("c9a66b")},
	"forest": {"name": "Rừng", "color": Color("4f7d3a"), "skill": "don_go"},
	"rock": {"name": "Mỏ đá", "color": Color("8d8b7c"), "skill": "dap_da"},
	"field": {"name": "Ruộng lúa", "color": Color("b9c45a"), "skill": "trong_lua"},
	"grass": {"name": "Đồng cỏ", "color": Color("7fae5a")},
	"water": {"name": "Sông", "color": Color("4a8fb8")},
	"camp": {"name": "Đồn thổ phỉ", "color": Color("7a4a35")},
}
const TILE_WEIGHTS := {"forest": 30, "rock": 16, "field": 12, "grass": 34, "water": 8}

# ---------- Quân đội ----------
const UNITS := {
	"dan_quan": {"name": "Dân quân", "cost": {"lua": 10, "go": 5}, "hp": 40.0, "atk": 6.0, "range": 40.0,
		"speed": 60.0, "time": 4.0, "upkeep": 0.004, "power": 5, "row": 1, "desc": "Rẻ, đông"},
	"cung_thu": {"name": "Cung thủ", "cost": {"lua": 10, "go": 15}, "hp": 25.0, "atk": 7.0, "range": 170.0,
		"speed": 55.0, "time": 6.0, "upkeep": 0.005, "power": 7, "row": 2, "desc": "Đánh xa"},
	"linh_khien": {"name": "Lính khiên", "cost": {"lua": 15, "go": 5, "da": 20}, "hp": 95.0, "atk": 4.0, "range": 40.0,
		"speed": 50.0, "time": 8.0, "upkeep": 0.006, "power": 10, "row": 0, "desc": "Đỡ đòn ở hàng trước"},
}
const UNIT_ORDER := ["dan_quan", "cung_thu", "linh_khien"]
const ENEMIES := {
	"tho_phi": {"name": "Thổ phỉ", "hp": 36.0, "atk": 5.5, "range": 40.0, "speed": 55.0},
	"cung_phi": {"name": "Cung phỉ", "hp": 22.0, "atk": 6.0, "range": 160.0, "speed": 50.0},
}
const BATTLE_MAX_PER_SIDE := 40
const BATTLE_TIME_LIMIT := 90.0

# ---------- Đồn địch ----------
const CAMPS := [Vector2i(3, -1), Vector2i(-3, 2), Vector2i(0, -3), Vector2i(4, 1),
	Vector2i(-4, -1), Vector2i(1, 4), Vector2i(-2, 5), Vector2i(6, -3)]

# ---------- Phòng thủ ----------
const STRUCTURES := {
	"rao": {"name": "Hàng rào tre", "cost": {"go": 30}, "def": 15},
	"thap_cung": {"name": "Tháp cung", "cost": {"go": 60, "da": 25}, "def": 35},
}
const STRUCTURE_ORDER := ["rao", "thap_cung"]
const VILLAGE_BASE_DEF := 10
const GARRISON_SHARE := 0.5        # quân ở nhà góp 50% sức mạnh vào phòng thủ
const RAID_INTERVAL := 1800.0      # 30 phút một đợt cướp (bản prototype)
const RAID_LOSS := 0.15


static func xp_for_level(lvl: int) -> float:
	## Tổng XP cần để lên cấp lvl + 1.
	return 50.0 * pow(float(lvl), 2.2)


static func camp_power(i: int) -> int:
	return int(50.0 * pow(1.4, i))


static func camp_name(i: int) -> String:
	if i == CAMPS.size() - 1:
		return "Sào huyệt thủ lĩnh thổ phỉ"
	return "Đồn thổ phỉ số %d" % (i + 1)


static func raid_power(camps_taken: int) -> int:
	return int(30.0 * pow(1.3, camps_taken))
