# Aurora Cruise · Phiên bản 100%

Web responsive quản lý hoạt động và dịch vụ du thuyền cho môn Hệ quản trị cơ sở dữ liệu. Dự án độc lập, không cần Java/Tomcat/MySQL hay code GitHub cũ.

Frontend dùng React để quản lý màn hình, giữ các template giao diện và CSS hiện có. Backend Node.js xác thực phiên đăng nhập, kiểm tra quyền và gọi stored procedure SQL Server thông qua `sqlcmd` với Windows Authentication. Nghiệp vụ cập nhật nhiều bảng nằm trong T-SQL, không tính giá hoặc quyết định sức chứa tại trình duyệt.

## Chạy trên máy hiện tại

Cách nhanh: nhấp đúp **CHAY-WEB.cmd**. Script kiểm tra công cụ, cài dependency nếu chưa có, chạy setup không xóa dữ liệu rồi khởi động web. Giữ cửa sổ terminal mở khi dùng hệ thống. Để dừng, nhấn Ctrl+C. Nếu cổng 3000 đã được dùng, dừng phiên cũ hoặc đặt biến PORT trước khi chạy.

Mở PowerShell trong thư mục `phien-ban-100`:

```powershell
npm ci
npm run setup
npm start
```

Mở http://localhost:3000. `npm start` tự build frontend trước khi chạy server. Yêu cầu Node.js 18 trở lên, SQL Server 2019 trở lên và `sqlcmd` ODBC trong PATH. Máy hiện tại đã có Node.js, SQL Server và sqlcmd. Không cần cài Java.

Database riêng của phiên bản này được tạo tên `CruiseCourseworkV3`. Setup không xóa database hoặc dữ liệu hiện có; lần sau chỉ cập nhật procedure/view/trigger và bổ sung dữ liệu mẫu chưa có. Nếu một bước setup lỗi, sửa lỗi rồi chạy lại. Script schema không được chạy lại trên database đã có bảng. Scripts SQL chạy ở chế độ SQLCMD vì có `GO` và `:ON ERROR EXIT`; bật SQLCMD Mode khi dùng SSMS.

Nếu SQL Server dùng instance khác, đặt biến trước khi setup và start:

```powershell
$env:SQL_SERVER = '.\SQLEXPRESS'
npm run setup
npm start
```

User Windows chạy backend cần quyền tạo database cho setup, và quyền truy cập database khi chạy. Backend không lưu mật khẩu SQL Server. Biến `PORT` đổi cổng web, `SQLCMD_PATH` đổi đường dẫn sqlcmd. Database ứng dụng dùng tên cố định trong các script. Server mặc định chỉ nghe trên máy này; dùng F12 → Ctrl+Shift+M để trình diễn giao diện điện thoại.

## Đăng nhập

Mật khẩu của tất cả tài khoản mẫu: **Aurora123!**. Password được lưu bằng scrypt có salt; đây là mật khẩu trình diễn. Tài khoản mới nhập qua trang quản trị được băm riêng.

| Vai trò | Email |
|---|---|
| Hành khách | guest1@demo.local đến guest20@demo.local |
| Điều phối hành trình | itinerary@demo.local |
| Quản lý hoạt động | checkin@demo.local |
| Quản lý tour bờ | shore@demo.local |
| Nhân viên POS | pos@demo.local |
| Tài chính – Lễ tân | finance@demo.local |
| Quản lý vận hành | operations@demo.local |
| Quản trị | admin@demo.local |

Hành khách chỉ thấy đặt chỗ, chi phí, QR và hóa đơn của mình. API kiểm tra chủ sở hữu đặt chỗ, không tin BookingId từ frontend. Quản trị có thể đổi không gian làm việc để xem các màn hình vận hành; các tài khoản bộ phận chỉ có quyền được gán. Phiên đăng nhập dùng cookie HttpOnly/SameSite, hết hạn sau 8 giờ và mất khi restart server. Người dùng bị khóa sẽ không truy cập API tiếp được.

## Dữ liệu mẫu và cách trình diễn

Có 20 hành khách, 2 chuyến nhiều ngày, các cảng, cabin, gói, hoạt động trên tàu và tour bờ. Ngày chuyến được tính theo ngày chạy setup lần đầu. Chuyến `Hành trình Di sản` bắt đầu sau 7 ngày; chuyến `Vịnh xanh · Đang khởi hành` diễn ra quanh ngày setup. Seed không tự dời ngày khi chạy lại, để giữ lịch sử.

1. Đăng nhập `guest1`: xem lịch trình, hoạt động, dịch vụ đã gồm trong gói và chi phí. Đăng ký hoạt động chưa bắt đầu. Chỗ hết sẽ đưa vào WAITLIST; hủy đúng hạn hoàn phí và tự chuyển khách chờ đầu tiên vào chỗ trống. Đặt chỗ đã chốt không được đăng ký/ghi thêm phí.
2. Mở Thẻ hành khách. Mã chuyến tương lai của guest1 là `AURORA-001`; chuyến đang đi là `SAIL-001`. Có ảnh QR thật được tạo từ cùng mã. Đầu đọc thẻ/RFID/NFC được mô phỏng bằng nhập mã hoặc máy quét QR hoạt động như bàn phím.
3. Đăng nhập `checkin` hoặc `shore`: chọn hoạt động, nhập mã khách đã đăng ký và check-in. Thử lại để thấy chặn trùng. Tour bờ hỗ trợ nhóm/xe/hướng dẫn viên và xác nhận khách về tàu. Dashboard liệt kê khách chưa về trong vòng 30 phút trước giờ rời cảng (và sau giờ đó nếu vẫn chưa về).
4. Đăng nhập `pos`: ghi Nước uống cho `AURORA-001` (Premium, 0 đồng), hoặc `AURORA-010` (Tiêu chuẩn, tính phí). Giá được tra tại SQL Server. Chọn Lưu tạm để mô phỏng mất mạng, sau đó Đồng bộ ngay. Nếu mất kết nối thật trong lúc gửi, giao dịch được lưu lại với UUID cố định để gửi lại an toàn.
5. Đăng nhập hành khách: gửi tranh chấp một chi phí. Đăng nhập `finance`: thử chốt sẽ bị chặn nếu còn tranh chấp; xử lý tranh chấp, void/hoàn giao dịch POS nếu cần, bấm Đối soát cho giao dịch POS còn hiệu lực, sau đó chốt hóa đơn. Khi bấm chốt, hệ thống ghi nhận thanh toán **mô phỏng**, không kết nối cổng thanh toán thật. Hóa đơn có trang in, có thể Save as PDF từ trình duyệt.
6. Đăng nhập `itinerary`: sửa lịch cảng với lý do, xem lịch sử và thông báo tự tạo. Lịch mới không được xung đột tour bờ; điều chỉnh tour trước nếu cần. Có chức năng tạo chuyến và điểm dừng mới.
7. Chọn chuyến đang đi, mở Đăng ký của tôi của `guest1`: đánh giá Workshop ẩm thực biển đã hoàn thành. Phản hồi chuyến chỉ được gửi khi chuyến kết thúc hoặc được đánh dấu CLOSED.
8. Đăng nhập `operations`: xem doanh thu ròng, lấp đầy, check-in, phản hồi, cảnh báo tour bờ, xuất CSV. BLE là vùng mẫu và thời điểm quan sát, không phải định vị thật.
9. Đăng nhập `admin`: quản lý người dùng, tàu/khu vực/cabin/cảng/dịch vụ/thiết bị/gói, gán hành khách vào chuyến, định danh, chính sách hủy/hoàn và audit log. Các quan hệ sai tàu/chuyến, dữ liệu trùng hoặc không hợp lệ bị SQL Server từ chối.

## POS ngoại tuyến

Hàng đợi lưu tại localStorage theo UserId; item có `sync_status=PENDING` và UUID. Khi đồng bộ, `usp_SyncPOS` gọi nghiệp vụ POS và ghi `SyncReceipts` trong transaction. `Transactions.SyncStatus=SYNCED` chỉ xuất hiện khi đã ghi thành công vào server. Cùng UUID/cùng nội dung trả `ALREADY_SYNCED`; cùng UUID/nội dung khác bị từ chối. Hàng đợi chỉ bỏ item sau phản hồi thành công. Không xóa dữ liệu trình duyệt khi còn giao dịch chưa đồng bộ.

Service worker giữ bộ giao diện. Sau khi tài khoản POS đã đăng nhập online một lần, reload cùng tab khi mất kết nối vẫn vào được màn hình POS từ cache phiên (chỉ danh mục dịch vụ/thiết bị, không cache bảng chi phí của khách). Đồng bộ yêu cầu phiên đăng nhập hợp lệ; nếu phiên hết hạn, đăng nhập lại bằng cùng tài khoản. Hàng đợi không chuyển sang tài khoản khác. Đồng bộ ở mức đơn giản, không xử lý xung đột nghiệp vụ giữa nhiều thiết bị như một hệ thống POS thương mại.

## Kiểm thử

```powershell
npm run check
npm run test:db
# Giữ npm start ở terminal khác:
npm run test:api
npm run docs
```

`node scripts/verify-install.mjs` kiểm tra đủ 7 script trên database tạm mới hoàn toàn, chạy 29 ca SQL rồi chỉ dọn database tạm do nó tạo. Không reset database đồ án.

29 ca SQL (bao gồm tranh suất cuối bằng 2 kết nối đồng thời) và 19 ca API. Các ca SQL dùng transaction rollback; ca đồng thời và ca API tạo danh mục có tên test rồi dọn đúng dữ liệu do ca đó tạo. Test giả định bộ seed ban đầu chưa bị đổi để các trường hợp đã biết còn đúng. Xem `docs/TEST-RESULTS.md`.

## Cấu trúc

```text
database/01-schema.sql       30 bảng nền, khóa ngoại, index, trigger audit
database/02-business.sql     procedure và view nền
database/03-seed.sql         chuyến tương lai và 20 hành khách
database/04-complete.sql     mở rộng thành 38 bảng, tài chính/tour/quản trị
database/05-api.sql          nghiệp vụ đồng bộ, người dùng, thông báo
database/06-integrity.sql    ràng buộc chéo, index, audit, điều kiện đánh giá
database/07-demo.sql         chuyến đang đi và kịch bản demo bổ sung
src/db.mjs                  adapter SQL Server, encoding, thông báo lỗi
server.mjs                  phiên đăng nhập, phân quyền, API, QR
public/app.js + ui.jsx      giao diện, React mount, form và luồng sử dụng
public/style.css            giao diện desktop/mobile
public/sw.js                cache giao diện POS ngoại tuyến
scripts/                   setup, build, xuất metadata tài liệu
tests/                     kiểm thử SQL Server và API thật
docs/                      ERD, từ điển, đối chiếu yêu cầu, hướng dẫn
```

Nghiệp vụ và bảng có thể giải thích độc lập với frontend. Backend gọn dùng process sqlcmd phù hợp bản trình diễn cục bộ; không có connection pool và không được thiết kế cho lượng truy cập lớn. Web/POS responsive thay app native theo phạm vi kế hoạch. QR/RFID/NFC/BLE và thanh toán có giới hạn mô phỏng đã ghi ở trên; không gọi các tích hợp thiết bị hoặc thanh toán thật là đã hoàn thành.
