"""Run repository regression groups against both generated platforms in WSL."""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
failed = False
with tempfile.TemporaryDirectory(prefix='nexum-repos-', dir=str(pathlib.Path.home())) as temporary:
    base = pathlib.Path(temporary)
    shutil.copytree(root / 'pruebas', base / 'pruebas')
    for file in (base / 'pruebas').glob('*.sh'):
        file.write_bytes(file.read_bytes().replace(b'\r\n', b'\n'))
    for platform, script in [('linux', 'lvm-instalador.sh'), ('mac', 'macos/lvm-instalador.sh')]:
        for group in ('repos', 'clonar-ssh'):
            result = subprocess.run(['bash', str(base/'pruebas'/f'{group}.sh'), str(root/script)],
                                    capture_output=True, text=True, timeout=60)
            passed = sum(line.startswith('  ok') for line in result.stdout.splitlines())
            print(platform, group, 'rc', result.returncode, 'passed', passed)
            if result.returncode:
                print(result.stdout)
                print(result.stderr)
                failed = True
raise SystemExit(1 if failed else 0)
