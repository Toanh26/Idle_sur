extends RefCounted
## Nạp và vẽ asset ô đất / đồ vật (tạo bởi tools/slice_assets.py).
## Mọi ảnh ô có cùng canvas; tâm mặt trên ô nằm ở ANCHOR. Thiếu ảnh thì hàm vẽ trả về false để dùng hình vẽ tạm.

const CANVAS := Vector2(200, 300)
const ANCHOR := Vector2(100, 192)  # tâm mặt trên ô trong canvas
const FACE_W := 164.0     # bề rộng mặt trên ô trong canvas
const DEPTH := 34.0       # chiều dày phần đất bên hông trong canvas

var _cache := {}


func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var full := "res://assets/%s.png" % path
	var t: Texture2D = null
	if ResourceLoader.exists(full):
		t = load(full)
	_cache[path] = t
	return t


func has_tile(name: String) -> bool:
	return tex("tiles/" + name) != null


func scale_for(hex_size: float) -> float:
	return 2.0 * hex_size / FACE_W


func side_depth(hex_size: float) -> float:
	return DEPTH * scale_for(hex_size)


func draw_tile(ci: CanvasItem, name: String, center: Vector2, hex_size: float, mod: Color = Color.WHITE) -> bool:
	var t := tex("tiles/" + name)
	if t == null:
		return false
	var k := scale_for(hex_size)
	ci.draw_texture_rect(t, Rect2(center - ANCHOR * k, CANVAS * k), false, mod)
	return true


func draw_prop(ci: CanvasItem, name: String, foot: Vector2, height: float, mod: Color = Color.WHITE) -> bool:
	## Vẽ đồ vật với chân (giữa cạnh dưới) tại foot, cao height px.
	var t := tex("props/" + name)
	if t == null:
		return false
	var w := height * float(t.get_width()) / float(t.get_height())
	ci.draw_texture_rect(t, Rect2(foot.x - w / 2.0, foot.y - height, w, height), false, mod)
	return true
