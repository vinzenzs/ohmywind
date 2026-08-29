# Unified entry points for a repo where each package has its own toolchain:
# three uv projects and one npm workspace, previously four different
# incantations to remember depending on what you had just touched.
#
# These targets run exactly what CI runs, so a green `make check` locally
# means a green pipeline.

PY_PACKAGES := packages/data-adapters packages/mcp-core packages/hf-space
WEB := packages/web

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install every package's dependencies
	@for p in $(PY_PACKAGES); do echo "→ $$p"; (cd $$p && uv sync --extra dev); done
	npm ci

.PHONY: test
test: test-py test-web ## Run every test suite

.PHONY: test-py
test-py: ## Python suites (data-adapters, mcp-core, hf-space)
	@for p in $(PY_PACKAGES); do echo "→ $$p"; (cd $$p && uv run pytest -q) || exit 1; done

.PHONY: test-web
test-web: ## Web suite
	cd $(WEB) && npm run test

.PHONY: lint
lint: lint-py lint-web ## Lint everything

.PHONY: lint-py
lint-py: ## ruff check + format check
	uvx ruff check $(PY_PACKAGES)
	uvx ruff format --check $(PY_PACKAGES)

.PHONY: lint-web
lint-web: ## Typecheck + the lint budget CI enforces
	cd $(WEB) && npm run typecheck && npm run lint:budget

.PHONY: fmt
fmt: ## Apply Python formatting
	uvx ruff format $(PY_PACKAGES)
	uvx ruff check --fix $(PY_PACKAGES)

.PHONY: build
build: ## Production build of the web app
	cd $(WEB) && npm run build

.PHONY: check
check: lint test build ## Everything CI runs, in one command

.PHONY: dev
dev: ## Vite dev server
	cd $(WEB) && npm run dev

# ---- container & chart (deploy/). Same steps as .github/workflows/container.yml.

IMAGE ?= ohmywind-mcp:local
WEB_IMAGE ?= ohmywind-web:local
# Backend the web bundle calls, substituted at container start.
WEB_API_BASE ?= http://localhost:7860
CHART := deploy/helm/ohmywind-mcp

.PHONY: docker-build
docker-build: ## Build the generic server image from the repo root
	docker build -f deploy/docker/Dockerfile -t $(IMAGE) .

.PHONY: docker-run
docker-run: ## Run the image locally on :7860
	docker run --rm -p 7860:7860 -e 'OPENWIND_ALLOWED_HOSTS=localhost:*' $(IMAGE)

.PHONY: docker-build-web
docker-build-web: ## Build the web app image (nginx, backend-agnostic)
	docker build -f deploy/docker/Dockerfile.web -t $(WEB_IMAGE) .

.PHONY: docker-run-web
docker-run-web: ## Run the web image locally on :8080 against WEB_API_BASE
	docker run --rm -p 8080:8080 -e API_BASE=$(WEB_API_BASE) $(WEB_IMAGE)

.PHONY: helm-lint
helm-lint: ## Lint + render the chart with every optional resource enabled
	helm lint --strict $(CHART)
	helm template ci $(CHART) --set edgeSecret.value=x --set atlas.enabled=true \
		--set ingress.enabled=true --set autoscaling.enabled=true \
		--set podDisruptionBudget.enabled=true --set web.enabled=true --set auth.token=x \
		--set web.apiBase=https://mcp.example.test \
		--set web.ingress.enabled=true > /dev/null

.PHONY: mcp
mcp: ## Local MCP server over stdio, for a client on this machine
	cd packages/mcp-core && uv run python scripts/run_local.py
