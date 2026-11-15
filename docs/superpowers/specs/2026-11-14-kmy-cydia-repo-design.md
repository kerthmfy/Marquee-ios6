# KMY Cydia Repo and Site Design

**Date:** 2026-11-14
**Status:** accepted; approval waived by the user on 2026-11-14
**Approach:** dedicated public GitHub repo, GitHub Pages, local publisher

## Intent

Give every KMY iOS 6 app and tweak one stable Cydia source and one public
home. Marquee is the first package. The repo should stay useful when Matinee
and future projects are added, and publishing an update should be one command
with no server maintenance.

The build is also a walkthrough: scripts are commented, the README explains the
moving parts, and the site is plain HTML/CSS with no hidden framework.

## Goals

- Cydia source at `https://kerthmfy.github.io/repo/` for iOS 6, served by
  GitHub Pages over HTTPS to both Cydia and modern browsers.
- Users can add the source in Cydia, install Marquee, and receive version
  updates through the normal Changes/Refresh flow.
- A public site at the same URL lists every package, explains how to add the
  source, and gives each package a detail page with screenshots and source link.
- One command in an app repo builds the `.deb`, imports it, regenerates the
  apt indexes and site, and commits the repo repo.
- The setup is teachable: a reader can follow the README and understand where
  `Packages`, `Release`, the `.deb`, and the HTML come from.

## Non-goals

- No paid hosting, custom domain, database, or server process in v1.
- No GitHub Actions build of the iOS 6 app in v1; the Theos toolchain already
  lives on this Mac.
- No GPG-signed `Release` in v1. Cydia accepts the repo; signing can be added
  later without changing package URLs.
- No analytics, comments, accounts, or automatic submission to default repos.
- No publishing Matinee or other apps in this pass; the structure must accept
  them.

## Anti-goals

- A repo whose indexes are edited by hand and drift from the `.deb` files.
- Generated packages checked into an app's source repo.
- A site that needs Node, a framework, or a build service to preview.
- Breaking iOS 6 Cydia with an index format it cannot read.
- Two `.deb` versions for the same package in the repo; that makes
  `Packages` ambiguous.

## Approaches considered

1. **Dedicated GitHub Pages repo (chosen).** Separate `kerthmfy/repo` with
   published artifacts and site. App repos keep source. Free, static, scales to
   every project, and the apt root and site root can be the same folder.
2. **`gh-pages` branch in each app repo.** One repo per app, but every app's
   Cydia source would be separate and future apps would publish into Marquee's
   repo. Rejected.
3. **Custom domain/server.** Better control and URL, but adds hosting and DNS
   work before there is a second package. The chosen layout is portable to this
   later.

## Architecture

### Repos

- `kerthmfy/Marquee-ios6` — app source. Gains `control` metadata and
  `tools/publish-cydia.sh` plus a publishing README section.
- `kerthmfy/repo` — new public repo. Holds apt indexes, `.deb` files, site
  source, generated site, icons, and screenshots.

Local default layout:

```text
~/Documents/
  marquee-worktree/        # app source (this repo)
  repo/                    # distribution repo, sibling
```

`REPO_DIR` can override the sibling path.

### Published layout (`repo` repo)

```text
repo/
  README.md
  data/
    packages.json          # site manifest, hand-curated
  site/
    styles.css
    app.js
    templates.py           # page shells and card rendering
  tools/
    update-repo.sh         # apt indexes + site + commit
    build-site.py          # renders index and package pages
  docs/                    # GitHub Pages root (main /docs)
    .nojekyll
    index.html
    p/marquee/index.html
    Packages
    Packages.bz2
    Packages.gz
    Release
    CydiaIcon.png
    favicon.png
    assets/
      styles.css
      app.js
      icons/marquee.png
      screenshots/marquee/attachment-0.png
      screenshots/marquee/attachment-1.png
      screenshots/marquee/attachment-2.png
    debs/
      com.kerthmfy.marquee.app_1.0_iphoneos-arm.deb
```

GitHub Pages serves `main` / `docs`. The Cydia source URL is the directory
root, so `.../repo/Packages` and `.../repo/p/marquee/` both work under the same
URL. `docs/debs/...` is referenced by `Filename: debs/...` in `Packages`.

### Apt metadata

`tools/update-repo.sh`, run from the repo root:

- verifies exactly one `.deb` per package in `docs/debs/`;
- runs `dpkg-scanpackages docs/debs /dev/null > docs/Packages` (without `-m`);
- writes `Packages.bz2` and `Packages.gz`;
- writes `Release` with `Origin: KMY`, `Label: KMY Repo`, `Suite: stable`,
  `Codename: ios`, `Architectures: iphoneos-arm`, `Components: main`,
  RFC-2822 UTC `Date:`, and MD5Sum/SHA1/SHA256 entries for all three indexes;
- runs `build-site.py`;
- commits the repo repo and, when asked, pushes it.

No hand-edited `Packages` or `Release`. `Filename` stays relative to the repo
root.

### Site manifest

`data/packages.json` holds only editorial data:

```json
{
  "repo": {
    "name": "KMY Repo",
    "tagline": "iOS 6 apps and tweaks, made to feel native.",
    "url": "https://kerthmfy.github.io/repo/"
  },
  "packages": [
    {
      "slug": "marquee",
      "package": "com.kerthmfy.marquee.app",
      "tag": "Simkl client",
      "description": [
        "A standalone, native Simkl client for iOS 6.",
        "For You, Library, Search and Profile in an iOS 6 card stack."
      ],
      "icon": "assets/icons/marquee.png",
      "screenshots": [
        "assets/screenshots/marquee/attachment-2.png",
        "assets/screenshots/marquee/attachment-1.png",
        "assets/screenshots/marquee/attachment-0.png"
      ],
      "source": "https://github.com/kerthmfy/Marquee-ios6",
      "featured": true
    }
  ]
}
```

Version, size, section, architecture, and `.deb` filename come from the
published package metadata, not from the manifest. Adding a future app means:
add its `.deb`, add one manifest entry, add its icon/screenshots, publish.

### Site

A static, dependency-free site:

- `index.html`: KMY Repo masthead, repo URL with copy button, a three-step
  “Add to Cydia” panel, featured package, then a package grid.
- `p/<slug>/index.html`: package icon, name, version, iOS requirement,
  screenshots, description, install steps, direct `.deb` link, source link,
  and metadata table.
- Visual language: an intentional iOS 6 skeuomorphic storefront, not a flat
  modern page.
  - Charcoal linen/pinstripe page background with subtle depth.
  - Glossy blue navigation bar with a top highlight, dark bottom edge, and
    Helvetica Neue title with a soft text shadow.
  - White grouped-table cards with 8 px corners, hairline borders, inner top
    highlights, and soft drop shadows.
  - Uppercase blue-gray section headers like iOS 6 grouped tables.
  - Glossy blue primary buttons and a green install button with beveled edges,
    inner highlights, and 1 px dark outlines.
  - Inset white source-URL field with rounded corners and inner shadow.
  - App icons presented in rounded, glossed frames; screenshot frames get the
    same poster-edge feel as the app.
  - Charcoal tab-bar-style footer with simple line icons.
  - Texture from CSS gradients and a small locally generated pattern only; no
    external images or fonts. The result should feel native to 2012 without
    becoming a parody or hurting readability.
- System font stack only (`-apple-system`, `Helvetica Neue`, Helvetica, Arial).
  Monospace for URLs. No web fonts.
- CSS must render in iOS 6 Safari and Cydia's UIWebView for the depiction page:
  no CSS variables, grid, or modern flexbox. Use inline-block/float layout,
  vendor-prefixed gradients, border-radius, box-shadow, and media queries.
- Responsive from 320 px up; single column on phones, multi-column on desktop.
- `app.js` only copies the repo URL and enhances the Cydia button. All content
  and links work without JavaScript.
- `favicon.png`, `CydiaIcon.png`, and an Open Graph image are generated from a
  simple KMY monogram with ImageMagick.

Install controls:

- Copyable `https://kerthmfy.github.io/repo/` source URL for iOS 6 Cydia.
- “Add to Cydia” link:
  `cydia://url/https://cydia.saurik.com/api/share#?source=<encoded https repo URL>`.
- Plain instructions for iOS 6 Cydia: Sources → Edit → Add → enter URL →
  Add Source, then search Marquee and install.
- The site is canonical at `https://kerthmfy.github.io/repo/`.
- Every URL Cydia itself fetches is HTTPS: the source, package `Icon:`,
  `Depiction:`, and the `cydia://` share link.
- The 4S's system curl rejects GitHub Pages' TLS with
  `tlsv1 alert protocol version`, but Cydia's apt transport fetches the HTTPS
  source successfully. GitHub Pages stays HTTPS-enforced; APT, not curl, is the
  meaningful device test.

### App publisher

Each participating app repo gets two small files:

- `tools/publish-cydia.sh`
- `tools/publish.conf` (slug, icon source, screenshot source)

`publish-cydia.sh` is reusable across apps. It finds its slug in
`$REPO_DIR/data/packages.json` by matching the `.deb` `Package` field, and
refuses to publish if the package has no manifest entry. Asset paths come from
`publish.conf`, so a new app copies both files and edits the config rather than
rewriting the publisher.

The script:

1. Sources `tools/publish.conf` and reads `Package` and `Version` from
   `control`.
2. Refuses to continue unless `REPO_DIR` exists and the package is present in
   `data/packages.json`.
3. Runs `THEOS=$HOME/theos make clean package FINALPACKAGE=1`.
4. Verifies the built `.deb` with `dpkg-deb -I`.
5. Refuses to overwrite an already-published version unless `--replace` is
   passed; this forces a `control` version bump for real updates.
6. Copies the `.deb` to `$REPO_DIR/docs/debs/`, removing older versions of the
   same package only after the new file is in place.
7. Copies the configured icon and screenshots into the repo assets.
8. Calls `$REPO_DIR/tools/update-repo.sh` with optional `--push`.

The app repo is not committed or pushed by this script; source history stays
under the app's normal workflow.

### Marquee package metadata

`control` gains:

```text
Homepage: https://github.com/kerthmfy/Marquee-ios6
Icon: https://kerthmfy.github.io/repo/assets/icons/marquee.png
Depiction: https://kerthmfy.github.io/repo/p/marquee/
Tag: purpose::application
```

Cydia-facing URLs use HTTPS. Device testing showed Cydia's apt transport can
fetch GitHub Pages even though the 4S system curl only speaks TLS 1.0 and
fails. The `Homepage` is HTTPS for the same reason as every other link.

`Description` stays a one-line summary; the site carries the longer copy.
The first public release is `1.0.1`. `1.0` is published first only to prove the
upgrade path; the app's `control`, `Info.plist`, and README end at `1.0.1`, and
`1.0.1` is what remains in the repo.

### GitHub setup

- Create public `kerthmfy/repo` with no README from the web UI.
- Push the prepared local repo.
- Settings → Pages → Source: `Deploy from a branch`, branch `main`, folder
  `/docs`.
- Leave “Enforce HTTPS” on. GitHub Pages requires it for `github.io` sites,
  and Cydia's apt transport reads the HTTPS source successfully.

## Publishing workflow

For every app release:

1. Make the app change and bump `Version:` in `control`.
2. Commit the app repo.
3. Run `./tools/publish-cydia.sh --push`.
4. Push the app repo.
5. In Cydia: Changes → Refresh. The new version appears; install/update.
6. Open the site and confirm the new version and metadata.

For a new app: copy `tools/publish-cydia.sh` and
`tools/publish.conf.example`, add its manifest entry, its icon and screenshots,
then run the publisher. `update-repo.sh` can also be run by itself from the repo
repo after any manual import.

## Verification

1. `update-repo.sh` on a clean checkout produces non-empty `Packages`,
   `Packages.bz2`, `Packages.gz`, and `Release`; checksums match; the package
   entry contains the correct `Filename` and `Size`.
2. `python3 tools/build-site.py` renders the index and Marquee page; open them
   in a browser at desktop and 320 px widths; check links, copy button, image
   paths, and no console errors.
3. On the 4S over SSH:
   - add the HTTPS source to a throwaway APT source file, run `apt-get update`,
     and confirm it fetches `Release` and `Packages`; the system `curl` only
     speaks TLS 1.0 against GitHub Pages, so APT is the meaningful test;
   - confirm `apt-cache policy com.kerthmfy.marquee.app` offers `1.0`;
   - `apt-get install --reinstall` and launch Marquee.
4. Publish a throwaway `1.0.1` version, refresh APT, confirm the upgrade is
   offered and installs. Bump the app source to `1.0.1` as the final release
   and leave `1.0.1` published.
5. Add the HTTPS source in the Cydia UI and install Marquee from it. This is the
   human-only check; the SSH APT test proves the metadata, but Cydia's UI is
   the real acceptance.
6. After the first Pages deployment, fetch `https://kerthmfy.github.io/repo/`,
   `/p/marquee/`, and `https://kerthmfy.github.io/repo/Packages`, `/Release`,
   and confirm 200.

## Walkthrough deliverables

- `repo/README.md`: how the repo works, how to add the source, how to publish,
  how to add a new app, and troubleshooting (TLS, duplicate versions, Pages
  not enabled, stale Cydia cache).
- Comments in `publish-cydia.sh`, `update-repo.sh`, and `build-site.py` at every
  non-obvious step.
- A short “Publishing to Cydia” section in Marquee's README.
- Chat narration while building: create the repo folder, generate the indexes,
  render the site, deploy, add the source, publish an update, and verify on the
  4S.

## Decisions left to the builder

- Exact HTML/CSS details, spacing, and icon artwork within the iOS 6
  skeuomorphic direction above.
- Whether the site uses one featured card or a small hero carousel.
- Whether the direct `.deb` link is labeled “Download .deb” or “Manual install”.
- Copy microcopy for install steps and empty states.
- Whether to add a `Release.gpg` later.
