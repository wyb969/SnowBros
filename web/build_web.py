"""Build the browser shell from a Web export.

With --reuse-engine, first export a replacement game.pck with the same Godot
version and Web preset as the existing distribution. The engine payloads are
content-addressed independently of game.pck and the browser UI.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
from zipfile import ZIP_DEFLATED, ZipFile

from build_reports import build_reports


WEB = Path(__file__).resolve().parent
SHARED_MODULES = ("controls-model.js", "web-loader.js", "godot-runtime.js")
MODULES = (*SHARED_MODULES, "touch-ui.js", "touch-ui.css")
PART_SIZE = 2 * 1024 * 1024


def read_wasm(output, config, reuse):
    if not reuse:
        wasm = (output / "game.wasm").read_bytes()
    elif "wasmParts" in config:
        raw_parts = []
        for part in config["wasmParts"]:
            raw = (output / part["rawUrl"]).read_bytes()
            if len(raw) != part["bytes"] or hashlib.sha256(raw).hexdigest() != part["sha256"]:
                raise SystemExit(f"Existing engine slice failed verification: {part['rawUrl']}")
            raw_parts.append(raw)
        wasm = b"".join(raw_parts)
    else:
        wasm = b"".join((output / f"game.wasm.part{i}").read_bytes() for i in range(2))
    if len(wasm) != config["fileSizes"]["game.wasm"] or not wasm.startswith(b"\x00asm\x01\x00\x00\x00"):
        raise SystemExit("Existing engine is incomplete or does not have a WebAssembly header.")
    return wasm


def write_engine(output, wasm):
    directory = output / "engine"
    directory.mkdir(exist_ok=True)
    manifest = []
    for offset in range(0, len(wasm), PART_SIZE):
        raw = wasm[offset:offset + PART_SIZE]
        raw_hash = hashlib.sha256(raw).hexdigest()
        with io.BytesIO() as buffer:
            with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, compresslevel=6, mtime=0) as stream:
                stream.write(raw)
            compressed = buffer.getvalue()
        gzip_hash = hashlib.sha256(compressed).hexdigest()
        # Both representations are ordinary binary assets. Compression is part of
        # the payload rather than HTTP Content-Encoding and can be verified/retried.
        raw_path = directory / f"{raw_hash}.bin"
        gzip_path = directory / f"{gzip_hash}.gz.bin"
        raw_path.write_bytes(raw)
        gzip_path.write_bytes(compressed)
        manifest.append({
            "url": gzip_path.relative_to(output).as_posix(),
            "rawUrl": raw_path.relative_to(output).as_posix(),
            "bytes": len(raw),
            "compressedBytes": len(compressed),
            "sha256": raw_hash,
        })
    return manifest


def read_config(output, reuse):
    page = (output / "game.html").read_text()
    marker = r"window\.GODOT_CONFIG\s*=" if reuse else r"const GODOT_CONFIG\s*="
    match = re.search(marker + r"\s*(\{[^\n]*?\});", page)
    if not match:
        raise SystemExit("Expected a packaged game.html for --reuse-engine, or a fresh Godot export otherwise.")
    config = json.loads(match[1])
    config["wasmParts"] = write_engine(output, read_wasm(output, config, reuse))
    config["packSha256"] = hashlib.sha256((output / "game.pck").read_bytes()).hexdigest()
    config.update(args=["--audio-driver", "Dummy"], canvasResizePolicy=0, ensureCrossOriginIsolationHeaders=False)
    config.pop("serviceWorker", None)
    config["fileSizes"]["game.pck"] = (output / "game.pck").stat().st_size
    return config


def write_source_archive(output):
    project = WEB.parent
    files = [project / name for name in ("README.md", "export_presets.cfg", "project.godot")]
    for name in ("assets", "docs", "scenes", "scripts", "tests", "web"):
        files.extend(sorted(path for path in (project / name).rglob("*")
                            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"))
    with ZipFile(output / "SnowBro-Godot47-Source.zip", "w", compression=ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(project))


def build_web(output, reuse):
    config = read_config(output, reuse)
    revision = hashlib.sha256(json.dumps(config, sort_keys=True).encode())
    revision.update((output / "game.js").read_bytes())
    for name in (*MODULES, "shell.html"):
        revision.update((WEB / name).read_bytes())
    model = (WEB / "controls-model.js").read_text()
    label = re.search(r"BUILD = '([^']+)'", model)[1]
    build = f"{label}-{revision.hexdigest()[:12]}"
    page = (WEB / "shell.html").read_text().replace("__CONFIG_JSON__", json.dumps(config, separators=(",", ":")))
    page = page.replace("__BUILD__", build)
    for name in ("game.html", "index.html"):
        (output / name).write_text(page)
    for name in MODULES:
        text = (WEB / name).read_text()
        if name == "controls-model.js":
            text = text.replace(f"BUILD = '{label}'", f"BUILD = '{build}'")
        if name.endswith(".js"):
            for module in SHARED_MODULES:
                for quote in ("'", '"'):
                    text = text.replace(f"{quote}./{module}{quote}", f"{quote}./{module}?v={build}{quote}")
        (output / name).write_text(text)
    (output / "audio").mkdir(exist_ok=True)
    shutil.copy2(WEB / "forest.mp3", output / "audio/forest.mp3")
    build_reports(output)
    write_source_archive(output)
    for name in ("game.wasm", "game.wasm.part0", "game.wasm.part1"):
        (output / name).unlink(missing_ok=True)
    current = {part[key] for part in config["wasmParts"] for key in ("url", "rawUrl")}
    for path in (output / "engine").glob("*.bin"):
        if re.fullmatch(r"[0-9a-f]{64}(?:\.gz)?\.bin", path.name) and path.relative_to(output).as_posix() not in current:
            path.unlink()
    print(f"Built {build} (game.pck: {config['fileSizes']['game.pck']} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Web export directory")
    parser.add_argument("--reuse-engine", action="store_true", help="Reuse the existing matching Web engine")
    args = parser.parse_args()
    build_web(args.directory.resolve(), args.reuse_engine)
