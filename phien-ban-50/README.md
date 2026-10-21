# Aurora Cruise tuần 1 · Phiên bản 50%

Mốc tiến độ 50%: hoàn tất nền tảng đăng nhập/phân quyền và nghiệp vụ chuyến/lịch trình. Điều phối viên có thể tạo/sửa chuyến, thêm/sửa điểm dừng, cập nhật giờ đến/rời cảng kèm lý do; hệ thống lưu lịch sử và tạo thông báo. Phạm vi bản này giữ các chức năng đã hoàn thành ổn định, không giả lập các nghiệp vụ chưa làm.

Các phần tiếp theo của dự án gồm quản lý hoạt động và đăng ký, check-in, POS/đồng bộ, tài chính/hóa đơn, dashboard và quản trị dữ liệu đầy đủ. Chi tiết phạm vi: [docs/PHIEN-BAN-50.md](docs/PHIEN-BAN-50.md).

## Chạy

Cần Node.js từ 18, SQL Server và sqlcmd trong PATH. Mở terminal ở thư mục này:

```powershell
npm run setup
npm start
```

Mở http://localhost:3001 hoặc nhấp đúp CHAY-WEB.cmd. Database riêng CruiseWeek1; không dùng CruiseCoursework của bản đầy đủ. Nếu dùng SQLEXPRESS, đặt $env:SQL_SERVER = '.\SQLEXPRESS' trước setup/start. Có thể đổi SQL_DATABASE và PORT; giữ cùng cấu hình khi setup/server/test. Không có dependency bên ngoài hoặc bước build.

## Tài khoản

Mật khẩu demo: Aurora123! Mỗi tài khoản được lưu hash với salt riêng.

| Vai trò | Email |
|---|---|
| Hành khách | guest1@demo.local đến guest20@demo.local |
| Điều phối | itinerary@demo.local |
| Hoạt động | checkin@demo.local |
| Tour bờ | shore@demo.local |
| POS | pos@demo.local |
| Tài chính | finance@demo.local |
| Vận hành | operations@demo.local |
| Quản trị | admin@demo.local |

## SQL và kiểm tra

Setup chạy 01-schema → 03-seed → 04-auth → 08-itinerary trên DB mới; lần sau giữ dữ liệu/mật khẩu hiện có và cập nhật các procedure lịch trình. Seed không gọi usp_Register. Nếu dùng SSMS bật SQLCMD Mode. Sau khi chạy SQL bằng tay, chạy setup để cấp hash demo.

Chạy npm run check và npm run test:auth. Test dùng SQL Server thật, cổng tạm và một fixture tài khoản được dọn sau kiểm tra. Chi tiết API/quyền: docs/AUTH.md. Kết quả: docs/AUTH-TEST-RESULTS.md. ERD/DICTIONARY/DESIGN/REQUIREMENTS cũ mô tả thiết kế đích, chưa phải toàn bộ chức năng đã triển khai.

## Code cần push

Push server.mjs, src, public, scripts, tests, database, docs, README.md, CHAY-WEB.cmd, package.json, package-lock.json và .gitignore. Không push .tmp, node_modules, .env hoặc log.

Các API hiện có: POST /api/login, POST /api/logout, GET /api/me, GET /api/state, GET /api/bookings/:id, GET /api/departments/:role, GET /api/admin/users và các API POST /api/itinerary/cruise, /api/itinerary/stop dành cho ITINERARY/ADMIN. Backend kiểm tra quyền; SQL Server kiểm tra ngày chuyến, trùng lịch cảng và xung đột với hoạt động tour bờ. Cookie HttpOnly và SameSite=Strict; restart server cần đăng nhập lại. Bản học phần chạy localhost.
