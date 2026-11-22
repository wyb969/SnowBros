"""Build the browser shell from a Web export.

With --reuse-engine, first export a replacement game.pck with the same Godot
version and Web preset as the existing distribution. Its WASM stays in place.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from zipfile import ZIP_DEFLATED, ZipFile

from build_reports import build_reports


WEB = Path(__file__).resolve().parent
MODULES = ("controls-model.js", "web-loader.js", "touch-ui.js", "touch-ui.css")
PART_SIZE = 20_000_000


def read_config(output, reuse):
    page = (output / "game.html").read_text()
    marker = r"window\.GODOT_CONFIG\s*=" if reuse else r"const GODOT_CONFIG\s*="
    match = re.search(marker + r"\s*(\{[^\n]*?\});", page)
    if not match:
        raise SystemExit("Expected a packaged game.html for --reuse-engine, or a fresh Godot export otherwise.")
    config = json.loads(match[1])
    if reuse:
        parts = [output / f"game.wasm.part{i}" for i in range(2)]
        if sum(p.stat().st_size for p in parts) != config["fileSizes"]["game.wasm"]:
            raise SystemExit("Existing WebAssembly parts are incomplete.")
    else:
        wasm = output / "game.wasm"
        if not PART_SIZE < wasm.stat().st_size <= 2 * PART_SIZE:
            raise SystemExit("Unexpected engine size for the two-part streaming loader.")
        with wasm.open("rb") as stream:
            for i in range(2):
                (output / f"game.wasm.part{i}").write_bytes(stream.read(PART_SIZE))
        wasm.unlink()
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
    revision = hashlib.sha256((output / "game.pck").read_bytes())
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
        if name == "touch-ui.js":
            for module in ("controls-model.js", "web-loader.js"):
                text = text.replace(f"'./{module}'", f"'./{module}?v={build}'")
        (output / name).write_text(text)
    (output / "audio").mkdir(exist_ok=True)
    shutil.copy2(WEB / "forest.mp3", output / "audio/forest.mp3")
    build_reports(output)
    write_source_archive(output)
    print(f"Built {build} (game.pck: {config['fileSizes']['game.pck']} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Web export directory")
    parser.add_argument("--reuse-engine", action="store_true", help="Reuse the existing matching Web engine")
    args = parser.parse_args()
    build_web(args.directory.resolve(), args.reuse_engine)
