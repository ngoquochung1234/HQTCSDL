# Aurora Cruise · Phiên bản 70%

Bản này kế thừa nền tảng đăng nhập, phân quyền và quản lý chuyến/lịch trình của mốc 50%; bổ sung quản lý hoạt động, đăng ký hoạt động, sức chứa/danh sách chờ, check-in, điều phối tour bờ và POS có lưu tạm/đồng bộ giao dịch.

## Chạy

Yêu cầu Node.js 18+, SQL Server và `sqlcmd` trong PATH. Mở PowerShell ở thư mục này:

```powershell
npm ci
npm run setup
npm start
```

Mở http://localhost:3000. Có thể nhấp đúp `CHAY-WEB.cmd`. Database riêng là `CruiseCourseworkV2`; setup không xóa dữ liệu. Nếu dùng SQL Server Express, đặt `$env:SQL_SERVER = '.\SQLEXPRESS'` trước khi chạy setup và start. Có thể đặt `$env:PORT` để đổi cổng web.

## Tài khoản mẫu

Mật khẩu các tài khoản là `Aurora123!`.

| Vai trò | Email |
|---|---|
| Hành khách | `guest1@demo.local` đến `guest20@demo.local` |
| Điều phối lịch trình | `itinerary@demo.local` |
| Quản lý hoạt động/check-in | `checkin@demo.local` |
| Điều phối tour bờ | `shore@demo.local` |
| POS | `pos@demo.local` |

## Phạm vi mốc 70%

Đã mở các chức năng của mốc 50% cùng với quản lý hoạt động trên tàu/tour bờ, đăng ký và hủy hoạt động, sức chứa và danh sách chờ, check-in, nhóm tour/xác nhận khách về tàu, POS, lưu giao dịch khi ngoại tuyến và đồng bộ an toàn theo mã giao dịch.

Các không gian tài chính/đối soát, báo cáo vận hành và quản trị đầy đủ chưa được mở trong bản này. API chỉ cấp các vai trò PASSENGER, ITINERARY, ACTIVITY, SHORE và POS; vai trò khác bị loại khỏi phiên đăng nhập. Cơ sở dữ liệu có thể còn các bảng/procedure dùng chung với bản đầy đủ để hỗ trợ phí phát sinh và lịch sử giao dịch.

## Cấu trúc và tài liệu

- `database/`: schema và nghiệp vụ SQL Server.
- `server.mjs`, `src/`: API, phiên đăng nhập và kết nối SQL Server.
- `public/`: giao diện responsive.
- `docs/PHIEN-BAN-70.md`: danh sách chức năng và phần chưa mở.
- `docs/ERD.md`, `docs/DICTIONARY.md`, `docs/DESIGN.md`: mô hình dữ liệu tổng thể của dự án; một số bảng thuộc các mốc sau.
