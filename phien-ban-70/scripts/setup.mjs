import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {query,hashPassword,literal} from '../src/db.mjs';
const base=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const exists=await query("SELECT CASE WHEN OBJECT_ID('dbo.Ships') IS NULL THEN 0 ELSE 1 END;").catch(()=> '0');
const files=exists.trim()==='1'?['02-business.sql','04-complete.sql','05-api.sql','06-integrity.sql','07-demo.sql']:['01-schema.sql','02-business.sql','03-seed.sql','04-complete.sql','05-api.sql','06-integrity.sql','07-demo.sql'];
for(const file of files){const r=spawnSync('sqlcmd',['-S',process.env.SQL_SERVER||'.','-E','-C','-I','-b','-f','65001','-i',path.join(base,'database',file)],{encoding:'utf8',windowsHide:true});if(r.status!==0)throw Error(r.stderr||r.stdout);console.log('OK '+file);}
await query(`UPDATE Users SET PasswordHash=${literal(hashPassword('Aurora123!'))} WHERE PasswordHash IS NULL;`);
console.log('Database CruiseCourseworkV2 sẵn sàng. Mật khẩu demo: Aurora123!');
