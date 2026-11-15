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

control_field() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

for tool in git dpkg dpkg-deb python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is required to publish" >&2
    exit 1
  }
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

# Publish from a clean, known commit so a failure can restore the exact state
# the repo was in before this run.
git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "$REPO_DIR is not a git checkout" >&2
  exit 1
}
REPO_BRANCH="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD || true)"
[ "$REPO_BRANCH" = "main" ] || {
  echo "distribution repo must be on main, not ${REPO_BRANCH:-detached HEAD}" >&2
  exit 1
}
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo "distribution repo has uncommitted changes; commit or stash them first:" >&2
  git -C "$REPO_DIR" status --short >&2
  exit 1
fi
PREFLIGHT_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
PUBLISH_OK=0

cleanup_on_failure() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$PUBLISH_OK" -ne 1 ]; then
    echo "publish failed; restoring $REPO_DIR to $PREFLIGHT_HEAD" >&2
    git -C "$REPO_DIR" reset --hard "$PREFLIGHT_HEAD" >/dev/null 2>&1 || true
    git -C "$REPO_DIR" clean -fd >/dev/null 2>&1 || true
  fi
}
trap cleanup_on_failure EXIT

[ -f "$APP_ROOT/control" ] || { echo "missing $APP_ROOT/control" >&2; exit 1; }
PACKAGE="$(control_field Package "$APP_ROOT/control")"
VERSION="$(control_field Version "$APP_ROOT/control")"
[ -n "$PACKAGE" ] || { echo "control has no Package field" >&2; exit 1; }
[ -n "$VERSION" ] || { echo "control has no Version field" >&2; exit 1; }
if ! dpkg --compare-versions "$VERSION" eq "$VERSION" 2>/dev/null; then
  echo "control has an invalid Version: $VERSION" >&2
  exit 1
fi

ICON_SOURCE="$APP_ROOT/$REPO_ICON_SOURCE"
[ -f "$ICON_SOURCE" ] || { echo "icon not found: $ICON_SOURCE" >&2; exit 1; }
[ -s "$ICON_SOURCE" ] || { echo "icon is empty: $ICON_SOURCE" >&2; exit 1; }

SCREENSHOTS_SOURCE="$APP_ROOT/$REPO_SCREENSHOTS_SOURCE"
[ -e "$SCREENSHOTS_SOURCE" ] || {
  echo "screenshots not found: $SCREENSHOTS_SOURCE" >&2
  exit 1
}
if [ -d "$SCREENSHOTS_SOURCE" ]; then
  SHOT_COUNT="$(find "$SCREENSHOTS_SOURCE" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | wc -l | tr -d ' ')"
  [ "$SHOT_COUNT" -gt 0 ] || {
    echo "screenshots directory has no PNG or JPEG files: $SCREENSHOTS_SOURCE" >&2
    exit 1
  }
else
  case "$SCREENSHOTS_SOURCE" in
    *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG) ;;
    *) echo "screenshots file must be PNG or JPEG: $SCREENSHOTS_SOURCE" >&2; exit 1 ;;
  esac
fi

# The manifest must describe this exact package and slug, and its image paths
# must match what the publisher is about to copy. All of this runs before the
# repo is touched.
if ! python3 - "$MANIFEST" "$PACKAGE" "$REPO_SLUG" "$SCREENSHOTS_SOURCE" <<'PY'
import json
import os
import sys

manifest_path, package_id, repo_slug, shots_source = sys.argv[1:5]
try:
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as error:
    print("cannot read %s: %s" % (manifest_path, error), file=sys.stderr)
    sys.exit(1)

matches = [
    package
    for package in manifest.get("packages", [])
    if package.get("package") == package_id
]
if not matches:
    print(
        "add a manifest entry for %s in %s" % (package_id, manifest_path),
        file=sys.stderr,
    )
    sys.exit(1)

entry = matches[0]
manifest_slug = entry.get("slug", "")
if manifest_slug != repo_slug:
    print(
        "REPO_SLUG is %r but the manifest slug for %s is %r"
        % (repo_slug, package_id, manifest_slug),
        file=sys.stderr,
    )
    sys.exit(1)

expected_icon = "assets/icons/%s.png" % repo_slug
if entry.get("icon") != expected_icon:
    print(
        "manifest icon for %s is %r; expected %r"
        % (package_id, entry.get("icon"), expected_icon),
        file=sys.stderr,
    )
    sys.exit(1)

if os.path.isdir(shots_source):
    available = {
        name
        for name in os.listdir(shots_source)
        if name.lower().endswith((".png", ".jpg", ".jpeg"))
    }
else:
    available = {os.path.basename(shots_source)}

for shot in entry.get("screenshots") or []:
    prefix = "assets/screenshots/%s/" % repo_slug
    if not shot.startswith(prefix):
        print(
            "manifest screenshot %r must start with %r" % (shot, prefix),
            file=sys.stderr,
        )
        sys.exit(1)
    if os.path.basename(shot) not in available:
        print(
            "manifest screenshot %r has no matching file in %s"
            % (shot, shots_source),
            file=sys.stderr,
        )
        sys.exit(1)
PY
then
  exit 1
fi

# Find the newest version already imported for this package. Equal and lower
# versions are rejected unless the caller explicitly passes --replace.
LATEST=""
for deb in "$DEB_DIR"/*.deb; do
  [ -f "$deb" ] || continue
  if ! DEB_PACKAGE="$(dpkg-deb -f "$deb" Package 2>/dev/null)"; then
    echo "cannot read $deb; fix the repo before publishing" >&2
    exit 1
  fi
  [ "$DEB_PACKAGE" = "$PACKAGE" ] || continue
  DEB_VERSION="$(dpkg-deb -f "$deb" Version 2>/dev/null || true)"
  [ -n "$DEB_VERSION" ] || {
    echo "cannot read the version from $deb" >&2
    exit 1
  }
  if [ -z "$LATEST" ] || dpkg --compare-versions "$DEB_VERSION" gt "$LATEST"; then
    LATEST="$DEB_VERSION"
  fi
done

if [ -n "$LATEST" ] && [ "$REPLACE" -ne 1 ]; then
  if ! dpkg --compare-versions "$VERSION" gt "$LATEST"; then
    echo "published version $LATEST is not older than $VERSION" >&2
    echo "bump Version in control, or pass --replace to overwrite it" >&2
    exit 1
  fi
fi
if [ -n "$LATEST" ] && [ "$REPLACE" -eq 1 ] &&
  dpkg --compare-versions "$VERSION" lt "$LATEST"; then
  echo "warning: --replace is publishing $VERSION over newer $LATEST" >&2
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

NEW_DEB_NAME="$(basename "$BUILT_DEB")"
DEST_DEB="$DEB_DIR/$NEW_DEB_NAME"
cp "$BUILT_DEB" "$DEST_DEB.publishing"
mv "$DEST_DEB.publishing" "$DEST_DEB"

# One version per package. Match by control metadata so a renamed old deb is
# removed too; it is safe to delete only after the replacement is in place.
for deb in "$DEB_DIR"/*.deb; do
  [ -f "$deb" ] || continue
  [ "$deb" = "$DEST_DEB" ] && continue
  DEB_PACKAGE="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
  if [ "$DEB_PACKAGE" = "$PACKAGE" ]; then
    rm -f "$deb"
  fi
done

ICON_DEST="$REPO_DIR/docs/assets/icons/${REPO_SLUG}.png"
mkdir -p "$(dirname "$ICON_DEST")"
cp "$ICON_SOURCE" "$ICON_DEST.publishing"
mv "$ICON_DEST.publishing" "$ICON_DEST"

SHOT_DEST="$REPO_DIR/docs/assets/screenshots/$REPO_SLUG"
SHOT_TMP="$REPO_DIR/docs/assets/screenshots/.${REPO_SLUG}.publishing"
rm -rf "$SHOT_TMP"
mkdir -p "$SHOT_TMP"
if [ -d "$SCREENSHOTS_SOURCE" ]; then
  find "$SCREENSHOTS_SOURCE" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
    -exec cp {} "$SHOT_TMP/" \;
else
  cp "$SCREENSHOTS_SOURCE" "$SHOT_TMP/"
fi
rm -rf "$SHOT_DEST"
mv "$SHOT_TMP" "$SHOT_DEST"

if [ "$PUSH" -eq 1 ]; then
  (cd "$REPO_DIR" && ./tools/update_repo.sh \
    --message "publish: ${REPO_SLUG} ${VERSION}" --push)
else
  (cd "$REPO_DIR" && ./tools/update_repo.sh \
    --message "publish: ${REPO_SLUG} ${VERSION}")
fi
PUBLISH_OK=1

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
