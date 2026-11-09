"""Exercise two real Godot ENet processes; always reap the processes we create."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def run(godot, address="127.0.0.1", port=27841):
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    with tempfile.TemporaryDirectory(prefix="phaethon-online-") as tmp:
        processes, handles = [], []
        try:
            for role in ("host", "mismatch", "guest"):
                log = open(Path(tmp) / f"{role}.log", "w", encoding="utf-8")
                handles.append(log)
                proc = subprocess.Popen([str(godot), "--headless", "--path", str(ROOT / "godot"),
                    "-s", "res://tests/test_online_peer.gd", "--", f"--role={role}",
                    f"--address={address}", f"--port={port}"], stdout=log, stderr=subprocess.STDOUT,
                    creationflags=flags)
                processes.append(proc)
                if role == "host":
                    time.sleep(0.6)
                if role == "mismatch":
                    assert proc.wait(timeout=7) == 0, "incompatible build was not rejected"
                    time.sleep(0.3)
            for proc in processes:
                assert proc.wait(timeout=14) == 0, f"Peer failed with exit {proc.returncode}"
        finally:
            for proc in processes:
                if proc.poll() is None:
                    proc.kill()
                proc.wait(timeout=5)
            for handle in handles:
                handle.close()
            for path in sorted(Path(tmp).glob("*.log")):
                content = path.read_text(encoding="utf-8")
                print(f"{path.stem}:\n{content}")
                if "SCRIPT ERROR" in content or "ERROR:" in content:
                    raise AssertionError("Godot error in peer log")
    print(f"ONLINE TWO-PROCESS PASS via {address}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", type=Path)
    parser.add_argument("--address", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=27841)
    args = parser.parse_args()
    run(args.godot, args.address, args.port)
