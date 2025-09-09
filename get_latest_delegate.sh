#!/usr/bin/env bash
set -euo pipefail

# Optional: set to one of: minimal-fips | minimal | ubi | fips | "" (empty for no suffix preference)
PREFERRED_FLAVOR="${PREFERRED_FLAVOR:-minimal-fips}"

# Output mode: tag | image
PRINT_MODE="${PRINT_MODE:-image}"   # default: full image

HUB_URL="https://hub.docker.com/v2/repositories/harness/delegate/tags/?page_size=100&ordering=last_updated"

# Build the regex for tag names like 25.08.86600(.<flavor>)?
if [[ -n "$PREFERRED_FLAVOR" ]]; then
  NAME_REGEX="^[0-9]{2}\.[0-9]{2}\.[0-9]{5}\.${PREFERRED_FLAVOR}$"
else
  NAME_REGEX="^[0-9]{2}\.[0-9]{2}\.[0-9]{5}(\.[A-Za-z0-9-]+)?$"
fi

fetch_latest_with_regex() {
  local regex="$1"
  if command -v jq >/dev/null 2>&1; then
    curl -fsSL "$HUB_URL" \
      | jq -r --arg re "$regex" '
          .results
          | map(.name)
          | map(select(test($re)))
          | .[0] // empty
        '
  else
    curl -fsSL "$HUB_URL" \
      | tr ',' '\n' \
      | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' \
      | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
      | grep -E "$regex" \
      | head -n1
  fi
}

# 1) Try preferred flavor (if any)
TAG="$(fetch_latest_with_regex "$NAME_REGEX" || true)"

# 2) Fallback: any tag (still YY.MM.BBBBB) if preferred flavor not found
if [[ -z "${TAG:-}" && -n "$PREFERRED_FLAVOR" ]]; then
  TAG="$(fetch_latest_with_regex '^[0-9]{2}\.[0-9]{2}\.[0-9]{5}(\.[A-Za-z0-9-]+)?$' || true)"
fi

if [[ -z "${TAG:-}" ]]; then
  >&2 echo "ERROR: No delegate tag resolved from Docker Hub."
  exit 1
fi

IMG_PREFIX="${DELEGATE_IMAGE_PREFIX:-us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate}"
DELEGATE_IMAGE="${IMG_PREFIX}:${TAG}"

# Log to stderr, data to stdout
>&2 echo "Using delegate image: ${DELEGATE_IMAGE}"

if [[ "${PRINT_MODE}" == "tag" ]]; then
  printf '%s\n' "${TAG}"
else
  printf '%s\n' "${DELEGATE_IMAGE}"
fi
