:ON ERROR EXIT
USE CruiseCourseworkV3;
GO
SET NOCOUNT ON;
IF COL_LENGTH('Transactions','SyncStatus') IS NULL ALTER TABLE Transactions ADD SyncStatus varchar(10) NOT NULL DEFAULT 'SYNCED' CHECK(SyncStatus='SYNCED');
DECLARE @constraint sysname;
SELECT @constraint=kc.name FROM sys.key_constraints kc JOIN sys.index_columns ic ON ic.object_id=kc.parent_object_id AND ic.index_id=kc.unique_index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE kc.parent_object_id=OBJECT_ID('Transactions') AND kc.type='UQ' AND c.name='RegistrationId';
IF @constraint IS NOT NULL BEGIN DECLARE @ddl nvarchar(max)='ALTER TABLE Transactions DROP CONSTRAINT '+QUOTENAME(@constraint); EXEC sys.sp_executesql @ddl; END;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('Transactions') AND name='UX_ActiveRegistrationCharge') CREATE UNIQUE INDEX UX_ActiveRegistrationCharge ON Transactions(RegistrationId) WHERE RegistrationId IS NOT NULL AND Status='POSTED';
GO
CREATE OR ALTER PROCEDURE dbo.usp_RequireRole @StaffId int, @Role varchar(30) AS
BEGIN
 IF NOT EXISTS(SELECT 1 FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId JOIN Users u ON u.UserId=ur.UserId WHERE u.Active=1 AND ur.UserId=@StaffId AND r.Code IN(@Role,'ADMIN')) THROW 51001,N'Không có quyền thực hiện nghiệp vụ.',1;
 EXEC sys.sp_set_session_context @key=N'ActorId',@value=@StaffId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Feedback @BookingId int,@RegistrationId int,@Rating int,@Comment nvarchar(500) AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM Registrations r JOIN CheckIns c ON c.RegistrationId=r.RegistrationId JOIN Activities a ON a.ActivityId=r.ActivityId WHERE r.RegistrationId=@RegistrationId AND r.BookingId=@BookingId AND (a.EndsAt<SYSDATETIME() OR a.Status='COMPLETED')) THROW 51024,N'Chỉ khách đã check-in và hoạt động đã kết thúc mới được đánh giá.',1;
 INSERT Feedback(RegistrationId,Rating,Comment) VALUES(@RegistrationId,@Rating,@Comment);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Refund @TransactionId int,@StaffId int AS
EXEC usp_FinanceTransaction @TransactionId,@StaffId,'REFUNDED';
GO
CREATE OR ALTER PROCEDURE dbo.usp_Reconcile @TransactionId int,@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; EXEC usp_RequireRole @StaffId,'FINANCE';
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @AccountId int=(SELECT AccountId FROM Transactions WHERE TransactionId=@TransactionId);
  IF NOT EXISTS(SELECT 1 FROM Accounts WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@AccountId AND Status='OPEN') THROW 51304,N'Tài khoản đã chốt hoặc không tồn tại.',1;
  IF EXISTS(SELECT 1 FROM Disputes WHERE TransactionId=@TransactionId AND Status='OPEN') THROW 51305,N'Xử lý tranh chấp trước khi đối soát.',1;
  UPDATE Transactions SET ReconciledAt=SYSUTCDATETIME(),ReconciledBy=@StaffId WHERE TransactionId=@TransactionId AND Status='POSTED' AND ReconciledAt IS NULL;
  IF @@ROWCOUNT=0 THROW 51306,N'Giao dịch đã xử lý hoặc đã đối soát.',1;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER VIEW dbo.vw_CabinExpenses AS
SELECT b.CruiseId,c.Number AS Cabin,COUNT(*) AS Passengers,SUM(dbo.fn_AccountBalance(a.AccountId)) AS Total FROM Accounts a JOIN Bookings b ON b.BookingId=a.BookingId JOIN Cabins c ON c.CabinId=b.CabinId GROUP BY b.CruiseId,c.Number;
GO
CREATE OR ALTER TRIGGER dbo.tr_PaymentTotal ON dbo.Payments AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted p JOIN Invoices i ON i.InvoiceId=p.InvoiceId WHERE p.Amount<>i.Total) THROW 51307,N'Thanh toán phải bằng tổng hóa đơn.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_AccountSettlement ON dbo.Accounts AFTER UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted a WHERE a.Status='SETTLED' AND NOT EXISTS(SELECT 1 FROM Invoices i JOIN Payments p ON p.InvoiceId=i.InvoiceId WHERE i.AccountId=a.AccountId AND p.Amount=i.Total AND i.Total=dbo.fn_AccountBalance(a.AccountId))) THROW 51308,N'Chốt tài khoản cần hóa đơn và thanh toán khớp số dư.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ClosedAccountTransactions ON dbo.Transactions AFTER INSERT,UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM (SELECT AccountId FROM inserted UNION SELECT AccountId FROM deleted) t JOIN Accounts a ON a.AccountId=t.AccountId WHERE a.Status='SETTLED') THROW 51309,N'Không sửa giao dịch của tài khoản đã chốt.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_TourGroupConsistency ON dbo.TourGroups AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted g JOIN Activities a ON a.ActivityId=g.ActivityId WHERE a.Kind<>'SHORE') THROW 51300,N'Nhóm tour chỉ áp dụng tour bờ.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ShipCapacity ON dbo.Ships AFTER UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted s JOIN Cruises c ON c.ShipId=s.ShipId WHERE (SELECT COUNT(*) FROM Bookings WHERE CruiseId=c.CruiseId)>s.Capacity) THROW 51301,N'Sức chứa tàu nhỏ hơn số hành khách hiện có.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_CruiseConsistency ON dbo.Cruises AFTER INSERT,UPDATE AS
BEGIN
 IF EXISTS(SELECT 1 FROM inserted c JOIN Cruises other ON other.ShipId=c.ShipId AND other.CruiseId<>c.CruiseId AND other.StartDate<=c.EndDate AND other.EndDate>=c.StartDate) THROW 51302,N'Tàu đã có chuyến khác trong khoảng thời gian này.',1;
END;
GO
DECLARE @table sysname,@key sysname,@sql nvarchar(max);
DECLARE tables CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM (VALUES('Disputes','DisputeId'),('Invoices','InvoiceId'),('Payments','PaymentId'),('Identifiers','IdentifierId'),('CheckIns','CheckInId'),('Notifications','NotificationId'),('ItineraryChanges','ChangeId'),('Bookings','BookingId')) x(t,k);
OPEN tables; FETCH NEXT FROM tables INTO @table,@key;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @sql=N'CREATE OR ALTER TRIGGER '+QUOTENAME('tr_Audit_'+@table)+N' ON '+QUOTENAME(@table)+N' AFTER INSERT,UPDATE,DELETE AS BEGIN SET NOCOUNT ON; INSERT AuditLog(Entity,EntityId,Action,ActorId) SELECT '+QUOTENAME(@table,'''')+N',COALESCE(i.'+QUOTENAME(@key)+N',d.'+QUOTENAME(@key)+N'),CASE WHEN d.'+QUOTENAME(@key)+N' IS NULL THEN ''INSERT'' WHEN i.'+QUOTENAME(@key)+N' IS NULL THEN ''DELETE'' ELSE ''UPDATE'' END,TRY_CONVERT(int,SESSION_CONTEXT(N''ActorId'')) FROM inserted i FULL JOIN deleted d ON i.'+QUOTENAME(@key)+N'=d.'+QUOTENAME(@key)+N'; END';
 EXEC sys.sp_executesql @sql;
 FETCH NEXT FROM tables INTO @table,@key;
END;
CLOSE tables; DEALLOCATE tables;
GO
