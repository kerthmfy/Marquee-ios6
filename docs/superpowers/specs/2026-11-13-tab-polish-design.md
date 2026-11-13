# Marquee Tab Polish — Design

Date: 2026-11-13
Status: Proposed

## Intent

Make the four tabs read cleanly and feel intentional. The text should sit where
the eye expects it, the copy should sound human, and the existing iOS 6 /
Matinee chrome should stay untouched. This is a polish pass, not a redesign.

## Goals

- Remove dead space and awkward text placement in the For You hero.
- Make Search's Simkl attribution stop floating in the middle of the page.
- Replace vague Library and Profile labels with specific ones.
- Keep every string short enough for a 320 pt phone and an iPad split width.
- Preserve the current card shapes, pinstripe background, uppercase row headers,
  blue navigation bar, and charcoal tab bar.

## Non-goals

- No new features or write actions. The hero keeps a details action rather than
  adding a watchlist button.
- No new tabs, fonts, colors, or custom chrome.
- No redesign of the card or table structure.
- No iPad-only layout work beyond the shared `MRLayout` metrics.

## Constraints

- Objective-C / ARC, iOS 6, no third-party libraries.
- iPhone portrait; iPad portrait and both landscapes.
- UI changes are compile-verified; pure formatting helpers are unit-tested when
  they are worth extracting.
- Existing tests must pass and the package must still audit clean.

## Approach

Use the in-place polish route. Edit the existing view classes and strings
directly. Add only one small view element (the hero artwork layer) inside
`MRHeroView`; do not introduce a shared chrome abstraction for this pass.

## For You

### Hero

- Show the item's fanart (`_medium`) behind the text. Fall back to the poster
  (`_w`) when fanart is missing, and to the existing dark gradient when both are
  missing.
- Use a bottom-heavy dark gradient over the artwork so white text stays legible.
- Add a small uppercase eyebrow above the title:
  - recommendation: `TOP PICK FOR YOU`
  - connect card: `WELCOME TO MARQUEE`
  - genre picker: `MAKE IT YOURS`
- Add a metadata line under the title: year, media type, and up to two genres,
  separated by `·`. Omit missing pieces instead of leaving stray separators.
- Keep the title and the one-line reason.
- Change the item button title from `Details` to `View Details`.
- The connect and genre-picker cards keep their current titles, reasons, and
  buttons (`Sign In`, `Pick Genres`).

### Empty state

- Title: `Find something to watch`
- Subtitle: `Search Simkl to start your library.`

### Rows

- Keep the existing uppercase headers, cards, and row reasons. The seed, genre,
  watchlist, and trending headers already carry their reason in the title.

## Library

- Status chip `Plan` becomes `Plan to Watch`; the row already scrolls.
- Footer copy changes from `Updated ...` to `Synced ...`:
  - `Synced just now`
  - `Synced 5m ago` / `Synced 2h ago` / `Synced 3d ago`
  - `Waiting for first sync` instead of `Not synced yet`
- Keep `N changes waiting to sync`, `Offline — showing saved library`, and the
  existing empty/filter messages.

## Search

- Search bar placeholder: `Movies, TV shows, anime`.
- Idle suggestion subtitle: `Search movies, TV shows, and anime.`
- The suggestion title stays `Try Dune, The Bear, or Frieren` (the source already
  has the correct spelling).
- Replace the floating table footer with a fixed attribution bar pinned just
  above the tab bar:
  - `Powered by Simkl` plus the bundled Simkl badge
  - visible only while signed in
  - table height reduced by the bar height so no result is covered
- Keep the recent-search, trending, no-match, and error copy.

## Profile

- Account type line: `Simkl Free`, `Simkl PRO`, `Simkl VIP` (fallback
  `Simkl account`).
- Section titles:
  - `Stats` → `Your Library`
  - `Sync` → `Sync Status`
  - `For You` → `Recommendations`
- Stat captions: `Movies`, `TV Shows`, `Anime`, `Episodes`, `Ratings`,
  `Plan to Watch`.
- Recommendation rows:
  - `Favorite Genres` with `3 selected` / `None selected`
  - `Hidden Titles` with `3 hidden` / `None hidden`
- About rows:
  - `View on Simkl` → `Connected Apps` (opens the connected-apps page)
  - `Data from Simkl` → `Simkl Website` with a chevron (opens simkl.com)
  - `Version` and `Diagnostics` unchanged
- Sync row keeps `Up to date`, `Syncing…`, `Offline`, `N pending`, and
  `Last synced 2:16 PM`.

## Verification

- `./tests/run_tests.sh` passes.
- `make clean package FINALPACKAGE=1` exits 0 and the package still audits for
  iOS 6.0, device families 1+2, iPhone portrait, iPad orientations, system
  frameworks only, and a valid `ldid` signature.
- Device screenshots for all four tabs. Because no touch automation exists, use
  a temporary local build that selects each tab at launch for screenshots, then
  rebuild the committed tree without that selection hook.
- Confirm the hero artwork, metadata, and eyebrow render without clipping at
  320 pt; confirm the Search attribution bar sits above the tab bar; confirm
  Library and Profile text at their new sizes.

## What is left to the builder

- Choose exact insets inside the existing hero metrics so two-line titles,
  metadata, reason, and button do not collide.
- Decide whether a hero with both fanart and poster missing keeps the eyebrow
  and metadata or shows the gradient plus text only.
- Adjust only font sizes or line counts that actually clip during device
  verification.
