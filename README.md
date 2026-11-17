# Frontier Idle – prototype

Prototype 2D màn hình dọc làm bằng **Godot 4.3+** (GDScript), theo tài liệu thiết kế "GDD – Game Idle Khai thác, Tự động hóa & Lãnh thổ".

## Bản web (chơi trên điện thoại)

Thư mục `web/` là bản chuyển sang HTML5/JavaScript, cùng luật chơi và cùng bộ ảnh với bản Godot:
- Chơi ngay: https://claude.ai/artifact/9SZT4WNDkCAPrviJakp7eN (mở bằng trình duyệt điện thoại, đăng nhập claude.ai; save đồng bộ theo tài khoản).
- Chạy trên máy: `cd web && python3 -m http.server 8000` rồi mở http://localhost:8000. Khi chạy ngoài claude.ai, save lưu trong trình duyệt.
- Ảnh trong `web/assets/` là bản chép từ `assets/`; chạy lại `tools/slice_assets.py` thì chép lại sang.

## Chạy thử (Godot)

1. Cài Godot 4.3 trở lên (bản Standard, không cần .NET).
2. Mở Godot → **Import** → chọn file `project.godot` trong thư mục này.
3. Bấm **F5**. Cửa sổ mô phỏng màn hình điện thoại dọc.
4. Xuất APK cho Android: xem mục **Xuất APK** bên dưới (preset Android đã có sẵn trong `export_presets.cfg`).

## Xuất APK

Cần cài một lần:
1. **Export template**: trong Godot → *Editor → Manage Export Templates → Download and Install* (đúng phiên bản Godot đang dùng).
2. **OpenJDK 17** (ví dụ bản Temurin của Adoptium).
3. **Android SDK**: dễ nhất là cài Android Studio, mở một lần để nó tải SDK; trong *SDK Manager* tick thêm Platform-Tools, Build-Tools, SDK Platform và Command-line Tools bản mới nhất.
4. Trong Godot → *Editor → Editor Settings → Export → Android*: điền **Java SDK Path** (thư mục JDK 17) và **Android SDK Path** (Windows thường là `%LOCALAPPDATA%\Android\Sdk`).

Mỗi lần xuất:
1. *Project → Export…* → chọn preset **Android** → **Export Project…**.
2. Giữ tick **Export With Debug** (bản cá nhân, Godot tự ký bằng debug keystore) → lưu ra `build/FrontierIdle.apk`.
3. Chép APK sang điện thoại, cho phép cài ứng dụng từ nguồn không xác định rồi mở file để cài. Hoặc cắm cáp và chạy `adb install -r build/FrontierIdle.apk`.

Lỗi hay gặp: nút Export bị mờ hoặc báo thiếu template → cài lại export template đúng phiên bản; báo lỗi Java/SDK → kiểm tra lại 2 đường dẫn ở bước 4 và dùng JDK 17.

## Đã có trong prototype

- **Bản đồ lục giác góc nhìn 3/4** (thời kỳ 1 – Làng quê): kéo để di chuyển, chụm hai ngón / lăn chuột để thu phóng, ô có độ cao và sương mù.
- **Khai thác bằng tay** ở Rừng, Mỏ đá, Ruộng lúa. Mỗi lần làm tăng **thuần thục** (cấp 1–99): thao tác nhanh dần, mở mốc mới.
- **Tự động hóa 3 nấc**: cấp 10 thuê **thợ**, cấp 20 **tự lặp** thao tác tay, cấp 30 lắp **máy**.
- **Vận chuyển là nút thắt**: hàng do thợ/máy làm ra nằm ở bãi chứa của ô; phải giao **khuân vác** chở về kho. Ô có độ cao chở chậm hơn, xây **cần cẩu** (Đập đá cấp 15) để bỏ phạt. Mỗi ô hiển thị nút thắt hiện tại.
- **Kho** có giới hạn, nâng cấp được; **chợ** bán tài nguyên lấy vàng; **công cụ** tăng sản lượng mỗi lần làm.
- **Lương thực**: thợ và lính ăn lúa liên tục, hết lúa thì thợ làm rất chậm.
- **Quân đội**: Dân quân, Cung thủ, Lính khiên nuôi bằng tài nguyên; hàng chờ huấn luyện.
- **Tấn công đồn địch**: chọn quân → trận tự đánh trên bàn lục giác, chỉ có nút **Rút quân** và tăng tốc. Thắng thì chiếm ô xung quanh, mở sương mù. 8 đồn, đồn cuối là sào huyệt thủ lĩnh.
- **Phòng thủ**: đợt cướp mỗi 30 phút; xây hàng rào, tháp cung trên đồng cỏ; quân ở nhà góp 50% sức mạnh.
- **AFK/offline**: tự lưu mỗi 30 giây; mở lại game sẽ tính tối đa 12 giờ vắng mặt (thợ 50%, máy 100%) và báo nút thắt.
- **Tab Cài đặt**: lưu ngay, chơi lại từ đầu (có bước xác nhận), tăng tốc thế giới x5/x20, +500 tài nguyên.

Chưa làm (theo lộ trình): thời kỳ 2 trở đi, cáp treo, gương thông, cổng dịch chuyển, nghiên cứu, Tái thiết, Bảo tàng.

## Hình ảnh

Ô đất và công trình lấy từ sprite sheet `art_source/sheet_village.png`. Script `tools/slice_assets.py` cắt sheet, xoá nền và tạo:

- `assets/tiles/*.png` – ô **lục giác đỉnh phẳng** (cạnh trên/dưới nằm ngang), canvas 200×300, tâm mặt trên ở (100, 196), mặt trên rộng 164 px, tỉ lệ dẹt 0.67. Ảnh gốc là lục giác đỉnh nhọn nên script dựng lại từng ô: trải phẳng mặt đất, xoay 30° rồi ép lại theo góc nhìn; hông đất lấy từ dải đất của ảnh gốc uốn vào 3 mặt hông mới; cây, đá, núi, nhà, hàng rào dán lên như đồ vật. Gồm ô nền (cỏ, cỏ hoa, cỏ dài, đất, hồ, ruộng) và ô ghép: rừng thông, rừng nhỏ, rừng thu, bãi đá, núi, núi tuyết, làng, đồn thổ phỉ, mỏ đá có thợ, ruộng có cối xay, hồ có bến thuyền, sương mù, và sẵn cho thời kỳ sau: đất hoang, đất nhiễm độc, mỏ tinh thể.
- `assets/props/*.png` – nhà, tháp, cối xay, chợ, giếng, tinh thể, bến, cờ, thùng, cây, đá, hoa, hàng rào, đèn…

Muốn thêm/đổi asset: sửa `TILE_BOXES` / `PROP_BOXES` hoặc phần "asset tự tạo" trong script rồi chạy:

```bash
pip install pillow numpy scipy
python3 tools/slice_assets.py
```

Thiếu ảnh nào thì game tự vẽ hình tạm bằng code.

## Cấu trúc code

| File | Vai trò |
|---|---|
| `scripts/data.gd` | Toàn bộ số liệu cân bằng (autoload `Data`) |
| `scripts/game.gd` | Trạng thái, mô phỏng, lưu/tải, offline (autoload `Game`) |
| `scripts/hex.gd` | Toán lưới lục giác (đỉnh phẳng) |
| `scripts/tile_art.gd` | Nạp và vẽ ảnh ô / đồ vật |
| `scripts/map_view.gd` | Vẽ bản đồ, chạm/kéo/thu phóng |
| `scripts/ui.gd` | Thanh tài nguyên, bảng thông tin, 4 tab |
| `scripts/battle_view.gd` | Trận đánh tự động |
| `scripts/main.gd` | Ghép các phần lại |

Save nằm ở `user://save.json` (trên Windows: `%APPDATA%/Godot/app_userdata/Frontier Idle/`).
