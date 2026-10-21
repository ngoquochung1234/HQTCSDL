# Phạm vi phiên bản 70%

## Đã hoàn thành

- Toàn bộ nền tảng mốc 50%: đăng nhập/đăng xuất, phân quyền theo vai trò, chuyến và lịch trình có lưu lịch sử thay đổi.
- Tạo/sửa hoạt động trên tàu và tour bờ theo quyền bộ phận.
- Đăng ký hoạt động, giới hạn sức chứa, danh sách chờ theo thứ tự và tự chuyển khách khi có chỗ.
- Hủy đăng ký theo chính sách; phí và lịch sử giao dịch được xử lý ở nghiệp vụ SQL.
- Check-in theo mã hành khách, chống check-in trùng; nhóm tour bờ và xác nhận khách về tàu.
- POS tra giá từ SQL Server, lưu giao dịch ngoại tuyến và đồng bộ có mã chống ghi trùng.
- Vai trò có thể đăng nhập trong bản này: PASSENGER, ITINERARY, ACTIVITY, SHORE, POS.

## Chưa mở trong mốc này

- Quy trình nhân viên tài chính: xử lý tranh chấp, void/hoàn giao dịch, đối soát và chốt hóa đơn.
- Dashboard/báo cáo vận hành đầy đủ.
- Quản trị người dùng, quyền, danh mục và chính sách.

Các vai trò FINANCE, OPERATIONS và ADMIN không được cấp phiên đăng nhập trong bản này. Các bảng và procedure liên quan vẫn có thể tồn tại trong schema dùng chung, nhưng giao diện và API giới hạn nghiệp vụ theo vai trò 70%.
