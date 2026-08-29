# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Quentin Donnars

"""Open-Meteo answers 200 + ``{"latitude":nan,...}`` for a point outside a
regional model's domain (AROME France asked about the Adriatic). Bare ``nan``
is not JSON, so ``resp.json()`` used to blow up with ``Expecting value: line 1
column 13`` before the auto fallback chain could advance to ICON-EU. Every
tool died on the first wind fetch anywhere outside France.
"""

from __future__ import annotations

from datetime import UTC, datetime

import httpx
import respx

from openwind_data.adapters.openmeteo import (
    FORECAST_URL,
    MARINE_URL,
    OpenMeteoAdapter,
)
from openwind_data.routing.geometry import Point
from openwind_data.routing.passage import estimate_passage

# Kvarner, Croatia — well outside the AROME France grid.
PULA = Point(lat=44.87, lon=13.795)
SUSAK = Point(lat=44.50, lon=14.25)

# Verbatim shape of the upstream reply (2026-08): lowercase nan, HTTP 200.
NAN_BODY = (
    '{"latitude":nan,"longitude":nan,"generationtime_ms":0.0016,'
    '"utc_offset_seconds":0,"timezone":"GMT","timezone_abbreviation":"GMT"}'
)


def _window():
    return datetime(2026, 4, 26, 0, 0, tzinfo=UTC), datetime(2026, 4, 26, 23, 0, tzinfo=UTC)


@respx.mock
async def test_single_point_nan_payload_is_empty_series(marine_porquerolles):
    respx.get(FORECAST_URL).mock(
        return_value=httpx.Response(
            200, content=NAN_BODY, headers={"content-type": "application/json"}
        )
    )
    respx.get(MARINE_URL).mock(return_value=httpx.Response(200, json=marine_porquerolles))
    adapter = OpenMeteoAdapter(http_min_interval_s=0)
    start, end = _window()

    bundle = await adapter.fetch(
        SUSAK.lat, SUSAK.lon, start, end, models=["meteofrance_arome_france"]
    )

    assert bundle.wind_by_model["meteofrance_arome_france"].points == ()
    assert bundle.sea.points  # the marine endpoint is global and unaffected


@respx.mock
async def test_batch_partial_nan_keeps_covered_points(
    forecast_marseille_arome, marine_porquerolles
):
    covered = forecast_marseille_arome
    body = "[" + NAN_BODY + "," + httpx.Response(200, json=covered).text + "]"
    fc = respx.get(FORECAST_URL).mock(
        return_value=httpx.Response(200, content=body, headers={"content-type": "application/json"})
    )
    respx.get(MARINE_URL).mock(return_value=httpx.Response(200, json=[marine_porquerolles] * 2))
    adapter = OpenMeteoAdapter(http_min_interval_s=0)
    start, end = _window()
    points = [(SUSAK.lat, SUSAK.lon), (43.30, 5.35)]

    await adapter.prewarm_batch(points, start, end, ["meteofrance_arome_france"])
    assert fc.call_count == 1

    off = await adapter.fetch(*points[0], start, end, models=["meteofrance_arome_france"])
    on = await adapter.fetch(*points[1], start, end, models=["meteofrance_arome_france"])
    assert off.wind_by_model["meteofrance_arome_france"].points == ()
    assert on.wind_by_model["meteofrance_arome_france"].points
    assert fc.call_count == 1  # both served from the batch cache


@respx.mock
async def test_auto_chain_advances_past_nan_model(forecast_marseille_arome, marine_porquerolles):
    def route(request: httpx.Request) -> httpx.Response:
        if request.url.params.get("models") == "meteofrance_arome_france":
            return httpx.Response(
                200, content=NAN_BODY, headers={"content-type": "application/json"}
            )
        return httpx.Response(200, json=forecast_marseille_arome)

    respx.get(FORECAST_URL).mock(side_effect=route)
    respx.get(MARINE_URL).mock(return_value=httpx.Response(200, json=marine_porquerolles))
    adapter = OpenMeteoAdapter(http_min_interval_s=0)

    report = await estimate_passage(
        [PULA, SUSAK],
        datetime(2026, 4, 26, 6, 0, tzinfo=UTC),
        "cruiser_25ft",
        adapter=adapter,
        model="auto",
        segment_length_nm=10.0,
    )
    assert report.model == "icon_eu"
