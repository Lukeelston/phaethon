"""Two real game views through the actual lobby. Works with editor or exported game."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def run(executable, rendered=False, exported=False, address="127.0.0.1", out=None):
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    out = Path(out or ROOT / "godot/shots/online").resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="phaethon-game-") as tmp:
        processes, handles = [], []
        try:
            for role in ("host", "guest"):
                log = open(Path(tmp) / f"{role}.log", "w", encoding="utf-8")
                handles.append(log)
                cmd = [str(executable)]
                if not exported: cmd += ["--path", str(ROOT / "godot")]
                if not rendered: cmd += ["--headless"]
                cmd += ["--audio-driver", "Dummy", "--max-fps", "60", "--",
                    "--online-test", "--online-game-test", "--mute", "--port=27843", "--track=network", f"--name={role.title()}",
                    f"--capture={out / (role + '.png')}", "--host" if role == "host" else f"--join={address}"]
                proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, creationflags=flags)
                processes.append(proc)
                if role == "host": time.sleep(2)
            for proc in processes:
                assert proc.wait(timeout=65) == 0, f"Game client failed: {proc.returncode}"
        finally:
            for proc in processes:
                if proc.poll() is None: proc.kill()
                proc.wait(timeout=5)
            for handle in handles: handle.close()
            logs = []
            for path in sorted(Path(tmp).glob("*.log")):
                content = path.read_text(encoding="utf-8")
                (out / path.name).write_text(content, encoding="utf-8")
                print(path.stem + ":\n" + content)
                logs.append(content)
            assert all("SCRIPT ERROR" not in content and "ERROR:" not in content for content in logs), "Godot errors in game logs"
    print("ONLINE GAME PASS")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--exported", action="store_true")
    parser.add_argument("--address", default="127.0.0.1")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    run(args.executable, args.rendered, args.exported, args.address, args.out)
