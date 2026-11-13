"""Behavior checks on fixtures only; no hosts or trust-store mutations."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


integration = load('integration', 'integration.py')
opener = load('opener', 'open.py')


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nexum-integration-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.hosts = self.root / 'hosts'
        self.vhosts = self.root / 'vhosts'
        self.hosts.write_text('127.0.0.1 localhost nexum.test\n192.0.2.1 remote.test\n')
        self.vhosts.write_text('<VirtualHost *:80>\nServerName nexum.test\n</VirtualHost>')

    def manifest(self):
        return integration.manifest(str(self.hosts), str(self.vhosts))

    def certificate(self, ca=False, extra=''):
        cert = self.root / 'cert.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=nexum.test', '-addext', 'basicConstraints=critical,CA:' + ('TRUE' if ca else 'FALSE'),
                        '-addext', 'subjectAltName=DNS:nexum.test' + extra,
                        '-keyout', str(self.root / 'key.pem'), '-out', str(cert)], check=True, capture_output=True)
        self.vhosts.write_text('<VirtualHost *:443>\nServerName nexum.test\nSSLCertificateFile "' + str(cert) + '"\n</VirtualHost>')

    def test_only_active_virtual_hosts(self):
        self.assertEqual(self.manifest()['hosts'], {'nexum.test': '127.0.0.1'})

    def test_disabled_host_removed(self):
        self.hosts.write_text('#127.0.0.1 nexum.test\n')
        self.assertEqual(self.manifest()['hosts'], {})

    def test_leaf_certificate_exported_without_key(self):
        self.certificate()
        result = self.manifest()
        self.assertEqual(len(result['certificates']), 1)
        self.assertNotIn('PRIVATE', str(result))

    def test_ca_never_exported(self):
        self.certificate(ca=True)
        self.assertEqual(self.manifest()['certificates'], [])

    def test_unmapped_certificate_name_rejected(self):
        self.certificate(extra=',DNS:real.example.com')
        self.assertEqual(self.manifest()['certificates'], [])

    def test_opener_preserves_url_characters(self):
        url = 'https://nexum.test/?q=%22&x=$danger;hello'
        self.assertEqual(opener.windows_target(url), url)

    def test_opener_rejects_commands(self):
        for target in ('javascript:alert(1)', 'powershell:bad', 'relative/path', 'file://remote/share'):
            with self.assertRaises(ValueError):
                opener.windows_target(target)


if __name__ == '__main__':
    unittest.main()
