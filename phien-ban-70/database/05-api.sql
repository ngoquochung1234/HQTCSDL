:ON ERROR EXIT
USE CruiseCourseworkV2;
GO
CREATE OR ALTER PROCEDURE dbo.usp_SyncPOS @Code varchar(100),@ServiceId int,@Quantity int,@DeviceId int,@StaffId int,@ClientId uniqueidentifier AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC usp_PostPOS @Code,@ServiceId,@Quantity,@DeviceId,@StaffId,@ClientId;
  IF NOT EXISTS(SELECT 1 FROM SyncReceipts WITH(UPDLOCK,HOLDLOCK) WHERE ClientId=@ClientId) INSERT SyncReceipts(ClientId,DeviceId) VALUES(@ClientId,@DeviceId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_CheckIn @ActivityId int,@Code varchar(100),@DeviceId int,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Role varchar(30)=(SELECT CASE Kind WHEN 'SHORE' THEN 'SHORE' ELSE 'ACTIVITY' END FROM Activities WHERE ActivityId=@ActivityId);
 EXEC usp_RequireRole @StaffId,@Role;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @RegistrationId int;
  SELECT @RegistrationId=r.RegistrationId FROM Identifiers i JOIN Registrations r WITH(UPDLOCK,HOLDLOCK) ON r.BookingId=i.BookingId JOIN Activities a ON a.ActivityId=r.ActivityId WHERE i.Code=@Code AND i.Active=1 AND r.ActivityId=@ActivityId AND r.Status='CONFIRMED' AND a.Status IN('OPEN','DELAYED');
  IF @RegistrationId IS NULL THROW 51009,N'Mã không hợp lệ hoặc khách chưa đăng ký.',1;
  IF NOT EXISTS(SELECT 1 FROM Devices WHERE DeviceId=@DeviceId AND Kind='CHECKIN') THROW 51010,N'Thiết bị không phải máy check-in.',1;
  IF EXISTS(SELECT 1 FROM CheckIns WHERE RegistrationId=@RegistrationId) THROW 51011,N'Khách đã check-in.',1;
  INSERT CheckIns(RegistrationId,DeviceId,StaffId) VALUES(@RegistrationId,@DeviceId,@StaffId);
  INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES('CheckIn',SCOPE_IDENTITY(),'INSERT',@StaffId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_ManageUser @UserId int=0,@Name nvarchar(100),@Email varchar(150),@Role varchar(30),@Hash varchar(200)=NULL,@Active bit=1,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; EXEC usp_RequireRole @StaffId,'ADMIN';
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @RoleId int=(SELECT RoleId FROM Roles WHERE Code=@Role);
  IF @RoleId IS NULL THROW 51200,N'Vai trò không hợp lệ.',1;
  IF @UserId=@StaffId AND (@Active=0 OR @Role<>'ADMIN') THROW 51201,N'Không tự khóa hoặc bỏ quyền quản trị của mình.',1;
  IF @UserId=0 BEGIN
   IF @Hash IS NULL THROW 51202,N'Tài khoản mới cần mật khẩu.',1;
   INSERT Users(Name,Email,PasswordHash,Active) VALUES(@Name,@Email,@Hash,@Active); SET @UserId=SCOPE_IDENTITY();
  END ELSE BEGIN
   IF EXISTS(SELECT 1 FROM Passengers WHERE UserId=@UserId) AND @Role<>'PASSENGER' THROW 51203,N'Không chuyển vai trò tài khoản đã có hồ sơ hành khách.',1;
   UPDATE Users SET Name=@Name,Email=@Email,Active=@Active,PasswordHash=COALESCE(@Hash,PasswordHash) WHERE UserId=@UserId;
   IF @@ROWCOUNT=0 THROW 51204,N'Người dùng không tồn tại.',1;
   DELETE UserRoles WHERE UserId=@UserId;
  END;
  INSERT UserRoles VALUES(@UserId,@RoleId);
  IF @Role='PASSENGER' AND NOT EXISTS(SELECT 1 FROM Passengers WHERE UserId=@UserId) INSERT Passengers(UserId) VALUES(@UserId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_PackageService @PackageId int,@ServiceId int,@Included bit,@StaffId int AS
BEGIN
 EXEC usp_RequireRole @StaffId,'ADMIN';
 IF @Included=1 AND NOT EXISTS(SELECT 1 FROM PackageServices WHERE PackageId=@PackageId AND ServiceId=@ServiceId) INSERT PackageServices VALUES(@PackageId,@ServiceId);
 ELSE IF @Included=0 DELETE PackageServices WHERE PackageId=@PackageId AND ServiceId=@ServiceId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Notify @CruiseId int,@Message nvarchar(500),@StaffId int AS
BEGIN
 IF NOT EXISTS(SELECT 1 FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@StaffId AND r.Code IN('ADMIN','ITINERARY','OPERATIONS')) THROW 51205,N'Không có quyền gửi thông báo.',1;
 IF LEN(TRIM(@Message))=0 THROW 51206,N'Nội dung thông báo không được trống.',1;
 INSERT Notifications(CruiseId,Message) VALUES(@CruiseId,@Message);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_ReadNotification @NotificationId int,@UserId int AS
BEGIN
 IF NOT EXISTS(SELECT 1 FROM Notifications n JOIN Bookings b ON b.CruiseId=n.CruiseId JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE n.NotificationId=@NotificationId AND p.UserId=@UserId) THROW 51207,N'Thông báo không thuộc chuyến của bạn.',1;
 IF NOT EXISTS(SELECT 1 FROM NotificationReads WHERE NotificationId=@NotificationId AND UserId=@UserId) INSERT NotificationReads(NotificationId,UserId) VALUES(@NotificationId,@UserId);
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_StopConsistency ON dbo.Stops AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted s JOIN Cruises c ON c.CruiseId=s.CruiseId WHERE CAST(s.Arrival AS date)<c.StartDate OR CAST(s.Departure AS date)>c.EndDate) THROW 51208,N'Điểm dừng nằm ngoài chuyến đi.',1;
 IF EXISTS(SELECT 1 FROM inserted s JOIN Stops other ON other.CruiseId=s.CruiseId AND other.StopId<>s.StopId AND other.Arrival<s.Departure AND other.Departure>s.Arrival) THROW 51209,N'Hai điểm dừng không được trùng thời gian.',1;
 IF EXISTS(SELECT 1 FROM inserted s JOIN Activities a ON a.StopId=s.StopId WHERE a.Status<>'CANCELLED' AND (a.CruiseId<>s.CruiseId OR a.StartsAt<s.Arrival OR a.ReturnAt>s.Departure)) THROW 51210,N'Điểm dừng xung đột tour bờ.',1;
END;
GO
CREATE OR ALTER VIEW dbo.vw_BLELatest AS
WITH Ranked AS(SELECT l.*,ROW_NUMBER() OVER(PARTITION BY l.WearableId ORDER BY l.ObservedAt DESC,l.LocationId DESC) rn FROM BLELocations l)
SELECT w.BookingId,w.Code,z.Name AS Zone,l.ObservedAt FROM Ranked l JOIN Wearables w ON w.WearableId=l.WearableId JOIN BLEReceivers rx ON rx.ReceiverId=l.ReceiverId JOIN Zones z ON z.ZoneId=rx.ZoneId WHERE rn=1;
GO
