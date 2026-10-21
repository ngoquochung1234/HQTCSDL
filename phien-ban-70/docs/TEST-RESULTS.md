# Kết quả kiểm thử nguồn dùng chung

Tài liệu này ghi lại lần kiểm thử của nguồn dự án đầy đủ trước khi giới hạn đăng nhập cho mốc 70%. Các kết quả bên dưới không xác nhận bản 70% đã được kiểm thử sau khi đổi database và khóa các vai trò FINANCE, OPERATIONS, ADMIN.

Kiểm tra ngày 12/10/2026 trên SQL Server tại máy người dùng, với database CruiseCourseworkV2, backend Node.js và frontend React responsive.

| Nhóm | Số ca | Kết quả |
|---|---:|---|
| T-SQL, khóa ngoại/CHECK, đăng ký/chờ/hủy, check-in, giá theo gói, POS, đối soát/hóa đơn, lịch trình, audit | 28 | Đạt |
| Hai SQL connection cùng tranh chỗ cuối | 1 | Một CONFIRMED, một WAITLIST |
| API: login/logout, dữ liệu chủ sở hữu, QR, quyền bộ phận, tạo danh mục, tiếng Việt | 19 | Đạt |
| Build React và kiểm tra cú pháp backend/frontend/service worker | — | Đạt |

Script có thể chạy lại: tests/database.mjs và tests/api.mjs. Ca SQL dùng rollback để không thay đổi mẫu; ca race/API có cleanup dữ liệu do ca đó tạo. Test dùng những ID seed được ghi trong script, nên cần bộ dữ liệu mẫu chưa bị thay đổi nghiệp vụ trước khi chạy lại.

Giao diện đã được kiểm tra bằng trình duyệt: đăng nhập hành khách, dữ liệu SQL thật, màn hình desktop và viewport 390×844. Đã kiểm tra thêm thẻ QR, đổi đặt chỗ/chuyến, gửi phản hồi và xác nhận lưu SQL, dashboard theo chuyến/cabin. POS đã lưu một giao dịch mẫu vào hàng đợi, đồng bộ thành công sang SQL Server và hàng đợi về 0. Đã ngắt server preview thật, reload trang POS từ cache thành công, ghi thêm giao dịch khi ngoại tuyến, khởi động lại server, đăng nhập lại và đồng bộ thành công; hàng đợi về 0. Script cài đặt cũng đã chạy trên database mới hoàn toàn và toàn bộ 29 ca SQL đạt tại database đó; database kiểm tra tạm đã được dọn.
