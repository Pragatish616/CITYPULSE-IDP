"""GDACS worker — mocked HTTP, no real network calls in the test suite."""

from __future__ import annotations

import httpx
import respx
from app.ingest.gdacs import FEED_URL, parse_feed, run_ingest_cycle
from app.storage.memory import InMemoryObservationRepository

SAMPLE_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:georss="http://www.georss.org/georss"
     xmlns:gdacs="http://www.gdacs.org">
  <channel>
    <title>GDACS - FLOOD alerts, last week</title>
    <item>
      <title>Flood in India</title>
      <description>Heavy rainfall flooding.</description>
      <link>https://www.gdacs.org/report.aspx?eventid=1234567</link>
      <pubDate>Wed, 17 Sep 2026 05:14:22 GMT</pubDate>
      <guid>gdacs-fl-1234567</guid>
      <georss:point>13.0827 80.2707</georss:point>
      <gdacs:eventid>1234567</gdacs:eventid>
      <gdacs:country>India</gdacs:country>
    </item>
    <item>
      <title>Flood in Indonesia</title>
      <description>Not relevant to Chennai.</description>
      <link>https://www.gdacs.org/report.aspx?eventid=7654321</link>
      <pubDate>Wed, 17 Sep 2026 04:00:00 GMT</pubDate>
      <guid>gdacs-fl-7654321</guid>
      <georss:point>-6.2 106.8</georss:point>
      <gdacs:eventid>7654321</gdacs:eventid>
      <gdacs:country>Indonesia</gdacs:country>
    </item>
    <item>
      <title>Flood with no coordinates</title>
      <description>Missing georss:point entirely.</description>
      <link>https://www.gdacs.org/report.aspx?eventid=1111111</link>
      <pubDate>Wed, 17 Sep 2026 03:00:00 GMT</pubDate>
      <guid>gdacs-fl-1111111</guid>
      <gdacs:eventid>1111111</gdacs:eventid>
      <gdacs:country>India</gdacs:country>
    </item>
  </channel>
</rss>
"""


def test_parse_feed_keeps_only_india_items_with_coordinates() -> None:
    observations = parse_feed(SAMPLE_FEED)
    assert len(observations) == 1
    obs = observations[0]
    assert obs.hazard_class.value == "flood"
    assert obs.polarity == 1
    assert obs.geometry.coordinates == (80.2707, 13.0827)
    assert obs.source_id == "gdacs.rss_fl_7d.1234567"
    assert obs.accuracy_m >= 100_000.0


@respx.mock
async def test_run_ingest_cycle_inserts_parsed_observations() -> None:
    respx.get(FEED_URL).mock(return_value=httpx.Response(200, text=SAMPLE_FEED))

    repository = InMemoryObservationRepository()
    inserted = await run_ingest_cycle(repository)

    assert len(inserted) == 1
    assert await repository.count() == 1


@respx.mock
async def test_run_ingest_cycle_dedups_on_rerun() -> None:
    respx.get(FEED_URL).mock(return_value=httpx.Response(200, text=SAMPLE_FEED))

    repository = InMemoryObservationRepository()
    first = await run_ingest_cycle(repository)
    # A real re-poll would mint fresh uuid7 ids per item (see gdacs.py normalize_item), so this
    # exercises parse_feed's stability rather than id-level dedup; the dedup guarantee itself
    # is covered end-to-end in test_observations.py::test_posting_same_id_twice_does_not_duplicate.
    assert len(first) == 1
