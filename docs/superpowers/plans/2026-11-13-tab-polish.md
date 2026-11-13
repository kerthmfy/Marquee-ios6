# Marquee Tab Polish — Implementation Plan

Date: 2026-11-13
Design: `docs/superpowers/specs/2026-11-13-tab-polish-design.md`

## Goal

Ship the approved in-place polish for all four tabs: correct awkward copy,
move the Search attribution out of the scrolling content, and give the For You
hero artwork, an eyebrow, and metadata. Keep the existing iOS 6 chrome, card
shapes, pinstripe background, and navigation/tab bars unchanged.

## Ground Rules

- Objective-C / ARC only. No new libraries, storyboards, or nibs.
- Do not add features or write actions. The hero keeps a details action.
- Every task ends with `./tests/run_tests.sh` and a commit.
- UIKit-only changes are compile-verified by `make package`; test the pure
  formatting/empty-state strings directly.
- Do not commit `.superpowers/` or `docs/lessons/`.
- Do not ship the temporary tab-selection hook used for screenshots.

---

## Task 1 — Library copy

**Files**

- `Marquee/MRStatusChipsView.m`
- `Marquee/MRLibraryViewController.m`

**Steps**

1. In `MRStatusChipsView.m`, change the chip title array entry `Plan` to
   `Plan to Watch`.
2. In `MRLibraryViewController.m`, rename `updatedTextForDate:` to
   `syncedTextForDate:` and return:
   - `< 60s`: `Synced just now`
   - `< 1h`: `Synced %ldm ago`
   - `< 1d`: `Synced %ldh ago`
   - `< 7d`: `Synced %ldd ago`
   - older: `Synced %@` with the `MMM d` formatter
3. Replace the no-date fallback `Not synced yet` with
   `Waiting for first sync`.
4. Keep `N changes waiting to sync` and
   `Offline — showing saved library` unchanged.
5. Run `./tests/run_tests.sh`.
6. Commit: `polish: clarify library filter and sync copy`.

**Done when** the chip reads `Plan to Watch`, the footer begins with `Synced`,
and the first-run footer reads `Waiting for first sync`.

---

## Task 2 — Profile copy

**Files**

- `Marquee/MRProfileViewController.m`

**Steps**

1. `MRProfileAccountTypeText` returns `Simkl Free`, `Simkl PRO`, `Simkl VIP`,
   and `Simkl account` as the fallback.
2. Stats captions become
   `Movies`, `TV Shows`, `Anime`, `Episodes`, `Ratings`, `Plan to Watch`.
3. Section titles become:
   - `MRProfileSectionStats` → `Your Library`
   - `MRProfileSectionSync` → `Sync Status`
   - `MRProfileSectionForYou` → `Recommendations`
4. Recommendation row details:
   - Favorite Genres: `%lu selected` / `None selected`
   - Hidden Titles: `%lu hidden` / `None hidden`
5. About rows:
   - Row 0: `Connected Apps`, detail `nil`, chevron on.
   - Row 1: `Simkl Website`, detail `nil`, chevron on.
   - Keep the existing row actions (`MRProfileConnectedAppsURL` and
     `https://simkl.com`).
   - `Version` and `Diagnostics` unchanged.
6. Leave the sync detail copy (`Up to date`, `Syncing…`, `Offline`,
   `N pending`, `Last synced 2:16 PM`) unchanged.
7. Run `./tests/run_tests.sh`.
8. Commit: `polish: clarify profile labels and sections`.

**Done when** no section is titled `Stats`, `Sync`, or `For You`, and the
account line reads `Simkl Free` for the free account.

---

## Task 3 — Search attribution bar and copy

**Files**

- `Marquee/MRSearchViewController.m`

**Steps**

1. Change the search placeholder to `Movies, TV shows, anime`.
2. Change the idle suggestion subtitle to
   `Search movies, TV shows, and anime.`
3. Keep `Try Dune, The Bear, or Frieren` (already spelled correctly).
4. Replace the table-footer attribution with a fixed bar:
   - Add a `UIView *attributionBar` property; keep `footerButton` and
     `footerBadge`.
   - In `buildFooter` (rename to `buildAttributionBar`), create a 30 pt bar,
     add a 1 px top separator in `[MRAppearance sep]`, set the background to
     `[MRAppearance paper]`, add the button titled `Powered by Simkl`, and add
     the `SimklBadge.png` image view at 18 pt.
   - Add the bar to `self.view`, not `self.tableView.tableFooterView`.
   - Do not set a table footer view.
5. In `viewDidLayoutSubviews`:
   - Signed out: hide the bar.
   - Signed in: show the bar, compute
     `barHeight = 30`, place the bar at `height - barHeight`, and size the
     table to end at the bar's top edge.
   - Center the button text and badge inside the bar with a 6 pt gap.
6. Keep the tap target opening `https://simkl.com`.
7. Run `./tests/run_tests.sh`.
8. Commit: `polish: pin search attribution above the tab bar`.

**Done when** the attribution no longer scrolls with results, sits directly
above the tab bar, and disappears when signed out.

---

## Task 4 — For You empty-state copy

**Files**

- `Marquee/MRRecommendationEngine.m`
- `Marquee/MRForYouViewController.m`
- `tests/MRRecommendationRowsTests.m`

**Steps**

1. Update the two empty-state assertions in
   `tests/MRRecommendationRowsTests.m` from `Find something on Simkl` to
   `Find something to watch`.
2. Run `./tests/run_tests.sh` and confirm the assertions fail.
3. Replace every signed-in / public empty-state pair:
   - Title: `Find something to watch`
   - Subtitle: `Search Simkl to start your library.`
   - Locations: `MRRecommendationEngine.m` (two pairs) and
     `MRForYouViewController.m` (one pair).
4. Run `./tests/run_tests.sh`.
5. Commit: `polish: rewrite for-you empty state`.

**Done when** every empty feed card uses the new title and subtitle and the
tests pass.

---

## Task 5 — For You hero artwork, eyebrow, and metadata

**Files**

- `Marquee/MRHeroView.h`
- `Marquee/MRHeroView.m`
- `Marquee/MRForYouViewController.m`

**Steps**

1. Extend `MRHeroView` with:
   - An `UIImageView *artworkView` added above the base gradient.
   - A bottom-heavy `CAGradientLayer *scrimLayer` above the artwork and below
     the labels.
   - `UILabel *eyebrowLabel` (bold 10, white 70%, uppercase).
   - `UILabel *metadataLabel` (system 12, white 80%).
   - A new configure method:
     `configureWithTitle:subtitle:eyebrow:metadata:buttonTitle:`.
   - `setArtworkFanartPath:posterPath:imageCache:` and `cancelArtwork`.
2. Artwork loading mirrors `MRPosterImageView`:
   - Prefer `[MRURLBuilder fanartURLForPath:size:@"_medium"]`.
   - Fall back to `[MRURLBuilder posterURLForPath:size:@"_w"]`.
   - If neither path exists, keep the dark gradient and hide the artwork.
   - Use the cached image immediately when present; otherwise load through
     `MRImageCache` and cancel the previous token when the hero is reused.
3. Layout bottom-up with existing hero heights:
   - 12 pt bottom inset; 34 pt button.
   - Reason above the button, metadata above the reason, title above the
     metadata, eyebrow above the title.
   - Size the title for up to two lines (`21 pt` bold) and the reason for up
     to two lines (`12 pt`).
   - Keep 16 pt side insets and truncate long metadata.
   - No element may overlap at 180 pt (iPhone 4S landscape-height feed).
4. In `MRForYouViewController.m`:
   - Add a static helper that joins year, `MRMediaTypeDisplayName(type)`, and
     up to two genres with ` · `, omitting missing pieces.
   - In the hero cell branch, set:
     - Connect → eyebrow `WELCOME TO MARQUEE`
     - Genre picker → eyebrow `MAKE IT YOURS`
     - Item hero → eyebrow `TOP PICK FOR YOU`
   - Pass the hero item and `self.imageCache`.
   - Change the item button title from `Details` to `View Details`.
   - Add `prepareForReuse` to the hero cell to cancel artwork.
5. Make sure the hero cell forwards the new configure method and handler.
6. Run `./tests/run_tests.sh` and `make clean package FINALPACKAGE=1`.
7. Commit: `polish: give for-you hero artwork and context`.

**Done when** the recommended hero shows fanart (or poster/gradient), an
uppercase eyebrow, a year/type/genre line, its reason, and `View Details`;
connect and genre-picker heroes keep their copy and buttons.

---

## Task 6 — Full verification and screenshots

**Steps**

1. Run `./tests/run_tests.sh`.
2. Run `THEOS=$HOME/theos make clean package FINALPACKAGE=1`.
3. Audit the package:
   - `dpkg-deb -I` shows iOS 6.0 and device families 1+2.
   - The binary links only system frameworks.
   - `ldid -e` (or the existing signature check) validates.
4. Install on the 4S:
   - `scp` the deb to `/tmp/marquee.deb`.
   - `dpkg -i`, `su mobile -c /usr/bin/uicache`, relaunch.
5. Screenshot all four tabs. No touch automation exists, so:
   - Create a temporary local change that selects each tab at launch.
   - Build, install, screenshot, repeat.
   - Revert the hook; rebuild and reinstall the committed tree.
   - Verify the final installed binary does not contain the hook.
6. Check on device:
   - Hero artwork, eyebrow, metadata, reason, and button do not clip at
     320 pt.
   - Search attribution bar sits above the tab bar and never covers a row.
   - Library chip/footer and Profile labels read correctly.
   - iPad portrait/landscape still lays out (if available).
7. Update `.superpowers/sdd/2026-11-04-marquee/progress.md` (not pushed).
8. Commit any device-verification adjustments, push `feature/marquee`,
   fast-forward `main`, push `main`, and reinstall the final package.

## Out of Scope

- New write actions, watchlist button in the hero, or new tabs.
- Redesigning cards, headers, nav bars, or tab bars.
- Fixing unrelated image-loader behavior in the detail view.
- Pushing local progress/design scratch files.
