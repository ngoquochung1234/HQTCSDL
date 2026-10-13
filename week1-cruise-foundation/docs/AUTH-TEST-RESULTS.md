# Kết quả kiểm thử

Kiểm tra ngày 12/10/2026 trên SQL Server tại máy người dùng, với database CruiseCoursework, backend Node.js và frontend React responsive.

| Nhóm | Số ca | Kết quả |
|---|---:|---|
| T-SQL, khóa ngoại/CHECK, đăng ký/chờ/hủy, check-in, giá theo gói, POS, đối soát/hóa đơn, lịch trình, audit | 24 | Đạt |
| Hai SQL connection cùng tranh chỗ cuối | 1 | Một CONFIRMED, một WAITLIST |
| API: login/logout, dữ liệu chủ sở hữu, QR, quyền bộ phận, tạo danh mục, tiếng Việt | 19 | Đạt |
| Build React và kiểm tra cú pháp backend/frontend/service worker | — | Đạt |

Script có thể chạy lại: tests/database.mjs và tests/api.mjs. Ca SQL dùng rollback để không thay đổi mẫu; ca race/API có cleanup dữ liệu do ca đó tạo. Test dùng những ID seed được ghi trong script, nên cần bộ dữ liệu mẫu chưa bị thay đổi nghiệp vụ trước khi chạy lại.

Giao diện đã được kiểm tra bằng trình duyệt: đăng nhập hành khách, dữ liệu SQL thật, màn hình desktop và viewport 390×844. Các bước trình diễn còn lại được ghi trong README; kết quả UI bổ sung sẽ cập nhật sau lần kiểm tra cuối.
