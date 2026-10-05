"""Runs the field-log page's own logic tests (Node) as part of the server suite. Skipped where Node is not installed."""

import shutil
import subprocess
from pathlib import Path

import pytest

STATIC = Path(__file__).resolve().parents[1] / "app" / "static" / "fieldlog"


@pytest.mark.skipif(shutil.which("node") is None, reason="Node.js is not installed")
def test_page_logic_and_text_tables_pass_under_node() -> None:
    result = subprocess.run(
        ["node", "--test", "core.test.mjs"],
        cwd=STATIC,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, result.stdout[-1500:] + result.stderr[-500:]
