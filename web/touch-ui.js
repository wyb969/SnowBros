import { BUILD, BASE_SIZE, InputState, clamp, controlBox, loadSettings, saveSettings, structuredDefaults } from './controls-model.js';
import { createGameFetch, safeEngineConfig } from './web-loader.js';

const $ = id => document.getElementById(id);
let prefs = loadSettings(localStorage);
const inputs = new InputState();
// Safari Touch identifiers survive sliding off the control without capture.
const nativeTouch = navigator.maxTouchPoints > 0 && 'ontouchstart' in window;
const captures = new Map();
const safeProbe = document.createElement('div');
safeProbe.style.cssText='position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
document.body.appendChild(safeProbe);
const canvas = $('canvas'), settings = $('settings');
const elements = Object.fromEntries(Object.keys(BASE_SIZE).map(key => [key, $(key)]));
let receiver = null, loaded = false, attached = false, editing = false, selected = 'joy';
let savedPause = false, errorText = '', game = { state: 'title', paused: false, practice: false, case: 0, score: 0, lives: 3 };
let audioContext = null, audioVoices = 0;
const soundGates = new Map(), log = [];
let drag = null;
let recovered = false;
try { recovered = sessionStorage.getItem('snowbro.running') === '1'; } catch {}
if (recovered) { prefs.sound = false; saveSettings(localStorage, prefs); }
function markRunning(value) { try { value ? sessionStorage.setItem('snowbro.running','1') : sessionStorage.removeItem('snowbro.running'); } catch {} }
function send(data) {
  if (!receiver) return;
  try { receiver(JSON.stringify(data)); }
  catch (error) { fail('游戏输入中断', error); }
}
function sendInputs() { send(inputs.snapshot()); }
function dropCapture(id) {
  const element=captures.get(id); captures.delete(id);
  try { if (element?.hasPointerCapture(id)) element.releasePointerCapture(id); } catch {}
}
function release() {
  inputs.reset(); drag=null; $('joy-knob').style.transform = 'translate(0,0)';
  for (const element of Object.values(elements)) element.classList.remove('pressed');
  for (const id of [...captures.keys()]) dropCapture(id);
  send({ type: 'release' });
}
function persist() { if (!saveSettings(localStorage,prefs)) $('audio-note').textContent = '浏览器暂不允许保存，当前页面仍可使用这些设置。'; }
function size() { return { width: window.innerWidth, height: window.innerHeight }; }
function boxes() {
  const { width, height } = size();
  const safe=getComputedStyle(safeProbe);
  const insets={left:parseFloat(safe.paddingLeft)||0,right:parseFloat(safe.paddingRight)||0,bottom:parseFloat(safe.paddingBottom)||0,top:document.querySelector('.toolbar').getBoundingClientRect().bottom+8};
  return Object.fromEntries(Object.keys(BASE_SIZE).map(key => [key, controlBox(key,prefs[key],width,height,insets)]));
}
function layout() {
  for (const [key, box] of Object.entries(boxes())) {
    const e = elements[key]; e.style.left = `${box.x}px`; e.style.top = `${box.y}px`;
    e.style.width = `${box.size}px`; e.style.height = `${box.size}px`; e.style.opacity = String(prefs.opacity);
    e.classList.toggle('selected', editing && key === selected);
  }
  $('stage').style.top=`${document.querySelector('.toolbar').getBoundingClientRect().bottom}px`;
  const rect = $('stage').getBoundingClientRect();
  const scale = Math.min(rect.width/960,rect.height/540);
  canvas.style.width = `${Math.floor(960*scale)}px`; canvas.style.height = `${Math.floor(540*scale)}px`;
  canvas.style.left = `${Math.floor((rect.width-960*scale)/2)}px`;
  canvas.style.top = `${Math.floor((rect.height-540*scale)*(window.innerHeight>window.innerWidth ? .32 : .5))}px`;
  // The backing buffer stays fixed even on Retina screens.
}
function refreshSliders() {
  for (const e of document.querySelectorAll('[data-select]')) e.setAttribute('aria-pressed', String(e.dataset.select === selected));
  $('control-size').value = Math.round(prefs[selected].scale*100);
  $('control-x').value = Math.round(prefs[selected].x*100);
  $('control-y').value = Math.round(prefs[selected].y*100);
  $('control-opacity').value = Math.round(prefs.opacity*100);
  $('size-value').textContent = `${$('control-size').value}%`;
  $('x-value').textContent = `${$('control-x').value}%`;
  $('y-value').textContent = `${$('control-y').value}%`;
  $('opacity-value').textContent = `${$('control-opacity').value}%`;
  $('sound-enabled').checked = prefs.sound;
}
function render() {
  $('pause').disabled = !loaded || game.state !== 'play';
  $('restart').disabled = !loaded;
  $('pause').textContent = game.paused ? '继续' : '暂停';
  const visible = game.state !== 'play' || game.paused;
  $('menu').hidden = !visible || settings.open || editing;
  $('start').disabled = !(loaded && attached);
  $('practice').disabled = !(loaded && attached);
  if (!loaded) return;
  $('load-progress').hidden = true;
  $('load-status').textContent = recovered ? '上次意外中断，当前以固定分辨率、静音启动' : '左右手可同时操作，按住喷雪连续发射';
  $('start').textContent = game.paused ? '继续游戏' : game.state === 'title' ? '开始游戏' : '再玩一次';
  $('menu-title').textContent = game.paused ? '已暂停' : game.state === 'clear' ? '通关！' : game.state === 'over' ? '再来一次？' : 'SNOW / BRO';
  $('menu-description').textContent = game.state === 'clear' || game.state === 'over' ? `本次得分 ${game.score}` : '冻结敌人，踢出雪球，连锁清场。';
}
function openSettings() {
  if (settings.open) return;
  if (!editing) savedPause = game.paused;
  editing = false; document.body.classList.remove('editing'); $('edit-bar').hidden = true;
  release(); send({type:'pause',paused:true});
  settings.showModal(); refreshSliders(); render();
}
function closeSettings(edit = false) {
  settings.close(); editing = edit; document.body.classList.toggle('editing',edit); $('edit-bar').hidden = !edit;
  persist(); layout(); release();
  if (!edit) { send({type:'pause',paused:savedPause}); game.paused = savedPause; if(!savedPause && game.state==='play')unlockAudio(); canvas.focus(); }
  render();
}
function finishEdit() {
  editing = false; drag = null; document.body.classList.remove('editing'); $('edit-bar').hidden = true;
  release(); persist(); send({type:'pause',paused:savedPause}); game.paused = savedPause; if(!savedPause && game.state==='play')unlockAudio(); render(); canvas.focus();
}
function setSound(enabled, notify = true) {
  prefs.sound = !!enabled; persist(); $('sound-enabled').checked = prefs.sound;
  if (notify) send({type:'mute',muted:!prefs.sound});
  if (prefs.sound) unlockAudio();
  else { $('bgm').pause(); if (audioContext?.state === 'running') audioContext.suspend().catch(()=>{}); }
}
function unlockAudio() {
  if (!prefs.sound) return;
  try {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (Audio && !audioContext) audioContext = new Audio();
    if (audioContext?.state === 'suspended') audioContext.resume().catch(()=>{ $('audio-note').textContent='声音未能启动，游戏仍可继续。'; });
    $('bgm').volume = .18;
    const attempt = $('bgm').play();
    if (attempt?.catch) attempt.catch(()=>{ $('audio-note').textContent='音乐暂不可用，游戏仍可继续。'; });
  } catch { $('audio-note').textContent='声音暂不可用，游戏仍可继续。'; }
}
function sound(kind) {
  if (!prefs.sound || !audioContext || audioContext.state !== 'running' || audioVoices >= 6) return;
  const specs = { snow:[880,360,.045],kick:[180,55,.1],hit:[250,70,.09],chain:[330,760,.14],freeze:[720,1250,.14],pickup:[550,1100,.18],jump:[210,390,.07] };
  const spec = specs[kind]; if (!spec) return;
  const time = audioContext.currentTime;
  if (time-(soundGates.get(kind) ?? -100) < .045) return;
  soundGates.set(kind,time);
  try {
    const oscillator=audioContext.createOscillator(), gain=audioContext.createGain();
    oscillator.frequency.setValueAtTime(spec[0],time); oscillator.frequency.exponentialRampToValueAtTime(spec[1],time+spec[2]);
    gain.gain.setValueAtTime(.0001,time); gain.gain.linearRampToValueAtTime(.07,time+.006); gain.gain.exponentialRampToValueAtTime(.0001,time+spec[2]);
    oscillator.connect(gain); gain.connect(audioContext.destination); audioVoices++;
    oscillator.onended=()=>{ oscillator.disconnect(); gain.disconnect(); audioVoices--; };
    oscillator.start(time); oscillator.stop(time+spec[2]);
  } catch { /* Sound failure must never stop play. */ }
}
window.SnowBro = {
  attach(callback) { receiver=callback; attached=true; queueMicrotask(()=>{send({type:'mute',muted:!prefs.sound});render();}); },
  update(value) {
    try {
      const wasPaused=game.paused;
      game={...game,...JSON.parse(String(value))};
      markRunning(game.state==='play');
      if (game.paused) $('bgm').pause();
      else if (wasPaused && game.state==='play' && prefs.sound) unlockAudio();
      render();
    } catch (error) { log.push(`状态同步：${String(error)}`); }
  },
  sound, setSound: enabled => setSound(enabled, false)
};

function moveControl(id,x,y) {
  if (editing && drag?.id===id) {
    const {width,height}=size();
    prefs[drag.key].x=clamp((x-drag.dx)/width,0,1); prefs[drag.key].y=clamp((y-drag.dy)/height,.1,1); layout(); return;
  }
  if (inputs.pointers.get(id)!=='joy') return;
  const box=boxes().joy, v=inputs.move(id,x-box.x,y-box.y,box.radius*.55);
  $('joy-knob').style.transform=`translate(${v.x*box.radius*.55}px,${v.y*box.radius*.55}px)`; sendInputs();
}
function beginControl(key,id,x,y) {
  if (editing) {
    if (drag) return false;
    selected=key; const box=boxes()[key]; drag={id,key,dx:x-box.x,dy:y-box.y}; layout(); return true;
  }
  if (!loaded || game.state!=='play' || game.paused || inputs.pointers.has(id)) return false;
  const jump=inputs.down(id,key);
  if (inputs.pointers.get(id)!==key) return false;
  elements[key].classList.add('pressed');
  if (jump) send({type:'jump'});
  if (key==='joy') moveControl(id,x,y);
  else sendInputs();
  return true;
}
function endControl(id) {
  if (drag?.id===id) { drag=null; persist(); refreshSliders(); }
  const control=inputs.up(id);
  dropCapture(id);
  if (!control) return;
  if (control==='joy') $('joy-knob').style.transform='translate(0,0)';
  if (![...inputs.pointers.values()].includes(control)) elements[control].classList.remove('pressed');
  sendInputs();
}
function pointerMove(event) {
  if (nativeTouch && event.pointerType==='touch') return;
  // A missed mouse/pen up must not be resurrected by a hover move.
  if (event.pointerType!=='touch' && event.buttons===0) { endControl(event.pointerId); return; }
  if (inputs.pointers.has(event.pointerId) || drag?.id===event.pointerId) {
    event.preventDefault(); moveControl(event.pointerId,event.clientX,event.clientY);
  }
}
function pointerEnd(event) {
  if (!(nativeTouch && event.pointerType==='touch')) endControl(event.pointerId);
}
function auditTouches(touches) {
  const live=new Set(Array.from(touches,touch=>`touch:${touch.identifier}`));
  for (const id of [...inputs.pointers.keys()]) if (typeof id==='string' && id.startsWith('touch:') && !live.has(id)) endControl(id);
  if (typeof drag?.id==='string' && !live.has(drag.id)) endControl(drag.id);
}
for (const [key, element] of Object.entries(elements)) {
  element.addEventListener('contextmenu',event=>event.preventDefault());
  element.addEventListener('pointerdown',event=>{
    if (nativeTouch && event.pointerType==='touch') return;
    event.preventDefault();
    if (!beginControl(key,event.pointerId,event.clientX,event.clientY)) return;
    try { element.setPointerCapture(event.pointerId); captures.set(event.pointerId,element); } catch { /* Global listeners still own release. */ }
  });
  for (const name of ['pointerup','pointercancel','lostpointercapture']) element.addEventListener(name,pointerEnd);
  if (nativeTouch) element.addEventListener('touchstart',event=>{
    event.preventDefault(); auditTouches(event.touches);
    for (const touch of event.changedTouches) beginControl(key,`touch:${touch.identifier}`,touch.clientX,touch.clientY);
  },{passive:false});
}
// Capture phase receives releases even when the finger leaves the control or
// the browser retargets the event. Repeated end events are idempotent.
window.addEventListener('pointermove',pointerMove,{capture:true,passive:false});
for (const name of ['pointerup','pointercancel','lostpointercapture']) window.addEventListener(name,pointerEnd,true);
if (nativeTouch) {
  window.addEventListener('touchstart',event=>auditTouches(event.touches),{capture:true,passive:true});
  window.addEventListener('touchmove',event=>{
    auditTouches(event.touches);
    if (!inputs.pointers.size && !drag) return;
    event.preventDefault();
    for (const touch of event.changedTouches) moveControl(`touch:${touch.identifier}`,touch.clientX,touch.clientY);
  },{capture:true,passive:false});
  for (const name of ['touchend','touchcancel']) window.addEventListener(name,event=>{
    for (const touch of event.changedTouches) endControl(`touch:${touch.identifier}`);
    auditTouches(event.touches);
  },{capture:true,passive:true});
}
$('start').addEventListener('click',()=>{
  if (!(loaded && attached)) return;
  release();
  if (game.paused && game.state==='play') { send({type:'pause',paused:false}); game.paused=false; }
  else { send({type:'start'}); game.state='play'; game.paused=false; }
  unlockAudio(); markRunning(true); render(); canvas.focus();
});
$('practice').addEventListener('click',()=>{ release();send({type:'practice',case:0});game.state='play';game.paused=false;unlockAudio();render();canvas.focus(); });
$('pause').addEventListener('click',()=>{release();send({type:'pause',paused:!game.paused});game.paused=!game.paused;render();if(!game.paused)unlockAudio();canvas.focus();});
$('restart').addEventListener('click',()=>{release();send({type:'restart'});game.state='play';game.paused=false;render();canvas.focus();});
$('settings-open').addEventListener('click',openSettings);
$('credits-open').addEventListener('click',()=>{openSettings();document.querySelector('.help-details').open=true;});
$('settings-close').addEventListener('click',()=>closeSettings());
settings.addEventListener('cancel',event=>{event.preventDefault();closeSettings();});
$('drag-layout').addEventListener('click',()=>closeSettings(true));
$('edit-done').addEventListener('click',finishEdit);
$('edit-settings').addEventListener('click',openSettings);
for (const e of document.querySelectorAll('[data-select]')) e.addEventListener('click',()=>{selected=e.dataset.select;refreshSliders();layout();});
for (const [id,property,multiplier] of [['control-size','scale',.01],['control-x','x',.01],['control-y','y',.01]]) {
  $(id).addEventListener('input',()=>{prefs[selected][property]=Number($(id).value)*multiplier;layout();refreshSliders();persist();});
}
$('control-opacity').addEventListener('input',()=>{prefs.opacity=Number($('control-opacity').value)/100;layout();refreshSliders();persist();});
$('sound-enabled').addEventListener('change',()=>setSound($('sound-enabled').checked));
$('defaults').addEventListener('click',()=>{const sound=prefs.sound;prefs=structuredDefaults();prefs.sound=sound;persist();release();layout();refreshSliders();});
$('practice-next').addEventListener('click',()=>{send({type:'practice',case:game.practice ? (game.case+1)%4 : 0});game.state='play';savedPause=false;closeSettings();});
function blurPause() { release();if(game.state==='play'){send({type:'pause',paused:true});game.paused=true;render();}$('bgm').pause(); }
window.addEventListener('blur',blurPause);
document.addEventListener('visibilitychange',()=>{if(document.hidden)blurPause();});
window.addEventListener('pagehide',()=>{release();markRunning(false);});
window.addEventListener('resize',()=>{release();layout();});
window.visualViewport?.addEventListener('resize',()=>{release();layout();});
window.addEventListener('orientationchange',()=>{release();layout();});
window.addEventListener('keydown',event=>{if(!settings.open && ['Space','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.code))event.preventDefault();});

function fail(message,error) {
  if (!$('error').hidden) return;
  $('error').hidden=false; receiver=null;
  release(); markRunning(false); $('bgm').pause();
  errorText=`${message}\n${error?.stack || error?.message || String(error)}\nBuild: ${BUILD}\n${navigator.userAgent}\n${log.slice(-8).join('\n')}`;
  $('error-message').textContent=message; $('error-detail').textContent=errorText;
  $('error').hidden=false;
  try { localStorage.setItem('snowbro.lastError',errorText); } catch {}
}
window.addEventListener('error',event=>fail('游戏运行出现异常，已保留错误信息。',event.error || event.message));
window.addEventListener('unhandledrejection',event=>{event.preventDefault();fail('游戏运行中断，已保留错误信息。',event.reason);});
canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();fail('图形连接中断。请关闭其他高负载页面后重试。','WebGL context lost');});
$('error-copy').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(errorText);$('error-copy').textContent='已复制';}catch{$('error-copy').textContent='可长按选择下方错误信息';$('error-detail').style.userSelect='text';}});
$('error-reload').addEventListener('click',()=>{markRunning(false);window.location.reload();});

async function boot() {
  layout(); refreshSliders();
  window.fetch=createGameFetch(window.fetch.bind(window),window.location.href,BUILD,window.GODOT_CONFIG.fileSizes['game.wasm']);
  const missing=Engine.getMissingFeatures({threads:false});
  if (missing.length) throw new Error(`浏览器缺少运行功能：${missing.join(', ')}`);
  const engine=new Engine(safeEngineConfig(window.GODOT_CONFIG));
  await engine.startGame({
    canvas, onProgress(current,total) {
      if(total>0){const percent=Math.round(current/total*100);$('load-progress').value=percent;$('load-status').textContent=`正在加载游戏 ${percent}%`;}
    },
    onPrintError(line) { log.push(String(line)); if(log.length>16)log.shift(); },
    onExit(code) { fail('游戏引擎已停止。',`Exit code: ${code}`); }
  });
  loaded=true; $('start').textContent='开始游戏'; render(); layout();
}
boot().catch(error=>fail('游戏加载失败，请查看错误信息。',error));
