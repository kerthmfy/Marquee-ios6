# KMY Cydia Repo and Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Marquee through a public GitHub Pages Cydia repo with an iOS 6 skeuomorphic catalog site, and make future KMY apps one-command publishable.

**Architecture:** A new `~/Documents/repo` GitHub repo owns the published artifacts. `docs/` is the GitHub Pages root and therefore also the Cydia source root. Apt indexes are generated from `docs/debs/`; a Python generator renders the static site from one manifest plus the generated `Packages` file. The Marquee repo gets a reusable publisher that builds, imports, regenerates, and optionally pushes.

**Tech Stack:** Bash, Python 3 standard library, `dpkg-deb`, `dpkg-scanpackages`, bzip2/gzip, ImageMagick for one-time brand assets, Theos, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-11-14-kmy-cydia-repo-design.md`

## Global Constraints

- iOS 6 Cydia uses the HTTPS source: `https://kerthmfy.github.io/repo/`. Device testing showed Cydia's apt transport can fetch GitHub Pages over HTTPS even though the device's command-line curl cannot negotiate the same TLS; GitHub Pages stays HTTPS-enforced.
- Every Cydia-fetched URL is HTTPS: source, `Icon:`, `Depiction:`, and the `cydia://` share link.
- No external site dependencies, web fonts, CSS variables, CSS grid, or modern flexbox. The site must render in iOS 6 Safari and Cydia's UIWebView.
- Use vendor-prefixed gradients, border-radius, box-shadow, inline-block/float layout, and media queries.
- Exactly one `.deb` per package in `docs/debs/`.
- Version bumps are mandatory for updates; never overwrite a published version without `--replace`.
- The app repo is never committed or pushed by the publisher.
- Do not add GPG signing, CI builds, analytics, or a custom domain in this pass.
- Keep `.superpowers/` and `docs/lessons/` out of published commits.

## Review Focus

- **HTTPS parity:** Cydia's apt transport on iOS 6 fetched the HTTPS source in device testing; the device's command-line curl only speaks TLS 1.0 and still fails. The source, package icon, depiction, and install link must all be HTTPS, and every Mac-side URL must return 200.
- **Duplicate versions:** two `.deb`s for one package make `dpkg-scanpackages` choose the wrong file. Reject them before writing `Packages`.
- **Relative paths:** `Filename: debs/...` is relative to the repo root; package pages live two levels down and must prefix `../../`.
- **iOS 6 rendering:** if the CSS uses variables, grid, or modern flexbox, the Cydia depiction page breaks on the 4S.
- **Version consistency:** control, built `.deb`, `Packages`, site, and `Info.plist` must agree after the update test.
- **Quoting:** repo and app paths can contain spaces; every shell expansion must be quoted.

---

## File Structure

New distribution repo at `~/Documents/repo`:

```text
repo/
  .gitignore
  README.md
  data/packages.json
  site/styles.css
  site/app.js
  tools/build_site.py
  tools/update_repo.sh
  tests/run_tests.sh
  tests/test_build_site.py
  tests/test_update_repo.sh
  docs/.nojekyll
  docs/debs/                     # published .deb files
  docs/Packages                  # generated
  docs/Packages.bz2              # generated
  docs/Packages.gz               # generated
  docs/Release                   # generated
  docs/index.html                # generated
  docs/404.html                  # generated
  docs/p/<slug>/index.html       # generated
  docs/assets/styles.css         # copied from site/
  docs/assets/app.js             # copied from site/
  docs/assets/icons/<slug>.png
  docs/assets/screenshots/<slug>/*.png
  docs/CydiaIcon.png
  docs/favicon.png
  docs/assets/og.png
```

Marquee repo additions:

```text
Marquee/tools/publish-cydia.sh
Marquee/tools/publish.conf
Marquee/tools/publish.conf.example
Marquee/README.md                # install + publishing sections
Marquee/control                  # Icon, Depiction, Homepage, Tag
Marquee/Resources/Info.plist     # final 1.0.1
```

---

### Task 1: Distribution repo skeleton and manifest

**Files:**
- Create: `~/Documents/repo/.gitignore`
- Create: `~/Documents/repo/README.md`
- Create: `~/Documents/repo/data/packages.json`
- Create: `~/Documents/repo/docs/.nojekyll`
- Create: `~/Documents/repo/docs/debs/.gitkeep`
- Create: `~/Documents/repo/docs/assets/icons/.gitkeep`
- Create: `~/Documents/repo/docs/assets/screenshots/.gitkeep`

**Interfaces:**
- Produces: the manifest shape consumed by `tools/build_site.py`:
  `repo.name`, `repo.tagline`, `repo.url`, `repo.https_url`, `repo.github`,
  and `packages[]` with `slug`, `package`, `tag`, `description`, `minimum_os`,
  `icon`, `screenshots`, `source`, `changelog`, `featured`.

- [ ] **Step 1: Create the directory tree and initialize git**

```bash
mkdir -p ~/Documents/repo/{data,site,tools,tests,docs/debs,docs/assets/icons,docs/assets/screenshots}
cd ~/Documents/repo
git init -b main
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
__pycache__/
*.pyc
.scanpackages.log
```

- [ ] **Step 3: Write `data/packages.json`**

Use these exact values for Marquee; leave version/size/filename out because they
come from `docs/Packages`:

```json
{
  "repo": {
    "name": "KMY Repo",
    "tagline": "iOS 6 apps and tweaks, made to feel native.",
    "url": "https://kerthmfy.github.io/repo/",
    "https_url": "https://kerthmfy.github.io/repo/",
    "github": "https://github.com/kerthmfy/repo"
  },
  "packages": [
    {
      "slug": "marquee",
      "package": "com.kerthmfy.marquee.app",
      "tag": "Simkl client",
      "description": [
        "A standalone, native Simkl client for iOS 6.",
        "For You, Library, Search and Profile live in an iOS 6 card stack, with poster-led detail pages and a season-selectable episode guide."
      ],
      "minimum_os": "6.0",
      "icon": "assets/icons/marquee.png",
      "screenshots": [
        "assets/screenshots/marquee/attachment-2.png",
        "assets/screenshots/marquee/attachment-1.png",
        "assets/screenshots/marquee/attachment-0.png"
      ],
      "source": "https://github.com/kerthmfy/Marquee-ios6",
      "changelog": [
        "1.0.1 — Publishing verification and version bump.",
        "1.0 — Initial public release."
      ],
      "featured": true
    }
  ]
}
```

- [ ] **Step 4: Write a minimal `README.md`**

```markdown
# KMY Repo

Cydia source and catalog for KMY iOS 6 apps.

- Source (iOS 6 Cydia): https://kerthmfy.github.io/repo/
- Site: https://kerthmfy.github.io/repo/

Publishing and setup details are added in Task 8.
```

- [ ] **Step 5: Add `.nojekyll` and placeholder files**

```bash
touch docs/.nojekyll docs/debs/.gitkeep docs/assets/icons/.gitkeep docs/assets/screenshots/.gitkeep
```

- [ ] **Step 6: Validate the manifest and commit**

```bash
python3 -m json.tool data/packages.json >/dev/null
git add .
git commit -m "chore: scaffold KMY repo"
```

---

### Task 2: Site generator and skeuomorphic site

**Files:**
- Create: `repo/tests/test_build_site.py`
- Create: `repo/tests/run_tests.sh`
- Create: `repo/tools/build_site.py`
- Create: `repo/site/styles.css`
- Create: `repo/site/app.js`

**Interfaces:**
- Produces:
  - `parse_packages(text) -> list[dict]`
  - `load_manifest(path) -> dict`
  - `find_package(manifest, package_id) -> dict | None`
  - `write_site(repo_root) -> None`
  - CLI: `python3 tools/build_site.py --repo <path>`
- Consumes: `data/packages.json`, `docs/Packages`, `site/styles.css`,
  `site/app.js`.

- [ ] **Step 1: Write failing tests**

Cover:
- `parse_packages` handles blank lines and continuation lines.
- `find_package` matches by `Package`.
- The index contains the repo name, Marquee name, `1.0`, the copyable HTTP
  source, and a `-webkit-linear-gradient` reference.
- The Marquee page links `../../debs/com.kerthmfy.marquee.app_1.0_iphoneos-arm.deb`
  and `../../assets/screenshots/marquee/attachment-2.png`.
- A description containing `<script>` is escaped.
- Missing package metadata raises `ValueError` with the package ID in the
  message.
- `write_site` creates `docs/index.html`, `docs/404.html`, and
  `docs/p/marquee/index.html`.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
cd ~/Documents/repo
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: import failure for `tools/build_site.py`.

- [ ] **Step 3: Write `tests/run_tests.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py' -v
./tests/test_update_repo.sh
```

Make it executable. `test_update_repo.sh` arrives in Task 3; until then run the
unittest command directly.

- [ ] **Step 4: Implement `tools/build_site.py`**

Requirements:
- Read `data/packages.json` and `docs/Packages`.
- Parse RFC-822 stanzas: `Key: Value`, continuation lines starting with a
  space, blank line separates stanzas.
- For each manifest package, require matching `Packages` metadata; use its
  `Version`, `Section`, `Architecture`, `Size`, `Filename`, and `Depends`.
- Render full standalone HTML with a shared shell.
- Index: glossy nav, hero copy, inset HTTPS source field with a copy button,
  “Add to Cydia” button, three install steps, featured package, package grid.
- Package page: app icon, name, version, iOS requirement, screenshots,
  description, install card, direct `.deb` link, source link, metadata table,
  changelog.
- Root prefix is `""` on the index and `"../../"` on package pages.
- Copy `site/styles.css` to `docs/assets/styles.css` and `site/app.js` to
  `docs/assets/app.js`.
- Use `html.escape` for all metadata text.
- Render a 404 page that links home.
- Compute the Cydia install link as
  `cydia://url/https://cydia.saurik.com/api/share#?source=` plus
  `urllib.parse.quote(repo_url, safe="")`.
- Include canonical/Open Graph tags using `repo.https_url`.
- Format sizes as KB/MB.

- [ ] **Step 5: Write `site/styles.css`**

Implement the iOS 6 skeuomorphic design:
- Charcoal pinstripe/linen background, subtle radial depth.
- Glossy blue nav bar with `-webkit-linear-gradient` and `linear-gradient`,
  inner top highlight, dark bottom edge, Helvetica Neue title with text shadow.
- White grouped cards with 8 px radius, hairline border, inset highlight,
  soft shadow.
- Blue-gray uppercase section headers.
- Glossy blue buttons, green install button, inset white source field.
- Package cards/list rows with separators and chevrons.
- Screenshot frames with rounded corners and hairline edges.
- Charcoal tab-bar-style footer.
- Inline-block layout with widths in percentages; media query at 700 px.
- No CSS variables, grid, or flexbox. Use `-webkit-` prefixes for gradients,
  box-shadow, border-radius, and appearance.
- Focus-visible states and adequate contrast.

- [ ] **Step 6: Write `site/app.js`**

Copy-to-clipboard for `[data-copy]`:
- Prefer `navigator.clipboard.writeText`.
- Fallback to a temporary textarea plus `document.execCommand('copy')`.
- Update the button text to “Copied” for 1.5 seconds.
- No other behavior and no dependencies.

- [ ] **Step 7: Run tests and verify they pass**

```bash
cd ~/Documents/repo
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add tools/build_site.py site/styles.css site/app.js tests/test_build_site.py tests/run_tests.sh
git commit -m "feat: add repo site generator and theme"
```

---

### Task 3: Apt index and Release generator

**Files:**
- Create: `repo/tests/test_update_repo.sh`
- Create: `repo/tools/update_repo.sh`

**Interfaces:**
- Produces: `docs/Packages`, `docs/Packages.bz2`, `docs/Packages.gz`,
  `docs/Release`, regenerated site.
- CLI: `./tools/update_repo.sh [--message MSG] [--push] [--no-commit]`.

- [ ] **Step 1: Write the failing integration test**

The test must:
- Create a temp repo by copying `tools/`, `site/`, `data/`, and `docs/.nojekyll`.
- Write a temp manifest with one package `com.example.test`.
- Build a fake `com.example.test_1.0_iphoneos-arm.deb` with `dpkg-deb -b`.
- Run `./tools/update_repo.sh --no-commit`.
- Assert `docs/Packages` contains `Package: com.example.test`,
  `Version: 1.0`, `Filename: debs/com.example.test_1.0_iphoneos-arm.deb`, and a
  positive `Size`.
- Assert `Packages.bz2`, `Packages.gz`, and `Release` exist.
- Assert `Release` contains `Architectures: iphoneos-arm` and the SHA256 line
  for `Packages` matches `shasum -a 256`.
- Assert `docs/index.html` and `docs/p/marquee/index.html` are not generated
  for the fake package; instead the test manifest slug is `example` and
  `docs/p/example/index.html` exists.
- Add a second fake version, run again, and assert a clear
  `multiple versions` failure.

- [ ] **Step 2: Run it and verify it fails**

```bash
cd ~/Documents/repo
./tests/test_update_repo.sh
```

Expected: missing `tools/update_repo.sh`.

- [ ] **Step 3: Implement `tools/update_repo.sh`**

Requirements:
- Resolve `REPO_ROOT` from the script location and `cd` there.
- Parse `--message`, `--push`, `--no-commit`.
- Require `docs/debs`, `data/packages.json`, and `docs/Packages` parent.
- Reject duplicate package names before scanning:

```bash
find docs/debs -maxdepth 1 -name '*.deb' -exec basename {} \; |
  awk -F_ '{count[$1]++} END {for (p in count) if (count[p] > 1) print p}'
```

If the result is non-empty, print each package and exit 1 with the message
`multiple versions found; remove old .deb files`.

- [ ] **Step 4: Generate `Packages` with an override file**

```bash
(cd docs && dpkg-scanpackages debs /tmp/kmy-override > Packages)
```

Build `/tmp/kmy-override` from each deb's `Package` and `Section`:
`<package> optional <section>`. Quote all paths and use a `mktemp` file.

- [ ] **Step 5: Compress and write `Release`**

```bash
(cd docs && bzip2 -9 -k -f Packages && gzip -9 -k -f Packages)
```

`Release` fields:
`Origin: KMY`, `Label: KMY Repo`, `Suite: stable`, `Version: 1.0`,
`Codename: ios`, `Architectures: iphoneos-arm`, `Components: main`,
`Description: iOS 6 apps and tweaks by KMY.`, `Date:` in RFC-2822 UTC.
Digest blocks for `Packages`, `Packages.bz2`, `Packages.gz` using
`openssl dgst -md5 -r`, `-sha1 -r`, `-sha256 -r`; include byte size.

- [ ] **Step 6: Run the site generator**

```bash
python3 tools/build_site.py --repo "$REPO_ROOT"
```

- [ ] **Step 7: Commit and optionally push**

If `--no-commit` is passed, skip git. Otherwise:
`git add docs && git commit -m "$MESSAGE"` only when there is a staged diff.
With `--push`, run `git push origin main`.

- [ ] **Step 8: Run the tests and verify they pass**

```bash
cd ~/Documents/repo
chmod +x tools/update_repo.sh tests/*.sh
./tests/run_tests.sh
```

Expected: both Python and shell tests pass.

- [ ] **Step 9: Commit**

```bash
git add tools/update_repo.sh tests/test_update_repo.sh tests/run_tests.sh
git commit -m "feat: generate apt indexes and release metadata"
```

---

### Task 4: Brand assets and local visual review

**Files:**
- Create: `repo/docs/CydiaIcon.png`
- Create: `repo/docs/favicon.png`
- Create: `repo/docs/assets/og.png`
- Create: `repo/README.md` (visual/brand section only; full readme in Task 8)

- [ ] **Step 1: Generate the KMY monogram**

Use ImageMagick with a local system font. Create a 1024×1024 dark rounded-square
icon with a blue glossy top, white `KMY` letters, and a small `REPO` caption.
Downscale to 512×512 for `CydiaIcon.png` and 64×64 for `favicon.png`.

- [ ] **Step 2: Generate the Open Graph image**

Create a 1200×630 dark pinstripe card with a blue glossy top bar, the KMY
monogram, `KMY Repo`, and `iOS 6 apps and tweaks`. Save as `docs/assets/og.png`.

- [ ] **Step 3: Copy the Marquee icon and screenshots into the repo**

```bash
cp ../marquee-worktree/Marquee/Resources/Icon-72@2x.png docs/assets/icons/marquee.png
cp ../marquee-worktree/screenshots/attachment-*.png docs/assets/screenshots/marquee/
```

- [ ] **Step 4: Regenerate the site and preview**

```bash
cd ~/Documents/repo
python3 tools/build_site.py --repo .
python3 -m http.server 8000 --directory docs
```

Open `http://localhost:8000/` at 1440 px and 375 px widths; open
`/p/marquee/`; check the copy button, Cydia link, `.deb` link, screenshots, and
no console errors.

- [ ] **Step 5: Commit**

```bash
git add docs/CydiaIcon.png docs/favicon.png docs/assets/og.png docs/assets/icons docs/assets/screenshots README.md
git commit -m "feat: add KMY repo branding"
```

---

### Task 5: Marquee publisher and package metadata

**Files:**
- Modify: `Marquee/control`
- Create: `Marquee/tools/publish-cydia.sh`
- Create: `Marquee/tools/publish.conf`
- Create: `Marquee/tools/publish.conf.example`
- Modify: `Marquee/README.md`

**Interfaces:**
- `publish.conf` exports `REPO_SLUG`, `REPO_ICON_SOURCE`,
  `REPO_SCREENSHOTS_SOURCE`.
- Publisher CLI: `./tools/publish-cydia.sh [--push] [--replace] [--no-push]`.

- [ ] **Step 1: Add control metadata**

```text
Homepage: https://github.com/kerthmfy/Marquee-ios6
Icon: https://kerthmfy.github.io/repo/assets/icons/marquee.png
Depiction: https://kerthmfy.github.io/repo/p/marquee/
Tag: purpose::application
```

Keep the current `Version: 1.0` for the first publish.

- [ ] **Step 2: Write `tools/publish.conf`**

```bash
REPO_SLUG="marquee"
REPO_ICON_SOURCE="Marquee/Resources/Icon-72@2x.png"
REPO_SCREENSHOTS_SOURCE="screenshots"
```

`publish.conf.example` documents the same three variables with placeholder
values for future apps.

- [ ] **Step 3: Write `tools/publish-cydia.sh`**

Requirements:
- `set -euo pipefail`; resolve `APP_ROOT` from the script location.
- Default `REPO_DIR` to `$APP_ROOT/../repo`; allow env override.
- Source `tools/publish.conf`.
- Read `Package` and `Version` from `control` with `awk`.
- Verify `REPO_DIR/data/packages.json` contains the package ID; use a short
  Python check and exit with “add a manifest entry for <package>” if missing.
- Reject an existing `docs/debs/${PACKAGE}_${VERSION}_*.deb` unless
  `--replace`.
- Build with `THEOS=${THEOS:-$HOME/theos} make clean package FINALPACKAGE=1`.
- Find the built `.deb` in `packages/`; verify with `dpkg-deb -I` that Package
  and Version match.
- Copy the deb into `docs/debs/`; then delete older `debs/${PACKAGE}_*.deb`
  except the new file.
- Copy the icon to `docs/assets/icons/${REPO_SLUG}.png`.
- Copy screenshots to `docs/assets/screenshots/${REPO_SLUG}/` (remove stale
  files first).
- Call `(cd "$REPO_DIR" && ./tools/update_repo.sh --message "publish: ${REPO_SLUG} ${VERSION}"
  ${PUSH:+--push})`.
- Print the package, version, source URL, and site URL.

- [ ] **Step 4: Syntax-check and run the first publish**

```bash
cd ~/Documents/marquee-worktree
chmod +x tools/publish-cydia.sh
bash -n tools/publish-cydia.sh
./tools/publish-cydia.sh --no-push
```

Expected: Marquee builds, `~/Documents/repo/docs/debs/` gets 1.0,
`Packages` contains Marquee 1.0, and the site renders the package.

- [ ] **Step 5: Run existing Marquee tests**

```bash
./tests/run_tests.sh
```

Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add control tools/publish-cydia.sh tools/publish.conf tools/publish.conf.example README.md
git commit -m "feat: publish Marquee to the KMY repo"
```

---

### Task 6: Create GitHub repo, deploy Pages, verify HTTP

**Files:**
- Modify: `repo/README.md` once the URLs are live.

- [ ] **Step 1: Create the public repo**

Use the existing git credential without printing it. Verify the API identity,
then create `kerthmfy/repo` as public. If the token lacks scope, open
`https://github.com/new?name=repo` and have the user click Create; this is the
only manual step.

- [ ] **Step 2: Push and enable Pages**

```bash
cd ~/Documents/repo
git remote add origin https://github.com/kerthmfy/repo.git
git push -u origin main
```

Enable Pages from `main` `/docs` via the GitHub API if the token permits;
otherwise instruct the user in Settings. HTTPS enforcement stays on; Cydia's
apt transport can read the HTTPS source.

- [ ] **Step 3: Wait for deployment and verify**

```bash
curl -sS -I https://kerthmfy.github.io/repo/Packages
curl -sS https://kerthmfy.github.io/repo/ | head
curl -sS https://kerthmfy.github.io/repo/p/marquee/ | head
curl -sS https://kerthmfy.github.io/repo/Release | head
```

Expected: 200 for all, with no redirect. The device check happens in Task 7
through APT, because the system curl on iOS 6 only speaks TLS 1.0.

- [ ] **Step 4: Open the live site in the browser**

Check the hero, copy button, install steps, package card, detail page,
screenshots, and footer at desktop and 375 px widths.

- [ ] **Step 5: Commit any URL/documentation changes and push**

```bash
git add README.md data/packages.json
git commit -m "docs: point at the live KMY repo"
git push
```

---

### Task 7: Install and update Marquee on the 4S

**Files:**
- Modify: `Marquee/control` (Version 1.0.1)
- Modify: `Marquee/Resources/Info.plist` (short version 1.0.1, build 2)
- Modify: `Marquee/README.md` if the version is mentioned

- [ ] **Step 1: Verify the repo over HTTPS from the 4S through APT**

The system curl on iOS 6 only speaks TLS 1.0 and cannot fetch GitHub Pages.
Cydia's apt transport can, so test with a throwaway APT list instead:

```bash
ssh root@192.168.100.110 '
  rm -rf /tmp/kmy-https-test
  mkdir -p /tmp/kmy-https-test/lists/partial /tmp/kmy-https-test/cache/archives/partial
  printf "deb https://kerthmfy.github.io/repo/ ./\n" > /tmp/kmy-https-test/sources.list
  apt-get -o Dir::Etc::sourcelist=/tmp/kmy-https-test/sources.list \
    -o Dir::Etc::sourceparts=/dev/null \
    -o Dir::State::lists=/tmp/kmy-https-test/lists \
    -o Dir::Cache=/tmp/kmy-https-test/cache update
  grep -E "^(Package|Version|Filename):" /tmp/kmy-https-test/lists/*Packages
'
```

Expected: APT fetches `Release` and `Packages`, and the stanza has `1.0` with
`Filename: debs/...`.

- [ ] **Step 2: Add a temporary APT source and install 1.0**

```bash
ssh root@192.168.100.110 '
  echo "deb https://kerthmfy.github.io/repo/ ./" > /etc/apt/sources.list.d/kmy.list
  apt-get update
  apt-cache policy com.kerthmfy.marquee.app
  apt-get install --reinstall -y com.kerthmfy.marquee.app
  dpkg -s com.kerthmfy.marquee.app | grep Version
  sblaunch -p com.marquee.app
'
```

Expected: policy and dpkg report `1.0`; Marquee launches. If APT rejects an
unsigned repo, add `--allow-unauthenticated` to the install command and record
the warning; Cydia is the final UI check.

- [ ] **Step 3: Bump Marquee to 1.0.1 and publish**

Change `control` to `Version: 1.0.1`; change `Info.plist`
`CFBundleShortVersionString` to `1.0.1` and `CFBundleVersion` to `2`. Then:

```bash
cd ~/Documents/marquee-worktree
./tools/publish-cydia.sh --push
```

- [ ] **Step 4: Upgrade on the 4S and verify**

```bash
ssh root@192.168.100.110 '
  apt-get update
  apt-cache policy com.kerthmfy.marquee.app
  apt-get install -y com.kerthmfy.marquee.app
  dpkg -s com.kerthmfy.marquee.app | grep Version
  killall Marquee 2>/dev/null || true
  sblaunch -p com.marquee.app
'
```

Expected: `1.0.1` is offered and installed; the app launches. Capture a
screenshot as evidence.

- [ ] **Step 5: Remove the temporary source and clean up**

```bash
ssh root@192.168.100.110 'rm -f /etc/apt/sources.list.d/kmy.list; apt-get update'
```

Do not remove anything from Cydia's own source list; the user will add the
source through the UI.

- [ ] **Step 6: Confirm the site shows 1.0.1 and commit**

```bash
curl -sS https://kerthmfy.github.io/repo/Packages | grep -A3 '^Package: com.kerthmfy.marquee.app'
cd ~/Documents/marquee-worktree
git add control Marquee/Resources/Info.plist README.md
git commit -m "release: Marquee 1.0.1"
git push
```

---

### Task 8: Documentation, final verification, and walkthrough

**Files:**
- Modify: `repo/README.md`
- Modify: `Marquee/README.md`
- Modify: `.superpowers/sdd/2026-11-04-marquee/progress.md` (local, ignored)
- Commit: `docs/superpowers/specs/2026-11-14-kmy-cydia-repo-design.md`
- Commit: `docs/superpowers/plans/2026-11-14-kmy-cydia-repo.md`

- [ ] **Step 1: Write the full `repo/README.md`**

Cover:
- what the repo is and the live URLs;
- the folder map (`docs/` is both Pages root and apt root);
- how `Packages`, `Release`, and the site are generated;
- how to add the source in Cydia;
- the publishing workflow (bump version, run publisher, push app repo);
- how to add a new app (copy publisher/config, add manifest entry, assets);
- troubleshooting: Cydia HTTPS vs the device curl's TLS 1.0 limit, duplicate
  versions, Pages not enabled, stale Cydia cache, unsigned repo warnings.

- [ ] **Step 2: Add the Marquee README install/publishing sections**

Include the source URL, the three-step install, the publisher command, and the
version-bump rule.

- [ ] **Step 3: Run all tests**

```bash
cd ~/Documents/repo && ./tests/run_tests.sh
cd ~/Documents/marquee-worktree && ./tests/run_tests.sh
```

Expected: all pass.

- [ ] **Step 4: Verify the package and site one last time**

- `curl` the site, `Packages`, `Release`, and the `.deb`; confirm 200.
- Confirm `Packages` has exactly one Marquee stanza at 1.0.1.
- Confirm the site page shows 1.0.1 and the screenshots load.
- Open the site in the 4S browser/UIWebView if possible; confirm the
  skeuomorphic layout is readable and not distorted.

- [ ] **Step 5: Commit docs and push both repos**

```bash
cd ~/Documents/marquee-worktree
git add docs/superpowers/specs/2026-11-14-kmy-cydia-repo-design.md \
        docs/superpowers/plans/2026-11-14-kmy-cydia-repo.md \
        README.md
git commit -m "docs: document the KMY Cydia repo"
git push

cd ~/Documents/repo
git add README.md
git commit -m "docs: explain the KMY repo workflow"
git push
```

- [ ] **Step 6: Human-only acceptance**

Add `https://kerthmfy.github.io/repo/` in Cydia → Sources → Edit → Add, refresh,
open Marquee, and install/update. This is the only check that requires touch;
everything before it is covered by curl, APT, and screenshots.

---

## Self-Review

- Spec coverage: repo layout, apt indexes, site, publisher, metadata, Pages,
  HTTPS source, install/update verification, docs, and walkthrough each
  map to a task.
- Type consistency: `parse_packages`, `find_package`, `write_site`,
  `REPO_DIR`, `REPO_SLUG`, and the manifest keys are used consistently.
- Review focus tests: HTTPS is checked in Tasks 6 and 7; duplicate versions in
  Task 3; relative paths in Task 2; iOS 6 CSS in Task 4; version consistency
  in Tasks 5–7; quoting in the shell scripts.
- Proportion: the plan is longer than the spec because it carries exact
  commands and file contracts for a cross-repo build; implementation details
  remain in the code.
