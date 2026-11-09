"""Reproducible Windows package. Requires Godot 4.7.1 and matching export templates."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def stamp_build():
    digest = hashlib.sha256()
    for path in sorted((ROOT / "godot").rglob("*")):
        relative = path.relative_to(ROOT / "godot")
        if ".godot" in relative.parts or "tests" in relative.parts or "shots" in relative.parts:
            continue
        if path.is_file() and path.suffix in {".gd", ".gdshader", ".tscn", ".godot"}:
            digest.update(relative.as_posix().encode())
            digest.update(path.read_bytes().replace(b"\r\n", b"\n"))
    build_id = digest.hexdigest()
    (ROOT / "godot/online/build_id.txt").write_text(build_id + "\n", encoding="utf-8")
    return build_id

def main(godot):
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if not version.startswith("4.7.1.stable"):
        raise SystemExit(f"Use Godot 4.7.1 stable; found {version}")
    build_id = stamp_build()
    output = ROOT / "dist/Phaethon-Windows"
    output.mkdir(parents=True, exist_ok=True)
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    for args in (["--editor", "--import", "--quit"], ["--export-release", "Windows Desktop", str(output / "Phaethon.exe")]):
        result = subprocess.run([str(godot), "--headless", "--path", str(ROOT / "godot"), *args],
            text=True, capture_output=True, creationflags=flags)
        log = result.stdout + result.stderr
        (ROOT / "dist" / ("import.log" if "--import" in args else "export.log")).write_text(log, encoding="utf-8")
        if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            print(log)
            raise SystemExit("Godot import/export failed; see dist logs")
    shutil.copyfile(ROOT / "docs/ONLINE-PLAY.md", output / "START-HERE.txt")
    shutil.copyfile(ROOT / "godot/audio/engines/CREDITS.md", output / "AUDIO-CREDITS.txt")
    shutil.copyfile(ROOT / "docs/GODOT-LICENSE.txt", output / "GODOT-LICENSE.txt")
    shutil.copyfile(ROOT / "docs/GODOT-COPYRIGHT.txt", output / "GODOT-COPYRIGHT.txt")
    (output / "BUILD.txt").write_text(f"Phaethon online 1\nGodot {version}\nBuild {build_id}\n", encoding="utf-8")
    (output / "Play-VR.cmd").write_text(
        '@echo off\ncd /d "%~dp0"\n'
        'if exist "C:\\Program Files\\Meta Horizon\\Support\\oculus-runtime\\oculus_openxr_64.json" '
        'set "XR_RUNTIME_JSON=C:\\Program Files\\Meta Horizon\\Support\\oculus-runtime\\oculus_openxr_64.json"\n'
        'start "" "%~dp0Phaethon.exe" --xr-mode on -- --vr\n', encoding="utf-8")
    archive = ROOT / "dist/Phaethon-Windows.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(output.iterdir()):
            if path.is_file(): bundle.write(path, f"Phaethon-Windows/{path.name}")
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (ROOT / "dist/SHA256SUMS.txt").write_text(f"{checksum}  {archive.name}\n", encoding="utf-8")
    print(f"Built {archive} ({archive.stat().st_size:,} bytes), SHA256 {checksum}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", type=Path)
    main(parser.parse_args().godot)
