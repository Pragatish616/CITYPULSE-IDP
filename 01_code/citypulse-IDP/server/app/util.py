"""Small shared helpers."""

from __future__ import annotations

import os
import time
import uuid


def uuid7() -> uuid.UUID:
    """Generate a UUIDv7 (RFC 9562): time-ordered, client-generatable, per docs/CONTRACTS.md.

    Python's stdlib `uuid` module does not gain `uuid7()` until 3.14 (we target 3.11+ per
    CLAUDE.md §7), so this is a minimal, dependency-free implementation: 48-bit millisecond
    Unix timestamp in the top bits, then version/variant bits, then random fill. Used by the
    ingest workers when they mint observation ids on the server's behalf — a real client
    (the Flutter app / outbox in T5.4) generates its own ids the same way, or via an
    equivalent Dart implementation; both must be time-ordered UUIDv7s per the contract.
    """
    ms = int(time.time() * 1000) & 0xFFFFFFFFFFFF  # 48 bits
    rand_a = int.from_bytes(os.urandom(2), "big") & 0x0FFF  # 12 bits
    rand_b = int.from_bytes(os.urandom(8), "big") & 0x3FFFFFFFFFFFFFFF  # 62 bits

    time_hex = ms.to_bytes(6, "big")
    version_and_rand_a = (0x7000 | rand_a).to_bytes(2, "big")  # version 7
    variant_and_rand_b = (0x8000000000000000 | rand_b).to_bytes(8, "big")  # variant 10

    return uuid.UUID(bytes=time_hex + version_and_rand_a + variant_and_rand_b)
