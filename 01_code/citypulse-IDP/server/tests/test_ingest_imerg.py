"""NASA IMERG rain context: mocked HTTP only, no real network calls in the test suite.

Image fixtures are built with Pillow from a small, synthetic copy of GIBS's colour legend (same format as the real one:
rgb -> a half-open rate range, a transparent "below 0.1 mm/h" entry and an open top bin).
"""

from __future__ import annotations

import io
from datetime import datetime, timedelta, timezone

import httpx
import pytest
import respx
from PIL import Image

from app.ingest import imerg
from app.ingest.imerg import (
    COLORMAP_URL,
    DOMAINS_URL,
    WMS_URL,
    RainContextService,
    RainUnavailable,
    decode_slice,
    intensity_class,
    parse_colormap,
    parse_latest_time,
)

# Light, moderate, heavy and top colours used by the tests.
LIGHT = (0, 118, 78)  # [0.1, 0.1059)
MODERATE = (250, 200, 0)  # [3.0, 5.0)
HEAVY = (255, 100, 0)  # [10.0, 20.0)
TOP = (58, 3, 48)  # [53.0884, +INF)


def legend_xml() -> str:
    entries = [
        '<ColorMapEntry rgb="128,128,128" transparent="true" nodata="true" ref="0"/>',
        '<ColorMapEntry rgb="191,191,191" transparent="true" sourceValue="[-INF,0.1)" value="[-INF,0.1)" ref="1"/>',
        f'<ColorMapEntry rgb="{LIGHT[0]},{LIGHT[1]},{LIGHT[2]}" transparent="false" sourceValue="[0.1,0.1059)" value="[0.1,0.1059)" ref="2"/>',
    ]
    for i in range(
        22
    ):  # filler bins so the legend looks like the real one (>= 20 usable entries)
        lo = 0.11 + i * 0.01
        entries.append(
            f'<ColorMapEntry rgb="0,{140 + i},{60 + i}" transparent="false" value="[{lo:.2f},{lo + 0.01:.2f})" ref="{3 + i}"/>'
        )
    entries += [
        f'<ColorMapEntry rgb="{MODERATE[0]},{MODERATE[1]},{MODERATE[2]}" transparent="false" value="[3.0,5.0)" ref="30"/>',
        f'<ColorMapEntry rgb="{HEAVY[0]},{HEAVY[1]},{HEAVY[2]}" transparent="false" value="[10.0,20.0)" ref="31"/>',
        f'<ColorMapEntry rgb="{TOP[0]},{TOP[1]},{TOP[2]}" transparent="false" value="[53.0884,+INF)" ref="32"/>',
    ]
    return "<ColorMaps><ColorMap>" + "".join(entries) + "</ColorMap></ColorMaps>"


def png(pixels: dict[tuple[int, int], tuple[int, int, int]]) -> bytes:
    image = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    for xy, rgb in pixels.items():
        image.putpixel(xy, (*rgb, 255))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


# A real DescribeDomains reply captured from GIBS on 5 Oct 2026 (newest image 09:30Z).
REAL_DOMAINS = (
    "<Domains xmlns:ows='http://www.opengis.net/ows/1.1'><DimensionDomain><ows:Identifier>time</ows:Identifier>"
    "<Domain>1998-01-01T00:00:00Z/2025-09-13T19:30:00Z/PT30M,2025-09-13T20:30:00Z/2026-01-22T00:00:00Z/PT30M,"
    "2026-01-22T01:00:00Z/2026-02-10T00:00:00Z/PT30M,2026-02-10T01:00:00Z/2026-10-05T09:30:00Z/PT30M</Domain>"
    "<Size>4</Size></DimensionDomain></Domains>"
)
LATEST = datetime(2026, 10, 5, 9, 30, tzinfo=timezone.utc)
NOW = datetime(
    2026, 10, 5, 15, 30, tzinfo=timezone.utc
)  # six hours after the newest image, as seen in practice


# ---------------------------------------------------------------------------------------------- pure functions


def test_parse_colormap_keeps_rain_colours_and_skips_transparent_ones() -> None:
    legend = parse_colormap(legend_xml())
    assert (128, 128, 128) not in legend and (191, 191, 191) not in legend
    assert legend[LIGHT].low == 0.1 and legend[LIGHT].high == pytest.approx(0.1059)
    assert legend[MODERATE].mid == pytest.approx(4.0)
    assert legend[TOP].high == float("inf") and legend[TOP].mid == pytest.approx(
        53.0884
    )


def test_parse_colormap_refuses_a_legend_that_looks_wrong() -> None:
    with pytest.raises(ValueError):
        parse_colormap("<ColorMaps><ColorMap></ColorMap></ColorMaps>")


@pytest.mark.parametrize(
    ("rate", "expected"),
    [
        (0.0, "none"),
        (0.099, "none"),
        (0.1, "light"),
        (2.49, "light"),
        (2.5, "moderate"),
        (7.59, "moderate"),
        (7.6, "heavy"),
        (49.9, "heavy"),
        (50.0, "violent"),
        (120.0, "violent"),
    ],
)
def test_intensity_bands(rate: float, expected: str) -> None:
    assert intensity_class(rate) == expected


def test_parse_latest_time_reads_the_end_of_the_last_range() -> None:
    assert parse_latest_time(REAL_DOMAINS) == LATEST
    with pytest.raises(ValueError):
        parse_latest_time("<Domains/>")


def test_decode_a_dry_image_is_all_zero() -> None:
    stats = decode_slice(png({}), parse_colormap(legend_xml()), LATEST)
    assert (
        stats.wet_pixels,
        stats.unmatched_pixels,
        stats.mean_mm_h,
        stats.peak_mm_h,
    ) == (0, 0, 0.0, 0.0)
    assert stats.pixels == 100


def test_decode_counts_rates_and_peak() -> None:
    legend = parse_colormap(legend_xml())
    stats = decode_slice(
        png({(0, 0): MODERATE, (1, 0): MODERATE, (2, 0): HEAVY}), legend, LATEST
    )
    assert stats.wet_pixels == 3
    assert stats.peak_mm_h == pytest.approx(15.0)
    assert stats.mean_mm_h == pytest.approx((4.0 + 4.0 + 15.0) / 100)


def test_decode_matches_a_slightly_different_colour_but_not_a_far_one() -> None:
    legend = parse_colormap(legend_xml())
    near = (MODERATE[0] - 3, MODERATE[1] + 2, MODERATE[2])
    stats = decode_slice(png({(0, 0): near, (1, 1): (10, 200, 250)}), legend, LATEST)
    assert stats.wet_pixels == 1 and stats.unmatched_pixels == 1


def test_decode_rejects_something_that_is_not_an_image() -> None:
    with pytest.raises(ValueError):
        decode_slice(
            b"<ServiceException>no such time</ServiceException>",
            parse_colormap(legend_xml()),
            LATEST,
        )


# ---------------------------------------------------------------------------------------------- the service


def mock_gibs(
    router: respx.MockRouter,
    per_time: dict[datetime, bytes] | None = None,
    default: bytes | None = None,
) -> None:
    router.get(COLORMAP_URL).mock(return_value=httpx.Response(200, text=legend_xml()))
    router.get(DOMAINS_URL).mock(return_value=httpx.Response(200, text=REAL_DOMAINS))

    def wms(request: httpx.Request) -> httpx.Response:
        when = datetime.strptime(
            request.url.params["TIME"], "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=timezone.utc)
        body = (per_time or {}).get(when, default if default is not None else png({}))
        return httpx.Response(200, content=body, headers={"content-type": "image/png"})

    router.get(WMS_URL).mock(side_effect=wms)


async def test_service_builds_the_context_from_six_images() -> None:
    per_time = {
        LATEST: png({(0, 0): HEAVY}),  # 15 mm/h in one cell of 100
        LATEST - timedelta(minutes=30): png({(0, 0): MODERATE, (1, 0): MODERATE}),
    }
    with respx.mock(assert_all_called=False) as router:
        mock_gibs(router, per_time)
        out = await RainContextService(clock=lambda: NOW).get()
    assert out["as_of"] == "2026-10-05T09:30:00Z"
    assert (
        out["data_age_minutes"] == 360
        and out["stale"] is False
        and out["served"] == "fresh"
    )
    assert (
        out["now"]["intensity_class"] == "heavy"
        and out["now"]["peak_rate_mm_h"] == 15.0
    )
    assert out["now"]["wet_fraction"] == 0.01
    assert out["recent"]["slices_used"] == 6 and out["recent"]["slices_missing"] == 0
    # area means: 0.15 and 0.08 mm/h over two half-hours -> (0.15 + 0.08) * 0.5
    assert out["recent"]["area_mean_accumulation_mm"] == pytest.approx(0.12, abs=0.01)
    assert out["source_id"] == "nasa-gibs.imerg-30min" and "NASA" in out["credit"]
    assert any("not flooding" in n.lower() for n in out["notes"])


async def test_second_call_is_served_from_the_cache() -> None:
    with respx.mock(assert_all_called=False) as router:
        mock_gibs(router)
        service = RainContextService(clock=lambda: NOW)
        await service.get()
        calls_after_first = router.calls.call_count
        second = await service.get()
        assert router.calls.call_count == calls_after_first
    assert second["served"] == "cache"


async def test_failed_refresh_serves_the_last_good_result_marked_stale() -> None:
    clock = {"now": NOW}
    service = RainContextService(clock=lambda: clock["now"], ttl_seconds=900)
    with respx.mock(assert_all_called=False) as router:
        mock_gibs(router, default=png({(0, 0): LIGHT}))
        good = await service.get()
    clock["now"] = NOW + timedelta(minutes=20)  # cache expired
    with respx.mock(assert_all_called=False) as router:
        router.get(COLORMAP_URL).mock(
            return_value=httpx.Response(200, text=legend_xml())
        )
        router.get(DOMAINS_URL).mock(return_value=httpx.Response(503))
        later = await service.get()
    assert good["served"] == "fresh" and later["served"] == "last-good"
    assert later["stale"] is True and "refresh_error" in later
    assert (
        later["as_of"] == good["as_of"]
        and later["data_age_minutes"] == good["data_age_minutes"] + 20
    )


async def test_no_earlier_result_and_a_failure_is_reported_not_invented() -> None:
    with respx.mock(assert_all_called=False) as router:
        router.get(COLORMAP_URL).mock(return_value=httpx.Response(500))
        with pytest.raises(RainUnavailable):
            await RainContextService(clock=lambda: NOW).get()


async def test_old_upstream_data_is_flagged_stale_even_when_the_refresh_worked() -> (
    None
):
    with respx.mock(assert_all_called=False) as router:
        mock_gibs(router)
        out = await RainContextService(clock=lambda: LATEST + timedelta(hours=20)).get()
    assert out["stale"] is True and out["served"] == "fresh"


async def test_a_missing_older_image_is_counted_not_hidden() -> None:
    def wms(request: httpx.Request) -> httpx.Response:
        if request.url.params["TIME"].endswith("T08:00:00Z"):
            return httpx.Response(404)
        return httpx.Response(
            200, content=png({}), headers={"content-type": "image/png"}
        )

    with respx.mock(assert_all_called=False) as router:
        router.get(COLORMAP_URL).mock(
            return_value=httpx.Response(200, text=legend_xml())
        )
        router.get(DOMAINS_URL).mock(
            return_value=httpx.Response(200, text=REAL_DOMAINS)
        )
        router.get(WMS_URL).mock(side_effect=wms)
        out = await RainContextService(clock=lambda: NOW).get()
    assert out["recent"]["slices_missing"] == 1 and out["recent"]["slices_used"] == 5


async def test_the_newest_image_failing_is_a_failure() -> None:
    def wms(request: httpx.Request) -> httpx.Response:
        if request.url.params["TIME"] == "2026-10-05T09:30:00Z":
            return httpx.Response(500)
        return httpx.Response(
            200, content=png({}), headers={"content-type": "image/png"}
        )

    with respx.mock(assert_all_called=False) as router:
        router.get(COLORMAP_URL).mock(
            return_value=httpx.Response(200, text=legend_xml())
        )
        router.get(DOMAINS_URL).mock(
            return_value=httpx.Response(200, text=REAL_DOMAINS)
        )
        router.get(WMS_URL).mock(side_effect=wms)
        with pytest.raises(RainUnavailable):
            await RainContextService(clock=lambda: NOW).get()


# ---------------------------------------------------------------------------------------------- the endpoint


def test_endpoint_returns_the_context(client, app_instance) -> None:
    app_instance.state.rain_service = RainContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        mock_gibs(router, default=png({(0, 0): MODERATE}))
        router.route(host="testserver").pass_through()
        response = client.get("/context/rain")
    assert response.status_code == 200
    body = response.json()
    assert (
        body["now"]["intensity_class"] == "moderate" and body["data_age_minutes"] == 360
    )


def test_endpoint_says_503_when_nasa_cannot_be_reached(client, app_instance) -> None:
    app_instance.state.rain_service = RainContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        router.get(COLORMAP_URL).mock(return_value=httpx.Response(500))
        router.route(host="testserver").pass_through()
        response = client.get("/context/rain")
    assert response.status_code == 503
    assert "NASA GIBS" in response.json()["detail"]


def test_rain_is_not_written_to_the_observation_store(client, app_instance) -> None:
    app_instance.state.rain_service = RainContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        mock_gibs(router, default=png({(0, 0): HEAVY}))
        router.route(host="testserver").pass_through()
        client.get("/context/rain")
    assert client.get("/observations").json() == []


def test_module_constants_match_the_chennai_pack_box() -> None:
    assert imerg.CHENNAI_BBOX == (12.75, 79.95, 13.25, 80.35)
