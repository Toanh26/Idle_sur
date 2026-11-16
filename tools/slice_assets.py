"""Cắt sprite sheet art_source/sheet_village.png thành asset cho game và tạo thêm asset ghép/đổi màu.

Chạy:  python3 tools/slice_assets.py   (cần Pillow, numpy, scipy)

Kết quả:
  assets/tiles/<tên>.png  - ô đất, canvas cố định TILE_W x TILE_H, tâm mặt trên ô ở ANCHOR
  assets/props/<tên>.png  - công trình / đồ vật, đã cắt sát, gốc vẽ ở giữa cạnh dưới
  assets/tiles/meta.json  - kích thước canvas, anchor, độ rộng mặt trên (để game tính tỉ lệ)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "art_source", "sheet_village.png")
OUT_TILES = os.path.join(ROOT, "assets", "tiles")
OUT_PROPS = os.path.join(ROOT, "assets", "props")
BG = np.array([10, 21, 25])

TILE_W, TILE_H = 200, 300
ANCHOR = (100, 170)  # tâm mặt trên của ô trong canvas

# Ô trong lưới 3x3 bên phải sheet (x0, y0, x1, y1)
TILE_BOXES = {
    "grass": (1003, 22, 1176, 194),
    "grass_flowers": (1176, 22, 1348, 194),
    "dirt": (1348, 22, 1520, 194),
    "forest": (1003, 160, 1176, 362),
    "mountain": (1176, 160, 1348, 362),
    "rocks": (1348, 194, 1520, 362),
    "water": (1003, 335, 1176, 530),
    "field": (1176, 335, 1348, 530),
    "grass_tall": (1348, 335, 1520, 530),
}

PROP_BOXES = {
    "house_red": (950, 530, 1102, 676),
    "house_wood": (1104, 534, 1242, 674),
    "house_blue": (1244, 531, 1409, 679),
    "tower": (1410, 508, 1520, 691),
    "windmill": (941, 674, 1065, 831),
    "market": (1077, 685, 1234, 839),
    "well": (1256, 684, 1371, 829),
    "crystal": (1392, 693, 1522, 841),
    "dock": (931, 840, 1122, 979),
    "dock_boat": (1078, 840, 1372, 1002),
    "banner": (1376, 834, 1450, 988),
    "crate": (1432, 884, 1520, 976),
    "tree_round": (16, 680, 143, 821),
    "tree_round2": (140, 682, 263, 823),
    "pine": (257, 683, 365, 834),
    "pine2": (357, 684, 470, 839),
    "tree_pink": (469, 697, 606, 839),
    "rock_a": (613, 730, 720, 822),
    "rock_b": (722, 718, 815, 809),
    "rock_c": (819, 716, 909, 816),
    "lantern": (824, 847, 907, 993),
    "signpost": (645, 868, 809, 991),
    "log": (525, 838, 640, 910),
    "fence": (456, 917, 639, 988),
    "hay": (366, 914, 450, 991),
    "bush_flower": (21, 906, 137, 992),
    "bush_flower2": (143, 905, 265, 993),
    "log_mushroom": (269, 917, 365, 989),
    "grass_tuft": (404, 831, 515, 909),
    "flowers_white": (20, 836, 99, 901),
    "flowers_yellow": (101, 833, 172, 899),
}


def remove_bg(img: Image.Image, tol: int = 46) -> Image.Image:
    """Xoá nền tối nối liền với mép ảnh (flood fill theo màu)."""
    a = np.array(img.convert("RGB")).astype(int)
    diff = np.abs(a - BG).sum(axis=2)
    near = diff < tol
    lab, _ = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])))
    edge.discard(0)
    bgmask = np.isin(lab, list(edge))
    # làm mềm mép: viền 1px cạnh nền cho alpha 50%
    grown = ndimage.binary_dilation(bgmask, iterations=1)
    alpha = np.where(bgmask, 0, 255).astype(np.uint8)
    alpha[(grown & ~bgmask)] = 200
    rgba = np.dstack([a.astype(np.uint8), alpha])
    return Image.fromarray(rgba, "RGBA")


def trim(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def keep_largest(img: Image.Image) -> Image.Image:
    """Giữ mảng không trong suốt lớn nhất (bỏ mẩu ô bên cạnh lọt vào khung cắt)."""
    a = np.array(img)
    mask = a[:, :, 3] > 0
    lab, n = ndimage.label(mask)
    if n <= 1:
        return img
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    keep = 1 + int(np.argmax(sizes))
    a[:, :, 3] = np.where(lab == keep, a[:, :, 3], 0)
    return trim(Image.fromarray(a, "RGBA"))


def keep_at(img: Image.Image, seed, k: int = 3) -> Image.Image:
    """Tách vật chứa điểm seed: co mask k px để cắt chỗ dính mỏng với ô bên cạnh, chọn mảng chứa seed rồi nở lại."""
    a = np.array(img)
    mask = a[:, :, 3] > 0
    er = ndimage.binary_erosion(mask, iterations=k)
    lab, n = ndimage.label(er)
    if n == 0:
        return img
    sy, sx = int(seed[1] * a.shape[0]), int(seed[0] * a.shape[1])
    ys, xs = np.nonzero(lab)
    i = int(np.argmin((ys - sy) ** 2 + (xs - sx) ** 2))
    comp = lab == lab[ys[i], xs[i]]
    comp = ndimage.binary_dilation(comp, iterations=k + 2) & mask
    a[:, :, 3] = np.where(comp, a[:, :, 3], 0)
    return trim(Image.fromarray(a, "RGBA"))


def extract_tiles(sheet: Image.Image) -> dict:
    """Tách 9 ô trong lưới. Các ô nằm sát nhau (ngọn cây chạm đáy ô trên) nên dùng hình lăng trụ lục giác
    của từng ô để chia pixel: phần nằm trong lăng trụ ô nào thuộc ô đó; vật nhô lên trên mặt ô thuộc ô bên dưới."""
    from PIL import ImageDraw
    region = (995, 12, 1528, 540)
    full = np.array(remove_bg(sheet.crop(region)))
    alpha = full[:, :, 3]
    ox, oy = region[0], region[1]
    info = {}
    for name, (x0, y0, x1, y1) in TILE_BOXES.items():
        rough = keep_at(remove_bg(sheet.crop((x0, y0, x1, y1))), (0.5, 0.62))
        bbox = remove_bg(sheet.crop((x0, y0, x1, y1)))
        cx, cy, w = face_anchor(rough)
        # vị trí của rough trong crop: rough đã trim, tìm offset bằng getbbox của crop sau keep_at
        info[name] = (x0, y0, x1, y1, cx, cy, w, rough)
    # đo tỉ lệ mặt trên / chiều dày đất từ ô "dirt" (không có vật nào nhô lên)
    d = info["dirt"][7]
    _, dcy, dw = face_anchor(d)
    dh = dcy  # từ đỉnh mặt trên tới hàng 2 đỉnh trái/phải
    dD = d.height - 2 * dh
    polys = {}
    for name, (x0, y0, x1, y1, cx, cy, w, rough) in info.items():
        # toạ độ trong region: tìm vị trí rough bằng cách so khớp bbox của vùng chọn
        sub = np.array(rough)[:, :, 3] > 0
        crop_alpha = np.array(remove_bg(sheet.crop((x0, y0, x1, y1))))[:, :, 3] > 0
        # rough là crop đã trim của mặt nạ con trong crop_alpha; dùng tương quan để tìm offset
        best = (0, 0)
        best_score = -1
        for dy in range(0, crop_alpha.shape[0] - sub.shape[0] + 1, 1):
            for dx in range(0, crop_alpha.shape[1] - sub.shape[1] + 1, 2):
                sc = np.count_nonzero(crop_alpha[dy:dy + sub.shape[0], dx:dx + sub.shape[1]] & sub)
                if sc > best_score:
                    best_score, best = sc, (dx, dy)
        gx = x0 - ox + best[0] + cx
        gy = y0 - oy + best[1] + cy
        hw = w / 2.0
        k = w / dw
        h, D = dh * k, dD * k
        polys[name] = [(gx - hw, gy), (gx - hw / 2, gy - h), (gx + hw / 2, gy - h), (gx + hw, gy),
                       (gx + hw, gy + D), (gx + hw / 2, gy + h + D), (gx - hw / 2, gy + h + D), (gx - hw, gy + D)]
        info[name] = info[name] + (gx, gy, hw)
    H, W = alpha.shape
    prism = {}
    for name, poly in polys.items():
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        prism[name] = np.array(m) > 0
    yy, xx = np.mgrid[0:H, 0:W]
    out = {}
    for name in TILE_BOXES:
        gx, gy, hw = info[name][8], info[name][9], info[name][10]
        others = np.zeros_like(alpha, dtype=bool)
        for o in prism:
            if o != name:
                others |= prism[o]
        above = (xx >= gx - hw) & (xx <= gx + hw) & (yy < gy) & ~others

        own = (alpha > 0) & (prism[name] | above)
        a = full.copy()
        a[:, :, 3] = np.where(own, a[:, :, 3], 0)
        img = trim(Image.fromarray(a, "RGBA"))
        out[name] = keep_largest(img)
    return out


def face_anchor(img: Image.Image):
    """Tìm tâm mặt trên ô: hàng đầu tiên (từ trên xuống) đạt bề rộng gần tối đa = hàng chứa 2 đỉnh trái/phải."""
    a = np.array(img)[:, :, 3] > 0
    widths = []
    for row in a:
        xs = np.nonzero(row)[0]
        widths.append((xs[-1] - xs[0] + 1, xs[0], xs[-1]) if len(xs) else (0, 0, 0))
    maxw = max(w for w, _, _ in widths)
    for y, (w, x0, x1) in enumerate(widths):
        if w >= maxw * 0.97:
            return (x0 + x1) / 2.0, y, maxw
    return img.width / 2, img.height / 2, maxw


FLAT_RATIO = None  # (chiều cao từ đỉnh mặt trên tới hàng 2 đỉnh) / bề rộng, đo từ ô dirt


def place_tile(img: Image.Image, face_w_target: float, flat: bool = False):
    """Đặt ô lên canvas cố định sao cho tâm mặt trên trùng ANCHOR và bề rộng mặt trên = face_w_target.
    Ô phẳng tính tâm từ mép trên (ổn định hơn khi đáy dính mẩu ô khác)."""
    cx, cy, w = face_anchor(img)
    if flat and FLAT_RATIO:
        cy = FLAT_RATIO * w
    s = face_w_target / w
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    cx, cy = cx * s, cy * s
    canvas = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    canvas.alpha_composite(img, (int(round(ANCHOR[0] - cx)), int(round(ANCHOR[1] - cy))))
    return canvas


def paste_prop(canvas: Image.Image, prop: Image.Image, foot, height: float):
    """Dán đồ vật với chân (giữa cạnh dưới) tại foot, cao height px."""
    s = height / prop.height
    p = prop.resize((max(1, round(prop.width * s)), max(1, round(prop.height * s))), Image.LANCZOS)
    canvas.alpha_composite(p, (int(foot[0] - p.width / 2), int(foot[1] - p.height)))


def recolor(img: Image.Image, mult, sat=1.0, bright=1.0):
    a = np.array(img).astype(float)
    for i in range(3):
        a[:, :, i] *= mult[i]
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    if sat != 1.0:
        alpha = out.getchannel("A")
        out = ImageEnhance.Color(out.convert("RGB")).enhance(sat).convert("RGBA")
        out.putalpha(alpha)
    if bright != 1.0:
        alpha = out.getchannel("A")
        out = ImageEnhance.Brightness(out.convert("RGB")).enhance(bright).convert("RGBA")
        out.putalpha(alpha)
    return out


def main():
    if not os.path.exists(SHEET):
        sys.exit("Không thấy " + SHEET)
    sheet = Image.open(SHEET).convert("RGB")
    os.makedirs(OUT_TILES, exist_ok=True)
    os.makedirs(OUT_PROPS, exist_ok=True)

    # ---------- đồ vật ----------
    props = {}
    for name, box in PROP_BOXES.items():
        p = keep_largest(trim(remove_bg(sheet.crop(box))))
        props[name] = p
        p.save(os.path.join(OUT_PROPS, name + ".png"))

    # ---------- ô gốc ----------
    prism_cut = extract_tiles(sheet)
    raw = {}
    for name, box in TILE_BOXES.items():
        if name in ("forest", "mountain", "rocks"):
            raw[name] = prism_cut[name]          # ô có vật nhô cao: tách bằng lăng trụ
        else:
            raw[name] = keep_at(remove_bg(sheet.crop(box)), (0.5, 0.62))
    face_w = 164.0
    global FLAT_RATIO
    _, dcy, dw = face_anchor(raw["dirt"])
    FLAT_RATIO = dcy / dw
    flat_names = ("grass",)
    tiles = {name: place_tile(img, face_w, name in flat_names) for name, img in raw.items()}
    # Ô phẳng: cắt theo đúng hình khối của ô "dirt" để bỏ mẩu ô bên cạnh dính vào
    sil = np.array(tiles["dirt"])[:, :, 3] > 0
    sil = ndimage.binary_erosion(sil, iterations=1)
    for name in ("grass", "grass_flowers", "grass_tall", "field", "water"):
        a = np.array(tiles[name])
        a[:, :, 3] = np.where(sil, a[:, :, 3], 0)
        # cắt đáy: mặt trên cao ~130px + hông ~36px tính từ mép trên của ô
        ys = np.nonzero(a[:, :, 3] > 0)[0]
        a[int(ys.min()) + 168:, :, 3] = 0
        # bỏ mẩu nhỏ dính mép (vd ngọn cây của ô bên dưới)
        m = a[:, :, 3] > 0
        lab, n = ndimage.label(ndimage.binary_erosion(m, iterations=3))
        if n > 1:
            sizes = ndimage.sum(m, lab, range(1, n + 1))
            main = ndimage.binary_dilation(lab == 1 + int(np.argmax(sizes)), iterations=5) & m
            a[:, :, 3] = np.where(main, a[:, :, 3], 0)
        # xoá các hàng hẹp ở đáy (ngọn cây ô dưới lọt vào)
        m = a[:, :, 3] > 0
        widths = m.sum(axis=1)
        y = m.shape[0] - 1
        while y > 0 and widths[y] < 0.3 * widths.max():
            a[y, :, 3] = 0
            y -= 1
        tiles[name] = Image.fromarray(a, "RGBA")

    # ---------- asset tự tạo (ghép + đổi màu) ----------
    A = ANCHOR
    # Làng: nền hoa + nhà đỏ + giếng + chợ nhỏ
    v = tiles["grass_flowers"].copy()
    paste_prop(v, props["market"], (A[0] + 44, A[1] + 4), 58)
    paste_prop(v, props["house_red"], (A[0] - 18, A[1] + 2), 82)
    paste_prop(v, props["well"], (A[0] + 30, A[1] + 34), 44)
    tiles["village"] = v

    # Đồn thổ phỉ: nền đất + cờ đỏ + thùng + gỗ, ám đỏ
    camp = recolor(tiles["dirt"], (1.05, 0.9, 0.85))
    paste_prop(camp, props["log"], (A[0] - 40, A[1] + 28), 30)
    paste_prop(camp, props["crate"], (A[0] + 34, A[1] + 26), 40)
    paste_prop(camp, props["banner"], (A[0] - 6, A[1] + 12), 92)
    paste_prop(camp, props["crate"], (A[0] + 50, A[1] + 6), 30)
    tiles["camp"] = camp

    # Rừng mùa thu (biến thể), rừng thông dày
    tiles["forest_small"] = tiles["forest"]
    fd = tiles["grass_tall"].copy()
    for dx, dy, h in [(-46, -6, 70), (-6, -22, 78), (34, -4, 72), (-24, 24, 70), (22, 28, 74)]:
        paste_prop(fd, props["pine" if (dx + dy) % 2 == 0 else "pine2"], (A[0] + dx, A[1] + dy), h)
    tiles["forest"] = fd
    tiles["forest_autumn"] = recolor(fd, (1.35, 0.95, 0.55), sat=1.15)

    # Mỏ đá có cột gỗ + thùng (cho ô đá đã có thợ)
    q = tiles["rocks"].copy()
    paste_prop(q, props["crate"], (A[0] + 50, A[1] + 30), 30)
    paste_prop(q, props["log"], (A[0] - 52, A[1] + 30), 24)
    tiles["quarry"] = q

    # Ruộng có cối xay gió (khi đã lắp máy)
    fm = tiles["field"].copy()
    paste_prop(fm, props["windmill"], (A[0] - 40, A[1] + 6), 82)
    tiles["field_mill"] = fm

    # Hồ có bến thuyền
    wd = tiles["water"].copy()
    paste_prop(wd, props["dock_boat"], (A[0] + 26, A[1] + 44), 54)
    tiles["water_dock"] = wd

    # Sương mù: ô cỏ tối, nhạt màu
    tiles["fog"] = recolor(tiles["grass"], (0.32, 0.36, 0.42), sat=0.2)

    # Đất hoang hậu tận thế & đất nhiễm độc (chuẩn bị cho thời kỳ sau)
    tiles["wasteland"] = recolor(tiles["dirt"], (0.75, 0.7, 0.68), sat=0.45)
    tiles["toxic"] = recolor(tiles["grass_tall"], (0.7, 1.0, 0.55), sat=1.4, bright=0.85)
    # Ô tinh thể (mỏ tinh thể ở tầng sâu)
    cr = recolor(tiles["rocks"], (0.75, 0.8, 1.0), sat=0.8)
    paste_prop(cr, props["crystal"], (A[0] - 8, A[1] + 22), 70)
    tiles["crystal"] = cr
    # Đỉnh tuyết (núi cao)
    tiles["mountain_snow"] = recolor(tiles["mountain"], (1.08, 1.1, 1.18), sat=0.6, bright=1.1)

    for name, img in tiles.items():
        img.save(os.path.join(OUT_TILES, name + ".png"))

    # Đo mặt trên thật của ô dirt: mặt đất sáng, phần hông tối hơn hẳn.
    d = np.array(tiles["dirt"]).astype(int)
    ys = np.nonzero(d[:, 100, 3] > 0)[0]
    top, bottom = int(ys.min()), int(ys.max())
    bright = d[:, 100, :3].sum(axis=1) / 3
    face_bottom = top + 20
    for y in range(top + 20, bottom):
        if bright[y] < 110 and bright[y + 2] < 110:
            face_bottom = y
            break
    face_h = face_bottom - top
    center_y = top + face_h / 2.0
    squash = face_h / (face_w * 3 ** 0.5 / 2)
    depth = bottom - face_bottom
    print("face_w", face_w, "face_h", face_h, "center_y", center_y, "squash", round(squash, 3), "depth", depth)
    meta = {"canvas": [TILE_W, TILE_H], "face_center": [ANCHOR[0], center_y], "face_w": face_w,
            "face_h": face_h, "squash": round(squash, 3), "depth": depth,
            "tiles": sorted(tiles.keys()), "props": sorted(props.keys())}
    with open(os.path.join(OUT_TILES, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    print("tiles:", len(tiles), "props:", len(props))


if __name__ == "__main__":
    main()
