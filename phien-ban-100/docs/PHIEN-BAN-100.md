# Phiên bản 100%

Bản hoàn thiện theo nguồn dự án gốc, gồm toàn bộ chức năng hành khách, điều phối chuyến/lịch trình, hoạt động và đăng ký, check-in, tour bờ, POS ngoại tuyến/đồng bộ, tranh chấp và đối soát tài chính, hóa đơn, báo cáo vận hành và quản trị.

Tám vai trò mẫu được mở: PASSENGER, ITINERARY, ACTIVITY, SHORE, POS, FINANCE, OPERATIONS và ADMIN. Mật khẩu demo: `Aurora123!`.

## Chạy

Yêu cầu Node.js 18+, SQL Server và `sqlcmd` trong PATH. Ở thư mục này:

```powershell
npm ci
npm run setup
npm start
```

Mở http://localhost:3000. Database riêng là `CruiseCourseworkV3`; setup không xóa dữ liệu. Có thể nhấp đúp `CHAY-WEB.cmd`. Xem [README.md](../README.md) để biết chi tiết nghiệp vụ, tài khoản demo, API và kiểm tra.

## Phạm vi hoàn thành

- Đăng nhập, phiên an toàn và phân quyền cho hành khách cùng bảy bộ phận.
- Quản lý chuyến, lịch trình và lịch sử thay đổi.
- Hoạt động trên tàu, tour bờ, đăng ký/hủy, sức chứa và danh sách chờ.
- Check-in, quản lý nhóm tour, xác nhận khách về tàu và cảnh báo khách trễ.
- POS có chế độ lưu offline và đồng bộ idempotent.
- Tranh chấp, hoàn/void, đối soát, chốt tài khoản và hóa đơn.
- Dashboard vận hành, báo cáo và quản trị người dùng/danh mục.
