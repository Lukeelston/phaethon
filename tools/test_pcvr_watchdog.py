"""Exercise the release supervisor with a native-startup stall before GDScript."""
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    source = Path(__file__).with_name("PcvrBoot.cs")
    compiler = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        launcher = root / "BootTest.exe"
        worker = root / "BootTest.engine"
        subprocess.run([compiler, "/nologo", "/target:winexe", "/reference:System.Windows.Forms.dll",
                        f"/out:{launcher}", source], check=True)
        fake = root / "Worker.cs"
        fake.write_text('''
using System;
using System.Threading;
class Worker {
    static int Main(string[] args) {
        if (Array.IndexOf(args, "--track=range") < 0) return 9;
        if (Environment.GetEnvironmentVariable("PHAETHON_BOOT_ATTEMPT") == "1") {
            if (Array.IndexOf(args, "--runtime-failure") >= 0) {
                Console.Error.WriteLine("OpenXR loader failed to start");
                return 1;
            }
            if (Array.IndexOf(args, "--stall-menu") >= 0) {
                Console.WriteLine("PCVR BOOT: feature=true xr_ready=true");
                Console.WriteLine("PCVR STAGE: building menu");
            } else {
                Console.WriteLine("OpenXR: entering native session creation");
            }
            Console.WriteLine("last driver message");
            Thread.Sleep(90000);
            return 8;
        }
        Console.WriteLine("PCVR BOOT: feature=true xr_ready=true");
        Console.WriteLine("VR MENU: ready");
        return 0;
    }
}
''', encoding="utf-8")
        subprocess.run([compiler, "/nologo", f"/out:{worker}", fake], check=True)
        env = dict(os.environ, APPDATA=temporary)
        args = [launcher, "--headless", "--", "--track=range"]
        subprocess.run(args, env=env, timeout=80, capture_output=True, check=True)
        logs = root / "ElstonWorks/Phaethon-VR/boot"
        [first] = logs.glob("*.log")
        saved = first.read_bytes()
        text = saved.decode("utf-8-sig")
        for expected in ["process start", "WATCHDOG attempt=1 waiting_at=OpenXR: entering native session creation",
                         "DEADLINE terminating stalled engine", "attempt=2", "PCVR BOOT:", "exit=0"]:
            assert expected in text, expected
        # An initialized runtime can still freeze while the first menu is built.
        subprocess.run(args + ["--stall-menu"], env=env, timeout=80, capture_output=True, check=True)
        [second] = [path for path in logs.glob("*.log") if path != first]
        assert "WATCHDOG attempt=1 waiting_at=PCVR STAGE: building menu" in second.read_text()
        subprocess.run(args + ["--runtime-failure"], env=env, timeout=10, capture_output=True, check=True)
        [third] = [path for path in logs.glob("*.log") if path not in (first, second)]
        assert "OpenXR retry in 1 second" in third.read_text()
        assert first.read_bytes() == saved
    print("PCVR WATCHDOG PASS: native and post-XR stalls, early runtime failure, bounded retries, three intact logs")


if __name__ == "__main__":
    main()
