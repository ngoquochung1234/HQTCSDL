import {build} from 'esbuild';
await build({entryPoints:['public/app.js'],bundle:true,outfile:'public/dist/app.js',minify:true,platform:'browser',target:'es2020',define:{'process.env.NODE_ENV':'"production"'}});
console.log('React frontend built: public/dist/app.js');
