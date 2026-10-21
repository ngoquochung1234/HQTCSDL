:ON ERROR EXIT
USE CruiseCourseworkV2;
GO
SET NOCOUNT ON; SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM Cruises WHERE Name=N'Vịnh xanh · Đang khởi hành')
BEGIN
 BEGIN TRAN;
 INSERT Cruises(ShipId,Name,StartDate,EndDate,Status) VALUES(1,N'Vịnh xanh · Đang khởi hành',DATEADD(day,-1,CAST(GETDATE() AS date)),DATEADD(day,2,CAST(GETDATE() AS date)),'OPEN');
 DECLARE @cruise int=SCOPE_IDENTITY(),@i int=1;
 WHILE @i<=20
 BEGIN
  INSERT Bookings(CruiseId,PassengerId,CabinId,PackageId) VALUES(@cruise,@i,((@i-1)/2)+1,CASE WHEN @i<=5 THEN 2 ELSE 1 END);
  DECLARE @b int=SCOPE_IDENTITY(); INSERT Accounts(BookingId) VALUES(@b);
  INSERT Identifiers(BookingId,Code,Kind) VALUES(@b,'SAIL-'+RIGHT('000'+CAST(@i AS varchar(10)),3),'QR');
  SET @i+=1;
 END;
 UPDATE Cruises SET Status='SAILING' WHERE CruiseId=@cruise;
 INSERT Stops(CruiseId,PortId,Arrival,Departure) VALUES(@cruise,1,DATEADD(minute,-40,SYSDATETIME()),DATEADD(minute,25,SYSDATETIME()));
 DECLARE @s int=SCOPE_IDENTITY();
 INSERT Activities(CruiseId,StopId,ProviderId,Name,Kind,StartsAt,EndsAt,ReturnAt,Capacity,Fee,Status) VALUES(@cruise,@s,1,N'Tham quan làng chài','SHORE',DATEADD(minute,-35,SYSDATETIME()),DATEADD(minute,-10,SYSDATETIME()),DATEADD(minute,-5,SYSDATETIME()),20,250000,'DELAYED');
 DECLARE @a int=SCOPE_IDENTITY(),@booking int=(SELECT BookingId FROM Bookings WHERE CruiseId=@cruise AND PassengerId=2);
 INSERT Registrations(ActivityId,BookingId,Status,CreatedAt) VALUES(@a,@booking,'CONFIRMED',DATEADD(hour,-2,SYSUTCDATETIME()));
 DECLARE @r int=SCOPE_IDENTITY();
 INSERT Transactions(AccountId,RegistrationId,Amount) SELECT AccountId,@r,250000 FROM Accounts WHERE BookingId=@booking;
 INSERT CheckIns(RegistrationId,DeviceId,StaffId,CreatedAt) VALUES(@r,2,3,DATEADD(minute,-35,SYSUTCDATETIME()));
 INSERT Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee,Status) VALUES(@cruise,3,N'Workshop ẩm thực biển','ONBOARD',DATEADD(hour,-2,SYSDATETIME()),DATEADD(hour,-1,SYSDATETIME()),15,200000,'COMPLETED');
 SET @a=SCOPE_IDENTITY(); SET @booking=(SELECT BookingId FROM Bookings WHERE CruiseId=@cruise AND PassengerId=1);
 INSERT Registrations(ActivityId,BookingId,Status,CreatedAt) VALUES(@a,@booking,'CONFIRMED',DATEADD(hour,-3,SYSUTCDATETIME())); SET @r=SCOPE_IDENTITY();
 INSERT Transactions(AccountId,RegistrationId,Amount) SELECT AccountId,@r,200000 FROM Accounts WHERE BookingId=@booking;
 INSERT CheckIns(RegistrationId,DeviceId,StaffId,CreatedAt) VALUES(@r,2,3,DATEADD(hour,-2,SYSUTCDATETIME()));
 INSERT Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee,Status,IncludedServiceId) VALUES(@cruise,2,N'Đêm nhạc Acoustic','ONBOARD',DATEADD(hour,2,SYSDATETIME()),DATEADD(hour,3,SYSDATETIME()),30,150000,'OPEN',3);
 INSERT Stops(CruiseId,PortId,Arrival,Departure) VALUES(@cruise,2,DATEADD(hour,8,CAST(DATEADD(day,1,CAST(GETDATE() AS date)) AS datetime2)),DATEADD(hour,17,CAST(DATEADD(day,1,CAST(GETDATE() AS date)) AS datetime2))); SET @s=SCOPE_IDENTITY();
 INSERT Activities(CruiseId,StopId,ProviderId,Name,Kind,StartsAt,EndsAt,ReturnAt,Capacity,Fee,Status) SELECT @cruise,@s,1,N'Khám phá rừng Cát Bà','SHORE',DATEADD(hour,1,Arrival),DATEADD(hour,5,Arrival),DATEADD(hour,6,Arrival),12,450000,'OPEN' FROM Stops WHERE StopId=@s;
 INSERT TourGroups(ActivityId,Name,Vehicle,Guide) VALUES(SCOPE_IDENTITY(),N'Nhóm khám phá',N'Xe 03',N'Phạm An');
 IF NOT EXISTS(SELECT 1 FROM PackageServices WHERE PackageId=2 AND ServiceId=3) INSERT PackageServices VALUES(2,3);
 INSERT Notifications(CruiseId,Message) VALUES(@cruise,N'Đừng quên giờ tập trung và giờ về tàu của tour bờ. Các dịch vụ đã gồm trong gói sẽ được ghi nhận với phí 0 đồng.');
 COMMIT;
END;
GO
