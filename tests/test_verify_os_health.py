import os
from pathlib import Path
import subprocess
import tempfile
import textwrap


def test_verify_os_health_extract_only(tmp_path, capsys):
    # create simulated boot and root directories under the repo WORKDIR
    repo_root = os.getcwd()
    boot_sim = Path(repo_root) / "boot-sim"
    root_sim = Path(repo_root) / "root-sim"
    boot_sim.mkdir(exist_ok=True)
    root_sim.mkdir(exist_ok=True)
    (boot_sim / "cmdline.txt").write_text("root=UUID=01234567-89ab-cdef-0123-456789abcdef quiet splash")
    (boot_sim / "config.txt").write_text("# config test\ndtoverlay=example-overlay\n")
    (root_sim / "etc").mkdir()
    (root_sim / "etc" / "os-release").write_text("NAME=OpenSUSE\n")
    (root_sim / "etc" / "fstab").write_text("# fstab\n")
    (root_sim / "lib").mkdir()
    (root_sim / "lib" / "modules").mkdir()

    # run the script in EXTRACT_ONLY=1 mode
    script = os.path.join(os.getcwd(), "scripts", "verify_os_health_v2.sh")
    env = os.environ.copy()
    env["EXTRACT_ONLY"] = "1"
    result = subprocess.run([script, "/dev/null"], check=False, env=env)
    assert result.returncode in (0, 2)  # 0 OK, 2 warns
