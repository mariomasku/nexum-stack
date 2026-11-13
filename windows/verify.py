"""Windows/WSL smoke test runner. Stops only its own process groups."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
results = {}


def run(name, args, timeout=90):
    p = subprocess.run(args, capture_output=True, timeout=timeout)
    results[name] = dict(rc=p.returncode, stdout=p.stdout.decode('utf-8', errors='replace'),
                         stderr=p.stderr.decode('utf-8', errors='replace'))


try:
    linux_root = subprocess.check_output(['wsl', '-d', 'Ubuntu', '--exec', 'wslpath', '-a', '-u', str(ROOT)], timeout=30).decode('utf-8').strip()
    run('powershell', ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT/'test.ps1')])
    run('integration', ['wsl', '-d', 'Ubuntu', '--exec', 'python3', linux_root + '/test_integration.py'])
    run('cli', ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT/'nexum.ps1'), 'Run', 'version'])
    code = '''import subprocess,time,os,signal,json,pathlib
p=subprocess.Popen(['/opt/nexum/nexum.sh','ventana'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
try:
 time.sleep(12)
 alive=p.poll() is None
 log=pathlib.Path.home()/'.nexum/ventana.log'
 log_text=log.read_text() if log.exists() else ''
finally:
 try: os.killpg(p.pid,signal.SIGTERM)
 except ProcessLookupError: pass
 try: out,err=p.communicate(timeout=8)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
teardown_log=log.read_text() if log.exists() else ''
print(json.dumps(dict(alive_after_12s=alive,stdout=out,stderr=err,window_log=log_text,log_after_stop=teardown_log)))
raise SystemExit(0 if alive and 'Traceback' not in err+log_text else 1)
'''
    run('gui', ['wsl', '-d', 'Ubuntu', '--exec', 'python3', '-c', code])
finally:
    (ROOT/'verification.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, result in results.items():
        print(name, result['rc'], result['stdout'][:180], result['stderr'][:500])
raise SystemExit(1 if any(r['rc'] for r in results.values()) else 0)
