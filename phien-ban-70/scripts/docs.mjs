import {mkdir,writeFile} from 'node:fs/promises';
import {jsonQuery} from '../src/db.mjs';
const columns=await jsonQuery(`SELECT t.name AS TableName,c.name AS ColumnName,ty.name AS Type,c.max_length AS MaxLength,c.precision AS Precision,c.scale AS Scale,c.is_nullable AS Nullable,c.is_identity AS IsIdentity,CAST(CASE WHEN EXISTS(SELECT 1 FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id WHERE i.object_id=t.object_id AND i.is_primary_key=1 AND ic.column_id=c.column_id) THEN 1 ELSE 0 END AS bit) AS IsPrimaryKey,dc.definition AS DefaultValue FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id JOIN sys.types ty ON ty.user_type_id=c.user_type_id LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id ORDER BY t.name,c.column_id FOR JSON PATH`);
const fks=await jsonQuery(`SELECT OBJECT_NAME(f.parent_object_id) AS Child,c.name AS ChildColumn,OBJECT_NAME(f.referenced_object_id) AS Parent,p.name AS ParentColumn FROM sys.foreign_key_columns f JOIN sys.columns c ON c.object_id=f.parent_object_id AND c.column_id=f.parent_column_id JOIN sys.columns p ON p.object_id=f.referenced_object_id AND p.column_id=f.referenced_column_id FOR JSON PATH`);
const objects=await jsonQuery("SELECT name,type_desc FROM sys.objects WHERE type IN('P','V','TR','FN') AND is_ms_shipped=0 ORDER BY type,name FOR JSON PATH");
const names=[...new Set(columns.map(c=>c.TableName))];
let dictionary='# Từ điển dữ liệu\n\nĐược sinh từ metadata SQL Server đang chạy, không suy đoán cấu trúc.\n\n';
function type(c){if(['nvarchar','varchar','varbinary'].includes(c.Type))return `${c.Type}(${c.MaxLength===-1?'max':c.Type==='nvarchar'?c.MaxLength/2:c.MaxLength})`;if(c.Type==='decimal')return `decimal(${c.Precision},${c.Scale})`;return c.Type;}
for(const name of names){dictionary+=`## ${name}\n\n| Trường | Kiểu | Khóa | Nullable | Mặc định |\n|---|---|---|---|---|\n`;
 for(const c of columns.filter(c=>c.TableName===name)){const ref=fks.find(f=>f.Child===name&&f.ChildColumn===c.ColumnName);dictionary+=`| ${c.ColumnName} | ${type(c)}${c.IsIdentity?' IDENTITY':''} | ${c.IsPrimaryKey?'PK ':''}${ref?'FK → '+ref.Parent+'.'+ref.ParentColumn:''} | ${c.Nullable?'Có':'Không'} | ${(c.DefaultValue||'').replaceAll('|','\\|')} |\n`;}
 dictionary+='\n';
}
let erd=`# ERD đầy đủ\n\n${names.length} bảng và ${fks.length} khóa ngoại. Một hành khách có thể tham gia nhiều chuyến; mỗi đặt chỗ có một tài khoản chi tiêu. Một tài khoản tạo tối đa một hóa đơn cuối chuyến.\n\n\`\`\`mermaid\nerDiagram\n`;
for(const name of names){erd+=`    ${name} {\n`;for(const c of columns.filter(c=>c.TableName===name))erd+=`        ${c.Type} ${c.ColumnName}${c.IsPrimaryKey?' PK':fks.some(f=>f.Child===name&&f.ChildColumn===c.ColumnName)?' FK':''}\n`;erd+='    }\n';}
for(const f of fks)erd+=`    ${f.Parent} ||--o{ ${f.Child} : "${f.ChildColumn}"\n`;
erd+='```\n\nKý hiệu cạnh biểu diễn khóa ngoại. Một số quan hệ bị giới hạn thành 1–1 bởi UNIQUE; xem script và từ điển dữ liệu để biết ràng buộc chính xác.\n';
let obj='# Đối tượng T-SQL\n\n| Tên | Loại |\n|---|---|\n'+objects.map(o=>`| ${o.name} | ${o.type_desc} |`).join('\n')+'\n';
await mkdir('docs',{recursive:true});await Promise.all([writeFile('docs/DICTIONARY.md',dictionary),writeFile('docs/ERD.md',erd),writeFile('docs/TSQL-OBJECTS.md',obj)]);
console.log(`Documented ${names.length} tables, ${fks.length} foreign keys, ${objects.length} SQL objects.`);
