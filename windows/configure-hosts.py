#!/usr/bin/python3
"""Preserve Nexum's hosts entries across WSL restarts during installation."""
import pathlib
import re
import shutil


def configure():
    config = pathlib.Path('/etc/wsl.conf')
    original = config.read_text(encoding='utf-8') if config.exists() else ''
    section = re.search(r'^\s*\[network\][^\n]*\n(?:(?!^\s*\[).*(?:\n|$))*',
                        original, re.M | re.I)
    if section:
        block = section.group()
        option = r'^[ \t]*generateHosts[ \t]*=[^\n]*'
        if re.search(option, block, re.M | re.I):
            block = re.sub(option, 'generateHosts=false', block, flags=re.M | re.I)
        else:
            block = block.rstrip('\n') + '\ngenerateHosts=false\n'
        updated = original[:section.start()] + block + original[section.end():]
    else:
        updated = original.rstrip('\n') + '\n\n[network]\ngenerateHosts=false\n'
    if updated != original:
        if config.exists():
            shutil.copy2(config, '/etc/wsl.conf.nexum.bak')
        config.write_text(updated, encoding='utf-8')

    # WSL may already have removed the project's names. Restore only the standard
    # project vhost; production domains deliberately disabled by Nexum stay disabled.
    vhosts = pathlib.Path('/opt/config/httpd-vhosts.conf')
    if not vhosts.is_file():
        return
    text = vhosts.read_text(encoding='utf-8')
    if not re.search(r'^[ \t]*ServerName[ \t]+web\.local[ \t]*$', text, re.M | re.I):
        return
    hosts = pathlib.Path('/etc/hosts')
    original = hosts.read_text(encoding='utf-8')
    existing = set()
    for line in original.splitlines():
        fields = line.split('#', 1)[0].split()
        existing.update(name.lower() for name in fields[1:])
    missing = [name for name in ('web.local', 'www.web.local') if name not in existing]
    if missing:
        shutil.copy2(hosts, '/etc/hosts.nexum.bak')
        hosts.write_text(original.rstrip('\n') + '\n127.0.0.1\t' + ' '.join(missing) + '\n',
                         encoding='utf-8')


if __name__ == '__main__':
    configure()
