#!/bin/sh
# Runs from /docker-entrypoint.d/ before nginx starts (nginx-unprivileged
# executes every *.sh there, as uid 101).
#
# The bundle in the image was built with the placeholder __OHMYWIND_API_BASE__
# instead of a backend URL, so one public image serves any deployment and no
# hostname is ever compiled into a published artefact. This script copies the
# bundle into the (writable, typically emptyDir/tmpfs) document root and
# substitutes the placeholder with API_BASE. Missing API_BASE is a hard stop:
# a silent fallback is how a frontend ends up talking to someone else's server.
set -eu

SRC=/opt/ohmywind-web
DEST=/usr/share/nginx/html
PLACEHOLDER=__OHMYWIND_API_BASE__

if [ -z "${API_BASE:-}" ]; then
  echo >&2 "ohmywind-web: API_BASE is not set (e.g. API_BASE=https://mcp.example.org). Refusing to start."
  exit 1
fi
case "$API_BASE" in
  http://*|https://*) ;;
  *) echo >&2 "ohmywind-web: API_BASE must be an absolute http(s) URL, got '$API_BASE'"; exit 1 ;;
esac
# Trailing slash would produce '//api/v1/...' in the bundle's template strings.
API_BASE="${API_BASE%/}"

rm -rf "${DEST:?}"/* 2>/dev/null || true
cp -R "$SRC"/. "$DEST"/

# '|' as the sed delimiter: the URL contains '/'. Only files that carry the
# placeholder are rewritten, so hashed assets that don't stay byte-identical.
# Plain `grep -rl`: busybox grep has no --include.
grep -rl "$PLACEHOLDER" "$DEST" | while read -r f; do
  sed -i "s|${PLACEHOLDER}|${API_BASE}|g" "$f"
done

if grep -rq "$PLACEHOLDER" "$DEST"; then
  echo >&2 "ohmywind-web: placeholder still present after substitution"; exit 1
fi
echo "ohmywind-web: backend set to ${API_BASE}"
