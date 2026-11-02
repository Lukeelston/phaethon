"""Bounded Godot invocation with hidden process and complete log evidence."""
import subprocess, sys, pathlib, json, time

engine = pathlib.Path(r'C:\Users\Luke\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe')
root = pathlib.Path(__file__).resolve().parents[1]
log = root / 'evidence' / sys.argv[1]
timeout = int(sys.argv[2])
args = sys.argv[3:]
log.parent.mkdir(exist_ok=True)
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = subprocess.SW_HIDE
start = time.monotonic()
with log.open('w',encoding='utf-8') as out:
    proc = subprocess.Popen([str(engine),*args],cwd=root,stdout=out,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
    try: code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
        proc.wait(timeout=15)
        code = 124
data=log.read_text(encoding='utf-8',errors='replace')
errors=[line for line in data.splitlines() if any(t in line for t in ['ERROR:', 'SCRIPT ERROR:', 'FAIL','Error:'])]
print(json.dumps({'exit_code':code,'elapsed':round(time.monotonic()-start,2),'log':str(log),'errors':errors[:30],'tail':data.splitlines()[-12:]}))
sys.exit(code)
