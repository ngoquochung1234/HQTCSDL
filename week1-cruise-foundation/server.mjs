import http from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'public');
const port=Number(process.env.PORT||3000);
const contentTypes={
  '.html':'text/html; charset=utf-8',
  '.css':'text/css; charset=utf-8',
  '.js':'text/javascript; charset=utf-8',
  '.json':'application/json; charset=utf-8'
};

const server=http.createServer(async(req,res)=>{
  try{
    if(req.method!=='GET'){
      res.writeHead(405,{'Content-Type':'application/json; charset=utf-8'});
      res.end(JSON.stringify({error:'Method không hỗ trợ'}));
      return;
    }
    const url=new URL(req.url,`http://localhost:${port}`);
    const requested=url.pathname==='/'?'/index.html':decodeURIComponent(url.pathname);
    const file=path.resolve(root,'.'+requested);
    if(!file.startsWith(root+path.sep)){
      res.writeHead(403,{'Content-Type':'application/json; charset=utf-8'});
      res.end(JSON.stringify({error:'Không được phép truy cập'}));
      return;
    }
    const data=await readFile(file);
    res.writeHead(200,{
      'Content-Type':contentTypes[path.extname(file)]||'application/octet-stream',
      'X-Content-Type-Options':'nosniff'
    });
    res.end(data);
  }catch(error){
    const status=error.code==='ENOENT'?404:500;
    res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});
    res.end(JSON.stringify({error:status===404?'Không tìm thấy tài nguyên':'Lỗi máy chủ'}));
  }
});

server.listen(port,'127.0.0.1',()=> {
  console.log(`Aurora Week 1: http://localhost:${port}`);
});
