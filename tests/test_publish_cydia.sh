#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SOURCE="${KMY_REPO:-$ROOT/../repo}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kmy-publish-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -d "$REPO_SOURCE/tools" ] || fail "distribution repo not found at $REPO_SOURCE (set KMY_REPO)"

DIST="$TMP/repo"
APP="$TMP/app"
FAKEBIN="$TMP/bin"
mkdir -p "$DIST" "$APP/tools" "$APP/packages" "$APP/Marquee/Resources" \
  "$APP/screenshots" "$FAKEBIN"

cp -R "$REPO_SOURCE/tools" "$DIST/tools"
cp -R "$REPO_SOURCE/site" "$DIST/site"
cp -R "$REPO_SOURCE/data" "$DIST/data"
mkdir -p "$DIST/docs/debs"
cp "$REPO_SOURCE/docs/.nojekyll" "$DIST/docs/.nojekyll"

cat > "$DIST/data/packages.json" <<'JSON'
{
  "repo": {
    "name": "KMY Test Repo",
    "tagline": "A tiny repo used by the publisher tests.",
    "url": "https://example.test/repo/",
    "https_url": "https://example.test/repo/",
    "github": "https://github.com/example/repo"
  },
  "packages": [
    {
      "slug": "example",
      "package": "com.example.test",
      "tag": "Test app",
      "description": ["A fake package for the publisher test."],
      "minimum_os": "6.0",
      "icon": "assets/icons/example.png",
      "screenshots": ["assets/screenshots/example/shot.png"],
      "source": "https://github.com/example/test",
      "changelog": ["1.0 - Test release."],
      "featured": true
    }
  ]
}
JSON

git -C "$DIST" init -q
git -C "$DIST" symbolic-ref HEAD refs/heads/main
git -C "$DIST" config user.name "KMY Test"
git -C "$DIST" config user.email "test@example.com"
git -C "$DIST" config commit.gpgsign false
git -C "$DIST" add .
git -C "$DIST" commit -qm "fixture"

cat > "$APP/control" <<'CONTROL'
Package: com.example.test
Name: Example App
Version: 1.0
Architecture: iphoneos-arm
Description: A test package.
Maintainer: Test <test@example.com>
Section: Utilities
CONTROL

cat > "$APP/tools/publish.conf" <<'CONF'
REPO_SLUG="example"
REPO_ICON_SOURCE="Marquee/Resources/Icon.png"
REPO_SCREENSHOTS_SOURCE="screenshots"
CONF
cp "$ROOT/tools/publish-cydia.sh" "$APP/tools/publish-cydia.sh"
chmod +x "$APP/tools/publish-cydia.sh"
printf 'icon-v1\n' > "$APP/Marquee/Resources/Icon.png"
printf 'shot-v1\n' > "$APP/screenshots/shot.png"

cat > "$FAKEBIN/make" <<'MAKE'
#!/bin/bash
set -e

root="$PWD"
package="$(sed -n 's/^Package:[[:space:]]*//p' "$root/control" | head -1)"
version="$(sed -n 's/^Version:[[:space:]]*//p' "$root/control" | head -1)"
[ -n "$package" ] && [ -n "$version" ]

build="$root/.fake-build"
rm -rf "$build"
mkdir -p "$build/DEBIAN" "$root/packages"
cat > "$build/DEBIAN/control" <<CONTROL
Package: $package
Version: $version
Architecture: iphoneos-arm
Section: Utilities
Maintainer: Test <test@example.com>
Description: A test package.
CONTROL
rm -f "$root/packages/${package}_${version}_"*.deb
dpkg-deb -b "$build" "$root/packages/${package}_${version}_iphoneos-arm.deb" >/dev/null 2>&1
MAKE
chmod +x "$FAKEBIN/make"

set_version() {
  python3 - "$APP/control" "$1" <<'PY'
import sys

path, version = sys.argv[1], sys.argv[2]
lines = []
seen = False
for line in open(path, "r", encoding="utf-8"):
    if line.startswith("Version:"):
        lines.append("Version: %s\n" % version)
        seen = True
    else:
        lines.append(line)
if not seen:
    raise SystemExit("control has no Version field")
open(path, "w", encoding="utf-8").writelines(lines)
PY
}

run_publish() {
  local repo="$1"
  shift
  (cd "$APP" && PATH="$FAKEBIN:$PATH" REPO_DIR="$repo" ./tools/publish-cydia.sh "$@")
}

expect_failure() {
  local repo="$1"
  local pattern="$2"
  shift 2
  set +e
  OUTPUT="$(run_publish "$repo" "$@" 2>&1)"
  STATUS=$?
  set -e
  [ "$STATUS" -ne 0 ] || fail "expected publish failure containing: $pattern"
  case "$OUTPUT" in
    *"$pattern"*) ;;
    *) fail "expected '$pattern' in output, got: $OUTPUT" ;;
  esac
}

assert_repo() {
  local repo="$1"
  local head="$2"
  [ "$(git -C "$repo" rev-parse HEAD)" = "$head" ] ||
    fail "$repo moved from $head; publish was not rolled back"
  [ -z "$(git -C "$repo" status --porcelain)" ] || {
    git -C "$repo" status --short >&2
    fail "$repo is dirty after a failed publish"
  }
}

# Happy path.
run_publish "$DIST" >/dev/null || fail "publisher failed on the happy path"
HAPPY_HEAD="$(git -C "$DIST" rev-parse HEAD)"

grep -q "^Package: com.example.test$" "$DIST/docs/Packages" || fail "package missing from Packages"
grep -q "^Version: 1.0$" "$DIST/docs/Packages" || fail "version missing from Packages"
grep -q "^Filename: debs/com.example.test_1.0_iphoneos-arm.deb$" "$DIST/docs/Packages" ||
  fail "filename missing from Packages"
[ "$(find "$DIST/docs/debs" -maxdepth 1 -name '*.deb' | wc -l | tr -d ' ')" = "1" ] ||
  fail "expected exactly one deb"
[ -f "$DIST/docs/assets/icons/example.png" ] || fail "icon was not copied"
[ "$(cat "$DIST/docs/assets/icons/example.png")" = "icon-v1" ] || fail "icon content changed"
[ -f "$DIST/docs/assets/screenshots/example/shot.png" ] || fail "screenshot was not copied"
[ "$(git -C "$DIST" log -1 --pretty=%s)" = "publish: example 1.0" ] ||
  fail "publisher commit message is wrong"
[ -s "$DIST/docs/index.html" ] || fail "site index was not generated"
[ -s "$DIST/docs/p/example/index.html" ] || fail "package page was not generated"

COMMITTED="$(git -C "$DIST" show --pretty=format: --name-only HEAD)"
for expected in \
  "docs/Packages" \
  "docs/Release" \
  "docs/index.html" \
  "docs/assets/icons/example.png" \
  "docs/assets/screenshots/example/shot.png"
do
  case "$COMMITTED" in
    *"$expected"*) ;;
    *) fail "publish commit did not include $expected" ;;
  esac
done

# A dirty distribution repo is rejected before anything is built or copied.
printf 'dirty\n' > "$DIST/untracked.txt"
expect_failure "$DIST" "uncommitted changes"
rm -f "$DIST/untracked.txt"
assert_repo "$DIST" "$HAPPY_HEAD"

# Downgrades and equal versions are rejected without --replace.
set_version 0.9
expect_failure "$DIST" "not older"
assert_repo "$DIST" "$HAPPY_HEAD"
[ ! -e "$APP/packages/com.example.test_0.9_iphoneos-arm.deb" ] ||
  fail "downgrade was built before being rejected"

set_version 1.0
expect_failure "$DIST" "not older"
assert_repo "$DIST" "$HAPPY_HEAD"

# The manifest slug must match REPO_SLUG.
cp "$APP/tools/publish.conf" "$TMP/publish.conf.bak"
cat > "$APP/tools/publish.conf" <<'CONF'
REPO_SLUG="wrong"
REPO_ICON_SOURCE="Marquee/Resources/Icon.png"
REPO_SCREENSHOTS_SOURCE="screenshots"
CONF
expect_failure "$DIST" "REPO_SLUG"
cp "$TMP/publish.conf.bak" "$APP/tools/publish.conf"
assert_repo "$DIST" "$HAPPY_HEAD"

# The manifest must contain the control Package field.
cp "$APP/control" "$TMP/control.bak"
sed 's/^Package: com.example.test$/Package: com.example.missing/' \
  "$TMP/control.bak" > "$APP/control"
expect_failure "$DIST" "manifest entry"
cp "$TMP/control.bak" "$APP/control"
assert_repo "$DIST" "$HAPPY_HEAD"

# Missing icon and screenshot sources fail before mutation.
mv "$APP/Marquee/Resources/Icon.png" "$APP/Marquee/Resources/Icon.png.bak"
expect_failure "$DIST" "icon not found"
mv "$APP/Marquee/Resources/Icon.png.bak" "$APP/Marquee/Resources/Icon.png"
assert_repo "$DIST" "$HAPPY_HEAD"

mv "$APP/screenshots" "$APP/screenshots.bak"
expect_failure "$DIST" "screenshots not found"
mv "$APP/screenshots.bak" "$APP/screenshots"
assert_repo "$DIST" "$HAPPY_HEAD"

# Manifest image paths must match the files this publisher will copy.
DIST_MANIFEST="$TMP/repo-manifest"
cp -R "$DIST" "$DIST_MANIFEST"
python3 - "$DIST_MANIFEST/data/packages.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["packages"][0]["icon"] = "assets/icons/wrong.png"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
git -C "$DIST_MANIFEST" add data/packages.json
git -C "$DIST_MANIFEST" commit -qm "wrong icon"
MANIFEST_HEAD="$(git -C "$DIST_MANIFEST" rev-parse HEAD)"
expect_failure "$DIST_MANIFEST" "manifest icon"
assert_repo "$DIST_MANIFEST" "$MANIFEST_HEAD"

python3 - "$DIST_MANIFEST/data/packages.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["packages"][0]["icon"] = "assets/icons/example.png"
manifest["packages"][0]["screenshots"] = ["assets/screenshots/example/missing.png"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
git -C "$DIST_MANIFEST" add data/packages.json
git -C "$DIST_MANIFEST" commit -qm "wrong screenshot"
MANIFEST_HEAD="$(git -C "$DIST_MANIFEST" rev-parse HEAD)"
expect_failure "$DIST_MANIFEST" "no matching file"
assert_repo "$DIST_MANIFEST" "$MANIFEST_HEAD"

# If index/site generation fails after files are imported, the repo returns to
# the exact preflight commit and the previous deb and assets survive.
DIST_ROLLBACK="$TMP/repo-rollback"
cp -R "$DIST" "$DIST_ROLLBACK"
cat > "$DIST_ROLLBACK/tools/update_repo.sh" <<'SH'
#!/bin/bash
echo "synthetic update failure" >&2
exit 1
SH
chmod +x "$DIST_ROLLBACK/tools/update_repo.sh"
git -C "$DIST_ROLLBACK" add tools/update_repo.sh
git -C "$DIST_ROLLBACK" commit -qm "failing updater"
ROLLBACK_HEAD="$(git -C "$DIST_ROLLBACK" rev-parse HEAD)"

printf 'icon-v2\n' > "$APP/Marquee/Resources/Icon.png"
printf 'shot-v2\n' > "$APP/screenshots/shot.png"
printf 'extra\n' > "$APP/screenshots/extra.png"
set_version 1.1
expect_failure "$DIST_ROLLBACK" "synthetic update failure"
assert_repo "$DIST_ROLLBACK" "$ROLLBACK_HEAD"
[ -f "$DIST_ROLLBACK/docs/debs/com.example.test_1.0_iphoneos-arm.deb" ] ||
  fail "rollback lost the published deb"
[ ! -e "$DIST_ROLLBACK/docs/debs/com.example.test_1.1_iphoneos-arm.deb" ] ||
  fail "rollback kept the failed deb"
[ "$(cat "$DIST_ROLLBACK/docs/assets/icons/example.png")" = "icon-v1" ] ||
  fail "rollback did not restore the icon"
[ "$(cat "$DIST_ROLLBACK/docs/assets/screenshots/example/shot.png")" = "shot-v1" ] ||
  fail "rollback did not restore the screenshot"
[ ! -e "$DIST_ROLLBACK/docs/assets/screenshots/example/extra.png" ] ||
  fail "rollback kept a new screenshot"

printf 'icon-v1\n' > "$APP/Marquee/Resources/Icon.png"
printf 'shot-v1\n' > "$APP/screenshots/shot.png"
rm -f "$APP/screenshots/extra.png"
set_version 1.0

# --replace explicitly permits republishing the same version.
run_publish "$DIST" --replace >/dev/null || fail "--replace failed"
grep -q "^Version: 1.0$" "$DIST/docs/Packages" || fail "--replace lost the version"
[ "$(git -C "$DIST" log -1 --pretty=%s)" = "publish: example 1.0" ] ||
  fail "--replace commit message is wrong"

echo "test_publish_cydia: PASS"
