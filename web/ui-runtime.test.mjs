// DOM model tests: no browser is launched and no iPhone QA is implied.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import * as model from './controls-model.js';
import * as loader from './web-loader.js';
class Element {
  constructor(id='') { this.id=id;this.style={};this.hidden=['error','edit-bar'].includes(id);this.open=false;this.value='100';this.dataset={};this.events={};this.attributes={};this.children=[];this.paused=true;this.captures=new Set();const classes=new Set();this.classList={add:v=>classes.add(v),remove:v=>classes.delete(v),contains:v=>classes.has(v),toggle:(v,on)=>on?classes.add(v):classes.delete(v)}; }
  addEventListener(name,fn){(this.events[name]??=[]).push(fn)}
  emit(name,values={}){for(const fn of this.events[name]??[])fn({preventDefault(){},...values})}
  setAttribute(key,value){this.attributes[key]=value}
  setPointerCapture(id){if(this.captureFails)throw Error('capture unavailable');this.captures.add(id)}
  hasPointerCapture(id){return this.captures.has(id)}
  releasePointerCapture(id){this.captures.delete(id)}
  focus(){}
  showModal(){this.open=true}
  close(){this.open=false}
  appendChild(e){this.children.push(e)}
  getBoundingClientRect(){return this.id==='toolbar'?{bottom:60,width:844,height:60}:{left:0,top:60,width:844,height:330}}
  play(){this.paused=false;return Promise.resolve()}
  pause(){this.paused=true}
}
async function setup(nativeTouch=false) {
  const elements=new Map(),el=id=>{if(!elements.has(id))elements.set(id,new Element(id));return elements.get(id)};
  const selectors=['joy','jump','fire'].map(k=>{const e=new Element();e.dataset.select=k;return e});
  const storage=new Map(),session=new Map();
  const localStorage={getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};
  const sessionStorage={getItem:k=>session.get(k),setItem:(k,v)=>session.set(k,v),removeItem:k=>session.delete(k)};
  const document=Object.assign(new Element(),{body:new Element(),hidden:false,getElementById:el,createElement:()=>new Element(),querySelector:q=>el(q==='.toolbar'?'toolbar':'help-details'),querySelectorAll:()=>selectors});
  const commands=[];let reloads=0,audioStarts=0,capturedConfig;
  const window=new Element();Object.assign(window,{innerWidth:844,innerHeight:390,location:{href:'https://example.com/game.html',reload(){reloads++}},fetch:async()=>new Response(''),GODOT_CONFIG:{fileSizes:{'game.wasm':7}},visualViewport:new Element(),AudioContext:class{constructor(){audioStarts++;this.state='suspended'}resume(){this.state='running';return Promise.resolve()}suspend(){this.state='suspended';return Promise.resolve()}}});
  if(nativeTouch)window.ontouchstart=null;
  let state={state:'title',paused:false,practice:false,case:0,score:0,lives:3};
  class Engine {
    static getMissingFeatures(){return []}
    constructor(config){capturedConfig=config}
    async startGame(){window.SnowBro.attach(value=>{
      const command=JSON.parse(value);commands.push(command);
      if(command.type==='start'||command.type==='restart')state={...state,state:'play',paused:false};
      if(command.type==='pause')state.paused=command.paused;
      if(command.type==='practice')state={...state,state:'play',paused:false,practice:true,case:command.case};
      queueMicrotask(()=>window.SnowBro.update(JSON.stringify(state)));
    });}
  }
  const source=fs.readFileSync(new URL('./touch-ui.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
  const context={...model,...loader,window,document,localStorage,sessionStorage,Engine,Response,ReadableStream,URL,queueMicrotask,getComputedStyle:()=>({paddingLeft:'0',paddingRight:'0',paddingBottom:'0'}),navigator:{maxTouchPoints:nativeTouch?5:0,userAgent:'iPhone DOM test',clipboard:{writeText:async()=>{}}},console};
  vm.runInNewContext(source,context);await new Promise(setImmediate);await new Promise(setImmediate);
  return {el,selectors,window,document,commands,storage,stats:()=>({reloads,audioStarts,config:capturedConfig})};
}
test('first click and repeated starts never reload or create audio while silent',async()=>{
  const ui=await setup();assert.equal(ui.el('start').disabled,false);
  for(let i=0;i<50;i++)ui.el('start').emit('click');
  await new Promise(setImmediate);
  assert.equal(ui.stats().reloads,0);assert.equal(ui.stats().audioStarts,0);
  assert.equal(ui.el('error').hidden,true);assert.equal(ui.el('menu').hidden,true);
  assert.deepEqual(ui.stats().config.args,['--audio-driver','Dummy']);
});
test('settings can resize, drag and save a button, then resume game',async()=>{
  const ui=await setup();ui.el('start').emit('click');await new Promise(setImmediate);
  ui.el('settings-open').emit('click');assert.equal(ui.el('settings').open,true);
  ui.selectors[2].emit('click');ui.el('control-size').value='150';ui.el('control-size').emit('input');
  let prefs=JSON.parse(ui.storage.get(model.STORAGE_KEY));assert.equal(prefs.fire.scale,1.5);
  ui.el('drag-layout').emit('click');assert.equal(ui.el('edit-bar').hidden,false);
  ui.el('fire').emit('pointerdown',{pointerId:9,clientX:760,clientY:320});
  ui.window.emit('pointermove',{pointerId:9,buttons:1,clientX:700,clientY:240});
  ui.el('fire').emit('pointerup',{pointerId:9});ui.el('edit-done').emit('click');
  prefs=JSON.parse(ui.storage.get(model.STORAGE_KEY));assert.ok(prefs.fire.x<.9);assert.ok(prefs.fire.y<.87);
  assert.equal(ui.el('edit-bar').hidden,true);assert.equal(ui.el('error').hidden,true);
  assert.ok(ui.commands.some(c=>c.type==='pause'&&c.paused===false));
});
test('joystick, jump and fire hold independently in UI handlers',async()=>{
  const ui=await setup();ui.el('start').emit('click');await new Promise(setImmediate);
  ui.el('joy').emit('pointerdown',{pointerId:1,clientX:160,clientY:310});
  ui.el('fire').emit('pointerdown',{pointerId:2,clientX:760,clientY:320});
  ui.el('jump').emit('pointerdown',{pointerId:3,clientX:560,clientY:250});
  assert.ok(ui.commands.some(c=>c.type==='jump'));
  let input=ui.commands.filter(c=>c.type==='input').at(-1);assert.equal(input.fire,true);assert.ok(input.axis>0);
  ui.el('joy').emit('pointercancel',{pointerId:1});input=ui.commands.filter(c=>c.type==='input').at(-1);assert.equal(input.axis,0);assert.equal(input.fire,true);
  ui.el('fire').emit('lostpointercapture',{pointerId:2});input=ui.commands.filter(c=>c.type==='input').at(-1);assert.equal(input.fire,false);
  assert.equal(ui.stats().reloads,0);
});
test('native callback failure produces a persistent error without recursion',async()=>{
  const ui=await setup();ui.window.SnowBro.attach(()=>{throw Error('test callback failure')});await new Promise(setImmediate);
  assert.equal(ui.el('error').hidden,false);assert.ok(ui.el('error-detail').textContent.includes('test callback failure'));assert.equal(ui.stats().reloads,0);
});
const lastInput=ui=>ui.commands.filter(c=>c.type==='input').at(-1);
async function play(nativeTouch=false){const ui=await setup(nativeTouch);ui.el('start').emit('click');await new Promise(setImmediate);return ui}
test('global release recenters joystick outside its original control without releasing fire',async()=>{
  const ui=await play();
  ui.el('joy').emit('pointerdown',{pointerId:1,pointerType:'touch',clientX:170,clientY:310});
  ui.el('fire').emit('pointerdown',{pointerId:2,pointerType:'touch',clientX:760,clientY:320});
  ui.window.emit('pointermove',{pointerId:1,pointerType:'touch',buttons:1,clientX:500,clientY:200});
  ui.window.emit('pointerup',{pointerId:1,pointerType:'touch'});
  assert.equal(lastInput(ui).axis,0);assert.equal(lastInput(ui).fire,true);
  assert.equal(ui.el('joy-knob').style.transform,'translate(0,0)');assert.equal(ui.el('joy').classList.contains('pressed'),false);
  assert.equal(ui.el('joy').captures.size,0);
  ui.window.emit('pointermove',{pointerId:1,pointerType:'touch',clientX:500,clientY:200});assert.equal(lastInput(ui).axis,0);
});
test('failed capture and missed mouse release recover on global hover or cancel',async()=>{
  const ui=await play();ui.el('joy').captureFails=true;
  ui.el('joy').emit('pointerdown',{pointerId:1,pointerType:'mouse',buttons:1,clientX:170,clientY:310});
  assert.ok(lastInput(ui).axis>0);assert.equal(ui.el('error').hidden,true);
  ui.window.emit('pointermove',{pointerId:1,pointerType:'mouse',buttons:0,clientX:700,clientY:200});assert.equal(lastInput(ui).axis,0);
  ui.el('joy').emit('pointerdown',{pointerId:2,clientX:170,clientY:310});
  ui.window.emit('pointercancel',{pointerId:2});assert.equal(lastInput(ui).axis,0);
});
test('Safari native touch identifiers own three controls and ignore compatibility pointers',async()=>{
  const ui=await play(true),joy={identifier:41,clientX:170,clientY:310},fire={identifier:7,clientX:760,clientY:320},jump={identifier:9,clientX:560,clientY:250};
  ui.el('joy').emit('pointerdown',{pointerId:888,pointerType:'touch',clientX:170,clientY:310});
  assert.equal(lastInput(ui),undefined);
  ui.el('joy').emit('touchstart',{touches:[joy],changedTouches:[joy]});
  ui.el('fire').emit('touchstart',{touches:[joy,fire],changedTouches:[fire]});
  ui.el('jump').emit('touchstart',{touches:[joy,fire,jump],changedTouches:[jump]});
  ui.el('jump').emit('pointerdown',{pointerId:999,pointerType:'touch',clientX:560,clientY:250});
  assert.equal(ui.commands.filter(c=>c.type==='jump').length,1);assert.equal(lastInput(ui).fire,true);assert.ok(lastInput(ui).axis>0);
  ui.window.emit('touchend',{touches:[fire,jump],changedTouches:[joy]});
  assert.equal(lastInput(ui).axis,0);assert.equal(lastInput(ui).fire,true);
  ui.window.emit('touchcancel',{touches:[jump],changedTouches:[fire]});assert.equal(lastInput(ui).fire,false);
});
test('live Safari touches reconcile a lost end without clearing the other hand',async()=>{
  const ui=await play(true),joy={identifier:0,clientX:170,clientY:310},fire={identifier:1,clientX:760,clientY:320};
  ui.el('joy').emit('touchstart',{touches:[joy],changedTouches:[joy]});
  ui.el('fire').emit('touchstart',{touches:[joy,fire],changedTouches:[fire]});
  ui.window.emit('touchmove',{touches:[fire],changedTouches:[fire]});
  assert.equal(lastInput(ui).axis,0);assert.equal(lastInput(ui).fire,true);assert.equal(ui.el('joy-knob').style.transform,'translate(0,0)');
  ui.window.emit('touchcancel',{touches:[],changedTouches:[]});assert.equal(lastInput(ui).fire,false);
});
test('touch identifier reuse and alternating release order never leave rightward input',async()=>{
  const ui=await play(true),joy={identifier:3,clientX:170,clientY:310},fire={identifier:4,clientX:760,clientY:320};
  for(let i=0;i<100;i++){
    ui.el('joy').emit('touchstart',{touches:[joy],changedTouches:[joy]});
    ui.el('fire').emit('touchstart',{touches:[joy,fire],changedTouches:[fire]});
    const first=i%2?joy:fire,second=i%2?fire:joy;
    ui.window.emit('touchend',{touches:[second],changedTouches:[first]});
    ui.window.emit('touchend',{touches:[],changedTouches:[second]});
    assert.equal(lastInput(ui).axis,0);assert.equal(lastInput(ui).fire,false);
  }
  assert.equal(ui.el('error').hidden,true);
});
test('screen rotation and backgrounding release captures and restore joystick center',async()=>{
  const ui=await play();
  for(const target of ['viewport','rotation','background']){
    ui.el('joy').emit('pointerdown',{pointerId:1,clientX:170,clientY:310});
    if(target==='viewport')ui.window.visualViewport.emit('resize');
    if(target==='rotation')ui.window.emit('orientationchange');
    if(target==='background'){ui.document.hidden=true;ui.document.emit('visibilitychange')}
    assert.equal(ui.commands.at(-1).type==='release'||ui.commands.at(-2)?.type==='release',true);
    assert.equal(ui.el('joy-knob').style.transform,'translate(0,0)');assert.equal(ui.el('joy').captures.size,0);
  }
});
test('Safari touch can drag and save a button layout without starting gameplay input',async()=>{
  const ui=await play(true);ui.el('settings-open').emit('click');ui.selectors[2].emit('click');ui.el('drag-layout').emit('click');
  const touch={identifier:20,clientX:760,clientY:320};
  ui.el('fire').emit('touchstart',{touches:[touch],changedTouches:[touch]});
  const moved={...touch,clientX:680,clientY:240};
  ui.window.emit('touchmove',{touches:[moved],changedTouches:[moved]});
  ui.window.emit('touchend',{touches:[],changedTouches:[moved]});ui.el('edit-done').emit('click');
  const prefs=JSON.parse(ui.storage.get(model.STORAGE_KEY));assert.ok(prefs.fire.x<.9);assert.ok(prefs.fire.y<.87);
  assert.equal(ui.el('error').hidden,true);assert.equal(ui.el('edit-bar').hidden,true);
  assert.ok(!ui.commands.some(c=>c.type==='input'&&c.fire));
});
