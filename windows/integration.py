#!/usr/bin/python3
"""Read-only Windows integration manifest. Never exports private keys."""
import base64
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

DOMAIN = re.compile(r'(?=.{1,253}$)[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\Z')


def manifest(hosts_file='/etc/hosts', vhosts_file='/opt/config/httpd-vhosts.conf'):
    hosts = {}
    for line in pathlib.Path(hosts_file).read_text().splitlines():
        fields = line.split('#', 1)[0].split()
        if fields and fields[0] in ('127.0.0.1', '::1'):
            for name in fields[1:]:
                name = name.lower()
                if DOMAIN.fullmatch(name) and name not in ('localhost', os.uname().nodename.lower()):
                    hosts[name] = '127.0.0.1'
    path = pathlib.Path(vhosts_file)
    text = path.read_text() if path.is_file() else ''
    domains = set()
    certificates = {}
    for block in re.findall(r'<VirtualHost\b[^>]*>(.*?)</VirtualHost>', text, re.I | re.S):
        names = set()
        certificate = None
        for line in block.splitlines():
            parts = line.strip().split()
            if len(parts) < 2 or parts[0].startswith('#'):
                continue
            if parts[0].lower() in ('servername', 'serveralias'):
                names.update(n.lower() for n in parts[1:] if DOMAIN.fullmatch(n.lower()))
            if parts[0].lower() == 'sslcertificatefile':
                certificate = pathlib.Path(' '.join(parts[1:]).strip('"'))
        active = names.intersection(hosts)
        domains.update(active)
        if not active or certificate is None or not certificate.is_absolute() or not certificate.is_file():
            continue
        if certificate.stat().st_size > 65536:
            continue
        details = subprocess.run(['openssl', 'x509', '-in', str(certificate), '-noout', '-text'], capture_output=True, text=True)
        dns_names = set(re.findall(r'DNS:([A-Za-z0-9.-]+)', details.stdout))
        verified = subprocess.run(['openssl', 'verify', '-check_ss_sig', '-CAfile', str(certificate), str(certificate)], capture_output=True)
        if (details.returncode or verified.returncode or 'CA:FALSE' not in details.stdout
                or not dns_names or not dns_names.issubset(hosts)):
            continue
        # Export one certificate per virtual host, only if all its DNS names remain mapped.
        # Windows additionally rejects CA certificates and checks SANs against this manifest.
        p = subprocess.run(['openssl', 'x509', '-in', str(certificate), '-outform', 'DER'], capture_output=True)
        if p.returncode == 0:
            certificates[str(certificate)] = dict(der=base64.b64encode(p.stdout).decode(), domains=sorted(dns_names))
    return dict(schema=1, hosts={n: hosts[n] for n in sorted(domains)}, certificates=list(certificates.values()))


def doctor():
    checks = {}
    for name, args in {
        'systemd': ['systemctl', '--user', 'is-system-running'],
        'gtk': ['python3', '-c', 'import gi;gi.require_version("Gtk","3.0");from gi.repository import Gtk,Gdk,GdkPixbuf;assert Gtk.init_check()[0];p=GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB,True,8,2,2);assert Gdk.cairo_surface_create_from_pixbuf(p,1,None)'],
        'engine': ['/opt/nexum/nexum.sh', 'version'],
        'docker': ['docker', 'info', '--format', '{{.ServerVersion}}'],
        'keyring': ['gdbus', 'call', '--session', '--dest', 'org.freedesktop.secrets', '--object-path', '/org/freedesktop/secrets', '--method', 'org.freedesktop.DBus.Peer.Ping'],
    }.items():
        try:
            p = subprocess.run(args, capture_output=True, text=True, timeout=20)
            output = (p.stdout + p.stderr).strip()
            ok = p.returncode == 0
            if name == 'docker':
                ok = ok and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+[^\s]*', p.stdout.strip()) is not None
            checks[name] = dict(ok=ok, output=output)
        except (OSError, subprocess.TimeoutExpired) as error:
            checks[name] = dict(ok=False, output=str(error))
    checks['linux_projects'] = dict(ok=str(pathlib.Path('/opt/htdocs').resolve()).startswith('/opt/'), output='/opt/htdocs')
    checks['secret_tool'] = dict(ok=shutil.which('secret-tool') is not None, output=shutil.which('secret-tool') or 'Instalar libsecret-tools')
    print(json.dumps(checks, ensure_ascii=False, indent=2))
    return 0 if all(c['ok'] for n, c in checks.items() if n != 'docker') else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['manifest']:
        print(json.dumps(manifest()))
    elif sys.argv[1:] == ['doctor']:
        sys.exit(doctor())
    else:
        sys.exit('Uso: integration.py doctor|manifest')
