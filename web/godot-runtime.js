import { safeEngineConfig } from './web-loader.js';

// The pinned Godot Web export exposes this Emscripten factory and its filesystem
// bridge. Supplying bytes keeps the engine from fetching its own WASM a second time.
export async function startGodotGame(settings, assets, {canvas, onPrintError, onExit, onAbort}, factory = globalThis.Godot) {
  if (typeof factory !== 'function') throw new Error('游戏引擎脚本未加载（game.js）');
  const config = safeEngineConfig(settings);
  const {wasm, pack} = assets;
  const binary = wasm.byteOffset === 0 && wasm.byteLength === wasm.buffer.byteLength
    ? wasm.buffer : wasm.slice().buffer;
  const executable = config.executable;
  const module = await factory({
    wasmBinary: binary,
    thisProgram: executable,
    printErr: onPrintError,
    onAbort,
    locateFile(path) {
      return path.startsWith('godot.') ? executable + path.slice('godot'.length) : path;
    }
  });
  // Native preferences and touch layouts are already stored by the page.
  // This game has no save files in user://, so no IndexedDB mount is necessary.
  await module.initFS([]);
  module.initConfig({
    canvas,
    canvasResizePolicy: config.canvasResizePolicy,
    locale: (navigator.language || 'en').replace(/-/g, '_'),
    focusCanvas: config.focusCanvas,
    godotPoolSize: config.godotPoolSize,
    virtualKeyboard: false,
    onExit
  });
  const mainPack = config.mainPack || executable + '.pck';
  module.copyToFS(mainPack, pack);
  module.callMain(['--main-pack', mainPack, ...config.args]);
}
