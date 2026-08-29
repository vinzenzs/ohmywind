# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Quentin Donnars

"""``/healthz`` is the probe target of the container image and Helm chart.

Kubernetes probes it every few seconds: it has to be cheap, uncached, and
must not be swallowed by the catch-all MCP mount or the rate limiter.
"""

from __future__ import annotations

import importlib.util
import pathlib

from starlette.testclient import TestClient

_APP_PATH = (pathlib.Path(__file__).parents[1] / "app.py").resolve()
_spec = importlib.util.spec_from_file_location("hf_app_healthz", _APP_PATH)
app = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(app)


class _StubMcpApp:
    """Stands in for FastMCP's streamable-http app: never reached by /healthz."""

    class router:  # noqa: N801 — mirrors the Starlette attribute name
        @staticmethod
        def lifespan_context(_app):
            import contextlib

            @contextlib.asynccontextmanager
            async def _noop():
                yield

            return _noop()

    async def __call__(self, scope, receive, send):
        raise AssertionError("/healthz must not fall through to the MCP mount")


def test_healthz_is_cheap_and_uncached() -> None:
    client = TestClient(app.build_app(_StubMcpApp()))
    for _ in range(50):  # well past the POST rate limit; GET probes are never counted
        response = client.get("/healthz")
        assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["cache-control"] == "no-store"
