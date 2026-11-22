class AssetError extends Error {
  constructor(message, retryable = false) {
    super(message);
    this.retryable = retryable;
  }
}

function checkManifest(bytes, hash) {
  if (!Number.isSafeInteger(bytes) || bytes <= 0 || !/^[0-9a-f]{64}$/i.test(hash || '')) {
    throw new AssetError('游戏文件清单的字节数或 SHA-256 无效，请刷新页面');
  }
}

function looksLikeHtml(bytes) {
  const prefix = new TextDecoder().decode(bytes.subarray(0, 160)).trimStart();
  return /^(<!doctype\s+html\b|<html\b|<head\b|<body\b)/i.test(prefix);
}

async function readBody(stream, limit, signal) {
  if (!stream) throw new AssetError('响应正文为空', true);
  const reader = stream.getReader();
  const cancel = () => { reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, { once: true });
  const bytes = new Uint8Array(limit);
  let length = 0;
  try {
    while (!signal.aborted) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value.byteLength > limit - length) {
        const prefix = new Uint8Array(Math.min(160, length + value.byteLength));
        const saved = Math.min(prefix.length, length);
        prefix.set(bytes.subarray(0, saved));
        prefix.set(value.subarray(0, prefix.length - saved), saved);
        if (looksLikeHtml(prefix)) throw htmlError();
        throw new AssetError('响应正文超出清单长度', true);
      }
      bytes.set(value, length);
      length += value.byteLength;
    }
    if (signal.aborted) throw signal.reason;
    return bytes.subarray(0, length);
  } catch (error) {
    cancel();
    throw error;
  } finally {
    signal.removeEventListener('abort', cancel);
    reader.releaseLock();
  }
}

function htmlError() {
  return new AssetError('收到网页而非游戏文件，请检查登录状态并刷新');
}

async function matchesHash(bytes, expected) {
  const hash = new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', bytes));
  return Array.from(hash, value => value.toString(16).padStart(2, '0')).join('') === expected;
}

async function fetchAsset(asset, fetchImpl, Decompress, attempt, signal) {
  const gzip = Boolean(Decompress && asset.rawUrl);
  const response = await fetchImpl(gzip ? asset.url : (asset.rawUrl || asset.url), {
    signal, cache: attempt === 1 ? 'default' : 'reload', credentials: 'same-origin'
  });
  if (!response.ok) {
    response.body?.cancel().catch(() => {});
    const status = response.status;
    if (status === 401 || status === 403) throw new AssetError(`访问被拒绝 (HTTP ${status})，请检查登录账号和访问权限`);
    throw new AssetError(`HTTP ${status}`, [408, 425, 429, 500, 502, 503, 504].includes(status));
  }
  if (/\b(text\/html|application\/xhtml\+xml)\b/i.test(response.headers.get('content-type') || '')) {
    response.body?.cancel().catch(() => {});
    throw htmlError();
  }
  let bytes = await readBody(response.body, gzip ? Math.max(asset.bytes, asset.compressedBytes) : asset.bytes, signal);
  if (looksLikeHtml(bytes)) throw htmlError();
  // A host may apply Content-Encoding: gzip to the stored gzip file. Fetch
  // then already yields raw bytes. Only accept that case after a digest match.
  if (bytes.length === asset.bytes && await matchesHash(bytes, asset.sha256)) return bytes;
  if (gzip && bytes[0] === 0x1f && bytes[1] === 0x8b) {
    if (bytes.length !== asset.compressedBytes) throw new AssetError(`压缩数据长度不符 (${bytes.length}/${asset.compressedBytes})`, true);
    const compressed = bytes;
    const source = new ReadableStream({ start(writer) { writer.enqueue(compressed); writer.close(); } });
    bytes = await readBody(source.pipeThrough(new Decompress('gzip')), asset.bytes, signal);
    if (bytes.length === asset.bytes && await matchesHash(bytes, asset.sha256)) return bytes;
  }
  if (bytes.length !== asset.bytes) throw new AssetError(`文件长度不符 (${bytes.length}/${asset.bytes})`, true);
  throw new AssetError('SHA-256 校验失败', true);
}

// A deadline must also cover reading the body and inflating it. Race against
// the signal even if a network implementation ignores abort during a stalled read.
async function withDeadline(operation, groupSignal, timeoutMs) {
  const controller = new AbortController();
  const forward = () => controller.abort(groupSignal.reason);
  groupSignal.addEventListener('abort', forward, { once: true });
  if (groupSignal.aborted) forward();
  const timer = setTimeout(() => controller.abort(new AssetError('读取超时', true)), timeoutMs);
  const stopped = new Promise((_, reject) => {
    if (controller.signal.aborted) reject(controller.signal.reason);
    else controller.signal.addEventListener('abort', () => reject(controller.signal.reason), { once: true });
  });
  try {
    return await Promise.race([stopped, operation(controller.signal)]);
  } finally {
    clearTimeout(timer);
    groupSignal.removeEventListener('abort', forward);
  }
}

export async function loadGameAssets(config, pageURL, {
  fetchImpl = fetch, onProgress = () => {}, DecompressionStreamImpl = globalThis.DecompressionStream,
  timeoutMs = 30000, maxAttempts = 3, retryDelayMs = 250
} = {}) {
  if (!globalThis.crypto?.subtle) throw new AssetError('浏览器无法校验游戏文件，请使用 HTTPS 打开试玩页');
  if (!Array.isArray(config.wasmParts) || !config.wasmParts.length) throw new AssetError('缺少引擎分片清单，请刷新页面');
  let Decompress = DecompressionStreamImpl;
  try { new Decompress('gzip'); } catch { Decompress = null; }
  const packBytes = config.fileSizes?.['game.pck'];
  checkManifest(packBytes, config.packSha256);
  const packURL = new URL('game.pck', pageURL);
  packURL.searchParams.set('v', config.packSha256);
  const tasks = [{ name: '关卡 game.pck', url: packURL.href, bytes: packBytes, sha256: config.packSha256.toLowerCase() }];
  let wasmBytes = 0;
  for (const [i, part] of config.wasmParts.entries()) {
    checkManifest(part.bytes, part.sha256);
    if (!part.url || !part.rawUrl || !Number.isSafeInteger(part.compressedBytes) || part.compressedBytes <= 0) {
      throw new AssetError(`引擎分片 ${i+1} 清单不完整`);
    }
    const url = new URL(part.url, pageURL);
    const raw = new URL(part.rawUrl, pageURL);
    const fileName = (Decompress ? url : raw).pathname.split('/').pop();
    tasks.push({ ...part, url: url.href, rawUrl: raw.href, sha256: part.sha256.toLowerCase(),
      offset: wasmBytes, name: `引擎 ${i+1}/${config.wasmParts.length} · ${fileName}` });
    wasmBytes += part.bytes;
  }
  if (wasmBytes !== config.fileSizes?.['game.wasm']) throw new AssetError('引擎分片总长度与清单不符');
  const wasm = new Uint8Array(wasmBytes);
  const total = wasmBytes + packBytes;
  const group = new AbortController();
  let loaded = 0, next = 0, pack;

  async function worker() {
    while (!group.signal.aborted && next < tasks.length) {
      const asset = tasks[next++];
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        onProgress({ label: asset.name, loaded, total, attempt });
        let data;
        try {
          data = await withDeadline(signal => fetchAsset(asset, fetchImpl, Decompress, attempt, signal), group.signal, timeoutMs);
        } catch (error) {
          if (group.signal.aborted) return;
          const message = `${asset.name}（第 ${attempt}/${maxAttempts} 次） · ${error.message || error}`;
          if (error.retryable === false || attempt === maxAttempts) {
            const failure = new AssetError(message);
            group.abort(failure);
            throw failure;
          }
          if (retryDelayMs > 0) await new Promise(resolve => setTimeout(resolve, retryDelayMs * attempt));
          if (group.signal.aborted) return;
          continue;
        }
        if (group.signal.aborted) return;
        if (asset.offset === undefined) pack = data;
        else wasm.set(data, asset.offset);
        loaded += asset.bytes;
        onProgress({ label: asset.name, loaded, total, attempt });
        break;
      }
    }
  }
  try {
    await Promise.all([worker(), worker()]);
    return { wasm, pack };
  } finally {
    group.abort();
  }
}

export function safeEngineConfig(config) {
  const result = { ...config, args: ['--audio-driver', 'Dummy'], canvasResizePolicy: 0, focusCanvas: true, ensureCrossOriginIsolationHeaders: false };
  delete result.serviceWorker;
  return result;
}
