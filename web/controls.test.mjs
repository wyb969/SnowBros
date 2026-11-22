import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { normalize, structuredDefaults, loadSettings, saveSettings, controlBox, joystickVector, InputState } from './controls-model.js';
import { createGameFetch, safeEngineConfig } from './web-loader.js';

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
test('engine streaming concatenates both files sequentially without Blob copies',async()=>{
  const calls=[];
  const fetch=createGameFetch(async url=>{
    calls.push(url);return new Response(new Uint8Array(url.includes('part0')?[0,97,115,109]:[1,2,3]));
  },'https://example.com/game.html','test-build',7);
  const response=await fetch('game.wasm');
  assert.equal(response.headers.get('Content-Type'),'application/wasm');
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[0,97,115,109,1,2,3]);
  assert.ok(calls[0].includes('part0?v=test-build'));assert.ok(calls[1].includes('part1?v=test-build'));
});
test('missing engine part surfaces a load error',async()=>{
  const fetch=createGameFetch(async url=>url.includes('part0')?new Response(new Uint8Array([1])):new Response('',{status:404}),'https://example.com/game.html','test',2);
  const response=await fetch('game.wasm');await assert.rejects(()=>response.arrayBuffer(),/加载失败/);
});
test('game pack requests bypass stale release cache',async()=>{
  let received;const fetch=createGameFetch(async url=>{received=url;return new Response('ok')},'https://example.com/game.html','next',1);
  await fetch('game.pck?v=old');assert.ok(received.endsWith('game.pck?v=next'));
});
test('restart is explicit and runtime errors stay visible',()=>{
  const ui=fs.readFileSync(new URL('./touch-ui.js',import.meta.url),'utf8');
  assert.equal((ui.match(/location\.reload\(/g)||[]).length,1);
  assert.ok(ui.includes("$('error-reload').addEventListener('click'"));
  assert.ok(ui.includes("$('error').hidden=false; receiver=null;"));
});
