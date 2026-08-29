# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Quentin Donnars

"""Bearer-token gate on the MCP endpoint (OPENWIND_API_TOKEN)."""

from __future__ import annotations

import contextlib

import pytest
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.responses import PlainTextResponse
from starlette.routing import Mount, Route
from starlette.testclient import TestClient

import security  # sys.path prepared by conftest.py


def _app(*, tokens: tuple[str, ...]) -> TestClient:
    async def ok(_request):
        return PlainTextResponse("ok")

    async def mcp(scope, receive, send):
        await PlainTextResponse("mcp")(scope, receive, send)

    @contextlib.asynccontextmanager
    async def lifespan(_app):
        yield

    app = Starlette(
        routes=[
            Route("/healthz", ok),
            Route("/api/v1/archetypes", ok),
            Mount("/", app=mcp),
        ],
        middleware=[Middleware(security.ApiTokenMiddleware, tokens=tokens)],
        lifespan=lifespan,
    )
    return TestClient(app)


def test_unconfigured_leaves_mcp_open() -> None:
    client = _app(tokens=())
    assert client.post("/mcp").status_code == 200


def test_missing_token_is_401_with_challenge() -> None:
    client = _app(tokens=("s3cret",))
    resp = client.post("/mcp")
    assert resp.status_code == 401
    assert resp.headers["www-authenticate"].startswith("Bearer")
    assert "token" in resp.json()["error"]


@pytest.mark.parametrize(
    "header",
    ["Bearer wrong", "Basic czNjcmV0", "s3cret", "Bearer ", "bearer s3cret-but-longer"],
)
def test_wrong_or_malformed_credentials_are_401(header: str) -> None:
    client = _app(tokens=("s3cret",))
    assert client.post("/mcp", headers={"Authorization": header}).status_code == 401


def test_valid_token_passes_and_scheme_is_case_insensitive() -> None:
    client = _app(tokens=("s3cret",))
    assert client.post("/mcp", headers={"Authorization": "Bearer s3cret"}).status_code == 200
    assert client.post("/mcp", headers={"Authorization": "bearer s3cret"}).status_code == 200


def test_any_configured_token_is_accepted_for_rotation() -> None:
    client = _app(tokens=("old", "new"))
    for token in ("old", "new"):
        assert client.post("/mcp", headers={"Authorization": f"Bearer {token}"}).status_code == 200


def test_only_the_mcp_prefix_is_protected() -> None:
    client = _app(tokens=("s3cret",))
    assert client.get("/healthz").status_code == 200
    assert client.get("/api/v1/archetypes").status_code == 200
    # Sub-paths of the mount are covered, look-alike prefixes are not.
    assert client.post("/mcp/anything").status_code == 401
    assert client.get("/mcpx").status_code == 200


def test_preflight_is_never_challenged() -> None:
    client = _app(tokens=("s3cret",))
    assert client.options("/mcp").status_code == 200


def test_env_parsing_splits_and_strips(monkeypatch: pytest.MonkeyPatch) -> None:
    import importlib

    monkeypatch.setenv("OPENWIND_API_TOKEN", " a , b,,c ")
    mod = importlib.reload(security)
    try:
        assert mod.API_TOKENS == ("a", "b", "c")
    finally:
        monkeypatch.delenv("OPENWIND_API_TOKEN")
        importlib.reload(security)
