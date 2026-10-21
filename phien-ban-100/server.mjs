import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {randomBytes,scryptSync,timingSafeEqual} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {query,jsonQuery,literal,procedure,hashPassword} from './src/db.mjs';
import QRCode from 'qrcode';
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'public');
const port=Number(process.env.PORT||3000),sessions=new Map(),attempts=new Map();
const num=(v,zero=false)=>{const n=Number(v);if(!Number.isSafeInteger(n)||n<(zero?0:1))throw Error('ID/số lượng không hợp lệ');return n;};
const text=(v,max=500)=>{if(typeof v!=='string'||v.length>max)throw Error('Nội dung quá dài/không hợp lệ');return v;};
const requireRoles=(u,...roles)=>{if(!u.roles.includes('ADMIN')&&!roles.some(r=>u.roles.includes(r)))throw Object.assign(Error('Không có quyền thao tác.'),{status:403});};
async function getUser(req){const sid=/aurora=([a-f0-9]+)/.exec(req.headers.cookie||'')?.[1],s=sessions.get(sid);if(!s||s.expires<Date.now()){sessions.delete(sid);return null;}
 const u=(await jsonQuery(`SELECT UserId,Name,Email,JSON_QUERY((SELECT r.Code FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=u.UserId FOR JSON PATH)) roles FROM Users u WHERE UserId=${s.userId} AND Active=1 FOR JSON PATH`))[0];
 if(!u){sessions.delete(sid);return null;}u.roles=u.roles.map(r=>r.Code);return u;
}
async function state(u){
 const guest=u.roles.includes('PASSENGER')&&!u.roles.includes('ADMIN'),finance=u.roles.some(r=>['ADMIN','FINANCE','OPERATIONS'].includes(r));
 const bs=guest?`SELECT b.BookingId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE p.UserId=${u.UserId}`:'SELECT BookingId FROM Bookings';
 const cs=guest?`SELECT CruiseId FROM Bookings WHERE BookingId IN(${bs})`:'SELECT CruiseId FROM Cruises';
 const rs=`SELECT RegistrationId FROM Registrations WHERE BookingId IN(${bs})`,acs=`SELECT AccountId FROM Accounts WHERE BookingId IN(${bs})`;
 const cols={
  cruises:`SELECT * FROM Cruises WHERE CruiseId IN(${cs})`,stops:`SELECT s.*,p.Name FROM Stops s JOIN Ports p ON p.PortId=s.PortId WHERE s.CruiseId IN(${cs})`,activities:`SELECT * FROM vw_ActivitySummary WHERE CruiseId IN(${cs})`,
  services:'SELECT * FROM Services',packages:'SELECT * FROM Packages',packageServices:'SELECT * FROM PackageServices',
  cabinExpenses:finance?'SELECT * FROM vw_CabinExpenses':'SELECT * FROM vw_CabinExpenses WHERE 1=0',
  guests:`SELECT b.*,p.UserId,u.Name,i.Code,pk.Name AS Package FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId JOIN Users u ON u.UserId=p.UserId OUTER APPLY(SELECT TOP(1) Code FROM Identifiers WHERE BookingId=b.BookingId AND Active=1 ORDER BY IdentifierId) i JOIN Packages pk ON pk.PackageId=b.PackageId WHERE b.BookingId IN(${bs})`,
  registrations:`SELECT * FROM Registrations WHERE BookingId IN(${bs})`,checkins:`SELECT * FROM CheckIns WHERE RegistrationId IN(${rs})`,
  notifications:`SELECT n.*,CAST(CASE WHEN nr.UserId IS NULL THEN 0 ELSE 1 END AS bit) AS IsRead FROM Notifications n LEFT JOIN NotificationReads nr ON nr.NotificationId=n.NotificationId AND nr.UserId=${u.UserId} WHERE n.CruiseId IN(${cs})`,
  feedback:`SELECT * FROM Feedback WHERE RegistrationId IN(${rs})`,cruiseFeedback:`SELECT * FROM CruiseFeedback WHERE BookingId IN(${bs})`,
  groups:`SELECT g.* FROM TourGroups g JOIN Activities a ON a.ActivityId=g.ActivityId WHERE a.CruiseId IN(${cs})`,groupMembers:`SELECT * FROM GroupMembers WHERE RegistrationId IN(${rs})`,
  accounts:guest||finance?`SELECT * FROM vw_AccountSummary WHERE BookingId IN(${bs})`:'SELECT * FROM vw_AccountSummary WHERE 1=0',
  transactions:guest||finance?`SELECT t.*,s.Name AS Service FROM Transactions t LEFT JOIN Services s ON s.ServiceId=t.ServiceId WHERE AccountId IN(${acs})`:'SELECT * FROM Transactions WHERE 1=0',
  invoices:guest||finance?`SELECT * FROM Invoices WHERE AccountId IN(${acs})`:'SELECT * FROM Invoices WHERE 1=0',payments:guest||finance?`SELECT p.* FROM Payments p JOIN Invoices i ON i.InvoiceId=p.InvoiceId WHERE i.AccountId IN(${acs})`:'SELECT * FROM Payments WHERE 1=0',
  disputes:guest||finance?`SELECT d.* FROM Disputes d JOIN Transactions t ON t.TransactionId=d.TransactionId WHERE AccountId IN(${acs})`:'SELECT * FROM Disputes WHERE 1=0',
  policy:'SELECT * FROM Policy',ships:'SELECT * FROM Ships',zones:'SELECT * FROM Zones',ports:'SELECT * FROM Ports',providers:'SELECT * FROM Providers',cabins:'SELECT * FROM Cabins',devices:guest?'SELECT * FROM Devices WHERE 1=0':'SELECT * FROM Devices',
  late:u.roles.some(r=>['ADMIN','OPERATIONS','SHORE'].includes(r))?'SELECT * FROM vw_LatePassengers':'SELECT * FROM vw_LatePassengers WHERE 1=0',revenue:finance?'SELECT * FROM vw_Revenue':'SELECT * FROM vw_Revenue WHERE 1=0',
  logs:u.roles.includes('ADMIN')?'SELECT TOP(200) * FROM AuditLog ORDER BY LogId DESC':'SELECT * FROM AuditLog WHERE 1=0',identifiers:u.roles.includes('ADMIN')?'SELECT * FROM Identifiers':'SELECT * FROM Identifiers WHERE 1=0',
  users:u.roles.includes('ADMIN')?'SELECT u.UserId,u.Name,u.Email,u.Active,r.Code AS Role FROM Users u JOIN UserRoles ur ON ur.UserId=u.UserId JOIN Roles r ON r.RoleId=ur.RoleId':'SELECT UserId,Name,Email,Active FROM Users WHERE 1=0',
  passengers:u.roles.includes('ADMIN')?'SELECT p.PassengerId,u.Name FROM Passengers p JOIN Users u ON u.UserId=p.UserId':'SELECT PassengerId FROM Passengers WHERE 1=0',ble:u.roles.some(r=>['ADMIN','OPERATIONS'].includes(r))?'SELECT * FROM vw_BLELatest':'SELECT * FROM vw_BLELatest WHERE 1=0',changes:guest?'SELECT * FROM ItineraryChanges WHERE 1=0':'SELECT * FROM ItineraryChanges',sync:finance||u.roles.includes('POS')?'SELECT * FROM SyncReceipts':'SELECT * FROM SyncReceipts WHERE 1=0'
 };
 const result=await jsonQuery('SELECT '+Object.entries(cols).map(([key,sql])=>`JSON_QUERY((${sql} FOR JSON PATH)) AS [${key}]`).join(',')+' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER');
 for(const key of Object.keys(cols))if(!Array.isArray(result[key]))result[key]=[];
 return result;
}
async function action(b,u){
 const actor=u.UserId;
 const own=async()=>{requireRoles(u,'PASSENGER');const id=num(b.bookingId);const rows=await jsonQuery(`SELECT b.BookingId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=${id} AND p.UserId=${actor} FOR JSON PATH`);if(!rows.length)throw Object.assign(Error('Đặt chỗ không thuộc tài khoản của bạn.'),{status:403});return id;};
 let proc,args;
 switch(b.action){
  case 'register':proc='usp_Register';args={BookingId:await own(),ActivityId:num(b.activityId)};break;
  case 'cancel':proc='usp_Cancel';args={BookingId:await own(),RegistrationId:num(b.registrationId)};break;
  case 'feedback':proc='usp_Feedback';args={BookingId:await own(),RegistrationId:num(b.registrationId),Rating:num(b.rating),Comment:text(b.comment)};break;
  case 'cruiseFeedback':proc='usp_CruiseFeedback';args={BookingId:await own(),Rating:num(b.rating),Comment:text(b.comment)};break;
  case 'dispute':proc='usp_Dispute';args={BookingId:await own(),TransactionId:num(b.transactionId),Reason:text(b.reason)};break;
  case 'checkin':requireRoles(u,'ACTIVITY','SHORE');proc='usp_CheckIn';args={ActivityId:num(b.activityId),Code:text(b.code,100),DeviceId:num(b.deviceId),StaffId:actor};break;
  case 'return':requireRoles(u,'SHORE');proc='usp_ReturnToShip';args={RegistrationId:num(b.registrationId),StaffId:actor};break;
  case 'groupMember':requireRoles(u,'SHORE');proc='usp_AssignGroup';args={RegistrationId:num(b.registrationId),GroupId:num(b.groupId),StaffId:actor};break;
  case 'pos':requireRoles(u,'POS');if(!/^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(b.clientId))throw Error('Mã đồng bộ không hợp lệ');proc='usp_SyncPOS';args={Code:text(b.code,100),ServiceId:num(b.serviceId),Quantity:num(b.quantity),DeviceId:num(b.deviceId),StaffId:actor,ClientId:b.clientId};break;
  case 'refund':case 'void':requireRoles(u,'FINANCE');proc='usp_FinanceTransaction';args={TransactionId:num(b.transactionId),StaffId:actor,Status:b.action==='void'?'VOID':'REFUNDED'};break;
  case 'settle':requireRoles(u,'FINANCE');proc='usp_Settle';args={AccountId:num(b.accountId),StaffId:actor};break;
  case 'resolve':requireRoles(u,'FINANCE');proc='usp_ResolveDispute';args={DisputeId:num(b.disputeId),StaffId:actor};break;
  case 'reconcile':requireRoles(u,'FINANCE');proc='usp_Reconcile';args={TransactionId:num(b.transactionId),StaffId:actor};break;
  case 'stop':requireRoles(u,'ITINERARY');proc='usp_ChangeStop';args={StopId:num(b.stopId),Arrival:text(b.arrival,40),Departure:text(b.departure,40),Reason:text(b.reason),StaffId:actor};break;
  case 'save':requireRoles(u,'ITINERARY','ACTIVITY','SHORE');proc='usp_SaveMaster';args={Entity:text(b.entity,30),Id:num(b.id||0,true),Data:JSON.stringify(b.data),StaffId:actor};break;
  case 'cancelActivity':requireRoles(u,'ACTIVITY','SHORE');proc='usp_CancelActivity';args={ActivityId:num(b.activityId),StaffId:actor};break;
  case 'booking':requireRoles(u,'ADMIN');proc='usp_BookPassenger';args={CruiseId:num(b.cruiseId),PassengerId:num(b.passengerId),CabinId:num(b.cabinId),PackageId:num(b.packageId),StaffId:actor};break;
  case 'user':requireRoles(u,'ADMIN');if(b.password&&b.password.length<8)throw Error('Mật khẩu tối thiểu 8 ký tự');proc='usp_ManageUser';args={UserId:num(b.id||0,true),Name:text(b.name,100),Email:text(b.email,150),Role:text(b.role,30),Hash:b.password?hashPassword(text(b.password,100)):null,Active:!!b.active,StaffId:actor};break;
  case 'packageService':requireRoles(u,'ADMIN');proc='usp_PackageService';args={PackageId:num(b.packageId),ServiceId:num(b.serviceId),Included:!!b.included,StaffId:actor};break;
  case 'notify':requireRoles(u,'ITINERARY','OPERATIONS');proc='usp_Notify';args={CruiseId:num(b.cruiseId),Message:text(b.message),StaffId:actor};break;
  case 'read':requireRoles(u,'PASSENGER');proc='usp_ReadNotification';args={NotificationId:num(b.notificationId),UserId:actor};break;
  default:throw Error('Nghiệp vụ không hỗ trợ');
 }
 return query(procedure(proc,args));
}
const server=http.createServer(async(req,res)=>{
 const send=(code,data)=>{res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data));};
 try{
  const url=new URL(req.url,`http://localhost:${port}`);
  if(req.method==='POST'&&req.headers.origin&&!([`http://localhost:${port}`,`http://127.0.0.1:${port}`].includes(req.headers.origin)))return send(403,{error:'Nguồn yêu cầu không hợp lệ'});
  let b={};if(req.method==='POST'){let raw='';for await(const x of req){raw+=x;if(raw.length>20000)return send(413,{error:'Yêu cầu quá lớn'});}b=JSON.parse(raw||'{}');}
  if(url.pathname==='/api/login'&&req.method==='POST'){
   const key=req.socket.remoteAddress,t=attempts.get(key)||{count:0,time:Date.now()};if(Date.now()-t.time>60000){t.count=0;t.time=Date.now();}t.count++;attempts.set(key,t);if(t.count>15)return send(429,{error:'Thử lại sau một phút.'});
   const rows=await jsonQuery(`SELECT UserId,PasswordHash FROM Users WHERE Email=${literal(text(b.email,150))} AND Active=1 FOR JSON PATH`);
   const stored=rows[0]?.PasswordHash;let valid=false;if(stored){const [salt,hash]=stored.split(':');const candidate=scryptSync(text(b.password,100),salt,64),target=Buffer.from(hash,'hex');valid=target.length===candidate.length&&timingSafeEqual(target,candidate);}
   if(!valid)return send(401,{error:'Email hoặc mật khẩu không đúng.'});
   const sid=randomBytes(32).toString('hex');sessions.set(sid,{userId:rows[0].UserId,expires:Date.now()+8*3600000});res.setHeader('Set-Cookie',`aurora=${sid}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800`);return send(200,{ok:true});
  }
  if(url.pathname==='/api/logout'&&req.method==='POST'){sessions.delete(/aurora=([a-f0-9]+)/.exec(req.headers.cookie||'')?.[1]);res.setHeader('Set-Cookie','aurora=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');return send(200,{ok:true});}
  if(url.pathname.startsWith('/api/')){
   const user=await getUser(req);if(!user)return send(401,{error:'Vui lòng đăng nhập.'});
   if(url.pathname==='/api/me')return send(200,user);
   if(url.pathname==='/api/qr'){
    const bid=num(url.searchParams.get('booking'));
    const rows=await jsonQuery(`SELECT TOP(1) i.Code FROM Identifiers i JOIN Bookings b ON b.BookingId=i.BookingId JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE i.BookingId=${bid} AND i.Active=1 AND ${user.roles.includes('ADMIN')?'1=1':`p.UserId=${user.UserId}`} ORDER BY i.IdentifierId FOR JSON PATH`);
    if(!rows.length)return send(403,{error:'Không có quyền xem mã.'});
    res.writeHead(200,{'Content-Type':'image/svg+xml','Cache-Control':'no-store'});return res.end(await QRCode.toString(rows[0].Code,{type:'svg',margin:2}));
   }
   if(url.pathname==='/api/state')return send(200,await state(user));
   if(url.pathname==='/api/action'&&req.method==='POST')return send(200,{ok:true,result:await action(b,user)});
   return send(404,{error:'API không tồn tại'});
  }
  if(req.method!=='GET')return send(405,{error:'Method không hỗ trợ'});
  const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':decodeURIComponent(url.pathname)));
  if(!file.startsWith(root+path.sep))return send(403,{error:'Không được phép'});
  const data=await readFile(file);res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json'})[path.extname(file)]||'application/octet-stream','X-Content-Type-Options':'nosniff','Cache-Control':'no-cache'});res.end(data);
 }catch(e){send(e.status||(e.code==='ENOENT'?404:400),{error:e.message});}
});
await query('SELECT 1;');
server.listen(port,'127.0.0.1',()=>console.log(`Aurora SQL Server: http://localhost:${port}`));
setInterval(()=>{for(const [id,s] of sessions)if(s.expires<Date.now())sessions.delete(id);},60000).unref();
