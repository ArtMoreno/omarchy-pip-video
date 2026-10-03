"""Exercise settings and media arguments without changing a live wallpaper."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(os.environ.get('PIP_TEST_ROOT', Path(__file__).resolve().parents[1]))


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.runtime = self.home / 'runtime'
        self.runtime.mkdir(mode=0o700)
        commands = self.home / 'bin'
        commands.mkdir()
        for name, body in {
            'pgrep': 'exit 1', 'pkill': 'exit 0',
            'omarchy-notification-send': 'exit 0',
            'wl-paste': 'cat "$TEST_MEDIA"',
            'mpvpaper': 'exec python3 -c \'import json,os,sys; open(os.environ["TEST_ARGS"],"w").write(json.dumps(sys.argv[1:]))\' "$@"',
            'hyprctl': 'exit 1', 'omarchy': 'exit 0',
        }.items():
            path = commands / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        self.log = self.home / 'args.json'
        self.clipboard = self.home / 'clipboard'
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(self.runtime),
                        PATH=f"{commands}:{os.environ['PATH']}",
                        TEST_MEDIA=str(self.clipboard), TEST_ARGS=str(self.log))

    def run_helper(self, name, *args):
        return subprocess.run(['bash', str(ROOT / 'bin' / name), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_muted_start_keeps_audio_available_for_unmuting(self):
        settings = self.home / '.config/artmrn.pip-video/settings.conf'
        settings.parent.mkdir(parents=True)
        settings.write_text('start_muted=1\n')
        result = self.run_helper('video-wallpaper', 'set', 'https://example.test/video')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.log.read_text())
        options = args[args.index('-o') + 1].split()
        self.assertIn('mute=yes', options)
        self.assertNotIn('no-audio', options)

    def test_clipboard_file_path_preserves_spaces(self):
        media = self.home / 'my video.mp4'
        media.touch()
        self.clipboard.write_text(str(media))
        result = self.run_helper('video-wallpaper', 'clip')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text())[-1], str(media))

    def test_doctor_reports_unavailable_compositor(self):
        result = self.run_helper('omarchy-pip-video', 'doctor')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('hyprland unavailable', result.stdout)
        self.assertNotIn('configerrors clean', result.stdout)


if __name__ == '__main__':
    unittest.main()
