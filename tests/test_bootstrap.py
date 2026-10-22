"""Test the stage-two handoff with fake Ansible and certificate scripts.

Run with: python3 -B -m unittest discover -s tests -v
"""

import os
from pathlib import Path
import pty
import subprocess
import tempfile
import unittest


class StageTwoTest(unittest.TestCase):
    def test_certificate_step_runs_after_ansible_as_user_with_terminal(self):
        with tempfile.TemporaryDirectory(prefix='workstation bootstrap tests ') as temporary:
            root = Path(temporary)
            toolkit = root / 'Expensify-ToolKit'
            (toolkit / 'ansible').mkdir(parents=True)
            (toolkit / 'laptop-config').mkdir()
            (toolkit / 'laptop-config/fixCACerts.sh').write_text('''#!/bin/bash
set -eu
[[ -t 0 ]] || exit 97
[[ "$EUID" -eq "$EXPECTED_UID" ]] || exit 98
[[ "$0" == "$HOME/Expensify-ToolKit/laptop-config/fixCACerts.sh" ]] || exit 95
echo fixer >> "$BOOTSTRAP_ORDER"
exit "$FIXER_STATUS"
''')
            binaries = root / 'bin'
            binaries.mkdir()
            ansible = binaries / 'ansible-playbook'
            ansible.write_text('''#!/bin/bash
[[ "$1" == --ask-become-pass ]] || exit 96
[[ "$PWD" == "$HOME/Expensify-ToolKit/ansible" ]] || exit 95
echo ansible >> "$BOOTSTRAP_ORDER"
exit "$ANSIBLE_STATUS"
''')
            ansible.chmod(0o755)
            tput = binaries / 'tput'
            tput.write_text('#!/bin/bash\nexit 0\n')
            tput.chmod(0o755)

            # Load only the real function definitions; never run installers or
            # account/SSH setup from the top-level onboarding flow.
            source = (Path(__file__).resolve().parents[1] / 'bootstrap.sh').read_text()
            marker = '# Note: Quoting the heredoc delimiter'
            self.assertEqual(source.count(marker), 1)
            functions = root / 'bootstrap-functions.sh'
            functions.write_text(source.split(marker)[0])
            order = root / 'order'
            env = dict(os.environ, PATH=f'{binaries}:/usr/bin:/bin', HOME=str(root),
                       BOOTSTRAP_ORDER=str(order), EXPECTED_UID=str(os.geteuid()))
            env.pop('BASH_ENV', None)
            master, terminal = pty.openpty()
            self.addCleanup(os.close, master)
            self.addCleanup(os.close, terminal)
            for ansible_status, fixer_status, expected_status, expected_order in (
                    (0, 0, 0, 'ansible\nfixer\n'),
                    (42, 0, 42, 'ansible\n'),
                    (0, 1, 1, 'ansible\nfixer\n')):
                with self.subTest(ansible_status=ansible_status, fixer_status=fixer_status):
                    order.unlink(missing_ok=True)
                    env.update(ANSIBLE_STATUS=str(ansible_status), FIXER_STATUS=str(fixer_status))
                    result = subprocess.run([
                        '/bin/bash', '-c',
                        'source "$1"; userFullName="Test User"; userEmail="test@example.invalid"; '
                        'userGithub="test-user"; start_bootstrap_stage2',
                        'test-bootstrap', str(functions),
                    ], stdin=terminal, env=env, capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, expected_status, result.stderr)
                    self.assertEqual(order.read_text(), expected_order)


if __name__ == '__main__':
    unittest.main()
