"use strict";
/* Frontier Idle – bản web (chuyển từ bản Godot). Chơi trên trình duyệt điện thoại.
   Lưu game: localStorage của trình duyệt + (khi chạy trên claude.ai) lưu đám mây theo tài khoản. */

// =====================================================================
//  DỮ LIỆU (tương ứng scripts/data.gd)
// =====================================================================
const D = {
  TICK: 0.25, AUTOSAVE_SEC: 30, OFFLINE_CAP: 12 * 3600, OFFLINE_STEP: 300, OFFLINE_NPC_EFF: 0.5,
  MAP_RADIUS: 6, START_OWNED_RADIUS: 2, START_REVEAL_RADIUS: 3, MAP_SEED: 20261116,
  RES: {
    lua: { name: "Lúa", color: "#f0d877", price: 0.4 },
    go: { name: "Gỗ", color: "#d9a46c", price: 0.5 },
    da: { name: "Đá", color: "#d4d4cc", price: 0.6 },
    vang: { name: "Vàng", color: "#f7c85a", price: 0 },
  },
  RES_ORDER: ["lua", "go", "da", "vang"],
  WAREHOUSE_BASE: 200, WAREHOUSE_GROWTH: 1.6,
  SKILLS: {
    don_go: { name: "Đốn gỗ", res: "go", t0: 2.0, verb: "Đốn gỗ" },
    dap_da: { name: "Đập đá", res: "da", t0: 2.5, verb: "Đập đá" },
    trong_lua: { name: "Trồng lúa", res: "lua", t0: 3.0, verb: "Gặt lúa" },
  },
  SKILL_ORDER: ["don_go", "dap_da", "trong_lua"],
  MANUAL_XP: 25, AUTO_XP: 5, MAX_LEVEL: 99,
  HUT_UNLOCK: 10, AUTO_REPEAT_UNLOCK: 20, CRANE_UNLOCK: 15, MACHINE_UNLOCK: 30,
  NPC_RATE: 0.3, NPC_FOOD: 0.02, MAX_NPC_PER_TILE: 5, MACHINE_BASE: 2.5, STOCK_CAP: 60,
  START_PORTERS: 2, PORTER_CARRY: 5, PORTER_TRIP_PER_HEX: 4, ELEV_PENALTY: 0.75, CRANE_BONUS: 1.5,
  MAX_PORTERS_PER_TILE: 8,
  TILES: {
    village: { name: "Làng", color: "#c9a66b" },
    forest: { name: "Rừng", color: "#4f7d3a", skill: "don_go" },
    rock: { name: "Mỏ đá", color: "#8d8b7c", skill: "dap_da" },
    field: { name: "Ruộng lúa", color: "#b9c45a", skill: "trong_lua" },
    grass: { name: "Đồng cỏ", color: "#7fae5a" },
    water: { name: "Sông", color: "#4a8fb8" },
    camp: { name: "Đồn thổ phỉ", color: "#7a4a35" },
  },
  TILE_WEIGHTS: [["forest", 30], ["rock", 16], ["field", 12], ["grass", 34], ["water", 8]],
  UNITS: {
    dan_quan: { name: "Dân quân", cost: { lua: 10, go: 5 }, hp: 40, atk: 6, range: 40, speed: 60, time: 4, upkeep: 0.004, power: 5, row: 1, desc: "Rẻ, đông" },
    cung_thu: { name: "Cung thủ", cost: { lua: 10, go: 15 }, hp: 25, atk: 7, range: 170, speed: 55, time: 6, upkeep: 0.005, power: 7, row: 2, desc: "Đánh xa" },
    linh_khien: { name: "Lính khiên", cost: { lua: 15, go: 5, da: 20 }, hp: 95, atk: 4, range: 40, speed: 50, time: 8, upkeep: 0.006, power: 10, row: 0, desc: "Đỡ đòn ở hàng trước" },
  },
  UNIT_ORDER: ["dan_quan", "cung_thu", "linh_khien"],
  ENEMIES: {
    tho_phi: { name: "Thổ phỉ", hp: 36, atk: 5.5, range: 40, speed: 55 },
    cung_phi: { name: "Cung phỉ", hp: 22, atk: 6, range: 160, speed: 50 },
  },
  BATTLE_MAX_PER_SIDE: 40, BATTLE_TIME_LIMIT: 90,
  CAMPS: [[3, -1], [-3, 2], [0, -3], [4, 1], [-4, -1], [1, 4], [-2, 5], [6, -3]],
  STRUCTURES: {
    rao: { name: "Hàng rào tre", cost: { go: 30 }, def: 15 },
    thap_cung: { name: "Tháp cung", cost: { go: 60, da: 25 }, def: 35 },
  },
  STRUCTURE_ORDER: ["rao", "thap_cung"],
  VILLAGE_BASE_DEF: 10, GARRISON_SHARE: 0.5, RAID_INTERVAL: 1800, RAID_LOSS: 0.15,
};
const xpForLevel = (l) => 50 * Math.pow(l, 2.2);
const campPower = (i) => Math.floor(50 * Math.pow(1.4, i));
const campName = (i) => (i === D.CAMPS.length - 1 ? "Sào huyệt thủ lĩnh thổ phỉ" : "Đồn thổ phỉ số " + (i + 1));
const raidPower = (n) => Math.floor(30 * Math.pow(1.3, n));

// =====================================================================
//  LƯỚI LỤC GIÁC ĐỈNH PHẲNG (scripts/hex.gd)
// =====================================================================
const HEX = { SIZE: 48, SQUASH: 0.67 };
const DIRS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];
const hkey = (q, r) => q + "," + r;
const toPixel = (q, r) => [HEX.SIZE * 1.5 * q, HEX.SIZE * Math.sqrt(3) * (r + q / 2) * HEX.SQUASH];
const hdist = (a, b) => (Math.abs(a[0] - b[0]) + Math.abs(a[0] + a[1] - b[0] - b[1]) + Math.abs(a[1] - b[1])) / 2;
function corners(cx, cy, size = HEX.SIZE) {
  const pts = [];
  for (let i = 0; i < 6; i++) {
    const a = (Math.PI / 180) * 60 * i;
    pts.push([cx + size * Math.cos(a), cy + size * Math.sin(a) * HEX.SQUASH]);
  }
  return pts;
}
function coordsInRadius(c, rad) {
  const out = [];
  for (let dq = -rad; dq <= rad; dq++)
    for (let dr = Math.max(-rad, -dq - rad); dr <= Math.min(rad, -dq + rad); dr++) out.push([c[0] + dq, c[1] + dr]);
  return out;
}
const neighbors = (q, r) => DIRS.map((d) => [q + d[0], r + d[1]]);
function pointInPoly(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// =====================================================================
//  ẢNH (scripts/tile_art.gd)
// =====================================================================
const ART = { CANVAS: [200, 300], ANCHOR: [100, 196], FACE_W: 164 };
const TILE_NAMES = ["camp", "crystal", "dirt", "field", "field_mill", "fog", "forest", "forest_autumn", "forest_small", "grass",
  "grass_flowers", "grass_tall", "mountain", "mountain_snow", "quarry", "rocks", "toxic", "village", "wasteland", "water", "water_dock"];
const PROP_NAMES = ["house_wood", "windmill", "crate", "fence", "tower"];
const IMG = { tiles: {}, props: {} };
function loadImages() {
  const all = [];
  const load = (bucket, folder, name) =>
    new Promise((res) => {
      const im = new Image();
      im.onload = () => { bucket[name] = im; res(); };
      im.onerror = () => res();
      im.src = "assets/" + folder + "/" + name + ".png";
    });
  TILE_NAMES.forEach((n) => all.push(load(IMG.tiles, "tiles", n)));
  PROP_NAMES.forEach((n) => all.push(load(IMG.props, "props", n)));
  return Promise.all(all);
}
function drawTileImg(ctx, name, cx, cy, size, alpha = 1, dim = false) {
  const im = IMG.tiles[name];
  if (!im) return false;
  const k = (2 * size) / ART.FACE_W;
  ctx.globalAlpha = alpha;
  ctx.drawImage(im, cx - ART.ANCHOR[0] * k, cy - ART.ANCHOR[1] * k, ART.CANVAS[0] * k, ART.CANVAS[1] * k);
  if (dim) {
    ctx.globalAlpha = 0.38;
    ctx.fillStyle = "#000";
    polyPath(ctx, corners(cx, cy, size));
    ctx.fill();
  }
  ctx.globalAlpha = 1;
  return true;
}
function drawProp(ctx, name, fx, fy, h) {
  const im = IMG.props[name];
  if (!im) return false;
  const w = (h * im.width) / im.height;
  ctx.drawImage(im, fx - w / 2, fy - h, w, h);
  return true;
}
function polyPath(ctx, pts) {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
  ctx.closePath();
}

// =====================================================================
//  TRẠNG THÁI & MÔ PHỎNG (scripts/game.gd)
// =====================================================================
const G = {
  res: {}, warehouse: 0, xp: {}, tool: {}, tiles: {}, order: [], army: {}, queue: [], porters: 0, camps: 0,
  raid: 0, manual: null, repeat: false, log: [], play: 0, speed: 1, starving: false, offlineReport: "",
};
let structureDirty = true;
const changed = () => { structureDirty = true; };

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function newGame() {
  G.res = { lua: 30, go: 0, da: 0, vang: 40 };
  G.warehouse = 0;
  G.xp = {}; G.tool = {};
  D.SKILL_ORDER.forEach((s) => { G.xp[s] = 0; G.tool[s] = 0; });
  G.army = {}; D.UNIT_ORDER.forEach((u) => (G.army[u] = 0));
  G.queue = []; G.porters = D.START_PORTERS; G.camps = 0; G.raid = D.RAID_INTERVAL;
  G.manual = null; G.repeat = false; G.log = []; G.play = 0; G.starving = false; G.offlineReport = "";
  genMap();
  addLog("Một làng quê yên bình bên sông. Hãy bắt đầu bằng đôi tay: chạm vào Rừng, Mỏ đá hoặc Ruộng lúa.");
}

function genMap() {
  G.tiles = {};
  const rnd = mulberry32(D.MAP_SEED);
  const total = D.TILE_WEIGHTS.reduce((a, b) => a + b[1], 0);
  const randType = () => {
    let roll = rnd() * total;
    for (const [k, w] of D.TILE_WEIGHTS) { roll -= w; if (roll <= 0) return k; }
    return "grass";
  };
  for (const c of coordsInRadius([0, 0], D.MAP_RADIUS)) {
    const d = hdist(c, [0, 0]);
    const type = randType();
    let elev = 0;
    if (type === "rock") elev = 1 + Math.floor(rnd() * 2);
    else if ((type === "forest" || type === "grass") && rnd() < 0.15) elev = 1;
    G.tiles[hkey(c[0], c[1])] = {
      q: c[0], r: c[1], type, elev, owned: d <= D.START_OWNED_RADIUS, revealed: d <= D.START_REVEAL_RADIUS,
      npcs: 0, porters: 0, machine: 0, crane: false, stock: 0, structure: "", camp: -1,
    };
  }
  const fixed = [[0, 0, "village", 0], [1, 0, "forest", 0], [1, -1, "rock", 1], [0, -1, "field", 0], [-1, 0, "grass", 0], [-1, 1, "forest", 0], [0, 1, "field", 0]];
  for (const [q, r, t, e] of fixed) { const tt = G.tiles[hkey(q, r)]; tt.type = t; tt.elev = e; }
  D.CAMPS.forEach((cp, i) => {
    const t = G.tiles[hkey(cp[0], cp[1])];
    t.type = "camp"; t.camp = i; t.elev = 0; t.owned = false;
  });
  buildOrder();
}
function buildOrder() {
  G.order = Object.keys(G.tiles).sort((a, b) => {
    const ta = G.tiles[a], tb = G.tiles[b];
    const ya = 2 * ta.r + ta.q, yb = 2 * tb.r + tb.q;
    return ya !== yb ? ya - yb : ta.q - tb.q;
  });
}

const tileSkill = (t) => D.TILES[t.type].skill || "";
function skillLevel(s) {
  let l = 1;
  while (l < D.MAX_LEVEL && G.xp[s] >= xpForLevel(l)) l++;
  return l;
}
function levelProgress(s) {
  const l = skillLevel(s);
  if (l >= D.MAX_LEVEL) return 1;
  const lo = l === 1 ? 0 : xpForLevel(l - 1), hi = xpForLevel(l);
  return Math.min(1, Math.max(0, (G.xp[s] - lo) / (hi - lo)));
}
function masteryMult(s) {
  const l = skillLevel(s);
  let m = 1 + 0.01 * l;
  if (l >= 50) m *= 1.25;
  if (l >= 99) m *= 2;
  return m;
}
const manualDuration = (s) => Math.max(0.2, D.SKILLS[s].t0 * Math.pow(0.97, skillLevel(s) - 1));
const manualYield = (s) => 1 + 0.5 * G.tool[s];
const manualProgress = (key) => (G.manual && G.manual.key === key ? Math.min(1, G.manual.t / G.manual.dur) : 0);
function tileRate(t, offline = false) {
  const s = tileSkill(t);
  if (!s) return 0;
  let npc = t.npcs * D.NPC_RATE;
  if (offline) npc *= D.OFFLINE_NPC_EFF;
  if (G.starving) npc *= 0.25;
  const mach = t.machine > 0 ? D.MACHINE_BASE * (1 + 0.5 * (t.machine - 1)) : 0;
  return (npc + mach) * masteryMult(s);
}
function transportRate(key) {
  const t = G.tiles[key];
  const d = Math.max(1, hdist([t.q, t.r], [0, 0]));
  let trip = D.PORTER_TRIP_PER_HEX * d;
  if (!t.crane) trip *= 1 + D.ELEV_PENALTY * t.elev;
  let r = (t.porters * D.PORTER_CARRY) / trip;
  if (t.crane) r += D.CRANE_BONUS;
  return r;
}
const cap = () => D.WAREHOUSE_BASE * Math.pow(D.WAREHOUSE_GROWTH, G.warehouse);
function addRes(id, amount) {
  if (amount <= 0) return 0;
  if (id === "vang") { G.res.vang += amount; return amount; }
  const add = Math.min(Math.max(0, cap() - G.res[id]), amount);
  G.res[id] += add;
  return add;
}
const sumTiles = (f) => Object.values(G.tiles).reduce((a, t) => a + f(t), 0);
const totalNpcs = () => sumTiles((t) => t.npcs);
const portersFree = () => G.porters - sumTiles((t) => t.porters);
const armyPower = () => D.UNIT_ORDER.reduce((a, u) => a + G.army[u] * D.UNITS[u].power, 0);
const armyCount = () => D.UNIT_ORDER.reduce((a, u) => a + G.army[u], 0);
const armyUpkeep = () => D.UNIT_ORDER.reduce((a, u) => a + G.army[u] * D.UNITS[u].upkeep, 0);
const defensePower = () => D.VILLAGE_BASE_DEF + sumTiles((t) => (t.structure ? D.STRUCTURES[t.structure].def : 0)) + Math.floor(armyPower() * D.GARRISON_SHARE);
function foodRate() {
  let inc = 0;
  for (const k in G.tiles) {
    const t = G.tiles[k];
    if (t.owned && tileSkill(t) === "trong_lua") inc += Math.min(tileRate(t), transportRate(k));
  }
  return inc - (totalNpcs() * D.NPC_FOOD + armyUpkeep());
}
function bottleneckText(key) {
  const t = G.tiles[key], s = tileSkill(t);
  if (!s) return "";
  const prod = tileRate(t), tr = transportRate(key), rid = D.SKILLS[s].res;
  if (prod <= 0) return "Chưa có thợ hay máy: chỉ khai thác bằng tay.";
  if (tr <= 0) return "Nút thắt: chưa có khuân vác, hàng nằm ở bãi.";
  if (G.res[rid] >= cap() - 0.5) return "Nút thắt: kho đầy. Nâng cấp kho hoặc bán bớt.";
  if (tr < prod) return `Nút thắt: vận chuyển (chở ${tr.toFixed(2)} < làm ra ${prod.toFixed(2)}/giây).`;
  return "Ổn định: vận chuyển theo kịp sản xuất.";
}
function isAttackable(key) {
  const t = G.tiles[key];
  if (t.type !== "camp" || !t.revealed) return false;
  return neighbors(t.q, t.r).some(([q, r]) => G.tiles[hkey(q, r)] && G.tiles[hkey(q, r)].owned);
}
function isFogEdge(key) {
  const t = G.tiles[key];
  if (t.revealed) return false;
  return neighbors(t.q, t.r).some(([q, r]) => G.tiles[hkey(q, r)] && G.tiles[hkey(q, r)].revealed);
}

// --- chi phí ---
const costNpc = () => ({ vang: Math.floor(15 * Math.pow(1.15, totalNpcs())), lua: 10 });
const costPorter = () => ({ vang: Math.floor(10 * Math.pow(1.12, G.porters - D.START_PORTERS)) });
const costTool = (s) => ({ go: Math.floor(15 * Math.pow(1.25, G.tool[s])), da: Math.floor(10 * Math.pow(1.25, G.tool[s])) });
const costMachine = (t) => { const n = t.machine; return { go: Math.floor(150 * Math.pow(1.3, n)), da: Math.floor(150 * Math.pow(1.3, n)), vang: Math.floor(80 * Math.pow(1.3, n)) }; };
const costCrane = () => ({ go: 80, da: 60 });
const costWarehouse = () => ({ go: Math.floor(100 * Math.pow(1.6, G.warehouse)), da: Math.floor(80 * Math.pow(1.6, G.warehouse)) });
const costClearField = () => ({ go: 20 });
const canAfford = (c) => Object.keys(c).every((id) => (G.res[id] || 0) >= c[id]);
function pay(c) {
  if (!canAfford(c)) return false;
  for (const id in c) G.res[id] -= c[id];
  return true;
}
const costText = (c) => D.RES_ORDER.filter((id) => c[id] !== undefined).map((id) => `${Math.floor(c[id])} ${D.RES[id].name}`).join(", ");

// --- hành động ---
function startManual(key) {
  if (G.manual) return;
  const t = G.tiles[key], s = tileSkill(t);
  if (!s || !t.owned) return;
  G.manual = { key, t: 0, dur: manualDuration(s) };
}
const stopManual = () => { G.manual = null; };
function canHireNpc(key) {
  const t = G.tiles[key], s = tileSkill(t);
  return !!s && t.owned && skillLevel(s) >= D.HUT_UNLOCK && t.npcs < D.MAX_NPC_PER_TILE && canAfford(costNpc());
}
function hireNpc(key) {
  if (!canHireNpc(key)) return;
  pay(costNpc());
  const t = G.tiles[key];
  t.npcs++;
  if (t.npcs === 1) addLog("Thợ đầu tiên đã đến làm việc. Đừng quên giao khuân vác cho ô này!");
  changed();
}
function hirePorter() { if (pay(costPorter())) { G.porters++; changed(); } }
function assignPorter(key, d) {
  const t = G.tiles[key];
  if (d > 0 && (portersFree() <= 0 || t.porters >= D.MAX_PORTERS_PER_TILE)) return;
  if (d < 0 && t.porters <= 0) return;
  t.porters += d;
  changed();
}
function canBuyMachine(key) {
  const t = G.tiles[key], s = tileSkill(t);
  return !!s && t.owned && skillLevel(s) >= D.MACHINE_UNLOCK && canAfford(costMachine(t));
}
function buyMachine(key) {
  if (!canBuyMachine(key)) return;
  const t = G.tiles[key];
  pay(costMachine(t));
  t.machine++;
  addLog(`Máy móc cấp ${t.machine} bắt đầu chạy.`);
  changed();
}
function canBuildCrane(key) {
  const t = G.tiles[key];
  return t.owned && t.elev > 0 && !t.crane && skillLevel("dap_da") >= D.CRANE_UNLOCK && canAfford(costCrane());
}
function buildCrane(key) {
  if (!canBuildCrane(key)) return;
  pay(costCrane());
  G.tiles[key].crane = true;
  addLog("Cần cẩu đầu tiên kéo hàng lên dốc. Phạt độ dốc đã hết!");
  changed();
}
function upgradeTool(s) { if (pay(costTool(s))) { G.tool[s]++; changed(); } }
function upgradeWarehouse() {
  if (pay(costWarehouse())) { G.warehouse++; addLog(`Kho lên cấp ${G.warehouse}, sức chứa ${Math.floor(cap())}.`); changed(); }
}
function sell(id, amount) {
  const a = Math.min(amount, G.res[id]);
  if (a <= 0) return;
  G.res[id] -= a;
  G.res.vang += a * D.RES[id].price;
}
function canBuildStructure(key, sid) {
  const t = G.tiles[key];
  return t.owned && t.type === "grass" && !t.structure && canAfford(D.STRUCTURES[sid].cost);
}
function buildStructure(key, sid) {
  if (!canBuildStructure(key, sid)) return;
  pay(D.STRUCTURES[sid].cost);
  G.tiles[key].structure = sid;
  changed();
}
function clearField(key) {
  const t = G.tiles[key];
  if (t.owned && t.type === "grass" && !t.structure && pay(costClearField())) { t.type = "field"; changed(); }
}
function canTrain(u, n = 1) {
  const c = D.UNITS[u].cost, tot = {};
  for (const id in c) tot[id] = c[id] * n;
  return canAfford(tot);
}
function train(u, n = 1) {
  for (let i = 0; i < n; i++) {
    if (!pay(D.UNITS[u].cost)) break;
    G.queue.push({ unit: u, t: D.UNITS[u].time });
  }
  changed();
}
function applyLosses(losses) {
  for (const u in losses) G.army[u] = Math.max(0, G.army[u] - losses[u]);
  changed();
}
function captureCamp(key) {
  const t = G.tiles[key], idx = t.camp, loot = 30 * (idx + 1);
  G.res.vang += loot;
  addRes("go", 20 * (idx + 1));
  addRes("da", 15 * (idx + 1));
  t.type = "grass"; t.camp = -1;
  G.camps++;
  const c = [t.q, t.r];
  for (const n of coordsInRadius(c, 3)) {
    const nt = G.tiles[hkey(n[0], n[1])];
    if (!nt) continue;
    nt.revealed = true;
    if (hdist(n, c) <= 1 && nt.type !== "camp") nt.owned = true;
  }
  if (idx === D.CAMPS.length - 1) addLog("Sào huyệt thủ lĩnh đã thất thủ! Thung lũng hoàn toàn thuộc về bạn. (Hết nội dung prototype)");
  else addLog(`Chiếm được ${campName(idx)}! +${loot} Vàng, lãnh thổ mở rộng.`);
  changed();
}
function resolveRaid() {
  const atk = raidPower(G.camps), def = defensePower();
  if (def >= atk) {
    const loot = Math.floor(atk * 0.3);
    G.res.vang += loot;
    addLog(`Đánh lui đợt cướp (địch ${atk} / phòng thủ ${def}). +${loot} Vàng.`);
  } else {
    ["lua", "go", "da"].forEach((id) => (G.res[id] *= 1 - D.RAID_LOSS));
    addLog(`Thổ phỉ cướp làng! Mất 15% lúa, gỗ, đá (địch ${atk} / phòng thủ ${def}). Xây tháp, hàng rào hoặc thêm quân.`);
  }
}
function addLog(msg) {
  const d = new Date();
  const stamp = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
  G.log.unshift(`[${stamp}] ${msg}`);
  if (G.log.length > 40) G.log.length = 40;
}

// --- mô phỏng ---
function simulate(dt, offline) {
  G.play += dt;
  const need = (totalNpcs() * D.NPC_FOOD + armyUpkeep()) * dt;
  if (G.res.lua >= need) { G.res.lua -= need; G.starving = false; }
  else { G.res.lua = 0; G.starving = need > 0; }
  for (const key in G.tiles) {
    const t = G.tiles[key];
    if (!t.owned) continue;
    const s = tileSkill(t);
    if (!s) continue;
    const prod = tileRate(t, offline) * dt;
    const before = t.stock, avail = before + prod;
    let moved = 0;
    if (avail > 0) moved = addRes(D.SKILLS[s].res, Math.min(avail, transportRate(key) * dt));
    const ns = Math.min(D.STOCK_CAP, avail - moved);
    const produced = ns + moved - before;
    if (produced > 0) G.xp[s] += produced * D.AUTO_XP;
    t.stock = ns;
  }
  let left = dt;
  while (left > 0 && G.queue.length) {
    const job = G.queue[0], use = Math.min(left, job.t);
    job.t -= use; left -= use;
    if (job.t <= 0) { G.army[job.unit]++; G.queue.shift(); if (!offline) changed(); }
  }
  G.raid -= dt;
  if (G.raid <= 0) { G.raid += D.RAID_INTERVAL; resolveRaid(); if (!offline) changed(); }
}
function tickManual(dt) {
  if (!G.manual) return;
  G.manual.t += dt;
  if (G.manual.t < G.manual.dur) return;
  const t = G.tiles[G.manual.key], s = tileSkill(t);
  addRes(D.SKILLS[s].res, manualYield(s));
  G.xp[s] += D.MANUAL_XP;
  if (G.repeat && skillLevel(s) >= D.AUTO_REPEAT_UNLOCK) { G.manual.t = 0; G.manual.dur = manualDuration(s); }
  else G.manual = null;
}
const lastLevels = {};
function checkLevels() {
  for (const s of D.SKILL_ORDER) {
    const l = skillLevel(s), old = lastLevels[s] ?? l;
    if (l > old) {
      let msg = `${D.SKILLS[s].name} lên cấp ${l}.`;
      if (old < D.HUT_UNLOCK && l >= D.HUT_UNLOCK) msg += " Đã mở thuê thợ!";
      if (old < D.AUTO_REPEAT_UNLOCK && l >= D.AUTO_REPEAT_UNLOCK) msg += " Đã mở tự lặp thao tác tay!";
      if (s === "dap_da" && old < D.CRANE_UNLOCK && l >= D.CRANE_UNLOCK) msg += " Đã mở cần cẩu!";
      if (old < D.MACHINE_UNLOCK && l >= D.MACHINE_UNLOCK) msg += " Đã mở máy móc!";
      addLog(msg);
      changed();
    }
    lastLevels[s] = l;
  }
}

// --- lưu / tải / offline ---
const SAVE_KEY = "frontier_idle_save_v1";
function serialize() {
  return JSON.stringify({ v: 1, time: Date.now() / 1000, res: G.res, warehouse: G.warehouse, xp: G.xp, tool: G.tool, tiles: G.tiles,
    army: G.army, queue: G.queue, porters: G.porters, camps: G.camps, raid: G.raid, log: G.log, repeat: G.repeat, play: G.play });
}
function applySave(d) {
  if (!d || !d.tiles || !Object.keys(d.tiles).length) return false;
  G.res = Object.assign({ lua: 0, go: 0, da: 0, vang: 0 }, d.res);
  G.warehouse = d.warehouse | 0;
  G.xp = {}; G.tool = {};
  D.SKILL_ORDER.forEach((s) => { G.xp[s] = +((d.xp || {})[s] || 0); G.tool[s] = ((d.tool || {})[s] || 0) | 0; });
  G.army = {}; D.UNIT_ORDER.forEach((u) => (G.army[u] = ((d.army || {})[u] || 0) | 0));
  G.tiles = d.tiles;
  for (const k in G.tiles) {
    const t = G.tiles[k];
    ["q", "r", "elev", "npcs", "porters", "machine", "camp"].forEach((f) => (t[f] = (t[f] || 0) | 0));
    if (t.camp === 0 && t.type !== "camp") t.camp = -1;
    t.stock = +t.stock || 0;
    t.crane = !!t.crane;
    t.structure = t.structure || "";
  }
  G.queue = d.queue || []; G.porters = d.porters ?? D.START_PORTERS; G.camps = d.camps | 0;
  G.raid = d.raid ?? D.RAID_INTERVAL; G.log = d.log || []; G.repeat = !!d.repeat; G.play = +d.play || 0;
  G.manual = null;
  buildOrder();
  return true;
}
function saveLocal(force) {
  const s = serialize();
  try { localStorage.setItem(SAVE_KEY, s); } catch (e) { /* trình duyệt chặn lưu */ }
  Cloud.save(s, force === true);
  return s;
}
function loadLocal() {
  try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch (e) { return null; }
}
function fmtDuration(s) {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h} giờ ${m} phút` : `${m} phút`;
}
function runOffline(elapsed) {
  const secs = Math.min(elapsed, D.OFFLINE_CAP);
  const before = Object.assign({}, G.res);
  let rem = secs;
  while (rem > 0) { const st = Math.min(D.OFFLINE_STEP, rem); simulate(st, true); rem -= st; }
  const lines = [`Bạn đã vắng mặt ${fmtDuration(elapsed)}${elapsed > D.OFFLINE_CAP ? " (tính tối đa 12 giờ)" : ""}.`];
  const gains = D.RES_ORDER.map((id) => [id, G.res[id] - before[id]]).filter(([, g]) => Math.abs(g) >= 1)
    .map(([id, g]) => `${g > 0 ? "+" : ""}${Math.floor(g)} ${D.RES[id].name}`);
  lines.push("Thu được: " + (gains.length ? gains.join(", ") : "không có gì (chưa có thợ hoặc máy)."));
  const hints = [];
  const full = Object.values(G.tiles).find((t) => t.owned && t.stock >= D.STOCK_CAP * 0.95);
  if (full) hints.push(`Bãi chứa ở ${D.TILES[full.type].name} đầy: cần thêm khuân vác hoặc cần cẩu.`);
  const fullRes = ["lua", "go", "da"].find((id) => G.res[id] >= cap() - 0.5);
  if (fullRes) hints.push(`Kho ${D.RES[fullRes].name} đã đầy: nâng cấp kho.`);
  if (G.starving) hints.push("Hết lúa: thợ làm việc rất chậm. Cần thêm ruộng hoặc thợ trồng lúa.");
  if (hints.length) lines.push("Nút thắt: " + hints.join(" "));
  G.offlineReport = lines.join("\n");
  addLog(`Thu hoạch AFK sau ${fmtDuration(elapsed)}.`);
}
function resetGame() {
  try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* bỏ qua */ }
  newGame();
  D.SKILL_ORDER.forEach((s) => (lastLevels[s] = skillLevel(s)));
  saveLocal();
  changed();
}

// --- lưu đám mây khi chạy trên claude.ai (mỗi tài khoản một bản) ---
const Cloud = {
  ref: null, ready: false, disabled: false, pending: null, writing: false, lastWrite: 0,
  async init() {
    try {
      if (!window.claude || typeof window.claude.use !== "function") return null;
      const db = await window.claude.use("db");
      const user = await window.claude.use("user");
      if (!db || !user) return null;
      const uid = await user.id();
      if (!uid || this.disabled) return null;
      const ref = db.collection("data/users/" + uid).doc("save");
      const snap = await ref.get();
      if (this.disabled) return null;
      this.ref = ref;
      this.ready = true;
      if (snap && snap.exists) {
        const d = snap.data();
        if (d && typeof d.json === "string") return JSON.parse(d.json);
      }
    } catch (e) { /* không có đám mây: chỉ lưu trên trình duyệt */ }
    return null;
  },
  save(json, force) {
    if (!this.ready || !this.ref) return;
    this.pending = json;
    if (this.writing) return;
    if (!force && Date.now() - this.lastWrite < 60000) return;
    this.flush();
  },
  async flush() {
    if (!this.pending) return;
    const json = this.pending;
    this.pending = null;
    this.writing = true;
    try { await this.ref.set({ json, time: Date.now() / 1000 }); this.lastWrite = Date.now(); }
    catch (e) { if (e && (e.code === "invalid_argument" || e.code === "revoked")) this.ready = false; }
    this.writing = false;
  },
};

// =====================================================================
//  BẢN ĐỒ (scripts/map_view.gd)
// =====================================================================
const mapCanvas = document.getElementById("map");
const mctx = mapCanvas.getContext("2d");
const cam = { x: 0, y: 0, zoom: 1 };
let selected = "";
let time = 0;
let viewW = 0, viewH = 0, dpr = 1;

function hash32(t) { return Math.abs(Math.imul(t.q, 73856093) ^ Math.imul(t.r, 19349663)); }
function spriteName(t) {
  const h = hash32(t);
  switch (t.type) {
    case "village": return "village";
    case "forest": { const v = h % 10; return v === 0 ? "forest_autumn" : v < 4 ? "forest_small" : "forest"; }
    case "rock":
      if (t.elev >= 2) return h % 3 === 0 ? "mountain_snow" : "mountain";
      return t.npcs > 0 || t.machine > 0 ? "quarry" : "rocks";
    case "field": return t.machine > 0 ? "field_mill" : "field";
    case "grass": { const g = h % 6; return g < 2 ? "grass_flowers" : g < 4 ? "grass_tall" : "grass"; }
    case "water": return h % 5 === 0 ? "water_dock" : "water";
    case "camp": return "camp";
  }
  return "grass";
}
function viewCenter() {
  const top = document.getElementById("top").getBoundingClientRect().bottom;
  const bottom = document.getElementById("bottom").getBoundingClientRect().top;
  return [viewW / 2, (top + bottom) / 2];
}
function worldToScreen(x, y) {
  const [cx, cy] = viewCenter();
  return [(x - cam.x) * cam.zoom + cx, (y - cam.y) * cam.zoom + cy];
}
function screenToWorld(x, y) {
  const [cx, cy] = viewCenter();
  return [(x - cx) / cam.zoom + cam.x, (y - cy) / cam.zoom + cam.y];
}
function resize() {
  dpr = window.devicePixelRatio || 1;
  viewW = window.innerWidth; viewH = window.innerHeight;
  for (const c of [mapCanvas, bCanvas]) { c.width = Math.round(viewW * dpr); c.height = Math.round(viewH * dpr); }
}
const tileCenter = (t) => toPixel(t.q, t.r);

function drawMap() {
  const ctx = mctx;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = "#1f2a24";
  ctx.fillRect(0, 0, mapCanvas.width, mapCanvas.height);
  const [vcx, vcy] = viewCenter();
  ctx.setTransform(dpr * cam.zoom, 0, 0, dpr * cam.zoom, dpr * (vcx - cam.x * cam.zoom), dpr * (vcy - cam.y * cam.zoom));
  ctx.imageSmoothingQuality = "high";
  for (const key of G.order) {
    const t = G.tiles[key];
    if (t.revealed) drawTile(ctx, key, t);
    else if (isFogEdge(key)) {
      const [x, y] = tileCenter(t);
      if (!drawTileImg(ctx, "fog", x, y, HEX.SIZE, 0.9)) { ctx.fillStyle = "#3a4045"; polyPath(ctx, corners(x, y)); ctx.fill(); }
    }
  }
  drawSelection(ctx);
}
function drawTile(ctx, key, t) {
  const [x, y] = tileCenter(t);
  const dim = !t.owned && t.type !== "camp";
  if (!drawTileImg(ctx, spriteName(t), x, y, HEX.SIZE, 1, dim)) {
    ctx.fillStyle = D.TILES[t.type].color;
    polyPath(ctx, corners(x, y));
    ctx.fill();
  }
  drawBuildings(ctx, t, x, y);
  ctx.textAlign = "center";
  if (t.type === "camp") {
    ctx.font = "bold 11px sans-serif";
    ctx.lineWidth = 3; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.fillStyle = "#ffd2c8";
    const txt = "Sức mạnh " + campPower(t.camp);
    ctx.strokeText(txt, x, y + 34); ctx.fillText(txt, x, y + 34);
  }
  if (t.stock >= 1) {
    const full = t.stock >= D.STOCK_CAP - 0.5;
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(x - 16, y + 12, 32, 15);
    ctx.font = "bold 11px sans-serif";
    ctx.fillStyle = full ? "#ff7359" : "#fff7cc";
    ctx.fillText(String(Math.floor(t.stock)), x, y + 23.5);
  }
  const p = manualProgress(key);
  if (p > 0) {
    ctx.lineWidth = 6; ctx.strokeStyle = "rgba(0,0,0,0.5)";
    ctx.beginPath(); ctx.arc(x, y - 40, 13, 0, Math.PI * 2); ctx.stroke();
    ctx.lineWidth = 4; ctx.strokeStyle = "#ffe066";
    ctx.beginPath(); ctx.arc(x, y - 40, 13, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.stroke();
  }
}
function drawBuildings(ctx, t, x, y) {
  if (t.npcs > 0) {
    if (t.type !== "rock") drawProp(ctx, "house_wood", x - 30, y + 6, 34);
    ctx.font = "bold 11px sans-serif"; ctx.textAlign = "left";
    ctx.lineWidth = 3; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.fillStyle = "#fff";
    ctx.strokeText("x" + t.npcs, x - 44, y + 22); ctx.fillText("x" + t.npcs, x - 44, y + 22);
  }
  if (t.machine > 0 && t.type !== "field") {
    drawProp(ctx, "windmill", x + 30, y + 4, 44);
    const puff = (time % 1.5) / 1.5;
    ctx.fillStyle = `rgba(230,230,230,${0.6 * (1 - puff)})`;
    ctx.beginPath(); ctx.arc(x + 34, y - 42 - puff * 14, 4 + puff * 4, 0, Math.PI * 2); ctx.fill();
  }
  if (t.crane) {
    const bx = x - 32, by = y + 12;
    ctx.strokeStyle = "#d9a43a"; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(bx, by - 46); ctx.moveTo(bx - 6, by - 46); ctx.lineTo(bx + 28, by - 46); ctx.stroke();
    const hook = 8 + (Math.sin(time * 1.6) * 0.5 + 0.5) * 20;
    ctx.strokeStyle = "#333"; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(bx + 24, by - 46); ctx.lineTo(bx + 24, by - 46 + hook); ctx.stroke();
    if (!drawProp(ctx, "crate", bx + 24, by - 40 + hook + 10, 12)) { ctx.fillStyle = "#8a6a3f"; ctx.fillRect(bx + 20, by - 46 + hook, 8, 6); }
  }
  if (t.porters > 0) {
    const [vx, vy] = toPixel(0, 0);
    let dx = vx - x, dy = vy - y;
    const len = Math.hypot(dx, dy) || 1;
    dx /= len; dy /= len;
    for (let i = 0; i < Math.min(t.porters, 3); i++) {
      const k = (time * 0.35 + i * 0.33) % 1;
      const f = Math.min(len, 44) * (k < 0.5 ? k : 1 - k) * 2;
      const px = x + dx * f, py = y + dy * f;
      ctx.fillStyle = "rgba(0,0,0,0.3)"; ctx.beginPath(); ctx.arc(px, py + 12, 4, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#f0d9a0"; ctx.beginPath(); ctx.arc(px, py + 8, 3.5, 0, Math.PI * 2); ctx.fill();
    }
  }
  if (t.structure === "rao") {
    drawProp(ctx, "fence", x, y + 16, 22);
    drawProp(ctx, "fence", x - 14, y - 4, 18);
  } else if (t.structure === "thap_cung") {
    drawProp(ctx, "tower", x, y + 14, 70);
  }
}
function drawSelection(ctx) {
  if (!selected || !G.tiles[selected]) return;
  const t = G.tiles[selected];
  if (!t.revealed && !isFogEdge(selected)) return;
  const [x, y] = tileCenter(t);
  const pts = corners(x, y);
  const pulse = 0.5 + 0.5 * Math.sin(time * 4);
  ctx.fillStyle = `rgba(255,242,153,${0.16 + 0.12 * pulse})`;
  polyPath(ctx, pts); ctx.fill();
  ctx.lineJoin = "round";
  ctx.strokeStyle = "rgba(0,0,0,0.45)"; ctx.lineWidth = 7; polyPath(ctx, pts); ctx.stroke();
  ctx.strokeStyle = `rgba(255,224,102,${0.8 + 0.2 * pulse})`; ctx.lineWidth = 3.5; polyPath(ctx, pts); ctx.stroke();
}
function focusTile(key) {
  const t = G.tiles[key];
  if (!t) return;
  [cam.x, cam.y] = tileCenter(t);
}

// --- chạm / kéo / thu phóng ---
const pointers = new Map();
let pressPos = null, dragging = false, pinchDist = 0;
mapCanvas.addEventListener("pointerdown", (e) => {
  mapCanvas.setPointerCapture(e.pointerId);
  pointers.set(e.pointerId, [e.clientX, e.clientY]);
  if (pointers.size === 1) { pressPos = [e.clientX, e.clientY]; dragging = false; }
  if (pointers.size === 2) { const p = [...pointers.values()]; pinchDist = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]); dragging = true; }
});
mapCanvas.addEventListener("pointermove", (e) => {
  if (!pointers.has(e.pointerId)) return;
  const prev = pointers.get(e.pointerId);
  pointers.set(e.pointerId, [e.clientX, e.clientY]);
  if (pointers.size === 2) {
    const p = [...pointers.values()];
    const d = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]);
    if (pinchDist > 1) zoomBy(d / pinchDist);
    pinchDist = d;
    return;
  }
  if (pressPos && Math.hypot(e.clientX - pressPos[0], e.clientY - pressPos[1]) > 10) dragging = true;
  if (dragging) {
    cam.x -= (e.clientX - prev[0]) / cam.zoom;
    cam.y -= (e.clientY - prev[1]) / cam.zoom;
    cam.x = Math.max(-800, Math.min(800, cam.x));
    cam.y = Math.max(-700, Math.min(700, cam.y));
  }
});
function endPointer(e) {
  if (!pointers.has(e.pointerId)) return;
  const was = pointers.size;
  pointers.delete(e.pointerId);
  if (was === 1 && !dragging && pressPos && e.type === "pointerup") tapAt(e.clientX, e.clientY);
  if (pointers.size === 0) pressPos = null;
}
mapCanvas.addEventListener("pointerup", endPointer);
mapCanvas.addEventListener("pointercancel", endPointer);
mapCanvas.addEventListener("wheel", (e) => { e.preventDefault(); zoomBy(e.deltaY < 0 ? 1.1 : 1 / 1.1); }, { passive: false });
function zoomBy(f) { cam.zoom = Math.max(0.45, Math.min(2.4, cam.zoom * f)); }
function tapAt(sx, sy) {
  const [wx, wy] = screenToWorld(sx, sy);
  for (let i = G.order.length - 1; i >= 0; i--) {
    const key = G.order[i], t = G.tiles[key];
    if (!t.revealed && !isFogEdge(key)) continue;
    const [x, y] = tileCenter(t);
    if (pointInPoly(wx, wy, corners(x, y))) { selectTile(key); return; }
  }
}

// =====================================================================
//  GIAO DIỆN (scripts/ui.gd)
// =====================================================================
const $ = (id) => document.getElementById(id);
const panel = $("panel");
let tab = "map";
let armyPick = {};
let live = [];
let resetArmed = false;

function fmt(v) {
  if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
  if (v >= 1e4) return (v / 1e3).toFixed(1) + "K";
  return String(Math.floor(v));
}
function mk(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}
function title(t) { panel.appendChild(mk("div", "title", t)); }
function sub(t) { panel.appendChild(mk("div", "sub", t)); }
function hr() { panel.appendChild(mk("hr")); }
function label(text, parent = panel, cls = "lbl") {
  const e = mk("div", cls);
  if (typeof text === "function") live.push(() => (e.textContent = text()));
  else e.textContent = text;
  parent.appendChild(e);
  return e;
}
function button(text, onClick, enabled, parent = panel) {
  const b = mk("button");
  if (typeof text === "function") live.push(() => (b.textContent = text()));
  else b.textContent = text;
  b.addEventListener("click", () => { onClick(); runLive(); });
  if (enabled) live.push(() => (b.disabled = !enabled()));
  parent.appendChild(b);
  return b;
}
function row(parent = panel) { const r = mk("div", "row"); parent.appendChild(r); return r; }
function bar(fn) {
  const b = mk("div", "bar"), f = mk("div");
  b.appendChild(f);
  live.push(() => (f.style.width = Math.round(fn() * 100) + "%"));
  panel.appendChild(b);
}
function runLive() { for (const f of live) f(); }

function buildTabs() {
  const tabs = $("tabs");
  [["map", "Bản đồ"], ["skills", "Ngành nghề"], ["army", "Quân đội"], ["village", "Làng & Kho"], ["settings", "Cài đặt"]].forEach(([id, name]) => {
    const b = mk("button", "", name);
    b.dataset.tab = id;
    b.addEventListener("click", () => { tab = id; panel.classList.remove("collapsed"); updateToggle(); rebuild(); });
    tabs.appendChild(b);
  });
  $("toggle").addEventListener("click", () => { panel.classList.toggle("collapsed"); updateToggle(); });
}
function updateToggle() { $("toggle").textContent = panel.classList.contains("collapsed") ? "▴" : "▾"; }

function rebuild() {
  structureDirty = false;
  const scroll = panel.scrollTop;
  live = [];
  panel.innerHTML = "";
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
  ({ map: buildMapTab, skills: buildSkillsTab, army: buildArmyTab, village: buildVillageTab, settings: buildSettingsTab })[tab]();
  runLive();
  panel.scrollTop = scroll;
}
function selectTile(key) {
  selected = key;
  tab = "map";
  armyPick = {};
  panel.classList.remove("collapsed");
  updateToggle();
  rebuild();
}
function updateTop() {
  const res = $("res");
  res.innerHTML = "";
  for (const id of D.RES_ORDER) {
    const s = mk("span", "", id === "vang" ? `${D.RES[id].name} ${fmt(G.res[id])}` : `${D.RES[id].name} ${fmt(G.res[id])}/${fmt(cap())}`);
    s.style.color = D.RES[id].color;
    res.appendChild(s);
  }
  const mins = Math.floor(G.raid / 60), secs = Math.floor(G.raid % 60);
  const food = G.starving ? "HẾT LÚA!" : `Lúa ${foodRate() >= 0 ? "+" : ""}${foodRate().toFixed(2)}/s`;
  $("info").textContent = `Quân ${armyPower()} · Phòng thủ ${defensePower()} · Cướp sau ${mins}:${String(secs).padStart(2, "0")} · ${food}${G.speed > 1 ? " · x" + G.speed : ""}`;
}

// --- tab Bản đồ ---
function buildMapTab() {
  if (!selected || !G.tiles[selected]) {
    title("Thung lũng Khởi Nguyên");
    label("Chạm vào một ô trên bản đồ để xem và ra lệnh. Kéo để di chuyển, chụm hai ngón để thu phóng.");
    label("Bắt đầu: tự tay đốn gỗ, đập đá, gặt lúa. Lên cấp 10 ở một ngành để thuê thợ, rồi giao khuân vác chở hàng về làng.");
    return;
  }
  const key = selected, t = G.tiles[key];
  if (!t.revealed) { title("Vùng sương mù"); label("Chưa khám phá. Chiếm đồn địch gần đó để mở rộng tầm nhìn."); return; }
  const name = t.type === "camp" ? campName(t.camp) : D.TILES[t.type].name;
  title(name + (t.owned || t.type === "camp" ? "" : "  (ngoài lãnh thổ)"));
  if (t.elev > 0) label(`Địa hình dốc: ${t.elev} bậc. Khuân vác đi chậm hơn nếu không có cần cẩu.`);
  if (t.type === "camp") buildCamp(key, t);
  else if (t.type === "village") {
    label("Trung tâm làng, nơi đặt kho. Khuân vác chở tài nguyên từ bãi chứa các ô về đây.");
    label(() => `Khuân vác: ${G.porters} tổng, ${portersFree()} đang rảnh.`);
    button(() => `Thuê khuân vác (${costText(costPorter())})`, hirePorter, () => canAfford(costPorter()));
  } else if (t.type === "grass") buildGrass(key, t);
  else if (t.type === "water") label("Dòng sông chảy qua thung lũng. (Thời kỳ sau: bánh xe nước, câu cá.)");
  else if (tileSkill(t)) buildResource(key, t);
}
function buildResource(key, t) {
  const s = tileSkill(t), sd = D.SKILLS[s], rname = D.RES[sd.res].name;
  if (!t.owned) { label("Ô này chưa thuộc lãnh thổ. Chiếm đồn địch gần đó để sở hữu."); return; }
  label(() => `${sd.name} cấp ${skillLevel(s)} · mỗi lần ${manualDuration(s).toFixed(1)}s được ${manualYield(s).toFixed(1)} ${rname}`);
  bar(() => manualProgress(key));
  const r = row();
  button(sd.verb, () => startManual(key), () => !G.manual, r);
  button("Dừng", stopManual, () => !!G.manual, r);
  if (skillLevel(s) >= D.AUTO_REPEAT_UNLOCK) {
    const lab = mk("label", "check");
    const cb = mk("input");
    cb.type = "checkbox"; cb.checked = G.repeat;
    cb.addEventListener("change", () => (G.repeat = cb.checked));
    lab.appendChild(cb); lab.appendChild(document.createTextNode("Tự lặp lại thao tác tay"));
    panel.appendChild(lab);
  } else label(`Cấp ${D.AUTO_REPEAT_UNLOCK}: mở tự lặp lại thao tác tay.`);
  hr();
  sub("Thợ");
  if (skillLevel(s) < D.HUT_UNLOCK) label(`Đạt ${sd.name} cấp ${D.HUT_UNLOCK} để thuê thợ làm thay (bán tự động).`);
  else {
    label(() => `Thợ: ${t.npcs}/${D.MAX_NPC_PER_TILE} · làm ra ${tileRate(t).toFixed(2)} ${rname}/giây${G.starving ? " (đói, chậm)" : ""}`);
    button(() => `Thuê thợ (${costText(costNpc())})`, () => hireNpc(key), () => canHireNpc(key));
  }
  sub("Máy móc");
  if (skillLevel(s) < D.MACHINE_UNLOCK) label(`Đạt ${sd.name} cấp ${D.MACHINE_UNLOCK} để lắp máy (tự động hoàn toàn, chạy 100% khi offline).`);
  else {
    label(() => `Máy cấp ${t.machine}`);
    button(() => `${t.machine === 0 ? "Lắp máy" : "Nâng cấp máy"} (${costText(costMachine(t))})`, () => buyMachine(key), () => canBuyMachine(key));
  }
  hr();
  sub("Vận chuyển");
  label(() => `Bãi chứa ${Math.floor(t.stock)}/${D.STOCK_CAP} · Khuân vác ${t.porters} · chở ${transportRate(key).toFixed(2)}/giây`);
  const r2 = row();
  button("– Khuân vác", () => assignPorter(key, -1), () => t.porters > 0, r2);
  button("+ Khuân vác", () => assignPorter(key, 1), () => portersFree() > 0 && t.porters < D.MAX_PORTERS_PER_TILE, r2);
  label(() => `Khuân vác rảnh: ${portersFree()} (thuê thêm ở ô Làng hoặc tab Làng & Kho)`);
  if (t.elev > 0) {
    if (t.crane) label(`Đã có cần cẩu: không còn phạt độ dốc, chở thêm ${D.CRANE_BONUS}/giây.`);
    else if (skillLevel("dap_da") < D.CRANE_UNLOCK) label(`Đập đá cấp ${D.CRANE_UNLOCK}: mở cần cẩu cho ô dốc.`);
    else button(`Xây cần cẩu (${costText(costCrane())})`, () => buildCrane(key), () => canBuildCrane(key));
  }
  label(() => bottleneckText(key), panel, "lbl warn");
}
function buildGrass(key, t) {
  if (!t.owned) { label("Ô này chưa thuộc lãnh thổ."); return; }
  if (t.structure) { const sd = D.STRUCTURES[t.structure]; label(`Đã xây: ${sd.name} (+${sd.def} phòng thủ).`); return; }
  label("Đất trống. Có thể xây công trình phòng thủ hoặc khai hoang thành ruộng.");
  for (const sid of D.STRUCTURE_ORDER) {
    const sd = D.STRUCTURES[sid];
    button(`Xây ${sd.name}, +${sd.def} phòng thủ (${costText(sd.cost)})`, () => buildStructure(key, sid), () => canBuildStructure(key, sid));
  }
  button(`Khai hoang thành ruộng lúa (${costText(costClearField())})`, () => clearField(key), () => canAfford(costClearField()));
}
function pickPower() { return D.UNIT_ORDER.reduce((a, u) => a + Math.min(armyPick[u] || 0, G.army[u]) * D.UNITS[u].power, 0); }
function buildCamp(key, t) {
  const idx = t.camp;
  label(`Sức mạnh địch ước tính: ${campPower(idx)}. Thắng sẽ chiếm các ô xung quanh và nhận ${30 * (idx + 1)} Vàng.`);
  if (!isAttackable(key)) { label("Cần có lãnh thổ giáp ranh mới tấn công được."); return; }
  if (armyCount() === 0) {
    label("Chưa có quân. Vào tab Quân đội để huấn luyện.");
    button("Mở tab Quân đội", () => { tab = "army"; rebuild(); });
    return;
  }
  if (!Object.keys(armyPick).length) D.UNIT_ORDER.forEach((u) => (armyPick[u] = G.army[u]));
  sub("Chọn quân xuất trận");
  for (const u of D.UNIT_ORDER) {
    if (G.army[u] <= 0) continue;
    const r = row();
    label(() => `${D.UNITS[u].name}: ${armyPick[u] || 0}/${G.army[u]}`, r);
    button("–", () => (armyPick[u] = Math.max(0, (armyPick[u] || 0) - 1)), null, r).className = "narrow";
    button("+", () => (armyPick[u] = Math.min(G.army[u], (armyPick[u] || 0) + 1)), null, r).className = "narrow";
  }
  label(() => `Sức mạnh mang theo: ${pickPower()} · Địch: ${campPower(idx)}`);
  button("Tấn công!", () => {
    const pick = {};
    let n = 0;
    D.UNIT_ORDER.forEach((u) => { pick[u] = Math.min(armyPick[u] || 0, G.army[u]); n += pick[u]; });
    if (!n) return;
    armyPick = {};
    Battle.start(key, pick);
  }, () => pickPower() > 0);
}

// --- tab Ngành nghề ---
function milestones(s) {
  const l = skillLevel(s);
  const items = [[D.HUT_UNLOCK, "thuê thợ"], [D.AUTO_REPEAT_UNLOCK, "tự lặp"], [D.MACHINE_UNLOCK, "máy móc"], [50, "máy +25%"], [99, "Bậc thầy, máy x2"]]
    .map(([lv, n]) => `${l >= lv ? "[x]" : "[ ]"} ${lv} ${n}`);
  if (s === "dap_da") items.push(`${l >= D.CRANE_UNLOCK ? "[x]" : "[ ]"} ${D.CRANE_UNLOCK} cần cẩu`);
  return "Mốc: " + items.join("  ");
}
function buildSkillsTab() {
  title("Ngành nghề & thuần thục");
  label("Mỗi lần làm (tay, thợ hay máy) đều tăng thuần thục. Cấp càng cao thao tác càng nhanh và máy càng mạnh.");
  for (const s of D.SKILL_ORDER) {
    const sd = D.SKILLS[s];
    hr(); sub(sd.name);
    label(() => `Cấp ${skillLevel(s)} · XP ${Math.floor(G.xp[s])}/${Math.floor(xpForLevel(skillLevel(s)))} · hệ số sản lượng x${masteryMult(s).toFixed(2)}`);
    bar(() => levelProgress(s));
    label(() => `Thao tác tay: ${manualDuration(s).toFixed(2)}s · công cụ cấp ${G.tool[s]} (mỗi lần +${manualYield(s).toFixed(1)})`);
    button(() => `Nâng công cụ (${costText(costTool(s))})`, () => upgradeTool(s), () => canAfford(costTool(s)));
    label(() => milestones(s));
  }
}

// --- tab Quân đội ---
function buildArmyTab() {
  title("Quân đội");
  label(() => `Sức mạnh ${armyPower()} · Lương thực nuôi quân ${armyUpkeep().toFixed(2)} lúa/giây · Phòng thủ làng ${defensePower()}`);
  label(() => `Đợt cướp kế tiếp: sức mạnh ${raidPower(G.camps)}, sau ${Math.floor(G.raid / 60)} phút.`);
  label(() => {
    if (!G.queue.length) return "Hàng chờ huấn luyện: trống.";
    const f = G.queue[0];
    return `Đang luyện: ${D.UNITS[f.unit].name} (còn ${Math.ceil(f.t)}s) · hàng chờ ${G.queue.length}`;
  });
  for (const u of D.UNIT_ORDER) {
    const d = D.UNITS[u];
    hr();
    label(() => `${d.name} (${G.army[u]}) · ${d.desc} · máu ${d.hp}, công ${d.atk}, sức mạnh ${d.power}`);
    const r = row();
    button(`Luyện 1 (${costText(d.cost)})`, () => train(u, 1), () => canTrain(u, 1), r);
    button("x5", () => train(u, 5), () => canTrain(u, 5), r).className = "narrow";
  }
  hr(); sub("Đồn địch đã phát hiện");
  let any = false;
  for (const key of G.order) {
    const t = G.tiles[key];
    if (t.type === "camp" && t.revealed) {
      any = true;
      button(`${campName(t.camp)} (sức mạnh ${campPower(t.camp)})${isAttackable(key) ? " · có thể tấn công" : ""}`, () => { focusTile(key); selectTile(key); });
    }
  }
  if (!any) label("Chưa thấy đồn địch nào.");
}

// --- tab Làng & Kho ---
function buildVillageTab() {
  title("Làng & Kho");
  label(() => `Kho cấp ${G.warehouse} · sức chứa ${Math.floor(cap())} mỗi loại (Vàng không giới hạn).`);
  button(() => `Nâng cấp kho (${costText(costWarehouse())})`, upgradeWarehouse, () => canAfford(costWarehouse()));
  label(() => `Khuân vác: ${G.porters} tổng, ${portersFree()} rảnh.`);
  button(() => `Thuê khuân vác (${costText(costPorter())})`, hirePorter, () => canAfford(costPorter()));
  hr(); sub("Chợ");
  for (const id of ["lua", "go", "da"]) {
    const r = row();
    label(`${D.RES[id].name}: ${D.RES[id].price} vàng/đơn vị`, r);
    button("Bán 50", () => sell(id, 50), () => G.res[id] >= 1, r);
  }
  hr(); sub("Nhật ký");
  label(() => G.log.slice(0, 12).join("\n"), panel, "log");
}

// --- tab Cài đặt ---
function buildSettingsTab() {
  title("Cài đặt");
  label(() => `Thời gian đã chơi: ${fmtDuration(G.play)} · Tự lưu mỗi ${D.AUTOSAVE_SEC} giây.`);
  label(() => (Cloud.ready ? "Lưu đám mây: đang bật (đồng bộ giữa các máy cùng tài khoản)." : "Lưu trên trình duyệt này."));
  button("Lưu ngay", () => { saveLocal(true); addLog("Đã lưu."); });
  hr(); sub("Chơi lại từ đầu");
  if (!resetArmed) {
    label("Xóa toàn bộ tiến độ (tài nguyên, thuần thục, lãnh thổ, quân đội) và bắt đầu lại ở làng quê.");
    button("Chơi lại từ đầu", () => { resetArmed = true; rebuild(); });
  } else {
    label("Bạn chắc chắn muốn xóa save? Không thể hoàn tác.", panel, "lbl warn");
    const r = row();
    button("Xóa và chơi lại", () => {
      resetArmed = false; selected = ""; armyPick = {}; G.speed = 1;
      resetGame(); saveLocal(true); cam.x = 0; cam.y = 0; tab = "map"; rebuild();
      showPopup("Bắt đầu lại", "Đã xóa save. Một làng quê yên bình bên sông đang chờ bạn.");
    }, null, r);
    button("Hủy", () => { resetArmed = false; rebuild(); }, null, r);
  }
  hr(); sub("Công cụ thử nghiệm");
  const r2 = row();
  button(() => `Tốc độ thế giới x${G.speed}`, () => { const o = [1, 5, 20]; G.speed = o[(o.indexOf(G.speed) + 1) % o.length]; }, null, r2);
  button("+500 mỗi loại", () => D.RES_ORDER.forEach((id) => addRes(id, 500)), null, r2);
}

// --- popup ---
function showPopup(t, m) {
  if (!m) return;
  const o = $("overlay");
  o.querySelector(".t").textContent = t;
  o.querySelector(".m").textContent = m;
  o.style.display = "flex";
}
$("overlay").querySelector("button").addEventListener("click", () => ($("overlay").style.display = "none"));

// =====================================================================
//  TRẬN ĐÁNH (scripts/battle_view.gd) — mô phỏng trong khung ảo 720x1280
// =====================================================================
const bCanvas = $("bcanvas");
const bctx = bCanvas.getContext("2d");
const Battle = {
  units: [], shots: [], key: "", pick: {}, time: 0, running: false, visible: false, speed: 1, lastWin: false, board: [],
  start(key, pick) {
    this.key = key; this.pick = Object.assign({}, pick);
    this.units = []; this.shots = []; this.time = 0; this.speed = 1; this.running = true; this.visible = true;
    $("bspeed").textContent = "x1"; $("bresult").style.display = "none"; $("bretreat").disabled = false;
    const W = 720, H = 1280, cx = W / 2;
    const rows = { 0: [], 1: [], 2: [] };
    D.UNIT_ORDER.forEach((u) => { for (let i = 0; i < (pick[u] || 0); i++) rows[D.UNITS[u].row].push(u); });
    let y = H * 0.62;
    [0, 1, 2].forEach((r) => (y = this.place(rows[r], cx, y, 1, true, 1)));
    const idx = G.tiles[key].camp, power = campPower(idx);
    const raw = Math.max(3, Math.floor(power / 7)), n = Math.min(raw, D.BATTLE_MAX_PER_SIDE), mult = raw / n;
    const nArch = Math.floor(n * 0.3);
    const er = { 0: Array(n - nArch).fill("tho_phi"), 2: Array(nArch).fill("cung_phi") };
    y = H * 0.38;
    [0, 2].forEach((r) => (y = this.place(er[r], cx, y, -1, false, mult)));
    this.title = campName(idx);
    this.buildBoard();
    $("battle").style.display = "block";
  },
  place(list, cx, y, dir, mine, mult) {
    if (!list.length) return y;
    const perRow = 10, spacing = 52;
    let i = 0;
    while (i < list.length) {
      const count = Math.min(perRow, list.length - i);
      for (let j = 0; j < count; j++) {
        const type = list[i + j], d = mine ? D.UNITS[type] : D.ENEMIES[type];
        this.units.push({ mine, type, hp: d.hp * mult, max: d.hp * mult, atk: d.atk * mult, range: d.range, speed: d.speed,
          x: cx + (j - (count - 1) / 2) * spacing, y, cd: Math.random() * 0.6 });
      }
      i += count; y += 46 * dir;
    }
    return y + 20 * dir;
  },
  buildBoard() {
    this.board = [];
    const hs = 42, k = hs / HEX.SIZE, cx = 360, cy = 640, names = ["grass", "grass_flowers", "grass_tall"];
    for (const c of coordsInRadius([0, 0], 9)) {
      const [px, py] = toPixel(c[0], c[1]);
      const x = cx + px * k, y = cy + py * k;
      if (x < -hs || x > 720 + hs || y < 128 || y > 1100) continue;
      const edge = x < hs * 1.2 || x > 720 - hs * 1.2;
      const h = Math.abs(Math.imul(c[0], 92821) ^ Math.imul(c[1], 68917));
      this.board.push({ x, y, name: edge ? (h % 2 ? "forest" : "forest_small") : names[h % 3] });
    }
    this.board.sort((a, b) => a.y - b.y);
  },
  step(dt) {
    this.time += dt;
    for (const u of this.units) {
      if (u.hp <= 0) continue;
      let best = null, bd = Infinity;
      for (const o of this.units) {
        if (o.mine === u.mine || o.hp <= 0) continue;
        const d = (o.x - u.x) ** 2 + (o.y - u.y) ** 2;
        if (d < bd) { bd = d; best = o; }
      }
      if (!best) continue;
      const dist = Math.sqrt(bd);
      if (dist > u.range) { u.x += ((best.x - u.x) / dist) * u.speed * dt; u.y += ((best.y - u.y) / dist) * u.speed * dt; }
      else {
        u.cd -= dt;
        if (u.cd <= 0) {
          u.cd = 1; best.hp -= u.atk;
          if (u.range > 60) this.shots.push({ ax: u.x, ay: u.y, bx: best.x, by: best.y, ttl: 0.15, mine: u.mine });
        }
      }
    }
    for (const a of this.units) {
      if (a.hp <= 0) continue;
      for (const b of this.units) {
        if (a === b || b.hp <= 0) continue;
        const dx = a.x - b.x, dy = a.y - b.y, d = Math.hypot(dx, dy);
        if (d < 22 && d > 0.01) { a.x += (dx / d) * (22 - d) * 0.5; a.y += (dy / d) * (22 - d) * 0.5; }
      }
    }
    let mineAlive = 0, enemyAlive = 0;
    for (const u of this.units) if (u.hp > 0) u.mine ? mineAlive++ : enemyAlive++;
    if (enemyAlive === 0) this.finish(true, false);
    else if (mineAlive === 0 || this.time >= D.BATTLE_TIME_LIMIT) this.finish(false, false);
  },
  finish(win, retreated) {
    this.running = false;
    $("bretreat").disabled = true;
    const alive = {};
    D.UNIT_ORDER.forEach((u) => (alive[u] = 0));
    for (const u of this.units) if (u.mine && u.hp > 0) alive[u.type]++;
    const losses = {};
    let lost = 0;
    D.UNIT_ORDER.forEach((u) => { losses[u] = (this.pick[u] || 0) - alive[u]; lost += losses[u]; });
    applyLosses(losses);
    let text;
    if (win) { text = `Chiến thắng!\nĐồn địch đã bị chiếm, lãnh thổ mở rộng.\nTổn thất: ${lost} lính.`; captureCamp(this.key); }
    else if (retreated) text = `Đã rút quân.\nTổn thất: ${lost} lính.`;
    else text = `Thất bại.\nTổn thất: ${lost} lính.\nHãy luyện thêm quân hoặc dùng lính khiên ở hàng trước.`;
    $("bresult").querySelector(".m").textContent = text;
    $("bresult").style.display = "block";
    this.lastWin = win;
    saveLocal(true);
  },
  update(dt) {
    if (!this.visible) return;
    if (this.running) {
      for (let i = 0; i < this.speed && this.running; i++) this.step(Math.min(dt, 0.05));
      $("btitle").textContent = `${this.title} — ${Math.floor(this.time)} giây`;
    }
    for (const s of this.shots) s.ttl -= dt;
    this.shots = this.shots.filter((s) => s.ttl > 0);
    this.draw();
  },
  draw() {
    const ctx = bctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#141813";
    ctx.fillRect(0, 0, bCanvas.width, bCanvas.height);
    const sc = Math.min(viewW / 720, viewH / 1280) * dpr;
    const ox = (bCanvas.width - 720 * sc) / 2, oy = (bCanvas.height - 1280 * sc) / 2;
    ctx.setTransform(sc, 0, 0, sc, ox, oy);
    for (const b of this.board) drawTileImg(ctx, b.name, b.x, b.y, 42, 0.92);
    for (const s of this.shots) {
      ctx.strokeStyle = s.mine ? "#99d9ff" : "#ff9973"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(s.ax, s.ay); ctx.lineTo(s.bx, s.by); ctx.stroke();
    }
    for (const u of this.units) {
      if (u.hp <= 0) continue;
      const body = u.mine ? "#4a7fc1" : "#b8483a";
      ctx.fillStyle = "rgba(0,0,0,0.25)"; ctx.beginPath(); ctx.ellipse(u.x, u.y + 9, 11, 5, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = body;
      if (u.type === "linh_khien") {
        ctx.fillRect(u.x - 11, u.y - 12, 22, 22);
        ctx.strokeStyle = "#e6e6e6"; ctx.lineWidth = 2; ctx.strokeRect(u.x - 11, u.y - 12, 22, 22);
      } else if (u.type === "cung_thu" || u.type === "cung_phi") {
        ctx.beginPath(); ctx.arc(u.x, u.y, 9, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = "#d9c08a"; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(u.x + 8, u.y, 8, -Math.PI / 2, Math.PI / 2); ctx.stroke();
      } else {
        ctx.beginPath(); ctx.arc(u.x, u.y, 10, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = "#cfcfcf"; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(u.x + 6, u.y + 6); ctx.lineTo(u.x + 14, u.y - 12); ctx.stroke();
      }
      const ratio = Math.max(0, Math.min(1, u.hp / u.max));
      ctx.fillStyle = "rgba(0,0,0,0.6)"; ctx.fillRect(u.x - 13, u.y - 22, 26, 4);
      ctx.fillStyle = u.mine ? "#6cd36c" : "#e86a5a"; ctx.fillRect(u.x - 13, u.y - 22, 26 * ratio, 4);
    }
    ctx.font = "bold 20px sans-serif"; ctx.textAlign = "left";
    ctx.fillStyle = "#ffb3a6"; ctx.fillText("Địch", 20, 1280 * 0.17);
    ctx.fillStyle = "#b3d9ff"; ctx.fillText("Quân ta", 20, 1280 * 0.8);
  },
  close() {
    this.visible = false;
    $("battle").style.display = "none";
    $("bresult").style.display = "none";
    rebuild();
  },
};
$("bretreat").addEventListener("click", () => { if (Battle.running) Battle.finish(false, true); });
$("bspeed").addEventListener("click", () => { Battle.speed = Battle.speed === 1 ? 2 : Battle.speed === 2 ? 4 : 1; $("bspeed").textContent = "x" + Battle.speed; });
$("bclose").addEventListener("click", () => Battle.close());

// =====================================================================
//  VÒNG LẶP
// =====================================================================
let acc = 0, saveAcc = 0, uiAcc = 0, lastT = performance.now(), hiddenAt = 0;
function frame(now) {
  const dt = Math.min(0.25, (now - lastT) / 1000);
  lastT = now;
  time += dt;
  acc += dt * G.speed;
  let steps = 0;
  while (acc >= D.TICK && steps < 400) { acc -= D.TICK; steps++; simulate(D.TICK, false); tickManual(D.TICK); }
  checkLevels();
  saveAcc += dt;
  if (saveAcc >= D.AUTOSAVE_SEC) { saveAcc = 0; saveLocal(); }
  if (structureDirty) rebuild();
  uiAcc += dt;
  if (uiAcc >= 0.2) { uiAcc = 0; updateTop(); runLive(); }
  if (Battle.visible) Battle.update(dt);
  else drawMap();
  requestAnimationFrame(frame);
}
document.addEventListener("visibilitychange", () => {
  if (document.hidden) { saveLocal(true); hiddenAt = Date.now() / 1000; }
  else if (hiddenAt) {
    const el = Date.now() / 1000 - hiddenAt;
    hiddenAt = 0;
    lastT = performance.now();
    if (el > 60) { runOffline(el); showPopup("Chào mừng trở lại", G.offlineReport); changed(); }
  }
});
window.addEventListener("pagehide", () => saveLocal(true));
window.addEventListener("resize", resize);

async function boot() {
  resize();
  buildTabs();
  await loadImages();
  const local = loadLocal();
  let cloud = null;
  let timedOut = false;
  try {
    cloud = await Promise.race([Cloud.init(), new Promise((r) => setTimeout(() => { timedOut = true; r(null); }, 10000))]);
  } catch (e) { cloud = null; }
  if (timedOut) Cloud.disabled = true; // đám mây trả lời quá chậm: lần này chỉ lưu trên trình duyệt
  const pickSave = [local, cloud].filter(Boolean).sort((a, b) => (b.time || 0) - (a.time || 0))[0];
  if (!pickSave || !applySave(pickSave)) newGame();
  else {
    const el = Date.now() / 1000 - (pickSave.time || Date.now() / 1000);
    if (el > 60) runOffline(el);
  }
  D.SKILL_ORDER.forEach((s) => (lastLevels[s] = skillLevel(s)));
  cam.zoom = Math.max(0.6, Math.min(1.3, viewW / 420));
  $("loading").style.display = "none";
  rebuild();
  updateTop();
  if (G.offlineReport) showPopup("Chào mừng trở lại", G.offlineReport);
  saveLocal(true);
  requestAnimationFrame((t) => { lastT = t; frame(t); });
}
boot();
