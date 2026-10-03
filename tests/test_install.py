"""Installer regression tests; no real desktop or user files are touched."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(os.environ.get('PIP_TEST_ROOT', Path(__file__).resolve().parents[1]))


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.hypr = self.home / '.config/hypr'
        self.hypr.mkdir(parents=True)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.original = {'hyprland.lua': '-- current desktop',
                         'bindings.lua': '-- current shortcuts\n'}
        for name, text in self.original.items():
            (self.hypr / name).write_text(text)
            (self.hypr / (name + '.bak')).write_text('-- stale backup\n')
        self.commands = self.home / 'commands'
        self.commands.mkdir()
        self.command('hyprctl', '''
if [[ "$1" == reload && "${FAIL_RELOAD:-}" == 1 ]]; then exit 1; fi
if [[ "$1" == configerrors ]]; then
  [[ "${FAIL_QUERY:-}" == 1 ]] && exit 1
  [[ "${FAIL_CONFIG:-}" == 1 ]] && echo 'injected config error'
fi
exit 0
''')
        self.command('sleep', 'exit 0')
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_STATE_HOME=str(self.home / 'state'),
                        PATH=f"{self.commands}:{os.environ['PATH']}")

    def command(self, name, body):
        path = self.commands / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def install(self, root=ROOT, **env):
        return subprocess.run(['bash', str(root / 'install'), '--yes'],
                              env=self.env | env, capture_output=True, text=True, timeout=10)

    def assert_original_configs(self):
        for name, text in self.original.items():
            self.assertEqual((self.hypr / name).read_text(), text)
            self.assertEqual((self.hypr / (name + '.bak')).read_text(), '-- stale backup\n')

    def test_failed_validation_restores_current_configs_and_all_helpers(self):
        original = self.bin / 'video-wallpaper'
        original.write_text('personal helper\n')
        original.chmod(0o700)
        link = self.bin / 'workspace-opacity'
        link.symlink_to('missing-original-target')
        result = self.install(FAIL_CONFIG='1')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_original_configs()
        self.assertEqual(original.read_text(), 'personal helper\n')
        self.assertEqual(original.stat().st_mode & 0o777, 0o700)
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), 'missing-original-target')
        self.assertFalse((self.bin / 'omarchy-pip-video').is_symlink())

    def test_hyprctl_failures_roll_back_instead_of_reporting_success(self):
        for failure in ('FAIL_RELOAD', 'FAIL_QUERY'):
            with self.subTest(failure=failure):
                result = self.install(**{failure: '1'})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assert_original_configs()
                self.assertEqual(list(self.bin.iterdir()), [])

    def test_missing_config_is_detected_before_helpers_change(self):
        (self.hypr / 'bindings.lua').unlink()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.bin.iterdir()), [])
        self.assertEqual((self.hypr / 'hyprland.lua').read_text(), self.original['hyprland.lua'])

    def test_helper_directory_is_never_modified(self):
        directory = self.bin / 'workspace-opacity'
        directory.mkdir()
        (directory / 'keep').write_text('keep')
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assert_original_configs()
        self.assertEqual((directory / 'keep').read_text(), 'keep')
        self.assertFalse((self.bin / 'video-wallpaper').is_symlink())

    def test_success_is_idempotent_and_keeps_replaced_helpers(self):
        (self.bin / 'video-wallpaper').write_text('personal helper\n')
        (self.bin / 'video-wallpaper.bak').write_text('old helper\n')
        for _ in range(2):
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stderr)
        for name in self.original:
            text = (self.hypr / name).read_text()
            self.assertTrue(text.startswith(self.original[name]))
            self.assertEqual(text.count('-- BEGIN artmrn.pip-video'), 1)
            self.assertIn('\n-- BEGIN artmrn.pip-video', text)
        self.assertEqual((self.bin / 'video-wallpaper').resolve(), ROOT / 'bin/video-wallpaper')
        backups = list((self.home / 'state/artmrn.pip-video').glob('install.*/bin/video-wallpaper'))
        self.assertTrue(any(not p.is_symlink() and p.read_text() == 'personal helper\n' for p in backups))
        self.assertEqual((self.bin / 'video-wallpaper.bak').read_text(), 'old helper\n')

    def test_config_symlink_survives_rollback(self):
        target = self.home / 'personal-bindings.lua'
        config = self.hypr / 'bindings.lua'
        config.rename(target)
        config.symlink_to(target)
        result = self.install(FAIL_CONFIG='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(config.is_symlink())
        self.assert_original_configs()

    def test_checkout_path_is_quoted_as_a_lua_string(self):
        root = self.home / 'plugin "with spaces"'
        shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        result = self.install(root)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, snippet in [('hyprland.lua', 'pip-video.lua'),
                              ('bindings.lua', 'pip-video-bindings.lua')]:
            line = next(x for x in (self.hypr / name).read_text().splitlines() if x.startswith('dofile('))
            self.assertEqual(json.loads(line[len('dofile('):-1]), str(root / 'hypr' / snippet))


if __name__ == '__main__':
    unittest.main()
