import assert from 'node:assert/strict';
import {query,jsonQuery} from '../src/db.mjs';
const tests=[];
const test=(name,sql,error)=>tests.push({name,sql,error});
test('Foreign key rejects unknown passenger',"INSERT Bookings(CruiseId,PassengerId,CabinId,PackageId) VALUES(1,999999,1,1);",547);
test('Capacity constraint rejects zero',"INSERT Ships(Name,Capacity) VALUES(N'Test',0);",547);
test('Duplicate registration rejected',"EXEC usp_Register 1,2;",51005);
test('Registration creates charge atomically',"EXEC usp_Register 10,3; IF NOT EXISTS(SELECT 1 FROM Registrations r JOIN Transactions t ON t.RegistrationId=r.RegistrationId WHERE r.BookingId=10 AND r.ActivityId=3 AND t.Amount=250000) THROW 51999,'Missing registration charge',1;");
test('Waitlist capacity and FIFO promotion',"UPDATE Activities SET Capacity=1 WHERE ActivityId=3; EXEC usp_Register 10,3; EXEC usp_Register 11,3; IF NOT EXISTS(SELECT 1 FROM Registrations WHERE BookingId=11 AND ActivityId=3 AND Status='WAITLIST') THROW 51999,'No waitlist',1; DECLARE @r int=(SELECT RegistrationId FROM Registrations WHERE BookingId=10 AND ActivityId=3); EXEC usp_Cancel 10,@r; IF NOT EXISTS(SELECT 1 FROM Registrations WHERE BookingId=11 AND ActivityId=3 AND Status='CONFIRMED') THROW 51999,'Promotion failed',1;");
test('Re-register after cancellation preserves financial history',"EXEC usp_Register 10,3; DECLARE @r int=(SELECT RegistrationId FROM Registrations WHERE BookingId=10 AND ActivityId=3); EXEC usp_Cancel 10,@r; EXEC usp_Register 10,3; IF (SELECT COUNT(*) FROM Transactions WHERE RegistrationId=@r)<>2 THROW 51999,'History lost',1;");
test('Invalid identity cannot check in',"EXEC usp_CheckIn 2,'INVALID',2,3;",51009);
test('Check-in duplicate rejected',"EXEC usp_CheckIn 2,'AURORA-001',2,3; EXEC usp_CheckIn 2,'AURORA-001',2,3;",51011);
test('Cannot cancel after check-in',"EXEC usp_CheckIn 2,'AURORA-001',2,3; EXEC usp_Cancel 1,1;",51008);
test('No feedback before activity ends',"EXEC usp_CheckIn 2,'AURORA-001',2,3; EXEC usp_Feedback 1,1,5,N'Great';",51024);
test('Premium service is free',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-001',1,2,1,2,@c; IF NOT EXISTS(SELECT 1 FROM Transactions WHERE ClientId=@c AND Amount=0) THROW 51999,'Included service charged',1;");
test('Paid service multiplied by quantity',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,2,1,2,@c; IF NOT EXISTS(SELECT 1 FROM Transactions WHERE ClientId=@c AND Amount=70000) THROW 51999,'Wrong price',1;");
test('Offline replay is idempotent and has sync receipt',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,2,1,2,@c; EXEC usp_SyncPOS 'AURORA-010',1,2,1,2,@c; IF (SELECT COUNT(*) FROM Transactions WHERE ClientId=@c)<>1 OR (SELECT COUNT(*) FROM SyncReceipts WHERE ClientId=@c)<>1 THROW 51999,'Duplicate synced',1;");
test('Replay with changed payload rejected',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,2,1,2,@c; EXEC usp_SyncPOS 'AURORA-010',1,3,1,2,@c;",51014);
test('POS role enforced in SQL',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,1,1,3,@c;",51001);
test('Dispute blocks settlement',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,1,1,2,@c; DECLARE @t int=(SELECT TransactionId FROM Transactions WHERE ClientId=@c); EXEC usp_Dispute 10,@t,N'Unexpected'; EXEC usp_Settle 10,4;",51021);
test('Refund resolves dispute and balance',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,1,1,2,@c; DECLARE @t int=(SELECT TransactionId FROM Transactions WHERE ClientId=@c); EXEC usp_Dispute 10,@t,N'Unexpected'; EXEC usp_FinanceTransaction @t,4,'REFUNDED'; IF dbo.fn_AccountBalance(10)<>0 OR EXISTS(SELECT 1 FROM Disputes WHERE TransactionId=@t AND Status='OPEN') THROW 51999,'Refund failed',1;");
test('Settlement creates matching invoice and payment',"EXEC usp_Settle 10,4; IF NOT EXISTS(SELECT 1 FROM Invoices i JOIN Payments p ON p.InvoiceId=i.InvoiceId JOIN Accounts a ON a.AccountId=i.AccountId WHERE a.AccountId=10 AND a.Status='SETTLED' AND i.Total=p.Amount) THROW 51999,'Incomplete settlement',1;");
test('Settled account rejects new POS charge',"EXEC usp_Settle 10,4; DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,1,1,2,@c;",51015);
test('Unreconciled POS charge blocks settlement',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,1,1,2,@c; EXEC usp_Settle 10,4;",51303);
test('Reconciled POS charge settles to the right amount',"DECLARE @c uniqueidentifier=NEWID(); EXEC usp_SyncPOS 'AURORA-010',1,2,1,2,@c; DECLARE @t int=(SELECT TransactionId FROM Transactions WHERE ClientId=@c); EXEC usp_Reconcile @t,4; EXEC usp_Settle 10,4; IF NOT EXISTS(SELECT 1 FROM Invoices WHERE AccountId=10 AND Total=70000) THROW 51999,'Wrong invoice total',1;");
test('Account cannot close without invoice/payment',"UPDATE Accounts SET Status='SETTLED' WHERE AccountId=10;",51308);
test('Payment must match invoice total',"EXEC usp_Settle 10,4; UPDATE Payments SET Amount=1 WHERE InvoiceId=(SELECT InvoiceId FROM Invoices WHERE AccountId=10);",51307);
test('Itinerary update records history and notification',"DECLARE @arrival datetime2=(SELECT DATEADD(minute,5,Arrival) FROM Stops WHERE StopId=1),@departure datetime2=(SELECT Departure FROM Stops WHERE StopId=1); EXEC usp_ChangeStop 1,@arrival,@departure,N'Test weather',5; IF NOT EXISTS(SELECT 1 FROM ItineraryChanges WHERE Reason=N'Test weather') OR NOT EXISTS(SELECT 1 FROM Notifications WHERE Message LIKE N'%Test weather%') THROW 51999,'No change log',1;");
test('Itinerary refuses shore excursion conflict',"DECLARE @arrival datetime2=(SELECT DATEADD(hour,2,Arrival) FROM Stops WHERE StopId=1),@departure datetime2=(SELECT Departure FROM Stops WHERE StopId=1); EXEC usp_ChangeStop 1,@arrival,@departure,N'Test',5;",51023);
test('Admin cannot remove own admin role',"EXEC usp_ManageUser 1,N'Admin','admin@demo.local','POS',NULL,1,1;",51201);
test('Audit logs registration actor',"EXEC usp_Register 10,3; IF NOT EXISTS(SELECT 1 FROM AuditLog WHERE Entity='Registration' AND ActorId=(SELECT p.UserId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=10)) THROW 51999,'Missing actor',1;");
test('Ratings constrained to 1..5',"EXEC usp_CheckIn 2,'AURORA-001',2,3; UPDATE Activities SET Status='COMPLETED' WHERE ActivityId=2; EXEC usp_Feedback 1,1,6,N'Test';",547);
let failures=0;
for(const t of tests){try{await query('BEGIN TRAN; '+t.sql+' IF @@TRANCOUNT>0 ROLLBACK;');assert.equal(t.error,undefined,'Expected SQL error '+t.error);console.log('PASS '+t.name);}catch(e){if(t.error&&e.message.includes('['+t.error+']'))console.log('PASS '+t.name);else{failures++;console.error('FAIL '+t.name+' '+e.message);}}}
const check=await jsonQuery("SELECT COUNT(*) AS Tables,(SELECT COUNT(*) FROM sys.foreign_keys) AS ForeignKeys FROM sys.tables FOR JSON PATH");
// Independent SQL sessions race for the last seat. Only test-owned rows are removed.
let fixture;
try{
 fixture=(await jsonQuery("SELECT DATEADD(hour,12,CAST(EndDate AS datetime2)) AS StartTime,CruiseId FROM Cruises WHERE CruiseId=1 FOR JSON PATH"))[0];
 const created=await query("INSERT Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee) SELECT 1,1,N'CONCURRENCY_TEST', 'ONBOARD',DATEADD(hour,12,CAST(EndDate AS datetime2)),DATEADD(hour,13,CAST(EndDate AS datetime2)),1,100 FROM Cruises WHERE CruiseId=1; SELECT SCOPE_IDENTITY();");
 fixture.id=Number(created.trim());
 await Promise.all([query(`EXEC usp_Register 18,${fixture.id};`),query(`EXEC usp_Register 19,${fixture.id};`)]);
 const rows=await jsonQuery(`SELECT Status FROM Registrations WHERE ActivityId=${fixture.id} FOR JSON PATH`);
 assert.equal(rows.filter(r=>r.Status==='CONFIRMED').length,1);assert.equal(rows.filter(r=>r.Status==='WAITLIST').length,1);console.log('PASS Concurrent SQL sessions cannot oversell');
}catch(e){failures++;console.error('FAIL Concurrency '+e.message);}finally{if(fixture?.id)await query(`BEGIN TRAN; DELETE Transactions WHERE RegistrationId IN(SELECT RegistrationId FROM Registrations WHERE ActivityId=${fixture.id}); DELETE Registrations WHERE ActivityId=${fixture.id}; DELETE Activities WHERE ActivityId=${fixture.id}; COMMIT;`);}
console.log(JSON.stringify({tests:tests.length+1,failures,schema:check[0]}));if(failures)process.exitCode=1;
