import {readFile,writeFile,mkdir,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {query,jsonQuery} from '../src/db.mjs';
const name='CruiseInstallCheck_'+Date.now();
const files=['01-schema.sql','02-business.sql','03-seed.sql','04-complete.sql','05-api.sql','06-integrity.sql','07-demo.sql'];
await mkdir('.tmp',{recursive:true});
let created=false;
try{
 for(const file of files){const source=(await readFile('database/'+file,'utf8')).replaceAll('CruiseCourseworkV3',name);const temp='.tmp/install-'+file;await writeFile(temp,'\uFEFF'+source,'utf8');const r=spawnSync('sqlcmd',['-S',process.env.SQL_SERVER||'.','-E','-C','-I','-b','-f','65001','-i',temp],{encoding:'utf8',windowsHide:true});if(file==='01-schema.sql'&&r.status===0)created=true;await unlink(temp);if(r.status!==0)throw Error(r.stderr||r.stdout);console.log('CLEAN INSTALL PASS '+file);}
 process.env.SQL_DATABASE=name;
 const s=await jsonQuery('SELECT COUNT(*) AS Tables,(SELECT COUNT(*) FROM sys.foreign_keys) ForeignKeys FROM sys.tables FOR JSON PATH');
 console.log(JSON.stringify(s[0]));
 const r=spawnSync(process.execPath,['tests/database.mjs'],{env:{...process.env,SQL_DATABASE:name},encoding:'utf8',windowsHide:true});console.log(r.stdout);if(r.status!==0)throw Error(r.stderr||r.stdout);
}finally{
 // Only this process's newly-created, uniquely named verification database.
 // No reset/drop ever targets the coursework database or an existing database.
 if(created){process.env.SQL_DATABASE='master';await query(`DROP DATABASE [${name}];`);console.log('Temporary install verification database removed.');}
}
