import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { normalize, structuredDefaults, loadSettings, saveSettings, controlBox, joystickVector, InputState } from './controls-model.js';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { loadGameAssets, safeEngineConfig } from './web-loader.js';

test('invalid or blocked saved settings fall back safely',()=>{
  assert.deepEqual(loadSettings({getItem(){throw Error('denied')}}),structuredDefaults());
  assert.deepEqual(loadSettings({getItem(){return '{broken'}}),structuredDefaults());
  assert.equal(saveSettings({setItem(){throw Error('quota')}},structuredDefaults()),false);
});
test('size and position settings persist and are bounded',()=>{
  const values=new Map(),storage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)};
  const prefs=structuredDefaults();prefs.joy={x:.35,y:.72,scale:1.6};prefs.fire={x:.8,y:.85,scale:1.4};
  assert.equal(saveSettings(storage,prefs),true);assert.deepEqual(loadSettings(storage),prefs);
  const invalid=normalize({joy:{x:-100,y:999,scale:Infinity},jump:{scale:99},opacity:0});
  assert.deepEqual(invalid.joy,{x:0,y:1,scale:1});assert.equal(invalid.jump.scale,1.7);assert.equal(invalid.opacity,.35);
});
for(const [width,height] of [[320,568],[390,844],[844,390],[1024,768],[1440,900]]) {
  test(`large controls stay on screen at ${width}x${height}`,()=>{
    for(const scale of [.7,1,1.7])for(const key of ['joy','jump','fire']) {
      const box=controlBox(key,{x:0,y:1,scale},width,height);
      assert.ok(box.x-box.radius>=7.9);assert.ok(box.x+box.radius<=width-7.9);
      assert.ok(box.y-box.radius>=67.9);assert.ok(box.y+box.radius<=height-7.9);
    }
  });
  test(`default controls do not overlap at ${width}x${height}`,()=>{
    const p=structuredDefaults(),boxes=['joy','jump','fire'].map(k=>controlBox(k,p[k],width,height));
    for(let i=0;i<3;i++)for(let j=i+1;j<3;j++)assert.ok(Math.hypot(boxes[i].x-boxes[j].x,boxes[i].y-boxes[j].y)>boxes[i].radius+boxes[j].radius);
  });
}
test('joystick uses deadzone, analog movement and bounded travel',()=>{
  assert.equal(joystickVector(2,0,50).axis,0);
  assert.equal(joystickVector(25,0,50).axis,.5);
  assert.equal(joystickVector(-200,0,50).axis,-1);
  const v=joystickVector(100,100,50);assert.ok(Math.abs(Math.hypot(v.x,v.y)-1)<1e-9);
});
test('three fingers independently hold joystick, fire and jump',()=>{
  const input=new InputState();input.down(1,'joy');input.move(1,30,0,50);input.down(2,'fire');
  assert.equal(input.down(3,'jump'),true);assert.deepEqual(input.snapshot(),{type:'input',axis:.6,fire:true});
  input.up(3);assert.equal(input.snapshot().fire,true);input.up(2);assert.equal(input.snapshot().axis,.6);
  input.up(1);assert.deepEqual(input.snapshot(),{type:'input',axis:0,fire:false});
});
test('cancel or backgrounding clears every held input',()=>{
  const input=new InputState();input.down(1,'joy');input.down(2,'fire');input.move(1,-50,0,50);
  input.reset();assert.deepEqual(input.snapshot(),{type:'input',axis:0,fire:false});assert.equal(input.pointers.size,0);
});
test('a second finger cannot steal the joystick or retrigger a held jump',()=>{
  const input=new InputState();input.down(1,'joy');input.move(1,50,0,50);
  input.down(2,'joy');assert.equal(input.move(2,-50,0,50),null);assert.equal(input.snapshot().axis,1);
  input.up(1);assert.equal(input.snapshot().axis,0);assert.equal(input.pointers.has(2),false);
  assert.equal(input.down(3,'jump'),true);assert.equal(input.down(3,'jump'),false);
});
test('invalid joystick geometry never creates a latched or non-finite axis',()=>{
  for(const values of [[0,0,0],[Infinity,0,50],[20,NaN,50],[20,0,-1]])assert.deepEqual(joystickVector(...values),{x:0,y:0,axis:0});
});
test('Web engine audio is Dummy, fixed canvas, and no service worker',()=>{
  const config=safeEngineConfig({args:['bad'],canvasResizePolicy:2,serviceWorker:'old.js'});
  assert.deepEqual(config.args,['--audio-driver','Dummy']);assert.equal(config.canvasResizePolicy,0);assert.equal(config.serviceWorker,undefined);
});
test('restart is explicit and runtime errors stay visible',()=>{
  const ui=fs.readFileSync(new URL('./touch-ui.js',import.meta.url),'utf8');
  assert.equal((ui.match(/location\.reload\(/g)||[]).length,1);
  assert.ok(ui.includes("$('error-reload').addEventListener('click'"));
  assert.match(ui,/\$\('error'\)\.hidden\s*=\s*false;\s*receiver\s*=\s*null;/);
});

const pageURL='https://example.com/play/index.html';
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
function assets() {
  const pack=Uint8Array.of(0x47,0x44,0x50,0x4b);
  const chunks=[Uint8Array.of(0,97,115,109),Uint8Array.of(1,2,3,4,5),Uint8Array.of(61,40,8)];
  const wasmParts=chunks.map((bytes,i)=>({url:'wasm/'+i+'.gz.bin',rawUrl:'wasm/'+i+'.bin',bytes:bytes.length,
    compressedBytes:gzipSync(bytes).length,sha256:digest(bytes)}));
  const config={fileSizes:{'game.wasm':chunks.reduce((n,c)=>n+c.length,0),'game.pck':pack.length},packSha256:digest(pack),wasmParts};
  const calls=[];
  const body=(url)=>{
    if(url.includes('game.pck'))return pack;
    const bytes=chunks[Number(url.match(/wasm\/(\d+)/)[1])];
    return url.includes('.gz.')?gzipSync(bytes):bytes;
  };
  function run(serve, options={}) {
    return loadGameAssets(config,pageURL,{retryDelayMs:0,...options, fetchImpl:async (url,init)=>{
      calls.push({url,init});return serve?serve(url,init):new Response(body(url));
    }});
  }
  return {config,pack,chunks,calls,run,body};
}

test('verified gzip chunks assemble in manifest order and keep the pack separate',async()=>{
  const a=assets(), progress=[];
  const saved=globalThis.fetch;
  let pending=0,peak=0;
  const result=await a.run(async url=>{
    pending++;peak=Math.max(peak,pending);
    await new Promise(r=>setTimeout(r,url.includes('0.gz')?20:1));
    pending--;return new Response(a.body(url));
  },{onProgress:event=>progress.push(event)});
  assert.deepEqual([...result.wasm],a.chunks.flatMap(c=>[...c]));
  assert.deepEqual(result.pack,a.pack);
  assert.equal(peak,2);assert.equal(globalThis.fetch,saved);
  assert.ok(a.calls.some(c=>c.url==='https://example.com/play/game.pck?v='+a.config.packSha256));
  assert.ok(a.calls.filter(c=>c.url.includes('/wasm/')).every(c=>c.url.includes('.gz.bin')));
  assert.ok(progress.every((p,i)=>p.total===16 && p.loaded >= (progress[i-1]?.loaded??0)));
  assert.equal(progress.at(-1).loaded,16);
});

test('a browser lacking gzip streams uses raw verified chunks; transparent server decoding also works',async()=>{
  const raw=assets(), plain=await raw.run(undefined,{DecompressionStreamImpl:null});
  assert.ok(raw.calls.every(c=>!c.url.includes('.gz.')));
  const encoded=assets();
  const decoded=await encoded.run(url=>new Response(encoded.body(url.replace('.gz.bin','.bin')),
    {headers:{'Content-Encoding':'gzip'}}));
  assert.deepEqual(decoded,plain);
});

test('a mid-body Safari Load failed retries only its own chunk without counting partial bytes',async()=>{
  const a=assets(), stats=[];
  let n=0;
  const result=await a.run(url=>{
    const bytes=a.body(url);
    if(!url.includes('1.gz')||++n!==1)return new Response(bytes);
    let sent=false;
    return new Response(new ReadableStream({pull(writer){
      if(!sent){writer.enqueue(bytes.subarray(0,4));sent=true;}
      else writer.error(new TypeError('Load failed'));
    }}));
  },{onProgress:e=>stats.push(e)});
  assert.deepEqual([...result.wasm],a.chunks.flatMap(c=>[...c]));
  assert.equal(a.calls.length,5);
  assert.equal(a.calls.filter(c=>c.url.includes('1.gz')&&c.init.cache==='reload').length,1);
  const successes=stats.filter((p,i)=>p.loaded>(stats[i-1]?.loaded??0));
  assert.equal(successes.length,4);
  assert.equal(successes.find(e=>e.label.includes('1.gz')).attempt,2);
});

test('transient status, compressed truncation, wrong raw digest, and same-size bad pack recover independently',async()=>{
  const a=assets(), seen=new Map();
  const result=await a.run(url=>{
    const first=!seen.has(url);seen.set(url,(seen.get(url)||0)+1);
    const bytes=a.body(url);
    if(first&&url.includes('game.pck'))return new Response(bytes.map(b=>b^4));
    if(first&&url.includes('0.gz'))return new Response(bytes.subarray(0,bytes.length-2));
    if(first&&url.includes('1.gz'))return new Response('',{status:503});
    if(first&&url.includes('2.gz'))return new Response(gzipSync(a.chunks[2].map(b=>b^1)));
    return new Response(bytes);
  });
  assert.deepEqual(result.pack,a.pack);assert.deepEqual([...result.wasm],a.chunks.flatMap(c=>[...c]));
  assert.ok([...seen.values()].every(count=>count===2));
});

test('a permanently corrupt chunk reports its name, attempt limit and SHA cause',async()=>{
  const a=assets();
  await assert.rejects(a.run(url=>new Response(url.includes('1.bin')?a.body(url).map(b=>b^1):a.body(url)),
    {DecompressionStreamImpl:null}),/1\.bin.*第 3\/3 次.*SHA-256/);
  assert.equal(a.calls.filter(c=>c.url.endsWith('/1.bin')).length,3);
});

for(const response of [
  ()=>new Response(null,{status:401}),()=>new Response(null,{status:403}),
  ()=>new Response(null,{status:404}),()=>new Response('<html>login</html>',{headers:{'Content-Type':'text/html'}}),
  ()=>new Response(new TextEncoder().encode('<!DOCTYPE html>login'))
]){
  test('permanent HTTP or HTML response stops the queue immediately: '+String(response),async()=>{
    const a=assets();
    await assert.rejects(a.run(url=>url.includes('game.pck')?response():new Response(a.body(url))),/game.pck.*第 1\/3 次.*(401|403|404|网页)/);
    assert.equal(a.calls.filter(c=>c.url.includes('game.pck')).length,1);
    assert.ok(a.calls.length<=2);
  });
}

test('deadline includes a stalled body and retry cancels the old reader',async()=>{
  const a=assets();
  let times=0,cancelled=0;
  const result=await a.run(url=>{
    if(url.includes('0.gz') && ++times===1)return new Response(new ReadableStream({
      start(c){c.enqueue(a.body(url).subarray(0,2));},cancel(){cancelled++;}
    }));
    return new Response(a.body(url));
  },{timeoutMs:30});
  assert.equal(cancelled,1);assert.equal(times,2);
  assert.deepEqual([...result.wasm],a.chunks.flatMap(c=>[...c]));
});

test('an entirely unresponsive fetch cannot strand retries or report unverified bytes',async()=>{
  const a=assets(),progress=[];
  await assert.rejects(a.run(url=>url.includes('0.gz')?new Promise(()=>{}):new Response(a.body(url)),
    {timeoutMs:20,maxAttempts:2,onProgress:e=>progress.push(e)}),/0\.gz\.bin.*第 2\/2 次.*超时/);
  assert.ok(progress.every(p=>p.loaded<=p.total-4));
});

test('unrelated fetches are never patched and invalid build metadata never makes a request',async()=>{
  const a=assets();
  a.config.fileSizes['game.wasm']++;
  await assert.rejects(a.run(),/总长度/);
  assert.equal(a.calls.length,0);
});
