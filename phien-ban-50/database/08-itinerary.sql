:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_SaveCruise
 @CruiseId int=0,@ShipId int,@Name nvarchar(150),@StartDate date,@EndDate date,@Status varchar(20),@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@StaffId AND r.Code IN('ITINERARY','ADMIN')) THROW 51300,N'Bạn không có quyền quản lý chuyến.',1;
  IF @ShipId IS NULL OR NOT EXISTS(SELECT 1 FROM Ships WHERE ShipId=@ShipId) OR NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL OR @StartDate IS NULL OR @EndDate IS NULL OR @EndDate<@StartDate OR @Status IS NULL OR @Status NOT IN('OPEN','SAILING','CLOSED') THROW 51301,N'Thông tin chuyến không hợp lệ.',1;
  IF @CruiseId=0
  BEGIN
   INSERT Cruises(ShipId,Name,StartDate,EndDate,Status) VALUES(@ShipId,@Name,@StartDate,@EndDate,@Status);
   SET @CruiseId=SCOPE_IDENTITY();
   INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES('Cruise',@CruiseId,'INSERT',@StaffId);
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM Cruises WITH(UPDLOCK,HOLDLOCK) WHERE CruiseId=@CruiseId) THROW 51302,N'Không tìm thấy chuyến.',1;
   IF EXISTS(SELECT 1 FROM Stops WHERE CruiseId=@CruiseId AND (CAST(Arrival AS date)<@StartDate OR CAST(Departure AS date)>@EndDate)) THROW 51303,N'Ngày chuyến phải bao trùm toàn bộ lịch cảng hiện có.',1;
   IF EXISTS(SELECT 1 FROM Bookings b JOIN Cabins c ON c.CabinId=b.CabinId WHERE b.CruiseId=@CruiseId AND c.ShipId<>@ShipId) THROW 51304,N'Tàu mới không khớp với cabin đã đặt.',1;
   IF EXISTS(SELECT 1 FROM Activities a LEFT JOIN Zones z ON z.ZoneId=a.ZoneId WHERE a.CruiseId=@CruiseId AND (CAST(a.StartsAt AS date)<@StartDate OR CAST(a.EndsAt AS date)>@EndDate OR (a.Kind='ONBOARD' AND z.ShipId<>@ShipId))) THROW 51312,N'Ngày hoặc tàu mới không phù hợp với hoạt động hiện có.',1;
   UPDATE Cruises SET ShipId=@ShipId,Name=@Name,StartDate=@StartDate,EndDate=@EndDate,Status=@Status WHERE CruiseId=@CruiseId;
   INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES('Cruise',@CruiseId,'UPDATE',@StaffId);
  END;
  COMMIT;
 END TRY
 BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_SaveStop
 @StopId int=0,@CruiseId int,@PortId int,@Arrival datetime2,@Departure datetime2,@Reason nvarchar(500)=NULL,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@StaffId AND r.Code IN('ITINERARY','ADMIN')) THROW 51305,N'Bạn không có quyền quản lý lịch trình.',1;
  IF @Arrival IS NULL OR @Departure IS NULL OR @Departure<=@Arrival OR NOT EXISTS(SELECT 1 FROM Ports WHERE PortId=@PortId) OR NOT EXISTS(SELECT 1 FROM Cruises WHERE CruiseId=@CruiseId) THROW 51306,N'Thông tin điểm dừng không hợp lệ.',1;
  IF NOT EXISTS(SELECT 1 FROM Cruises WHERE CruiseId=@CruiseId AND CAST(@Arrival AS date)>=StartDate AND CAST(@Departure AS date)<=EndDate) THROW 51307,N'Thời gian điểm dừng phải nằm trong ngày của chuyến.',1;
  IF EXISTS(SELECT 1 FROM Stops WHERE CruiseId=@CruiseId AND StopId<>@StopId AND Arrival<@Departure AND Departure>@Arrival) THROW 51308,N'Lịch cảng bị trùng với một điểm dừng khác.',1;
  IF EXISTS(SELECT 1 FROM Activities WHERE StopId=@StopId AND Status<>'CANCELLED' AND (StartsAt<@Arrival OR ReturnAt>@Departure)) THROW 51309,N'Giờ mới xung đột với hoạt động tour bờ.',1;
  IF @StopId=0
  BEGIN
   INSERT Stops(CruiseId,PortId,Arrival,Departure) VALUES(@CruiseId,@PortId,@Arrival,@Departure);
   SET @StopId=SCOPE_IDENTITY();
   INSERT Notifications(CruiseId,Message) SELECT @CruiseId,N'Đã thêm điểm dừng '+Name+N' vào lịch trình.' FROM Ports WHERE PortId=@PortId;
   INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES('Stop',@StopId,'INSERT',@StaffId);
  END
  ELSE
  BEGIN
   DECLARE @OldCruise int,@OldPort int,@OldArrival datetime2,@OldDeparture datetime2;
   SELECT @OldCruise=CruiseId,@OldPort=PortId,@OldArrival=Arrival,@OldDeparture=Departure FROM Stops WITH(UPDLOCK,HOLDLOCK) WHERE StopId=@StopId;
   IF @OldCruise IS NULL OR @OldCruise<>@CruiseId THROW 51310,N'Điểm dừng không thuộc chuyến đã chọn.',1;
   IF NULLIF(LTRIM(RTRIM(@Reason)),N'') IS NULL THROW 51311,N'Cần ghi lý do khi thay đổi lịch trình.',1;
   UPDATE Stops SET PortId=@PortId,Arrival=@Arrival,Departure=@Departure WHERE StopId=@StopId;
   INSERT ItineraryChanges(StopId,OldArrival,OldDeparture,NewArrival,NewDeparture,Reason,StaffId) VALUES(@StopId,@OldArrival,@OldDeparture,@Arrival,@Departure,@Reason,@StaffId);
   INSERT Notifications(CruiseId,Message) SELECT @CruiseId,N'Lịch trình tại '+Name+N' đã thay đổi. Lý do: '+@Reason FROM Ports WHERE PortId=@PortId;
   INSERT AuditLog(Entity,EntityId,Action,ActorId) VALUES('Stop',@StopId,'UPDATE',@StaffId);
  END;
  COMMIT;
 END TRY
 BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
