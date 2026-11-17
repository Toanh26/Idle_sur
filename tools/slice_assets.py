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
    "fence": (456, 917, 572, 988),
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


# =====================================================================
#  Dựng lại ô thành lục giác ĐỈNH PHẲNG (cạnh trên/dưới nằm ngang)
#  Ảnh gốc là lục giác đỉnh nhọn nhìn 3/4. Mặt trên được "trải phẳng", xoay 30° rồi ép lại;
#  hông đất lấy từ dải đất của ảnh gốc rồi uốn vào 3 mặt hông mới; cây, đá, núi, nhà dán lên như đồ vật.
# =====================================================================
SRC_SQ = 0.67      # độ dẹt của ảnh gốc (đo từ ô dirt)
OUT_SQ = 0.67      # độ dẹt của ô mới (giữ nguyên góc nhìn của bộ art)
OUT_R = 82.0       # bán kính ngoại tiếp mặt trên ô mới (mặt rộng 164 px)
OUT_D = 30.0       # chiều dày hông đất ô mới
OUT_CENTER = (100.0, 196.0)
COS30, SIN30 = 3 ** 0.5 / 2, 0.5


def flat_hex(cx, cy, r, sq):
    import math
    return [(cx + r * math.cos(math.radians(60 * i)), cy + r * math.sin(math.radians(60 * i)) * sq) for i in range(6)]


def src_geom(raw: Image.Image):
    """Ảnh gốc đã cắt sát: bề rộng = sqrt3*R, đỉnh trên của mặt ở y=0."""
    a = np.array(raw)[:, :, 3] > 0
    widths = a.sum(axis=1)
    y = int(np.argmax(widths))
    xs = np.nonzero(a[y])[0]
    w = xs[-1] - xs[0] + 1
    R = w / 3 ** 0.5
    return (xs[0] + xs[-1]) / 2.0, R * SRC_SQ, R


def poly_mask(size, poly):
    from PIL import ImageDraw
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return m


def rotated_face(raw: Image.Image) -> Image.Image:
    """Lấy mặt trên đỉnh nhọn của ảnh gốc, xoay 30° thành mặt đỉnh phẳng trên canvas mới."""
    cx, cy, R = src_geom(raw)
    s = R / OUT_R * 0.9   # lấy phần trong của mặt, bỏ viền tối và chỗ bo góc của ảnh gốc
    X0, Y0 = OUT_CENTER
    a = s * COS30
    b = -s * SIN30 / OUT_SQ
    c = cx - a * X0 - b * Y0
    d = SRC_SQ * s * SIN30
    e = SRC_SQ * s * COS30 / OUT_SQ
    f = cy - d * X0 - e * Y0
    out = raw.transform((TILE_W, TILE_H), Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC)
    mask = poly_mask((TILE_W, TILE_H), flat_hex(X0, Y0, OUT_R, OUT_SQ))
    # lót màu trung bình bên dưới để không có lỗ ở góc
    arr = np.array(out)
    m = (arr[:, :, 3] > 200) & (np.array(mask) > 0)
    avg = tuple(int(v) for v in arr[m][:, :3].mean(axis=0)) if m.any() else (100, 140, 60)
    base = Image.new("RGBA", (TILE_W, TILE_H), avg + (255,))
    base.alpha_composite(out)
    base.putalpha(mask)
    return base


def side_strip(raw: Image.Image) -> Image.Image:
    """Dải đất bên hông (mặt hông dưới-trái của ảnh gốc) kéo thẳng thành hình chữ nhật."""
    cx, cy, R = src_geom(raw)
    x0 = cx - R * COS30
    A = (x0, cy + R * 0.5 * SRC_SQ)          # đỉnh dưới-trái của mặt
    B = (cx, cy + R * SRC_SQ)                # đỉnh dưới của mặt
    D = raw.height - (cy + R * SRC_SQ)       # bề dày hông trong ảnh gốc
    L = int(((B[0] - A[0]) ** 2 + (B[1] - A[1]) ** 2) ** 0.5)
    quad = (A[0], A[1] - 3, A[0], A[1] + D - 2, B[0], B[1] + D - 2, B[0], B[1] - 3)
    return raw.transform((L, int(D)), Image.QUAD, quad, resample=Image.BICUBIC)


def warp_strip(canvas: Image.Image, strip: Image.Image, P0, P1, depth, shade=1.0):
    """Dán dải đất vào hình bình hành P0-P1 kéo xuống depth px."""
    ux, uy = P1[0] - P0[0], P1[1] - P0[1]
    vx, vy = 0.0, depth
    det = ux * vy - uy * vx
    # (s,t) = M^-1 (x - P0); strip_x = Ls*s, strip_y = Ds*t
    Ls, Ds = strip.width, strip.height
    i11, i12, i21, i22 = vy / det, -vx / det, -uy / det, ux / det
    a, b = Ls * i11, Ls * i12
    c = -(a * P0[0] + b * P0[1])
    d, e = Ds * i21, Ds * i22
    f = -(d * P0[0] + e * P0[1])
    out = strip.transform(canvas.size, Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC)
    if shade != 1.0:
        out = recolor(out, (shade, shade, shade))
    poly = [P0, P1, (P1[0], P1[1] + depth), (P0[0], P0[1] + depth)]
    m = np.array(poly_mask(canvas.size, poly))
    al = np.minimum(np.array(out.getchannel("A")), m)
    out.putalpha(Image.fromarray(al))
    canvas.alpha_composite(out)


def side_band(strip: Image.Image) -> Image.Image:
    """Dải đất liền mạch dưới mép trước của mặt lục giác (3 mặt hông dưới-trái, dưới, dưới-phải).
    Texture lấy theo cột từ dải đất của ảnh gốc nên không bị gãy ở góc."""
    import math
    X0, Y0 = OUT_CENTER
    R, D = OUT_R, OUT_D
    h = R * math.sqrt(3) / 2 * OUT_SQ
    st = np.array(strip.convert("RGBA")).astype(float)
    # bỏ hai đầu dải (hay dính viền trong suốt)
    w0 = st.shape[1]
    st = st[:, int(w0 * 0.12):int(w0 * 0.88)]
    sh, sw = st.shape[0], st.shape[1]
    out = np.zeros((TILE_H, TILE_W, 4), dtype=float)
    x_min, x_max = int(math.floor(X0 - R)), int(math.ceil(X0 + R))
    for x in range(x_min, x_max + 1):
        if x < X0 - R / 2:
            ytop = Y0 + (x - (X0 - R)) / (R / 2) * h
            shade = 0.78
        elif x <= X0 + R / 2:
            ytop = Y0 + h
            shade = 1.0
        else:
            ytop = Y0 + ((X0 + R) - x) / (R / 2) * h
            shade = 0.9
        sx = int((x - x_min) * 0.85) % sw
        for y in range(int(ytop) - 2, int(ytop + D) + 1):
            if not (0 <= y < TILE_H and 0 <= x < TILE_W):
                continue
            t = (y - ytop) / D
            if t > 1.0:
                continue
            sy = min(sh - 1, max(0, int(t * (sh - 1))))
            px = st[sy, sx]
            out[y, x, :3] = px[:3] * shade
            out[y, x, 3] = 255 if px[3] > 20 else 0
    # mép dưới tối để khối rõ hơn
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return img


def flat_tile(face: Image.Image, strip: Image.Image) -> Image.Image:
    X0, Y0 = OUT_CENTER
    hexp = flat_hex(X0, Y0, OUT_R, OUT_SQ)
    canvas = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    canvas.alpha_composite(side_band(strip))
    canvas.alpha_composite(face)
    from PIL import ImageDraw
    d = ImageDraw.Draw(canvas)
    # viền tối mảnh quanh mặt trên và mép dưới của hông
    d.line(hexp + [hexp[0]], fill=(40, 30, 22, 140), width=2)
    bottom = [hexp[0], hexp[1], hexp[2], hexp[3]]
    d.line([(x, y + OUT_D) for x, y in bottom], fill=(35, 25, 18, 160), width=2)
    for v in (hexp[0], hexp[1], hexp[2], hexp[3]):
        d.line([v, (v[0], v[1] + OUT_D)], fill=(35, 25, 18, 90), width=1)
    return canvas


def farm_face(base_face: Image.Image) -> Image.Image:
    """Mặt ruộng vẽ lại liền mạch: thửa lúa phủ gần kín mặt ô, chia 3 thửa bằng lối cỏ, có luống và viền
    (bảng màu lấy từ ô ruộng gốc). Vẽ ở góc nhìn thẳng rồi ép theo độ dẹt của ô."""
    import math
    rng = np.random.default_rng(7)
    X0, Y0 = OUT_CENTER
    up = 4
    R = OUT_R * up
    Htd = R * math.sqrt(3)
    W, H = int(2 * R) + 8, int(Htd) + 8
    cx, cy = W / 2, H / 2
    yy, xx = np.mgrid[0:H, 0:W]
    u, v = xx - cx, yy - cy
    # lục giác đỉnh phẳng thu nhỏ 84%
    r_in = R * 0.84
    inside = (np.abs(v) <= r_in * math.sqrt(3) / 2) & (np.abs(u) * math.sqrt(3) + np.abs(v) <= r_in * math.sqrt(3))
    path_w = 0.045 * Htd
    paths = (np.abs(v - 0.02 * Htd) < path_w) | ((np.abs(u - 0.12 * R) < path_w) & (v < 0.02 * Htd))
    wheat = inside & ~paths
    gold = np.array([232, 170, 52], float)
    rowcol = [np.array([249, 191, 53], float), np.array([206, 142, 40], float)]
    img = np.zeros((H, W, 4), float)
    band = ((v / (6 * up)).astype(int) % 2).astype(int)
    img[:, :, :3] = gold
    for k in (0, 1):
        sel = band == k
        img[sel, :3] = rowcol[k] * 0.6 + gold * 0.4
    noise = rng.normal(0, 10, (H, W))
    img[:, :, :3] += noise[:, :, None]
    # bông lúa sáng lấm tấm
    for _ in range(900):
        px, py = int(rng.uniform(0, W)), int(rng.uniform(0, H))
        img[max(0, py - 1):py + 2, max(0, px - 3):px + 4, :3] = (253, 216, 96)
    # viền thửa
    er = ndimage.binary_erosion(wheat, iterations=3 * up)
    border = wheat & ~er
    img[border, :3] = (150, 96, 30)
    img[:, :, 3] = np.where(wheat, 255, 0)
    td = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")
    td = td.resize((int(W / up), max(1, int(H / up * OUT_SQ))), Image.LANCZOS)
    face = base_face.copy()
    face.alpha_composite(td, (int(round(X0 - td.width / 2)), int(round(Y0 - td.height / 2))))
    mask = poly_mask((TILE_W, TILE_H), flat_hex(X0, Y0, OUT_R, OUT_SQ))
    al = np.minimum(np.array(face.getchannel("A")), np.array(mask))
    face.putalpha(Image.fromarray(al))
    return face


def texture_face(patch: Image.Image, rim: Image.Image = None) -> Image.Image:
    """Lát kín mặt lục giác bằng một mảnh texture (dùng cho ruộng lúa)."""
    X0, Y0 = OUT_CENTER
    tex = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    for y in range(0, TILE_H, patch.height):
        for x in range(0, TILE_W, patch.width):
            tex.alpha_composite(patch, (x, y))
    mask = np.array(poly_mask((TILE_W, TILE_H), flat_hex(X0, Y0, OUT_R - 8, OUT_SQ)))
    t = np.array(tex)
    t[:, :, 3] = np.minimum(t[:, :, 3], mask)
    face = Image.new("RGBA", (TILE_W, TILE_H), (0, 0, 0, 0))
    if rim is not None:
        face.alpha_composite(rim)
    face.alpha_composite(Image.fromarray(t, "RGBA"))
    return face


def object_mask(raw: Image.Image, kind: str) -> Image.Image:
    """Tách vật nổi (núi) khỏi nền cỏ của ô gốc theo màu: giữ phần xám/trắng/tối, bỏ cỏ xanh-vàng."""
    a = np.array(raw).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1)
    grassy = (g > r * 0.95) & (g > b * 1.25) & (sat > 0.25)
    keep = (a[:, :, 3] > 0) & ~grassy
    cx, cy, R = src_geom(raw)
    yy = np.arange(a.shape[0])[:, None]
    keep &= yy < cy + R * SRC_SQ * 0.75   # bỏ phần hông đất
    keep = ndimage.binary_opening(keep, iterations=1)
    lab, n = ndimage.label(keep)
    if n:
        sizes = ndimage.sum(keep, lab, range(1, n + 1))
        keep = lab == 1 + int(np.argmax(sizes))
        keep = ndimage.binary_closing(keep, iterations=2)
        keep = ndimage.binary_fill_holes(keep)
    out = a.copy().astype(np.uint8)
    out[:, :, 3] = np.where(keep, a[:, :, 3], 0).astype(np.uint8)
    return trim(Image.fromarray(out, "RGBA"))


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

    # ---------- ô gốc (đỉnh nhọn) ----------
    prism_cut = extract_tiles(sheet)
    raw = {}
    for name, box in TILE_BOXES.items():
        raw[name] = prism_cut[name] if name in ("forest", "mountain", "rocks") \
            else keep_at(remove_bg(sheet.crop(box)), (0.5, 0.62))

    # vật nổi lấy từ ô gốc
    props["mountain_peaks"] = object_mask(raw["mountain"], "mountain")
    props["mountain_peaks"].save(os.path.join(OUT_PROPS, "mountain_peaks.png"))

    # ---------- ô nền đỉnh phẳng ----------
    strips = {n: side_strip(raw[n]) for n in ("grass", "grass_flowers", "grass_tall", "dirt", "water")}
    tiles = {}
    for n in ("grass", "grass_flowers", "grass_tall", "dirt", "water"):
        tiles[n] = flat_tile(rotated_face(raw[n]), strips[n])
    # nền cỏ úa cho đá/núi (giống ô gốc)
    olive_face = recolor(rotated_face(raw["grass_tall"]), (1.0, 0.92, 0.62), sat=0.7)
    olive = flat_tile(olive_face, strips["grass_tall"])
    # ruộng: lát texture lúa lên nền cỏ
    tiles["field"] = flat_tile(farm_face(rotated_face(raw["grass_tall"])), strips["grass_tall"])

    X0, Y0 = OUT_CENTER
    A = (X0, Y0)

    def deco(base, items):
        img = base.copy()
        for name, dx, dy, h in sorted(items, key=lambda it: it[2]):
            paste_prop(img, props[name], (A[0] + dx, A[1] + dy), h)
        return img

    tiles["field"] = deco(tiles["field"], [("hay", 50, -18, 20), ("fence", -30, 46, 20), ("fence", 30, 46, 20)])
    tiles["forest"] = deco(tiles["grass_tall"], [("pine", -44, -8, 66), ("pine2", -4, -26, 72), ("pine", 38, -10, 68),
                                                 ("pine2", -24, 18, 70), ("pine", 22, 22, 72)])
    tiles["forest_small"] = deco(tiles["grass_flowers"], [("tree_round", -34, -6, 60), ("pine", 10, -20, 64),
                                                          ("tree_round2", 30, 16, 58), ("pine2", -12, 22, 62)])
    tiles["forest_autumn"] = recolor(tiles["forest"], (1.35, 0.95, 0.55), sat=1.15)
    tiles["rocks"] = deco(olive, [("rock_b", -30, 4, 40), ("rock_a", 14, -10, 52), ("rock_c", 30, 24, 38)])
    tiles["mountain"] = deco(olive, [("mountain_peaks", 0, 30, 100)])
    tiles["mountain_snow"] = recolor(tiles["mountain"], (1.08, 1.1, 1.18), sat=0.6, bright=1.1)
    tiles["village"] = deco(tiles["grass_flowers"], [("house_red", -22, 6, 80), ("market", 42, 4, 56),
                                                     ("well", 22, 34, 40), ("flowers_white", -48, 30, 18)])
    camp_base = recolor(tiles["dirt"], (1.05, 0.9, 0.85))
    tiles["camp"] = deco(camp_base, [("log", -40, 28, 28), ("banner", -6, 12, 90), ("crate", 46, 8, 30),
                                     ("crate", 32, 30, 38)])
    tiles["quarry"] = deco(tiles["rocks"], [("crate", 52, 30, 28), ("log", -54, 32, 22)])
    tiles["field_mill"] = deco(tiles["field"], [("windmill", -40, 4, 80)])
    tiles["water_dock"] = deco(tiles["water"], [("dock_boat", 28, 44, 52)])
    tiles["fog"] = recolor(tiles["grass"], (0.32, 0.36, 0.42), sat=0.2)
    tiles["wasteland"] = recolor(tiles["dirt"], (0.75, 0.7, 0.68), sat=0.45)
    tiles["toxic"] = recolor(tiles["grass_tall"], (0.7, 1.0, 0.55), sat=1.4, bright=0.85)
    cr = recolor(tiles["rocks"], (0.75, 0.8, 1.0), sat=0.8)
    tiles["crystal"] = deco(cr, [("crystal", -6, 24, 68)])

    for name, img in tiles.items():
        img.save(os.path.join(OUT_TILES, name + ".png"))

    meta = {"canvas": [TILE_W, TILE_H], "face_center": list(OUT_CENTER), "face_w": OUT_R * 2,
            "squash": OUT_SQ, "depth": OUT_D, "orientation": "flat-top",
            "tiles": sorted(tiles.keys()), "props": sorted(props.keys())}
    with open(os.path.join(OUT_TILES, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    print("tiles:", len(tiles), "props:", len(props))


if __name__ == "__main__":
    main()
