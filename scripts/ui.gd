extends CanvasLayer
## Giao diện: thanh tài nguyên, bảng thông tin và 4 tab dưới cùng.
## Bảng được dựng lại khi có thay đổi lớn; số liệu nhỏ cập nhật 5 lần/giây qua danh sách _live.

const TOP_H := 118
const PANEL_H := 470
const TAB_H := 96

var map_view
var battle

var root: Control
var top_labels := {}
var info_label: Label
var panel: PanelContainer
var content: VBoxContainer
var tab_buttons := {}
var popup: PanelContainer
var popup_title: Label
var popup_text: Label

var tab := "map"
var selected := ""
var army_pick := {}
var _live: Array = []
var _refresh_acc := 0.0
var _rebuild_pending := false
var _theme: Theme


func setup() -> void:
	_theme = _make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	_build_top()
	_build_tabs()
	_build_panel()
	_build_popup()
	if battle:
		battle.set_theme_from(_theme)
	Game.structure_changed.connect(_request_rebuild)
	Game.offline_ready.connect(func(): show_popup("Chào mừng trở lại", Game.offline_report))
	_rebuild()


# =====================================================================
#  Khung giao diện
# =====================================================================
func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.09, 0.93)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(14)
	sb.border_color = Color(0.55, 0.42, 0.24, 0.8)
	sb.set_border_width_all(2)
	th.set_stylebox("panel", "PanelContainer", sb)
	var b := StyleBoxFlat.new()
	b.bg_color = Color("6b4f2a")
	b.set_corner_radius_all(10)
	b.set_content_margin_all(10)
	var bh := b.duplicate() as StyleBoxFlat
	bh.bg_color = Color("86643a")
	var bp := b.duplicate() as StyleBoxFlat
	bp.bg_color = Color("4a361c")
	var bd := b.duplicate() as StyleBoxFlat
	bd.bg_color = Color(0.28, 0.27, 0.25, 0.85)
	th.set_stylebox("normal", "Button", b)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("disabled", "Button", bd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color("fff6e0"))
	th.set_color("font_disabled_color", "Button", Color(0.62, 0.6, 0.56))
	th.set_color("font_color", "Label", Color("f3ead8"))
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0, 0, 0, 0.45)
	pbg.set_corner_radius_all(6)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = Color("d9a43a")
	pfill.set_corner_radius_all(6)
	th.set_stylebox("background", "ProgressBar", pbg)
	th.set_stylebox("fill", "ProgressBar", pfill)
	return th


func _build_top() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pc.offset_left = 8
	pc.offset_right = -8
	pc.offset_top = 8
	pc.offset_bottom = TOP_H
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for id in Data.RES_ORDER:
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var col: Color = Data.RES[id]["color"]
		l.add_theme_color_override("font_color", col.lightened(0.25))
		hb.add_child(l)
		top_labels[id] = l
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 17)
	vb.add_child(info_label)


func _build_tabs() -> void:
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hb.offset_top = -TAB_H
	hb.offset_bottom = -8
	hb.offset_left = 8
	hb.offset_right = -8
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(hb)
	for pair in [["map", "Bản đồ"], ["skills", "Ngành nghề"], ["army", "Quân đội"], ["village", "Làng & Kho"]]:
		var b := Button.new()
		b.text = pair[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_tab.bind(pair[0]))
		hb.add_child(b)
		tab_buttons[pair[0]] = b


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -(TAB_H + PANEL_H)
	panel.offset_bottom = -TAB_H - 4
	panel.offset_left = 8
	panel.offset_right = -8
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	sc.add_child(content)


func _build_popup() -> void:
	popup = PanelContainer.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -300
	popup.offset_right = 300
	popup.offset_top = -220
	popup.offset_bottom = 220
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(popup)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	popup.add_child(vb)
	popup_title = Label.new()
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title.add_theme_font_size_override("font_size", 28)
	popup_title.add_theme_color_override("font_color", Color("f2c45a"))
	vb.add_child(popup_title)
	popup_text = Label.new()
	popup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(popup_text)
	var ok := Button.new()
	ok.text = "Nhận"
	ok.pressed.connect(func(): popup.visible = false)
	vb.add_child(ok)


func show_popup(title: String, text: String) -> void:
	if text == "":
		return
	popup_title.text = title
	popup_text.text = text
	popup.visible = true


# =====================================================================
#  Cập nhật
# =====================================================================
func _process(delta: float) -> void:
	_refresh_acc += delta
	if _refresh_acc < 0.2:
		return
	_refresh_acc = 0.0
	_update_top()
	for f in _live:
		f.call()


func _update_top() -> void:
	for id in Data.RES_ORDER:
		var l: Label = top_labels[id]
		var v := float(Game.res[id])
		if id == "vang":
			l.text = "%s %s" % [Data.RES[id]["name"], _fmt(v)]
		else:
			l.text = "%s %s/%s" % [Data.RES[id]["name"], _fmt(v), _fmt(Game.cap())]
	var mins := int(Game.raid_timer) / 60
	var secs := int(Game.raid_timer) % 60
	var food := Game.food_rate()
	var food_txt := "Lúa %+.2f/s" % food
	if Game.starving:
		food_txt = "HẾT LÚA!"
	info_label.text = "Quân %d · Phòng thủ %d · Cướp sau %d:%02d · %s%s" % [
		Game.army_power(), Game.defense_power(), mins, secs, food_txt,
		("  ·  x%d" % int(Game.world_speed)) if Game.world_speed > 1.0 else ""]


func _request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	_live.clear()
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	for k in tab_buttons:
		var b: Button = tab_buttons[k]
		b.modulate = Color(1, 1, 1) if k == tab else Color(0.75, 0.72, 0.68)
	match tab:
		"map":
			_build_map_tab()
		"skills":
			_build_skills_tab()
		"army":
			_build_army_tab()
		"village":
			_build_village_tab()
	for f in _live:
		f.call()


func _on_tab(id: String) -> void:
	tab = id
	_rebuild()


func on_tile_tapped(key: String) -> void:
	selected = key
	tab = "map"
	army_pick = {}
	_rebuild()


func on_battle_finished(_win: bool) -> void:
	_rebuild()


# =====================================================================
#  Hàm dựng phần tử
# =====================================================================
func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 27)
	l.add_theme_color_override("font_color", Color("f2c45a"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l


func _sub(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 23)
	l.add_theme_color_override("font_color", Color("e7b86a"))
	content.add_child(l)
	return l


func _label(text, parent: Control = null) -> Label:
	## text là String hoặc Callable trả về String (tự cập nhật).
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 19)
	if text is Callable:
		var f: Callable = text
		_live.append(func(): l.text = f.call())
	else:
		l.text = str(text)
	(parent if parent else content).add_child(l)
	return l


func _button(text, on_press: Callable, enabled: Callable = Callable(), parent: Control = null) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	if text is Callable:
		var f: Callable = text
		_live.append(func(): b.text = f.call())
	else:
		b.text = str(text)
	b.pressed.connect(on_press)
	if enabled.is_valid():
		_live.append(func(): b.disabled = not enabled.call())
	(parent if parent else content).add_child(b)
	return b


func _row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	content.add_child(hb)
	return hb


func _bar(value: Callable) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 18)
	_live.append(func(): pb.value = value.call())
	content.add_child(pb)
	return pb


func _sep() -> void:
	var s := HSeparator.new()
	s.modulate = Color(1, 1, 1, 0.35)
	content.add_child(s)


func _fmt(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%.1fK" % (v / 1000.0)
	return "%d" % int(v)


# =====================================================================
#  Tab Bản đồ
# =====================================================================
func _build_map_tab() -> void:
	if selected == "" or not Game.tiles.has(selected):
		_title("Thung lũng Khởi Nguyên")
		_label("Chạm vào một ô trên bản đồ để xem và ra lệnh. Kéo để di chuyển, chụm hai ngón (hoặc lăn chuột) để thu phóng.")
		_label("Bắt đầu: tự tay đốn gỗ, đập đá, gặt lúa. Lên cấp 10 ở một ngành để thuê thợ, rồi giao khuân vác chở hàng về làng.")
		return
	var key := selected
	var t: Dictionary = Game.tiles[key]
	if not t["revealed"]:
		_title("Vùng sương mù")
		_label("Chưa khám phá. Chiếm đồn địch gần đó để mở rộng tầm nhìn.")
		return
	var type: String = t["type"]
	var title_txt: String = Data.TILES[type]["name"]
	if type == "camp":
		title_txt = Data.camp_name(int(t["camp"]))
	_title(title_txt + ("" if t["owned"] or type == "camp" else "  (ngoài lãnh thổ)"))
	if int(t["elev"]) > 0:
		_label("Độ cao: %d bậc. Khuân vác đi chậm hơn nếu không có cần cẩu." % int(t["elev"]))
	match type:
		"camp":
			_build_camp(key, t)
		"village":
			_label("Trung tâm làng, nơi đặt kho. Khuân vác chở tài nguyên từ bãi chứa các ô về đây.")
			_label(func(): return "Khuân vác: %d tổng, %d đang rảnh." % [Game.porters_total, Game.porters_free()])
			_button(func(): return "Thuê khuân vác (%s)" % Game.cost_text(Game.cost_porter()),
				func(): Game.hire_porter(), func(): return Game.can_afford(Game.cost_porter()))
		"grass":
			_build_grass(key, t)
		"water":
			_label("Dòng sông chảy qua thung lũng. (Thời kỳ sau: bánh xe nước, câu cá.)")
		_:
			if Game.tile_skill(t) != "":
				_build_resource(key, t)


func _build_resource(key: String, t: Dictionary) -> void:
	var s := Game.tile_skill(t)
	var sdef: Dictionary = Data.SKILLS[s]
	var rid: String = sdef["res"]
	var rname: String = Data.RES[rid]["name"]
	if not t["owned"]:
		_label("Ô này chưa thuộc lãnh thổ. Chiếm đồn địch gần đó để sở hữu.")
		return
	# --- Thủ công ---
	_label(func(): return "%s cấp %d · mỗi lần %.1fs được %.1f %s" % [
		sdef["name"], Game.skill_level(s), Game.manual_duration(s), Game.manual_yield(s), rname])
	_bar(func(): return Game.manual_progress(key))
	var row := _row()
	_button(String(sdef["verb"]), func(): Game.start_manual(key), func(): return Game.manual.is_empty(), row)
	_button("Dừng", func(): Game.stop_manual(), func(): return not Game.manual.is_empty(), row)
	if Game.skill_level(s) >= Data.AUTO_REPEAT_UNLOCK:
		var cb := CheckButton.new()
		cb.text = "Tự lặp lại thao tác tay"
		cb.button_pressed = Game.auto_repeat
		cb.toggled.connect(func(on): Game.auto_repeat = on)
		content.add_child(cb)
	else:
		_label("Cấp %d: mở tự lặp lại thao tác tay." % Data.AUTO_REPEAT_UNLOCK)
	_sep()

	# --- Thợ ---
	_sub("Thợ")
	if Game.skill_level(s) < Data.HUT_UNLOCK:
		_label("Đạt %s cấp %d để thuê thợ làm thay (bán tự động)." % [sdef["name"], Data.HUT_UNLOCK])
	else:
		_label(func(): return "Thợ: %d/%d · làm ra %.2f %s/giây%s" % [
			int(t["npcs"]), Data.MAX_NPC_PER_TILE, Game.tile_rate(t), rname, " (đói, chậm)" if Game.starving else ""])
		_button(func(): return "Thuê thợ (%s)" % Game.cost_text(Game.cost_npc()),
			func(): Game.hire_npc(key), func(): return Game.can_hire_npc(key))

	# --- Máy ---
	_sub("Máy móc")
	if Game.skill_level(s) < Data.MACHINE_UNLOCK:
		_label("Đạt %s cấp %d để lắp máy (tự động hoàn toàn, chạy 100%% khi offline)." % [sdef["name"], Data.MACHINE_UNLOCK])
	else:
		_label(func(): return "Máy cấp %d" % int(t["machine"]))
		_button(func(): return ("Lắp máy" if int(t["machine"]) == 0 else "Nâng cấp máy") + " (%s)" % Game.cost_text(Game.cost_machine(t)),
			func(): Game.buy_machine(key), func(): return Game.can_buy_machine(key))
	_sep()

	# --- Vận chuyển ---
	_sub("Vận chuyển")
	_label(func(): return "Bãi chứa %d/%d · Khuân vác %d · chở %.2f/giây" % [
		int(t["stock"]), int(Data.STOCK_CAP), int(t["porters"]), Game.transport_rate(key)])
	var row2 := _row()
	_button("– Khuân vác", func(): Game.assign_porter(key, -1), func(): return int(t["porters"]) > 0, row2)
	_button("+ Khuân vác", func(): Game.assign_porter(key, 1),
		func(): return Game.porters_free() > 0 and int(t["porters"]) < Data.MAX_PORTERS_PER_TILE, row2)
	_label(func(): return "Khuân vác rảnh: %d (thuê thêm ở ô Làng hoặc tab Làng & Kho)" % Game.porters_free())
	if int(t["elev"]) > 0:
		if t["crane"]:
			_label("Đã có cần cẩu: không còn phạt độ cao, chở thêm %.1f/giây." % Data.CRANE_BONUS)
		elif Game.skill_level("dap_da") < Data.CRANE_UNLOCK:
			_label("Đập đá cấp %d: mở cần cẩu cho ô có độ cao." % Data.CRANE_UNLOCK)
		else:
			_button("Xây cần cẩu (%s)" % Game.cost_text(Game.cost_crane()),
				func(): Game.build_crane(key), func(): return Game.can_build_crane(key))
	var bl := _label(func(): return Game.bottleneck_text(key))
	bl.add_theme_color_override("font_color", Color("ffb38a"))


func _build_grass(key: String, t: Dictionary) -> void:
	if not t["owned"]:
		_label("Ô này chưa thuộc lãnh thổ.")
		return
	var st: String = t["structure"]
	if st != "":
		_label("Đã xây: %s (+%d phòng thủ)." % [Data.STRUCTURES[st]["name"], int(Data.STRUCTURES[st]["def"])])
		return
	_label("Đất trống. Có thể xây công trình phòng thủ hoặc khai hoang thành ruộng.")
	for sid in Data.STRUCTURE_ORDER:
		var sdef: Dictionary = Data.STRUCTURES[sid]
		_button("Xây %s, +%d phòng thủ (%s)" % [sdef["name"], int(sdef["def"]), Game.cost_text(sdef["cost"])],
			func(): Game.build_structure(key, sid), func(): return Game.can_build_structure(key, sid))
	_button("Khai hoang thành ruộng lúa (%s)" % Game.cost_text(Game.cost_clear_field()),
		func(): Game.clear_field(key), func(): return Game.can_afford(Game.cost_clear_field()))


func _build_camp(key: String, t: Dictionary) -> void:
	var idx := int(t["camp"])
	_label("Sức mạnh địch ước tính: %d. Thắng sẽ chiếm các ô xung quanh và nhận %d Vàng." % [Data.camp_power(idx), 30 * (idx + 1)])
	if not Game.is_attackable(key):
		_label("Cần có lãnh thổ giáp ranh mới tấn công được.")
		return
	if Game.army_count() == 0:
		_label("Chưa có quân. Vào tab Quân đội để huấn luyện.")
		_button("Mở tab Quân đội", func(): _on_tab("army"))
		return
	if army_pick.is_empty():
		for u in Data.UNIT_ORDER:
			army_pick[u] = int(Game.army[u])
	_sub("Chọn quân xuất trận")
	for u in Data.UNIT_ORDER:
		if int(Game.army[u]) <= 0:
			continue
		var row := _row()
		_label(func(): return "%s: %d/%d" % [Data.UNITS[u]["name"], int(army_pick.get(u, 0)), int(Game.army[u])], row)
		_button("–", func(): army_pick[u] = maxi(0, int(army_pick.get(u, 0)) - 1), Callable(), row).custom_minimum_size = Vector2(70, 0)
		_button("+", func(): army_pick[u] = mini(int(Game.army[u]), int(army_pick.get(u, 0)) + 1), Callable(), row).custom_minimum_size = Vector2(70, 0)
	_label(func(): return "Sức mạnh mang theo: %d · Địch: %d" % [_pick_power(), Data.camp_power(idx)])
	_button("Tấn công!", func(): _start_attack(key), func(): return _pick_power() > 0)


func _pick_power() -> int:
	var p := 0
	for u in Data.UNIT_ORDER:
		p += mini(int(army_pick.get(u, 0)), int(Game.army[u])) * int(Data.UNITS[u]["power"])
	return p


func _start_attack(key: String) -> void:
	var pick := {}
	var n := 0
	for u in Data.UNIT_ORDER:
		pick[u] = mini(int(army_pick.get(u, 0)), int(Game.army[u]))
		n += int(pick[u])
	if n == 0 or battle == null:
		return
	army_pick = {}
	battle.start(key, pick)


# =====================================================================
#  Tab Ngành nghề
# =====================================================================
func _build_skills_tab() -> void:
	_title("Ngành nghề & thuần thục")
	_label("Mỗi lần làm (tay, thợ hay máy) đều tăng thuần thục. Cấp càng cao thao tác càng nhanh và máy càng mạnh.")
	for s in Data.SKILL_ORDER:
		var sdef: Dictionary = Data.SKILLS[s]
		_sep()
		_sub(String(sdef["name"]))
		_label(func(): return "Cấp %d · XP %d/%d · hệ số sản lượng x%.2f" % [
			Game.skill_level(s), int(Game.xp[s]), int(Data.xp_for_level(Game.skill_level(s))), Game.mastery_mult(s)])
		_bar(func(): return Game.level_progress(s))
		_label(func(): return "Thao tác tay: %.2fs · công cụ cấp %d (mỗi lần +%.1f)" % [
			Game.manual_duration(s), int(Game.tool_lvl[s]), Game.manual_yield(s)])
		_button(func(): return "Nâng công cụ (%s)" % Game.cost_text(Game.cost_tool(s)),
			func(): Game.upgrade_tool(s), func(): return Game.can_afford(Game.cost_tool(s)))
		_label(func(): return _milestones(s))


func _milestones(s: String) -> String:
	var l := Game.skill_level(s)
	var items := PackedStringArray()
	for m in [[Data.HUT_UNLOCK, "thuê thợ"], [Data.AUTO_REPEAT_UNLOCK, "tự lặp"], [Data.MACHINE_UNLOCK, "máy móc"],
			[50, "máy +25%"], [99, "Bậc thầy, máy x2"]]:
		var mark := "[x]" if l >= int(m[0]) else "[ ]"
		items.append("%s %d %s" % [mark, int(m[0]), m[1]])
	if s == "dap_da":
		items.append("%s %d cần cẩu" % ["[x]" if l >= Data.CRANE_UNLOCK else "[ ]", Data.CRANE_UNLOCK])
	return "Mốc: " + "  ".join(items)


# =====================================================================
#  Tab Quân đội
# =====================================================================
func _build_army_tab() -> void:
	_title("Quân đội")
	_label(func(): return "Sức mạnh %d · Lương thực nuôi quân %.2f lúa/giây · Phòng thủ làng %d" % [
		Game.army_power(), Game.army_upkeep(), Game.defense_power()])
	_label(func(): return "Đợt cướp kế tiếp: sức mạnh %d, sau %d phút." % [Data.raid_power(Game.camps_taken), int(Game.raid_timer / 60.0)])
	_label(func(): return _queue_text())
	for u in Data.UNIT_ORDER:
		var d: Dictionary = Data.UNITS[u]
		_sep()
		_label(func(): return "%s (%d) · %s · máu %d, công %d, sức mạnh %d" % [
			d["name"], int(Game.army[u]), d["desc"], int(d["hp"]), int(d["atk"]), int(d["power"])])
		var row := _row()
		_button("Luyện 1 (%s)" % Game.cost_text(d["cost"]), func(): Game.train(u, 1), func(): return Game.can_train(u, 1), row)
		_button("x5", func(): Game.train(u, 5), func(): return Game.can_train(u, 5), row).custom_minimum_size = Vector2(90, 0)
	_sep()
	_sub("Đồn địch đã phát hiện")
	var any := false
	for key in Game.draw_order:
		var t: Dictionary = Game.tiles[key]
		if t["type"] == "camp" and t["revealed"]:
			any = true
			var idx := int(t["camp"])
			var tag := " · có thể tấn công" if Game.is_attackable(key) else ""
			var k: String = key
			_button("%s (sức mạnh %d)%s" % [Data.camp_name(idx), Data.camp_power(idx), tag], func(): _goto(k))
	if not any:
		_label("Chưa thấy đồn địch nào.")


func _queue_text() -> String:
	if Game.train_queue.is_empty():
		return "Hàng chờ huấn luyện: trống."
	var first: Dictionary = Game.train_queue[0]
	return "Đang luyện: %s (còn %.0fs) · hàng chờ %d" % [Data.UNITS[first["unit"]]["name"], float(first["t"]), Game.train_queue.size()]


func _goto(key: String) -> void:
	selected = key
	if map_view:
		map_view.selected = key
		map_view.focus(key)
	tab = "map"
	army_pick = {}
	_rebuild()


# =====================================================================
#  Tab Làng & Kho
# =====================================================================
func _build_village_tab() -> void:
	_title("Làng & Kho")
	_label(func(): return "Kho cấp %d · sức chứa %d mỗi loại (Vàng không giới hạn)." % [Game.warehouse_lvl, int(Game.cap())])
	_button(func(): return "Nâng cấp kho (%s)" % Game.cost_text(Game.cost_warehouse()),
		func(): Game.upgrade_warehouse(), func(): return Game.can_afford(Game.cost_warehouse()))
	_label(func(): return "Khuân vác: %d tổng, %d rảnh." % [Game.porters_total, Game.porters_free()])
	_button(func(): return "Thuê khuân vác (%s)" % Game.cost_text(Game.cost_porter()),
		func(): Game.hire_porter(), func(): return Game.can_afford(Game.cost_porter()))
	_sep()
	_sub("Chợ")
	for id in ["lua", "go", "da"]:
		var row := _row()
		var price := float(Data.RES[id]["price"])
		_label("%s: %.1f vàng/đơn vị" % [Data.RES[id]["name"], price], row)
		var rid: String = id
		_button("Bán 50", func(): Game.sell(rid, 50.0), func(): return float(Game.res[rid]) >= 1.0, row)
	_sep()
	_sub("Nhật ký")
	_label(func(): return "\n".join(PackedStringArray(Game.log_lines.slice(0, 10))))
	_sep()
	_sub("Công cụ riêng (dev)")
	var row2 := _row()
	_button(func(): return "Tốc độ x%d" % int(Game.world_speed), func(): _cycle_speed(), Callable(), row2)
	_button("+500 mỗi loại", func(): _cheat(), Callable(), row2)
	_button("Lưu ngay", _save_now, Callable(), row2)
	_button("Chơi lại từ đầu (xóa save)", func(): _confirm_reset())


func _save_now() -> void:
	Game.save_game()
	Game.add_log("Đã lưu.")


func _cycle_speed() -> void:
	var order := [1.0, 5.0, 20.0]
	var i := order.find(Game.world_speed)
	Game.world_speed = order[(i + 1) % order.size()]


func _cheat() -> void:
	for id in Data.RES_ORDER:
		Game.add_res(id, 500.0)


var _reset_armed := false


func _confirm_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		Game.add_log("Bấm 'Chơi lại từ đầu' thêm lần nữa để xóa save.")
		return
	_reset_armed = false
	selected = ""
	Game.reset_game()
