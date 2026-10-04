"""The repository-root Dockerfile is generated, and everything it copies is actually in Git.

The second part matters because a host such as Render builds from a fresh `git clone`: a file that exists only on the
author's disk (git-ignored data, a derived folder) makes the image build fail there although it builds locally.
"""

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
APP = HERE.parents[2]
REPO = APP.parent.parent
sys.path.insert(0, str(APP / "scripts"))

import make_root_dockerfile as gen  # noqa: E402


def test_root_files_are_up_to_date():
    dockerfile, ignore = gen.build()
    assert (REPO / "Dockerfile").read_text(encoding="utf-8") == dockerfile, "run: python scripts/make_root_dockerfile.py"
    assert (REPO / ".dockerignore").read_text(encoding="utf-8") == ignore, "run: python scripts/make_root_dockerfile.py"


def _tracked(path: str) -> bool:
    out = subprocess.run(["git", "ls-files", "--", path], cwd=REPO, capture_output=True, text=True, check=True).stdout
    return bool(out.strip())


def test_every_copied_source_is_tracked_by_git():
    missing = []
    for line in (REPO / "Dockerfile").read_text(encoding="utf-8").splitlines():
        if not line.startswith("COPY") or "--from=" in line:
            continue
        *sources, _dest = line.split()[1:]
        for s in sources:
            s = re.sub(r"\$\{PACK_DATE\}", "2026-10-02", s)  # the build argument's default
            if not _tracked(s):
                missing.append(s)
    assert not missing, f"COPY sources not in Git, so a fresh clone cannot build: {missing}"


def test_start_script_and_dockerfiles_use_linux_line_endings():
    for p in (APP / "deploy" / "single" / "start.sh", APP / "deploy" / "single" / "Dockerfile", REPO / "Dockerfile"):
        assert b"\r" not in p.read_bytes(), p
