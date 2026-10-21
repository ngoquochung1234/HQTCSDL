:ON ERROR EXIT
USE CruiseCourseworkV3;
GO
SET XACT_ABORT ON;
BEGIN TRAN;
INSERT Ships(Name,Capacity) VALUES(N'Aurora',300);
INSERT Zones(ShipId,Name) VALUES(1,N'Sân thượng'),(1,N'Nhà hát'),(1,N'Nhà hàng');
INSERT Cabins(ShipId,Number) VALUES(1,'A101'),(1,'A102'),(1,'A103'),(1,'A104'),(1,'A105'),(1,'A106'),(1,'A107'),(1,'A108'),(1,'A109'),(1,'A110');
INSERT Cruises(ShipId,Name,StartDate,EndDate) VALUES(1,N'Hành trình Di sản',DATEADD(day,7,CAST(GETDATE() AS date)),DATEADD(day,11,CAST(GETDATE() AS date)));
INSERT Ports(Name) VALUES(N'Hạ Long'),(N'Cát Bà');
INSERT Stops(CruiseId,PortId,Arrival,Departure) VALUES(1,1,DATEADD(hour,8,CAST(DATEADD(day,8,CAST(GETDATE() AS date)) AS datetime2)),DATEADD(hour,18,CAST(DATEADD(day,8,CAST(GETDATE() AS date)) AS datetime2))),(1,2,DATEADD(hour,8,CAST(DATEADD(day,9,CAST(GETDATE() AS date)) AS datetime2)),DATEADD(hour,18,CAST(DATEADD(day,9,CAST(GETDATE() AS date)) AS datetime2)));
INSERT Roles(Code,Name) VALUES('PASSENGER',N'Hành khách'),('ITINERARY',N'Điều phối hành trình'),('ACTIVITY',N'Quản lý hoạt động'),('SHORE',N'Quản lý tour bờ'),('POS',N'Nhân viên POS'),('FINANCE',N'Tài chính – Lễ tân'),('OPERATIONS',N'Quản lý vận hành'),('ADMIN',N'Quản trị hệ thống');
INSERT Users(Name,Email) VALUES(N'Quản trị demo','admin@demo.local'),(N'Nhân viên POS','pos@demo.local'),(N'Nhân viên check-in','checkin@demo.local'),(N'Tài chính','finance@demo.local'),(N'Điều phối','itinerary@demo.local');
INSERT UserRoles VALUES(1,8),(2,5),(3,3),(4,6),(5,2);
INSERT Packages(Name) VALUES(N'Tiêu chuẩn'),(N'Premium');
DECLARE @i int=1;
WHILE @i<=20
BEGIN
 INSERT Users(Name,Email) VALUES(CASE WHEN @i=1 THEN N'Nguyễn Minh Anh' ELSE N'Hành khách '+CAST(@i AS nvarchar(10)) END,'guest'+CAST(@i AS varchar(10))+'@demo.local');
 DECLARE @u int=SCOPE_IDENTITY();
 INSERT UserRoles VALUES(@u,1);
 INSERT Passengers(UserId) VALUES(@u);
 DECLARE @p int=SCOPE_IDENTITY();
 INSERT Bookings(CruiseId,PassengerId,CabinId,PackageId) VALUES(1,@p,((@i-1)/2)+1,CASE WHEN @i<=5 THEN 2 ELSE 1 END);
 DECLARE @b int=SCOPE_IDENTITY();
 INSERT Accounts(BookingId) VALUES(@b);
 INSERT Identifiers(BookingId,Code,Kind) VALUES(@b,'AURORA-'+RIGHT('000'+CAST(@i AS varchar(10)),3),'QR');
 SET @i+=1;
END;
INSERT Providers(Name) VALUES(N'Di sản Travel');
DECLARE @d datetime2=CAST(DATEADD(day,7,CAST(GETDATE() AS date)) AS datetime2);
INSERT Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee) VALUES
(1,1,N'Yoga đón bình minh','ONBOARD',DATEADD(hour,6,DATEADD(day,1,@d)),DATEADD(hour,7,DATEADD(day,1,@d)),12,0),
(1,2,N'Đêm nhạc trên biển','ONBOARD',DATEADD(hour,20,@d),DATEADD(hour,22,@d),40,150000),
(1,3,N'Lớp nấu ăn cùng bếp trưởng','ONBOARD',DATEADD(hour,15,DATEADD(day,2,@d)),DATEADD(hour,16,DATEADD(day,2,@d)),8,250000);
INSERT Activities(CruiseId,StopId,ProviderId,Name,Kind,StartsAt,EndsAt,ReturnAt,Capacity,Fee) VALUES
(1,1,1,N'Khám phá vịnh Hạ Long','SHORE',DATEADD(hour,9,DATEADD(day,1,@d)),DATEADD(hour,15,DATEADD(day,1,@d)),DATEADD(hour,16,DATEADD(day,1,@d)),20,650000),
(1,2,1,N'Trekking Cát Bà','SHORE',DATEADD(hour,9,DATEADD(day,2,@d)),DATEADD(hour,14,DATEADD(day,2,@d)),DATEADD(hour,15,DATEADD(day,2,@d)),10,450000);
INSERT Services(Name,Price) VALUES(N'Nước uống',35000),(N'Massage thư giãn',350000),(N'Bữa tối đặc biệt',500000);
INSERT PackageServices VALUES(2,1);
INSERT Devices(Name,Kind) VALUES(N'POS nhà hàng','POS'),(N'Check-in sảnh','CHECKIN');
INSERT Policy VALUES(1,2);
INSERT Notifications(CruiseId,Message) VALUES(1,N'Chào mừng bạn đến với Aurora. Hãy đăng ký hoạt động trước khi khởi hành.');
COMMIT;
GO
EXEC usp_Register 1,2;
EXEC usp_Register 2,4;
EXEC usp_Register 3,1;
GO
