"""Bounded runner for the distributed executable (never launches the editor)."""
from pathlib import Path
import json, subprocess, sys, time
root=Path(__file__).resolve().parents[1]
log_path=root/'evidence'/sys.argv[1]
timeout=int(sys.argv[2])
exe=Path(sys.argv[3]).resolve()
startup=subprocess.STARTUPINFO()
startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow=subprocess.SW_HIDE
t=time.time()
with log_path.open('w',encoding='utf-8') as log:
    p=subprocess.Popen([str(exe),*sys.argv[4:]],cwd=exe.parent,stdout=log,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
    try: code=p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True)
        p.wait(timeout=10);code=124
lines=log_path.read_text(encoding='utf-8',errors='replace').splitlines()
errors=[s for s in lines if 'ERROR:' in s or 'SCRIPT ERROR:' in s or 'FAIL' in s]
print(json.dumps({'exit_code':code,'elapsed':round(time.time()-t,2),'log':str(log_path),'errors':errors[:30],'tail':lines[-15:]}))
raise SystemExit(code if code else bool(errors))
