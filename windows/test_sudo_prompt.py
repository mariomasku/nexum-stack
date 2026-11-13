"""Verify GUI authentication marker without reading or supplying any password."""
import fcntl
import os
import pty
import select
import signal
import subprocess
import termios
import time

master, slave = pty.openpty()
marker = '@@NEXUM-CHECK@@'
process = subprocess.Popen(['/usr/bin/sudo', '-k', '-v'], stdin=slave, stdout=slave, stderr=slave,
                           env=dict(os.environ, SUDO_PROMPT=marker), start_new_session=True,
                           preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
os.close(slave)
data = b''
try:
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and marker.encode() not in data:
        if select.select([master], [], [], 0.3)[0]:
            data += os.read(master, 4096)
    assert marker.encode() in data, 'sudo did not emit the GUI authentication marker'
    print('PASS SUDO_PROMPT; no password supplied')
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    os.close(master)
