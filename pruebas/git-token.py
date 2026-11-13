"""Exercise the real Git credential protocol with a dummy token, without network."""
import os
import pathlib
import re
import subprocess
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'src/comun/repositorios-github/github_command.sh').read_text(encoding='utf-8')
function = re.search(r'^function repo_github_helper\(\) \{\n.*?^\}', source, re.M | re.S).group()
helper = subprocess.check_output(['bash', '-c', function + '\nrepo_github_helper'], text=True).strip()


class Credentials(unittest.TestCase):
    def request(self, protocol='https', host='github.com', operation='fill'):
        return subprocess.run(['git', '-c', 'credential.helper=', '-c', 'credential.helper=' + helper,
                               'credential', operation], input=f'protocol={protocol}\nhost={host}\n\n',
                              text=True, capture_output=True,
                              env=dict(os.environ, NEXUM_GIT_TOKEN='fixture-token', GIT_TERMINAL_PROMPT='0', GIT_ASKPASS='/bin/false'))

    def test_github(self):
        result = self.request()
        self.assertEqual(result.returncode, 0)
        self.assertIn('username=x-access-token', result.stdout)
        self.assertIn('password=fixture-token', result.stdout)

    def test_other_host(self):
        self.assertNotIn('fixture-token', self.request(host='github.com.attacker.test').stdout)

    def test_plain_http(self):
        self.assertNotIn('fixture-token', self.request(protocol='http').stdout)

    def test_never_store(self):
        self.assertEqual(self.request(operation='approve').stdout, '')


if __name__ == '__main__':
    unittest.main()
