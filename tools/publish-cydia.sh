#!/bin/bash
# Build this app, import it into the sibling KMY repo, regenerate indexes and
# the site, and optionally push the distribution repo.
#
# The app repo itself is never committed or pushed by this script.
#
# Usage: ./tools/publish-cydia.sh [--push] [--replace] [--no-push]
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_ROOT"

PUSH=0
REPLACE=0

usage() {
  cat <<'USAGE'
Usage: ./tools/publish-cydia.sh [options]

  --push      Push the distribution repo after committing
  --no-push   Do not push (default)
  --replace   Allow overwriting an already-published version
  -h, --help  Show this help

REPO_DIR defaults to the sibling ../repo and can be overridden in the
environment.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --push)
      PUSH=1
      shift
      ;;
    --no-push)
      PUSH=0
      shift
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

CONF="$APP_ROOT/tools/publish.conf"
[ -f "$CONF" ] || { echo "missing $CONF; copy publish.conf.example first" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

: "${REPO_SLUG:?set REPO_SLUG in tools/publish.conf}"
: "${REPO_ICON_SOURCE:?set REPO_ICON_SOURCE in tools/publish.conf}"
: "${REPO_SCREENSHOTS_SOURCE:?set REPO_SCREENSHOTS_SOURCE in tools/publish.conf}"

case "$REPO_SLUG" in
  *[!a-z0-9-]*|"")
    echo "REPO_SLUG must contain only lowercase letters, digits, and dashes" >&2
    exit 1
    ;;
esac

REPO_DIR="${REPO_DIR:-$APP_ROOT/../repo}"
[ -d "$REPO_DIR" ] || { echo "repo checkout not found: $REPO_DIR" >&2; exit 1; }
REPO_DIR="$(cd "$REPO_DIR" && pwd)"
MANIFEST="$REPO_DIR/data/packages.json"
DEB_DIR="$REPO_DIR/docs/debs"
[ -f "$MANIFEST" ] || { echo "missing manifest: $MANIFEST" >&2; exit 1; }
[ -d "$DEB_DIR" ] || { echo "missing deb directory: $DEB_DIR" >&2; exit 1; }
[ -x "$REPO_DIR/tools/update_repo.sh" ] || {
  echo "missing or non-executable $REPO_DIR/tools/update_repo.sh" >&2
  exit 1
}

PACKAGE="$(awk -F': ' '/^Package:/{print $2; exit}' "$APP_ROOT/control")"
VERSION="$(awk -F': ' '/^Version:/{print $2; exit}' "$APP_ROOT/control")"
[ -n "$PACKAGE" ] || { echo "control has no Package field" >&2; exit 1; }
[ -n "$VERSION" ] || { echo "control has no Version field" >&2; exit 1; }

if ! python3 - "$MANIFEST" "$PACKAGE" <<'PY'
import json
import sys

manifest_path, package_id = sys.argv[1], sys.argv[2]
try:
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as error:
    print("cannot read %s: %s" % (manifest_path, error), file=sys.stderr)
    sys.exit(1)

if not any(pkg.get("package") == package_id for pkg in manifest.get("packages", [])):
    print(
        "add a manifest entry for %s in %s" % (package_id, manifest_path),
        file=sys.stderr,
    )
    sys.exit(1)
PY
then
  exit 1
fi

EXISTING="$(find "$DEB_DIR" -maxdepth 1 -type f -name "${PACKAGE}_${VERSION}_*.deb" -print -quit)"
if [ -n "$EXISTING" ] && [ "$REPLACE" -ne 1 ]; then
  echo "already published: $(basename "$EXISTING")" >&2
  echo "bump Version in control, or pass --replace to overwrite it" >&2
  exit 1
fi

# Remove only stale local builds of this exact version so we cannot import an
# old artifact after make claims success.
find "$APP_ROOT/packages" -maxdepth 1 -type f \
  -name "${PACKAGE}_${VERSION}_*.deb" -exec rm -f {} + 2>/dev/null || true

echo "Building $PACKAGE $VERSION..."
THEOS="${THEOS:-$HOME/theos}" make clean package FINALPACKAGE=1

BUILT_DEB="$(find "$APP_ROOT/packages" -maxdepth 1 -type f \
  -name "${PACKAGE}_${VERSION}_*.deb" -print -quit)"
[ -n "$BUILT_DEB" ] || { echo "build produced no ${PACKAGE}_${VERSION}_*.deb" >&2; exit 1; }

# dpkg-deb -I proves the archive is readable; the field reads prove it is the
# package and version we just checked in control.
dpkg-deb -I "$BUILT_DEB" >/dev/null
BUILT_PACKAGE="$(dpkg-deb -f "$BUILT_DEB" Package)"
BUILT_VERSION="$(dpkg-deb -f "$BUILT_DEB" Version)"
[ "$BUILT_PACKAGE" = "$PACKAGE" ] || {
  echo "built package is $BUILT_PACKAGE, expected $PACKAGE" >&2
  exit 1
}
[ "$BUILT_VERSION" = "$VERSION" ] || {
  echo "built version is $BUILT_VERSION, expected $VERSION" >&2
  exit 1
}

cp "$BUILT_DEB" "$DEB_DIR/"
NEW_DEB_NAME="$(basename "$BUILT_DEB")"

# One version per package: remove older debs only after the new one is in place.
find "$DEB_DIR" -maxdepth 1 -type f -name "${PACKAGE}_*.deb" \
  ! -name "$NEW_DEB_NAME" -exec rm -f {} +

ICON_SOURCE="$APP_ROOT/$REPO_ICON_SOURCE"
[ -f "$ICON_SOURCE" ] || { echo "icon not found: $ICON_SOURCE" >&2; exit 1; }
mkdir -p "$REPO_DIR/docs/assets/icons"
cp "$ICON_SOURCE" "$REPO_DIR/docs/assets/icons/${REPO_SLUG}.png"

SCREENSHOTS_SOURCE="$APP_ROOT/$REPO_SCREENSHOTS_SOURCE"
SHOT_DEST="$REPO_DIR/docs/assets/screenshots/$REPO_SLUG"
[ -e "$SCREENSHOTS_SOURCE" ] || {
  echo "screenshots not found: $SCREENSHOTS_SOURCE" >&2
  exit 1
}
rm -rf "$SHOT_DEST"
mkdir -p "$SHOT_DEST"
if [ -d "$SCREENSHOTS_SOURCE" ]; then
  find "$SCREENSHOTS_SOURCE" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
    -exec cp {} "$SHOT_DEST/" \;
else
  cp "$SCREENSHOTS_SOURCE" "$SHOT_DEST/"
fi

if [ "$PUSH" -eq 1 ]; then
  (cd "$REPO_DIR" && ./tools/update_repo.sh \
    --message "publish: ${REPO_SLUG} ${VERSION}" --push)
else
  (cd "$REPO_DIR" && ./tools/update_repo.sh \
    --message "publish: ${REPO_SLUG} ${VERSION}")
fi

python3 - "$MANIFEST" "$PACKAGE" "$VERSION" <<'PY'
import json
import sys

manifest_path, package_id, version = sys.argv[1], sys.argv[2], sys.argv[3]
with open(manifest_path, "r", encoding="utf-8") as handle:
    repo = json.load(handle)["repo"]

print("Published %s %s" % (package_id, version))
print("Cydia source: %s" % repo["url"])
print("Site: %s" % repo["https_url"])
PY
