import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root=new URL('../',import.meta.url),output=new URL('ios/SnakeClash/Game/',root);
await mkdir(output,{recursive:true});
let html=await readFile(new URL('public/index.html',root),'utf8');
html=html.replace('<script type="module" src="/game.js"></script>','<script src="game.js"></script>').replaceAll('href="/','href="').replace(/<link rel="manifest"[^>]*>/,'').replace('<p><b>On iPad:</b> In Safari, use Share → Add to Home Screen for an app-like experience.</p>', '<p><b>Made for iPad:</b> Play offline, steer with one finger, and hold BOOST with another.</p>').replace('NO DOWNLOADS. JUST ONE MORE ROUND.', 'MADE FOR IPAD. ALWAYS READY TO PLAY.');
// Classic bundle avoids module-origin restrictions for WKWebView's local files.
const engine=(await readFile(new URL('public/engine.js',root),'utf8')).replaceAll('export ','');
const game=(await readFile(new URL('public/game.js',root),'utf8')).replace(/^import .*?;\n/,'').replace("if('serviceWorker' in navigator)","if(location.protocol!=='file:' && 'serviceWorker' in navigator)");
await writeFile(new URL('index.html',output),html);
await writeFile(new URL('game.js',output),'(()=>{\n'+engine+'\n'+game+'\n})();\n');
const css=(await readFile(new URL('public/style.css',root),'utf8')).replace(/^@import .*?;\n/,'');
await writeFile(new URL('style.css',output),css);
await copyFile(new URL('public/icon.svg',root),new URL('icon.svg',output));
console.log('Bundled offline iPad game in '+fileURLToPath(output));
