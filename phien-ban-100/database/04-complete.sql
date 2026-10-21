:ON ERROR EXIT
USE CruiseCourseworkV3;
GO
SET NOCOUNT ON;
IF COL_LENGTH('Users','PasswordHash') IS NULL ALTER TABLE Users ADD PasswordHash varchar(200) NULL, Active bit NOT NULL DEFAULT 1;
IF COL_LENGTH('Activities','IncludedServiceId') IS NULL ALTER TABLE Activities ADD IncludedServiceId int NULL REFERENCES Services;
IF COL_LENGTH('Policy','RefundPercent') IS NULL ALTER TABLE Policy ADD RefundPercent int NOT NULL DEFAULT 100 CHECK(RefundPercent BETWEEN 0 AND 100);
IF COL_LENGTH('Transactions','RefundAmount') IS NULL ALTER TABLE Transactions ADD RefundAmount decimal(18,2) NOT NULL DEFAULT 0 CHECK(RefundAmount>=0);
IF COL_LENGTH('Transactions','ReconciledAt') IS NULL ALTER TABLE Transactions ADD ReconciledAt datetime2 NULL, ReconciledBy int NULL REFERENCES Users;
IF OBJECT_ID('TourGroups') IS NULL CREATE TABLE TourGroups(GroupId int IDENTITY PRIMARY KEY, ActivityId int NOT NULL REFERENCES Activities, Name nvarchar(100) NOT NULL, Vehicle nvarchar(100) NOT NULL, Guide nvarchar(100) NOT NULL, UNIQUE(ActivityId,Name));
IF OBJECT_ID('GroupMembers') IS NULL CREATE TABLE GroupMembers(RegistrationId int PRIMARY KEY REFERENCES Registrations, GroupId int NOT NULL REFERENCES TourGroups);
IF OBJECT_ID('CruiseFeedback') IS NULL CREATE TABLE CruiseFeedback(BookingId int PRIMARY KEY REFERENCES Bookings, Rating int NOT NULL CHECK(Rating BETWEEN 1 AND 5), Comment nvarchar(500) NOT NULL, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('SyncReceipts') IS NULL CREATE TABLE SyncReceipts(ClientId uniqueidentifier PRIMARY KEY REFERENCES Transactions(ClientId), DeviceId int NOT NULL REFERENCES Devices, SyncedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('Wearables') IS NULL CREATE TABLE Wearables(WearableId int IDENTITY PRIMARY KEY, BookingId int NOT NULL REFERENCES Bookings, Code varchar(100) NOT NULL UNIQUE);
IF OBJECT_ID('BLEReceivers') IS NULL CREATE TABLE BLEReceivers(ReceiverId int IDENTITY PRIMARY KEY, ZoneId int NOT NULL REFERENCES Zones, Code varchar(100) NOT NULL UNIQUE);
IF OBJECT_ID('BLELocations') IS NULL CREATE TABLE BLELocations(LocationId bigint IDENTITY PRIMARY KEY, WearableId int NOT NULL REFERENCES Wearables, ReceiverId int NOT NULL REFERENCES BLEReceivers, ObservedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('NotificationReads') IS NULL CREATE TABLE NotificationReads(NotificationId int NOT NULL REFERENCES Notifications, UserId int NOT NULL REFERENCES Users, ReadAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), PRIMARY KEY(NotificationId,UserId));
GO
CREATE OR ALTER FUNCTION dbo.fn_AccountBalance(@AccountId int) RETURNS decimal(18,2) AS
BEGIN
 RETURN (SELECT COALESCE(SUM(CASE WHEN Status='POSTED' THEN Amount WHEN Status='REFUNDED' THEN Amount-RefundAmount ELSE 0 END),0) FROM Transactions WHERE AccountId=@AccountId);
END;
GO
CREATE OR ALTER VIEW dbo.vw_AccountSummary AS
SELECT a.AccountId,a.BookingId,a.Status,u.Name,c.Number AS Cabin,b.CruiseId,dbo.fn_AccountBalance(a.AccountId) AS Total
FROM Accounts a JOIN Bookings b ON b.BookingId=a.BookingId JOIN Passengers p ON p.PassengerId=b.PassengerId JOIN Users u ON u.UserId=p.UserId JOIN Cabins c ON c.CabinId=b.CabinId;
GO
CREATE OR ALTER VIEW dbo.vw_Revenue AS
SELECT b.CruiseId,COALESCE(s.Name,a.Name) AS Name,CASE WHEN t.ServiceId IS NULL THEN 'ACTIVITY' ELSE 'SERVICE' END AS Kind,
SUM(CASE WHEN t.Status='POSTED' THEN t.Amount WHEN t.Status='REFUNDED' THEN t.Amount-t.RefundAmount ELSE 0 END) AS Revenue,COUNT(*) AS Transactions
FROM Transactions t JOIN Accounts ac ON ac.AccountId=t.AccountId JOIN Bookings b ON b.BookingId=ac.BookingId LEFT JOIN Services s ON s.ServiceId=t.ServiceId LEFT JOIN Registrations r ON r.RegistrationId=t.RegistrationId LEFT JOIN Activities a ON a.ActivityId=r.ActivityId GROUP BY b.CruiseId,COALESCE(s.Name,a.Name),CASE WHEN t.ServiceId IS NULL THEN 'ACTIVITY' ELSE 'SERVICE' END;
GO
CREATE OR ALTER TRIGGER dbo.tr_RegistrationConsistency ON dbo.Registrations AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted r JOIN Activities a ON a.ActivityId=r.ActivityId JOIN Bookings b ON b.BookingId=r.BookingId WHERE a.CruiseId<>b.CruiseId) THROW 51100,N'Đăng ký phải thuộc đúng chuyến.',1;
 IF EXISTS(SELECT 1 FROM Activities a JOIN (SELECT DISTINCT ActivityId FROM inserted) i ON i.ActivityId=a.ActivityId WHERE (SELECT COUNT(*) FROM Registrations r WHERE r.ActivityId=a.ActivityId AND r.Status='CONFIRMED')>a.Capacity) THROW 51101,N'Vượt sức chứa hoạt động.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_GroupConsistency ON dbo.GroupMembers AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted m JOIN TourGroups g ON g.GroupId=m.GroupId JOIN Registrations r ON r.RegistrationId=m.RegistrationId WHERE g.ActivityId<>r.ActivityId OR r.Status<>'CONFIRMED') THROW 51102,N'Nhóm phải cùng tour và đăng ký hợp lệ.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TransactionConsistency ON dbo.Transactions AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted t JOIN Registrations r ON r.RegistrationId=t.RegistrationId JOIN Accounts a ON a.AccountId=t.AccountId WHERE r.BookingId<>a.BookingId OR t.RefundAmount>t.Amount OR (t.Status<>'REFUNDED' AND t.RefundAmount<>0)) THROW 51103,N'Giao dịch hoặc số tiền hoàn không hợp lệ.',1;
 IF EXISTS(SELECT 1 FROM inserted WHERE RefundAmount>Amount OR (Status<>'REFUNDED' AND RefundAmount<>0)) THROW 51103,N'Số tiền hoàn không hợp lệ.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Register @BookingId int,@ActivityId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CruiseId int,@Capacity int,@Fee decimal(18,2),@Start datetime2,@Status varchar(20),@AccountId int,@Actor int,@Included int;
  SELECT @CruiseId=CruiseId,@Capacity=Capacity,@Fee=Fee,@Start=StartsAt,@Status=Status,@Included=IncludedServiceId FROM Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId;
  IF @CruiseId IS NULL OR @Status<>'OPEN' OR @Start<=SYSDATETIME() THROW 51002,N'Hoạt động đã đóng hoặc đã bắt đầu.',1;
  IF NOT EXISTS(SELECT 1 FROM Bookings b JOIN Cruises c ON c.CruiseId=b.CruiseId WHERE b.BookingId=@BookingId AND b.CruiseId=@CruiseId AND c.Status<>'CLOSED') THROW 51003,N'Đặt chỗ không thuộc chuyến mở này.',1;
  SELECT @AccountId=AccountId FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE BookingId=@BookingId AND Status='OPEN';
  IF @AccountId IS NULL THROW 51004,N'Tài khoản đã chốt hoặc chưa tồn tại.',1;
  IF EXISTS(SELECT 1 FROM Registrations WHERE BookingId=@BookingId AND ActivityId=@ActivityId AND Status<>'CANCELLED') THROW 51005,N'Đã có đăng ký cho hoạt động này.',1;
  SELECT @Actor=p.UserId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=@BookingId;
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@Actor;
  IF EXISTS(SELECT 1 FROM Bookings b JOIN PackageServices ps ON ps.PackageId=b.PackageId WHERE b.BookingId=@BookingId AND ps.ServiceId=@Included) SET @Fee=0;
  DECLARE @State varchar(20)=CASE WHEN (SELECT COUNT(*) FROM Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED')>=@Capacity THEN 'WAITLIST' ELSE 'CONFIRMED' END;
  DECLARE @RegistrationId int=(SELECT RegistrationId FROM Registrations WHERE BookingId=@BookingId AND ActivityId=@ActivityId);
  IF @RegistrationId IS NULL BEGIN INSERT Registrations(ActivityId,BookingId,Status) VALUES(@ActivityId,@BookingId,@State); SET @RegistrationId=SCOPE_IDENTITY(); END
  ELSE BEGIN
   IF EXISTS(SELECT 1 FROM Transactions WHERE RegistrationId=@RegistrationId AND Status='POSTED') THROW 51104,N'Đăng ký còn khoản phí đang hiệu lực.',1;
   UPDATE Registrations SET Status=@State,CreatedAt=SYSUTCDATETIME() WHERE RegistrationId=@RegistrationId;
  END;
  IF @State='CONFIRMED' INSERT Transactions(AccountId,RegistrationId,Amount) VALUES(@AccountId,@RegistrationId,@Fee);
  COMMIT;
  SELECT @State AS Status,@RegistrationId AS RegistrationId;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_PromoteWaitlist @ActivityId int AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Capacity int,@Fee decimal(18,2),@Included int,@Reg int,@Account int;
 SELECT @Capacity=Capacity,@Fee=Fee,@Included=IncludedServiceId FROM Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId AND Status='OPEN' AND StartsAt>SYSDATETIME();
 IF @Capacity IS NULL RETURN;
 WHILE (SELECT COUNT(*) FROM Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED')<@Capacity
 BEGIN
  SET @Reg=NULL;
  SELECT TOP(1) @Reg=r.RegistrationId,@Account=ac.AccountId FROM Registrations r JOIN Accounts ac WITH(UPDLOCK,HOLDLOCK) ON ac.BookingId=r.BookingId WHERE r.ActivityId=@ActivityId AND r.Status='WAITLIST' AND ac.Status='OPEN' ORDER BY r.CreatedAt,r.RegistrationId;
  IF @Reg IS NULL BREAK;
  DECLARE @Price decimal(18,2)=@Fee;
  IF EXISTS(SELECT 1 FROM Registrations r JOIN Bookings b ON b.BookingId=r.BookingId JOIN PackageServices ps ON ps.PackageId=b.PackageId WHERE r.RegistrationId=@Reg AND ps.ServiceId=@Included) SET @Price=0;
  UPDATE Registrations SET Status='CONFIRMED' WHERE RegistrationId=@Reg;
  INSERT Transactions(AccountId,RegistrationId,Amount) VALUES(@Account,@Reg,@Price);
 END;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Cancel @BookingId int,@RegistrationId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @ActivityId int,@Start datetime2,@AccountId int,@Status varchar(20);
  SELECT @ActivityId=ActivityId FROM Registrations WHERE RegistrationId=@RegistrationId AND BookingId=@BookingId;
  SELECT @Start=StartsAt FROM Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId;
  SELECT @AccountId=AccountId FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE BookingId=@BookingId AND Status='OPEN';
  SELECT @Status=Status FROM Registrations WITH(UPDLOCK,HOLDLOCK) WHERE RegistrationId=@RegistrationId;
  IF @AccountId IS NULL OR @Status IS NULL OR @Status='CANCELLED' THROW 51006,N'Không thể hủy đăng ký này.',1;
  IF @Start<DATEADD(hour,(SELECT CancelHours FROM Policy WHERE PolicyId=1),SYSDATETIME()) THROW 51007,N'Đã qua hạn hủy.',1;
  IF EXISTS(SELECT 1 FROM CheckIns WHERE RegistrationId=@RegistrationId) THROW 51008,N'Đã check-in, không thể hủy.',1;
  DECLARE @Actor int=(SELECT p.UserId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=@BookingId);
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@Actor;
  UPDATE Registrations SET Status='CANCELLED' WHERE RegistrationId=@RegistrationId;
  DELETE GroupMembers WHERE RegistrationId=@RegistrationId;
  UPDATE Transactions SET Status='REFUNDED',RefundAmount=Amount*(SELECT RefundPercent FROM Policy WHERE PolicyId=1)/100.0 WHERE RegistrationId=@RegistrationId AND Status='POSTED';
  EXEC usp_PromoteWaitlist @ActivityId;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_FinanceTransaction @TransactionId int,@StaffId int,@Status varchar(20) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; EXEC usp_RequireRole @StaffId,'FINANCE';
 IF @Status NOT IN('REFUNDED','VOID') THROW 51105,N'Trạng thái không hợp lệ.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @AccountId int=(SELECT AccountId FROM Transactions WHERE TransactionId=@TransactionId);
  IF NOT EXISTS(SELECT 1 FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@AccountId AND Status='OPEN') THROW 51018,N'Tài khoản đã chốt.',1;
  IF EXISTS(SELECT 1 FROM Transactions WHERE TransactionId=@TransactionId AND RegistrationId IS NOT NULL) THROW 51106,N'Giao dịch đăng ký phải xử lý qua hủy đăng ký.',1;
  UPDATE Transactions SET Status=@Status,RefundAmount=CASE WHEN @Status='REFUNDED' THEN Amount ELSE 0 END WHERE TransactionId=@TransactionId AND Status='POSTED';
  IF @@ROWCOUNT=0 THROW 51019,N'Giao dịch không còn hiệu lực.',1;
  UPDATE Disputes SET Status='RESOLVED' WHERE TransactionId=@TransactionId;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Settle @AccountId int,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; EXEC usp_RequireRole @StaffId,'FINANCE';
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@AccountId AND Status='OPEN') THROW 51020,N'Tài khoản đã chốt hoặc không tồn tại.',1;
  IF EXISTS(SELECT 1 FROM Disputes d JOIN Transactions t ON t.TransactionId=d.TransactionId WHERE t.AccountId=@AccountId AND d.Status='OPEN') THROW 51021,N'Còn tranh chấp chưa xử lý.',1;
  IF EXISTS(SELECT 1 FROM Transactions WHERE AccountId=@AccountId AND ServiceId IS NOT NULL AND Status='POSTED' AND ReconciledAt IS NULL) THROW 51303,N'Còn giao dịch POS chưa đối soát.',1;
  DECLARE @Total decimal(18,2)=dbo.fn_AccountBalance(@AccountId);
  INSERT Invoices(AccountId,Total) VALUES(@AccountId,@Total);
  DECLARE @InvoiceId int=SCOPE_IDENTITY();
  INSERT Payments(InvoiceId,Amount,Method) VALUES(@InvoiceId,@Total,'DEMO');
  UPDATE Accounts SET Status='SETTLED' WHERE AccountId=@AccountId;
  UPDATE Registrations SET Status='CANCELLED' WHERE BookingId=(SELECT BookingId FROM Accounts WHERE AccountId=@AccountId) AND Status='WAITLIST';
  COMMIT; SELECT @InvoiceId AS InvoiceId,@Total AS Total;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Dispute @BookingId int,@TransactionId int,@Reason nvarchar(500) AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @Account int=(SELECT AccountId FROM Transactions WHERE TransactionId=@TransactionId);
  IF NOT EXISTS(SELECT 1 FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@Account AND BookingId=@BookingId AND Status='OPEN') THROW 51107,N'Giao dịch không thuộc tài khoản mở của bạn.',1;
  IF EXISTS(SELECT 1 FROM Disputes WHERE TransactionId=@TransactionId AND Status='OPEN') THROW 51108,N'Giao dịch đã có tranh chấp.',1;
  IF LEN(TRIM(@Reason))=0 THROW 51109,N'Cần nhập lý do.',1;
  INSERT Disputes(TransactionId,Reason) VALUES(@TransactionId,@Reason);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_ResolveDispute @DisputeId int,@StaffId int AS
BEGIN
 EXEC usp_RequireRole @StaffId,'FINANCE';
 UPDATE Disputes SET Status='RESOLVED' WHERE DisputeId=@DisputeId AND Status='OPEN';
 IF @@ROWCOUNT=0 THROW 51110,N'Tranh chấp không tồn tại hoặc đã xử lý.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_ReturnToShip @RegistrationId int,@StaffId int AS
BEGIN
 EXEC usp_RequireRole @StaffId,'SHORE';
 UPDATE ci SET ReturnedAt=SYSUTCDATETIME() FROM CheckIns ci JOIN Registrations r ON r.RegistrationId=ci.RegistrationId JOIN Activities a ON a.ActivityId=r.ActivityId WHERE ci.RegistrationId=@RegistrationId AND a.Kind='SHORE' AND ci.ReturnedAt IS NULL;
 IF @@ROWCOUNT=0 THROW 51111,N'Khách chưa check-in tour bờ hoặc đã về tàu.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AssignGroup @RegistrationId int,@GroupId int,@StaffId int AS
BEGIN
 EXEC usp_RequireRole @StaffId,'SHORE';
 IF EXISTS(SELECT 1 FROM GroupMembers WHERE RegistrationId=@RegistrationId) UPDATE GroupMembers SET GroupId=@GroupId WHERE RegistrationId=@RegistrationId;
 ELSE INSERT GroupMembers VALUES(@RegistrationId,@GroupId);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_SaveMaster @Entity varchar(30),@Id int=0,@Data nvarchar(max),@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF ISJSON(@Data)<>1 THROW 51112,N'Dữ liệu JSON không hợp lệ.',1;
 DECLARE @Role varchar(30)=CASE @Entity WHEN 'cruise' THEN 'ITINERARY' WHEN 'stop' THEN 'ITINERARY' WHEN 'activity' THEN CASE JSON_VALUE(@Data,'$.Kind') WHEN 'SHORE' THEN 'SHORE' ELSE 'ACTIVITY' END WHEN 'provider' THEN 'SHORE' WHEN 'group' THEN 'SHORE' ELSE 'ADMIN' END;
 EXEC usp_RequireRole @StaffId,@Role;
 DECLARE @Name nvarchar(150)=JSON_VALUE(@Data,'$.Name');
 BEGIN TRY
  BEGIN TRAN;
  IF @Entity='cruise'
  BEGIN
   IF @Id=0 INSERT Cruises(ShipId,Name,StartDate,EndDate,Status) SELECT ShipId,Name,StartDate,EndDate,Status FROM OPENJSON(@Data) WITH(ShipId int,Name nvarchar(150),StartDate date,EndDate date,Status varchar(20));
   ELSE BEGIN
    IF EXISTS(SELECT 1 FROM Stops s JOIN OPENJSON(@Data) WITH(StartDate date,EndDate date,ShipId int) j ON 1=1 WHERE s.CruiseId=@Id AND (CAST(s.Arrival AS date)<j.StartDate OR CAST(s.Departure AS date)>j.EndDate)) OR EXISTS(SELECT 1 FROM Bookings b JOIN Cabins c ON c.CabinId=b.CabinId WHERE b.CruiseId=@Id AND c.ShipId<>TRY_CONVERT(int,JSON_VALUE(@Data,'$.ShipId'))) THROW 51113,N'Lịch trình/cabin hiện tại không phù hợp chuyến mới.',1;
    IF EXISTS(SELECT 1 FROM Activities a JOIN OPENJSON(@Data) WITH(StartDate date,EndDate date,ShipId int) j ON 1=1 LEFT JOIN Zones z ON z.ZoneId=a.ZoneId WHERE a.CruiseId=@Id AND (CAST(a.StartsAt AS date)<j.StartDate OR CAST(a.EndsAt AS date)>j.EndDate OR z.ShipId<>j.ShipId)) THROW 51114,N'Hoạt động hiện tại không phù hợp chuyến mới.',1;
    UPDATE c SET ShipId=j.ShipId,Name=j.Name,StartDate=j.StartDate,EndDate=j.EndDate,Status=j.Status FROM Cruises c JOIN OPENJSON(@Data) WITH(ShipId int,Name nvarchar(150),StartDate date,EndDate date,Status varchar(20)) j ON 1=1 WHERE CruiseId=@Id;
   END;
  END
  ELSE IF @Entity='stop'
  BEGIN
   IF @Id=0
   BEGIN
    IF NOT EXISTS(SELECT 1 FROM Cruises c JOIN OPENJSON(@Data) WITH(CruiseId int,Arrival datetime2,Departure datetime2) j ON j.CruiseId=c.CruiseId WHERE j.Departure>j.Arrival AND CAST(j.Arrival AS date)>=c.StartDate AND CAST(j.Departure AS date)<=c.EndDate) THROW 51116,N'Điểm dừng phải có giờ hợp lệ và nằm trong chuyến.',1;
    INSERT Stops(CruiseId,PortId,Arrival,Departure) SELECT CruiseId,PortId,Arrival,Departure FROM OPENJSON(@Data) WITH(CruiseId int,PortId int,Arrival datetime2,Departure datetime2);
   END
   ELSE
   BEGIN
    DECLARE @PortId int=TRY_CONVERT(int,JSON_VALUE(@Data,'$.PortId')),@StopCruiseId int,@OldPortId int,@OldPortName nvarchar(100),@NewPortName nvarchar(100);
    SELECT @StopCruiseId=CruiseId,@OldPortId=PortId FROM Stops WITH(UPDLOCK,HOLDLOCK) WHERE StopId=@Id;
    IF @StopCruiseId IS NULL THROW 51115,N'Điểm dừng không tồn tại.',1;
    IF NOT EXISTS(SELECT 1 FROM Ports WHERE PortId=@PortId) THROW 51116,N'Cảng không tồn tại.',1;
    SELECT @OldPortName=Name FROM Ports WHERE PortId=@OldPortId;
    SELECT @NewPortName=Name FROM Ports WHERE PortId=@PortId;
    UPDATE Stops SET PortId=@PortId WHERE StopId=@Id;
    IF @OldPortId<>@PortId INSERT Notifications(CruiseId,Message) VALUES(@StopCruiseId,N'Cảng tại điểm dừng được đổi từ '+@OldPortName+N' sang '+@NewPortName+N'.');
   END;
  END
  ELSE IF @Entity='activity'
  BEGIN
   IF @Id=0 INSERT Activities(CruiseId,ZoneId,StopId,ProviderId,Name,Kind,StartsAt,EndsAt,ReturnAt,Capacity,Fee,Status,IncludedServiceId) SELECT * FROM OPENJSON(@Data) WITH(CruiseId int,ZoneId int,StopId int,ProviderId int,Name nvarchar(150),Kind varchar(20),StartsAt datetime2,EndsAt datetime2,ReturnAt datetime2,Capacity int,Fee decimal(18,2),Status varchar(20),IncludedServiceId int);
   ELSE BEGIN
    DECLARE @OldKind varchar(20),@OldCruise int;
    SELECT @OldKind=Kind,@OldCruise=CruiseId FROM Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@Id;
    EXEC usp_RequireRole @StaffId, @Role;
    IF @OldKind<>JSON_VALUE(@Data,'$.Kind') OR @OldCruise<>TRY_CONVERT(int,JSON_VALUE(@Data,'$.CruiseId')) THROW 51117,N'Không đổi loại/chuyến của hoạt động hiện có.',1;
    IF JSON_VALUE(@Data,'$.Status')='CANCELLED' AND EXISTS(SELECT 1 FROM Registrations WHERE ActivityId=@Id AND Status<>'CANCELLED') THROW 51118,N'Dùng chức năng hủy hoạt động để hoàn phí.',1;
    IF (SELECT COUNT(*) FROM Registrations WHERE ActivityId=@Id AND Status='CONFIRMED')>TRY_CONVERT(int,JSON_VALUE(@Data,'$.Capacity')) THROW 51119,N'Sức chứa nhỏ hơn số khách đã đăng ký.',1;
    UPDATE a SET ZoneId=j.ZoneId,StopId=j.StopId,ProviderId=j.ProviderId,Name=j.Name,StartsAt=j.StartsAt,EndsAt=j.EndsAt,ReturnAt=j.ReturnAt,Capacity=j.Capacity,Fee=j.Fee,Status=j.Status,IncludedServiceId=j.IncludedServiceId FROM Activities a JOIN OPENJSON(@Data) WITH(ZoneId int,StopId int,ProviderId int,Name nvarchar(150),StartsAt datetime2,EndsAt datetime2,ReturnAt datetime2,Capacity int,Fee decimal(18,2),Status varchar(20),IncludedServiceId int) j ON 1=1 WHERE ActivityId=@Id;
    EXEC usp_PromoteWaitlist @Id;
   END;
  END
  ELSE IF @Entity='service'
  BEGIN
   IF @Id=0 INSERT Services(Name,Price) VALUES(@Name,TRY_CONVERT(decimal(18,2),JSON_VALUE(@Data,'$.Price')));
   ELSE UPDATE Services SET Name=@Name,Price=TRY_CONVERT(decimal(18,2),JSON_VALUE(@Data,'$.Price')) WHERE ServiceId=@Id;
  END
  ELSE IF @Entity='ship'
  BEGIN
   IF @Id=0 INSERT Ships(Name,Capacity) VALUES(@Name,TRY_CONVERT(int,JSON_VALUE(@Data,'$.Capacity')));
   ELSE UPDATE Ships SET Name=@Name,Capacity=TRY_CONVERT(int,JSON_VALUE(@Data,'$.Capacity')) WHERE ShipId=@Id;
  END
  ELSE IF @Entity='port'
  BEGIN IF @Id=0 INSERT Ports(Name) VALUES(@Name); ELSE UPDATE Ports SET Name=@Name WHERE PortId=@Id; END
  ELSE IF @Entity='provider'
  BEGIN IF @Id=0 INSERT Providers(Name) VALUES(@Name); ELSE UPDATE Providers SET Name=@Name WHERE ProviderId=@Id; END
  ELSE IF @Entity='zone'
  BEGIN IF @Id=0 INSERT Zones(ShipId,Name) VALUES(TRY_CONVERT(int,JSON_VALUE(@Data,'$.ShipId')),@Name); ELSE UPDATE Zones SET Name=@Name WHERE ZoneId=@Id; END
  ELSE IF @Entity='cabin'
  BEGIN IF @Id=0 INSERT Cabins(ShipId,Number) VALUES(TRY_CONVERT(int,JSON_VALUE(@Data,'$.ShipId')),JSON_VALUE(@Data,'$.Number')); ELSE UPDATE Cabins SET Number=JSON_VALUE(@Data,'$.Number') WHERE CabinId=@Id; END
  ELSE IF @Entity='device'
  BEGIN IF @Id=0 INSERT Devices(Name,Kind) VALUES(@Name,JSON_VALUE(@Data,'$.Kind')); ELSE UPDATE Devices SET Name=@Name WHERE DeviceId=@Id; END
  ELSE IF @Entity='package'
  BEGIN IF @Id=0 INSERT Packages(Name) VALUES(@Name); ELSE UPDATE Packages SET Name=@Name WHERE PackageId=@Id; END
  ELSE IF @Entity='group'
  BEGIN IF @Id=0 INSERT TourGroups(ActivityId,Name,Vehicle,Guide) SELECT * FROM OPENJSON(@Data) WITH(ActivityId int,Name nvarchar(100),Vehicle nvarchar(100),Guide nvarchar(100)); ELSE UPDATE g SET Name=j.Name,Vehicle=j.Vehicle,Guide=j.Guide FROM TourGroups g JOIN OPENJSON(@Data) WITH(Name nvarchar(100),Vehicle nvarchar(100),Guide nvarchar(100)) j ON 1=1 WHERE GroupId=@Id; END
  ELSE IF @Entity='identifier'
  BEGIN IF @Id=0 INSERT Identifiers(BookingId,Code,Kind,Active) SELECT * FROM OPENJSON(@Data) WITH(BookingId int,Code varchar(100),Kind varchar(10),Active bit); ELSE UPDATE Identifiers SET Active=TRY_CONVERT(bit,JSON_VALUE(@Data,'$.Active')) WHERE IdentifierId=@Id; END
  ELSE IF @Entity='policy'
   UPDATE Policy SET CancelHours=TRY_CONVERT(int,JSON_VALUE(@Data,'$.CancelHours')),RefundPercent=TRY_CONVERT(int,JSON_VALUE(@Data,'$.RefundPercent')) WHERE PolicyId=1;
  ELSE THROW 51120,N'Danh mục không hỗ trợ.',1;
  DECLARE @SavedId int=CASE WHEN @Id=0 THEN CONVERT(int,SCOPE_IDENTITY()) ELSE @Id END;
  INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES(@Entity,COALESCE(@SavedId,1),CASE WHEN @Id=0 THEN 'INSERT' ELSE 'UPDATE' END,@StaffId);
  COMMIT; SELECT @SavedId AS Id;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_CancelActivity @ActivityId int,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Role varchar(30)=(SELECT CASE Kind WHEN 'SHORE' THEN 'SHORE' ELSE 'ACTIVITY' END FROM Activities WHERE ActivityId=@ActivityId);
 EXEC usp_RequireRole @StaffId,@Role;
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId AND Status<>'CANCELLED') THROW 51121,N'Hoạt động đã hủy/không tồn tại.',1;
  IF EXISTS(SELECT 1 FROM Registrations r JOIN Accounts ac WITH(UPDLOCK,HOLDLOCK) ON ac.BookingId=r.BookingId WHERE r.ActivityId=@ActivityId AND ac.Status='SETTLED' AND r.Status='CONFIRMED') THROW 51122,N'Có khách đã chốt hóa đơn; cần xử lý tài chính riêng.',1;
  UPDATE Transactions SET Status='REFUNDED',RefundAmount=Amount WHERE RegistrationId IN(SELECT RegistrationId FROM Registrations WHERE ActivityId=@ActivityId) AND Status='POSTED';
  UPDATE Registrations SET Status='CANCELLED' WHERE ActivityId=@ActivityId;
  DELETE GroupMembers WHERE RegistrationId IN(SELECT RegistrationId FROM Registrations WHERE ActivityId=@ActivityId);
  UPDATE Activities SET Status='CANCELLED' WHERE ActivityId=@ActivityId;
  INSERT Notifications(CruiseId,Message) SELECT CruiseId,N'Hoạt động đã hủy và hoàn phí: '+Name FROM Activities WHERE ActivityId=@ActivityId;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_BookPassenger @CruiseId int,@PassengerId int,@CabinId int,@PackageId int,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; EXEC usp_RequireRole @StaffId,'ADMIN';
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @Capacity int;
  SELECT @Capacity=s.Capacity FROM Cruises c WITH(UPDLOCK,HOLDLOCK) JOIN Ships s ON s.ShipId=c.ShipId WHERE c.CruiseId=@CruiseId AND c.Status='OPEN';
  IF @Capacity IS NULL OR (SELECT COUNT(*) FROM Bookings WHERE CruiseId=@CruiseId)>=@Capacity THROW 51123,N'Chuyến đóng hoặc hết sức chứa.',1;
  INSERT Bookings(CruiseId,PassengerId,CabinId,PackageId) VALUES(@CruiseId,@PassengerId,@CabinId,@PackageId);
  DECLARE @BookingId int=SCOPE_IDENTITY();
  INSERT Accounts(BookingId) VALUES(@BookingId);
  INSERT Identifiers(BookingId,Code,Kind) VALUES(@BookingId,'AURORA-'+CONVERT(varchar(36),NEWID()),'QR');
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_CruiseFeedback @BookingId int,@Rating int,@Comment nvarchar(500) AS
BEGIN
 IF NOT EXISTS(SELECT 1 FROM Bookings b JOIN Cruises c ON c.CruiseId=b.CruiseId WHERE b.BookingId=@BookingId AND (c.EndDate<CAST(GETDATE() AS date) OR c.Status='CLOSED')) THROW 51124,N'Chỉ đánh giá chuyến đã kết thúc.',1;
 INSERT CruiseFeedback VALUES(@BookingId,@Rating,@Comment,SYSUTCDATETIME());
END;
GO
IF NOT EXISTS(SELECT 1 FROM TourGroups) INSERT TourGroups(ActivityId,Name,Vehicle,Guide) VALUES(4,N'Nhóm A',N'Xe 01',N'Trần Huy'),(5,N'Nhóm B',N'Xe 02',N'Lê Mai');
IF NOT EXISTS(SELECT 1 FROM Wearables) INSERT Wearables(BookingId,Code) VALUES(1,'BLE-DEMO-001');
IF NOT EXISTS(SELECT 1 FROM BLEReceivers) INSERT BLEReceivers(ZoneId,Code) VALUES(1,'RX-DECK-001');
IF NOT EXISTS(SELECT 1 FROM BLELocations) INSERT BLELocations(WearableId,ReceiverId) VALUES(1,1);
IF NOT EXISTS(SELECT 1 FROM Users WHERE Email='shore@demo.local')
BEGIN
 INSERT Users(Name,Email) VALUES(N'Điều phối tour bờ','shore@demo.local'); DECLARE @u int=SCOPE_IDENTITY(); INSERT UserRoles SELECT @u,RoleId FROM Roles WHERE Code='SHORE';
 INSERT Users(Name,Email) VALUES(N'Quản lý vận hành','operations@demo.local'); SET @u=SCOPE_IDENTITY(); INSERT UserRoles SELECT @u,RoleId FROM Roles WHERE Code='OPERATIONS';
END;
GO
