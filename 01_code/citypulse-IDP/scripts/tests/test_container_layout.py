"""The report server starts from a folder laid out like the one-container image, not just from the whole repository.

Found on Render (4 Oct 2026): the image held server/app but not config/hazard_classes.yaml, which the server reads relative to its own
folder, so it crashed at start and the container restarted every ten seconds. Everything passed locally because the full repository
was there. This copies only what the image copies and imports the app.
"""

import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
DOCKERFILE = (APP / "deploy" / "single" / "Dockerfile").read_text(encoding="utf-8")


def test_report_server_imports_from_the_image_layout(tmp_path):
    srv = tmp_path / "srv"
    shutil.copytree(APP / "server" / "app", srv / "server" / "app", ignore=shutil.ignore_patterns("__pycache__"))
    # Only the config files the Dockerfile copies under /srv/config.
    for line in DOCKERFILE.splitlines():
        if line.startswith("COPY") and "/srv/config/" in line:
            src = line.split()[1]
            (srv / "config").mkdir(exist_ok=True)
            shutil.copy(APP / src, srv / "config" / Path(src).name)
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"], cwd=srv / "server", capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, result.stderr[-800:]


def test_router_finds_its_files_in_the_image_layout():
    """The router reads cities.yaml and hazard_classes.yaml from /app/config, plus the pack and places named inside cities.yaml."""
    copied = [line for line in DOCKERFILE.splitlines() if line.startswith("COPY") and "/app/" in line]
    text = "\n".join(copied)
    assert "config/cities.yaml" in text and "hazard_classes.yaml" in text
    assert "data/places" in text and "data/packs/" in text
