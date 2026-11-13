"""Build the shared scripts from Windows through a private LF snapshot in WSL."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
linux_root = subprocess.check_output(['wsl', '-d', 'Ubuntu', '--exec', 'wslpath', '-a', '-u', str(root)], text=True).strip()
code = '''import pathlib,sys,tempfile,shutil,subprocess
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="nexum-build-",dir=str(pathlib.Path.home())) as temp:
 target=pathlib.Path(temp)
 for name in ("src","ayuda"):
  shutil.copytree(root/name,target/name,ignore=shutil.ignore_patterns("windows-audit","__pycache__"))
 shutil.copy2(root/"construir.sh",target/"construir.sh")
 (target/"macos").mkdir()
 for path in target.rglob("*"):
  if path.is_file() and path.suffix in (".sh",".py",".swift",".html",".css",".js",".svg",".txt",".md"):
   path.write_bytes(path.read_bytes().replace(bytes([13,10]),bytes([10])))
 subprocess.run(["bash",str(target/"construir.sh")],check=True)
 for name in ("lvm-instalador.sh","macos/lvm-instalador.sh"):
  shutil.copyfile(target/name,root/name)
'''
subprocess.run(['wsl', '-d', 'Ubuntu', '--exec', 'python3', '-c', code, linux_root], check=True)
