"""Run with python3 on Linux; uses real Unix sockets and mocked desktop tools."""
import os
from pathlib import Path
import socket
import stat
import subprocess
import tempfile


def main():
    helper = Path(__file__).resolve().parents[1] / "bin/video-wallpaper"
    with tempfile.TemporaryDirectory(prefix="pip-socket-") as temporary:
        root = Path(temporary)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        commands = root / "bin"
        commands.mkdir()
        for name, body in {
            "pgrep": "exit 1",
            "pkill": 'printf "%s\\n" "$*" >> "$TEST_LOG"',
            "omarchy-notification-send": "exit 0",
            "socat": 'printf "%s\\n" "$*" >> "$TEST_LOG"; cat >> "$TEST_LOG"',
            "mpvpaper": '''exec python3 - "$@" <<'PY'
import os, socket, sys
options = sys.argv[sys.argv.index('-o') + 1].split()
path = next(x.split('=', 1)[1] for x in options if x.startswith('input-ipc-server='))
with socket.socket(socket.AF_UNIX) as server:
    server.bind(path)
assert os.stat(path).st_mode & 0o077 == 0
PY''',
        }.items():
            command = commands / name
            command.write_text("#!/bin/bash\n" + body + "\n")
            command.chmod(0o700)
        log = root / "commands.log"
        env = dict(os.environ, HOME=str(root), XDG_RUNTIME_DIR=str(runtime),
                   PATH=f"{commands}:{os.environ['PATH']}", TEST_LOG=str(log))

        def run(*args, ok=True, overrides=None):
            result = subprocess.run(["bash", str(helper), *args], env=env | (overrides or {}),
                                    capture_output=True, text=True)
            assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)

        private = runtime / "artmrn.pip-video"
        endpoint = private / "mpvpaper.sock"
        run("status")
        assert stat.S_IMODE(private.stat().st_mode) == 0o700
        run("set", "https://example.test/video")
        assert endpoint.is_socket()
        run("pause")
        run("mute")
        assert str(endpoint) in log.read_text() and "cycle mute" in log.read_text()
        run("stop")
        assert not endpoint.exists()
        assert all(f"-u {os.geteuid()} -x mpvpaper" in line
                   for line in log.read_text().splitlines() if "mpvpaper" in line and "sock" not in line)

        def refused():
            before = log.read_text()
            for command in ("status", "stop", "pause", "mute"):
                run(command, ok=False)
            run("set", "https://example.test/video", ok=False)
            assert log.read_text() == before

        victim = root / "keep"
        victim.write_text("keep")
        endpoint.symlink_to(victim)
        refused()
        assert victim.read_text() == "keep" and endpoint.is_symlink()
        endpoint.unlink()
        endpoint.write_text("keep")
        refused()
        assert endpoint.read_text() == "keep"
        endpoint.unlink()
        private.chmod(0o755)
        refused()
        private.chmod(0o700)
        private.rmdir()
        private.symlink_to(root, target_is_directory=True)
        refused()
        private.unlink()
        runtime.chmod(0o755)
        refused()
        runtime.chmod(0o700)
        alias = root / "runtime-alias"
        alias.symlink_to(runtime, target_is_directory=True)
        run("stop", ok=False, overrides={"XDG_RUNTIME_DIR": str(alias)})
        run("stop", ok=False, overrides={"XDG_RUNTIME_DIR": ""})
        run("status")
        if os.geteuid() == 0:
            # Ownership rejection requires privileges to create a foreign-owned path.
            os.chown(private, 65534, 65534)
            refused()
            os.chown(private, 0, 0)
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(endpoint))
            os.chown(endpoint, 65534, 65534)
            refused()
            endpoint.unlink()
    print("runtime socket security checks passed")


if __name__ == "__main__":
    main()
