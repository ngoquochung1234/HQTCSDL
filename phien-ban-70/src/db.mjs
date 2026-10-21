import {spawn} from 'node:child_process';
import {randomBytes,scryptSync} from 'node:crypto';
import {readFileSync} from 'node:fs';
const errors=new Map();
for(const name of ['01-schema.sql','02-business.sql','04-complete.sql','05-api.sql','06-integrity.sql']){
 const source=readFileSync(new URL('../database/'+name,import.meta.url),'utf8');
 for(const m of source.matchAll(/THROW\s+(\d+),\s*N'((?:[^']|'')*)'/g))errors.set(Number(m[1]),m[2].replaceAll("''","'"));
}
for(const [code,message] of [[2627,'Dữ liệu đã tồn tại (khóa duy nhất).'],[2601,'Dữ liệu đã tồn tại (chỉ mục duy nhất).'],[547,'Dữ liệu vi phạm khóa ngoại hoặc ràng buộc.'],[515,'Thiếu trường bắt buộc.'],[245,'Kiểu dữ liệu không hợp lệ.']])errors.set(code,message);
function sqlError(raw){const code=Number(/Msg\s+(\d+)/.exec(raw)?.[1]);return Object.assign(Error(errors.has(code)?`[${code}] ${errors.get(code)}`:raw),{status:code?400:503});}
export const literal=value=>value===null?'NULL':typeof value==='number'?String(value):typeof value==='boolean'?(value?'1':'0'):`CAST(0x${Buffer.from(String(value),'utf16le').toString('hex')} AS nvarchar(max))`;
export function procedure(name,args){if(!/^usp_[A-Za-z]+$/.test(name))throw Error('Invalid procedure');return Object.entries(args).map(([key,value],i)=>{if(!/^[A-Za-z]+$/.test(key))throw Error('Invalid parameter');return `DECLARE @p${i} ${typeof value==='number'?'int':typeof value==='boolean'?'bit':'nvarchar(max)'}=${literal(value)};`;}).join('\n')+`\nEXEC dbo.${name} `+Object.keys(args).map((key,i)=>`@${key}=@p${i}`).join(',')+';';}
export function hashPassword(password){const salt=randomBytes(16).toString('hex');return salt+':'+scryptSync(password,salt,64).toString('hex');}
export function query(sql){return new Promise((resolve,reject)=>{
 if(sql.length>28000)return reject(Error('Yêu cầu SQL quá lớn.'));
 const proc=spawn(process.env.SQLCMD_PATH||'sqlcmd',['-S',process.env.SQL_SERVER||'.','-d',process.env.SQL_DATABASE||'CruiseCourseworkV2','-E','-C','-I','-b','-l','5','-f','65001','-y','0','-w','65535','-Q','SET NOCOUNT ON; '+sql],{windowsHide:true});
 const stdout=[],stderr=[];const timer=setTimeout(()=>{proc.kill();reject(Error('SQL Server quá thời gian chờ.'));},20000);proc.stdout.on('data',x=>stdout.push(x));proc.stderr.on('data',x=>stderr.push(x));proc.on('error',e=>{clearTimeout(timer);reject(e);});proc.on('close',code=>{clearTimeout(timer);const out=Buffer.concat(stdout).toString('utf8').replace(/^\uFEFF/,'').trim(),err=Buffer.concat(stderr).toString('utf8').trim();if(code)reject(sqlError(err||out));else resolve(out);});
});}
// Hidden Windows consoles may replace Vietnamese glyphs. Transfer JSON as
// ASCII hexadecimal UTF-16 bytes so the console code page cannot alter data.
export async function jsonQuery(sql){const raw=(await query(`SELECT CONVERT(varchar(max),CONVERT(varbinary(max),(${sql})),2);`)).replace(/\s/g,'');return JSON.parse(Buffer.from(raw,'hex').toString('utf16le')||'[]');}
