"""Single source of truth for hazard-class and source-class vocabularies.

CLAUDE.md §8 and docs/CONTRACTS.md §5 require these to live in one config file
(config/hazard_classes.yaml) and never be duplicated in code. This module parses
that file once at import time and derives the enums the Pydantic models use.
"""

from __future__ import annotations

from enum import Enum
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

# server/app/config.py -> parents[0]=app, [1]=server, [2]=repo root
_REPO_ROOT = Path(__file__).resolve().parents[2]
HAZARD_CONFIG_PATH = _REPO_ROOT / "config" / "hazard_classes.yaml"


@lru_cache(maxsize=1)
def load_hazard_config() -> dict[str, Any]:
    """Parse config/hazard_classes.yaml. Cached — the file is read once per process."""
    with HAZARD_CONFIG_PATH.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not data or "classes" not in data or "source_reliability" not in data:
        raise ValueError(
            f"{HAZARD_CONFIG_PATH} is missing required 'classes' or 'source_reliability' keys"
        )
    return data


_config = load_hazard_config()
HAZARD_CLASS_NAMES: list[str] = list(_config["classes"].keys())
SOURCE_CLASS_NAMES: list[str] = list(_config["source_reliability"].keys())

# Dynamic (str, Enum) built from the yaml — this is the "one source of truth" the
# HazardObservation and EdgeBelief models import, rather than a second hardcoded list.
HazardClass = Enum("HazardClass", {name: name for name in HAZARD_CLASS_NAMES}, type=str)
SourceClass = Enum("SourceClass", {name: name for name in SOURCE_CLASS_NAMES}, type=str)


def hazard_class_params(hazard_class: str) -> dict[str, Any]:
    """T_c, severity, h_max_mm, display_noun, etc. for one hazard class."""
    return _config["classes"][hazard_class]
