# Frontier Idle – prototype

Prototype 2D màn hình dọc làm bằng **Godot 4.3+** (GDScript), theo tài liệu thiết kế "GDD – Game Idle Khai thác, Tự động hóa & Lãnh thổ".

## Chạy thử

1. Cài Godot 4.3 trở lên (bản Standard, không cần .NET).
2. Mở Godot → **Import** → chọn file `project.godot` trong thư mục này.
3. Bấm **F5**. Cửa sổ mô phỏng màn hình điện thoại dọc.
4. Muốn chạy trên Android: *Project → Export → Android* (cần cài Android export template theo hướng dẫn của Godot).

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

## Thay hình bằng asset miễn phí

Hiện tại mọi hình được vẽ tạm bằng code. Game **tự dùng ảnh** nếu bạn đặt file PNG đúng tên vào:

```
assets/tiles/village.png   assets/tiles/forest.png   assets/tiles/rock.png
assets/tiles/field.png     assets/tiles/grass.png    assets/tiles/water.png
assets/tiles/camp.png
```

Kích thước gợi ý 84×84 px, vẽ ở góc nhìn 3/4, nền trong suốt. Nguồn asset miễn phí (kiểm tra giấy phép từng gói trước khi dùng):

- **Kenney.nl** – các gói 2D giấy phép CC0 (ví dụ Hexagon Pack, Medieval RTS, Tiny Town).
- **itch.io** – lọc *Free* + *2D* + từ khóa "hex tiles", "isometric", "painterly".
- **OpenGameArt.org** – lọc giấy phép CC0 / CC-BY.

## Cấu trúc code

| File | Vai trò |
|---|---|
| `scripts/data.gd` | Toàn bộ số liệu cân bằng (autoload `Data`) |
| `scripts/game.gd` | Trạng thái, mô phỏng, lưu/tải, offline (autoload `Game`) |
| `scripts/hex.gd` | Toán lưới lục giác |
| `scripts/map_view.gd` | Vẽ bản đồ, chạm/kéo/thu phóng |
| `scripts/ui.gd` | Thanh tài nguyên, bảng thông tin, 4 tab |
| `scripts/battle_view.gd` | Trận đánh tự động |
| `scripts/main.gd` | Ghép các phần lại |

Save nằm ở `user://save.json` (trên Windows: `%APPDATA%/Godot/app_userdata/Frontier Idle/`).
