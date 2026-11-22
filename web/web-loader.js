export function createGameFetch(baseFetch, pageURL, build, wasmSize) {
  return async function gameFetch(resource, options) {
    const source = typeof resource === 'string' ? resource : resource.url;
    const url = new URL(source, pageURL);
    if (url.pathname.endsWith('/game.wasm')) {
      let part = 0, reader = null, cancelled = false;
      const body = new ReadableStream({
        async pull(controller) {
          try {
            while (part < 2 && !cancelled) {
              if (!reader) {
                const chunkURL = new URL(`game.wasm.part${part}`, pageURL);
                chunkURL.searchParams.set('v', build);
                const response = await baseFetch(chunkURL.href, options);
                if (!response.ok || !response.body) throw new Error(`引擎文件 ${part + 1}/2 加载失败 (${response.status})`);
                reader = response.body.getReader();
              }
              const next = await reader.read();
              if (next.done) { reader.releaseLock(); reader = null; part++; continue; }
              controller.enqueue(next.value); return;
            }
            if (!cancelled) controller.close();
          } catch (error) { controller.error(error); }
        },
        cancel() { cancelled = true; return reader?.cancel(); }
      });
      return new Response(body, { headers: { 'Content-Type': 'application/wasm', 'Content-Length': String(wasmSize) } });
    }
    if (/\/game\.(pck|js)$/.test(url.pathname)) url.searchParams.set('v', build);
    return baseFetch(url.href, options);
  };
}
export function safeEngineConfig(config) {
  const result = { ...config, args: ['--audio-driver', 'Dummy'], canvasResizePolicy: 0, focusCanvas: true, ensureCrossOriginIsolationHeaders: false };
  delete result.serviceWorker;
  return result;
}
