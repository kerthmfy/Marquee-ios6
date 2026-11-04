# Marquee — iOS 6 SimKL client design

Status: draft for builder check and approval  
Date: 2026-11-04  
Target: jailbroken iPhone, iOS 6.0+, armv7  
Language: Objective-C, ARC, Theos

## 1. Intent

Marquee is a standalone iOS 6 client for SimKL. It is not a Matinee feature, not a
relay client, and not a web wrapper. It talks directly to SimKL's public API and
uses the Matinee visual language so it feels at home beside Matinee on the same
device.

The first page is **For You**, a recommendation feed. SimKL does not offer a
free, ready-made recommendation endpoint, so Marquee builds one from data a free
account can already see:

- the user's synced library and ratings,
- `similar` and `users_recommendations` on item detail responses,
- SimKL's public Most Watched genre files,
- SimKL's public Trending files.

The app is deliberately small: four tabs, a readable recommendation recipe, a
real library, search, item actions, and offline-safe persistence. It is meant to
be built, installed, and used on one jailbroken device, not shipped to the App
Store.

## 2. Goals

1. Sign in with a free SimKL account through the AUTH V2 device/PIN flow, with no
   `client_secret` in the app and no relay.
2. Make **For You** the first tab and the emotional center of the app. It should
   feel personal when the library has signal, and honest and useful when it does
   not.
3. Sync the user's SimKL library well enough that Library, search, detail, and
   recommendations agree with simkl.com.
4. Let the user do the core tracking actions: set status, rate 1–10, mark a whole
   item watched, mark the next episode watched, and remove an item.
5. Survive iOS 6 conditions: no `NSURLSession`, no modern web auth, limited
   memory, no background fetch, and a TLS stack that must be treated as old.
6. Reuse Matinee's bottom-bar geometry, navigation chrome, card treatment, and
   iOS 6 restraint without sharing code or becoming a Matinee feature.
7. Build a device-installable `.deb` with Theos, armv7, deployment target 6.0.

## 3. Non-goals

- No SimKL PRO/VIP-only features: no rewatches, no custom lists, no PRO gates.
- No scrobbling or playback sessions. Marquee records completed watches, not
  real-time playback.
- No full episode browser. V1 marks the next episode or the whole item; it does
  not list every season and episode.
- No calendar, DVD releases, trailers, comments, social features, or imports.
- No push notifications, background sync, or widgets.
- No iPad-native layout and no landscape. iPhone portrait only; iPad runs in
  compatibility mode.
- No Core Data or SQLite. Persistence is file-backed JSON.
- No third-party SDKs, analytics, crash reporting, or image libraries.
- No relay server and no Cloudflare bypass. That Matinee idea stays parked.
- No logo or brand identity work. The logo is parked. V1 uses a clearly
  temporary placeholder icon and launch image.

## 4. Anti-goals

These would make the app a failure even if it technically runs:

- A recommendation page that is only a renamed trending list, with no library
  signal and no explanation of why an item is there.
- A client that writes to SimKL in a way that loses changes, duplicates watches,
  or fights the server's own status decisions.
- A sync loop that polls `/sync/all-items` on a timer and gets the `client_id`
  suspended.
- A UI that looks like a modern iOS app squeezed onto iOS 6: stacked views,
  alert controllers, blur effects, or auto layout.
- A second Matinee codebase with a different bar and a different feel.
- A hidden server dependency.

## 5. Constraints

### Platform

- iOS 6.0 deployment target, armv7. The device is a jailbroken iPhone.
- Objective-C only. ARC. No Swift, no CocoaPods, no SPM.
- Theos with `$HOME/theos`. The local install has `iPhoneOS11.4.sdk`; no iOS 6.1
  SDK is present. Build with the 11.4 SDK's armv7 slice and a 6.0 deployment
  target, as Matinee does.
- Only iOS 6-era UIKit/Foundation APIs. See the banned-API audit in §20.
- No storyboards and no nibs. Window and view controllers are built in code.
- UIKit, Foundation, CoreGraphics, QuartzCore, Security, and optionally
  SystemConfiguration. No other frameworks.

### Network

- SimKL API base: `https://api.simkl.com`.
- Public data files: `https://data.simkl.in`.
- Image proxy: `https://wsrv.nl`.
- Every API request carries `client_id`, `app-name=marquee`,
  `app-version=1.0`, and `User-Agent: Marquee/1.0 (iOS 6)` (plus `Accept:
  application/json`). Public data files also require these query parameters and
  the User-Agent, but never a bearer token.
- SimKL works from an iOS 6-era TLS stack; this was verified before design.
  Images use `wsrv.nl` because iOS 6 cannot decode SimKL's WebP posters.
- No request may carry a bearer token to `data.simkl.in` or `wsrv.nl`.

### API citizenship

- 10 GET/sec and 1 POST/sec per client and user token.
- AUTH V2 free users have 500 requests per day, reset at midnight US Eastern.
- Detail endpoints and Trending/Calendar files are documented as free of the
  daily quota and per-second limit. Cache them anyway.
- Never poll `/sync/all-items` on a timer. Always gate behind
  `/sync/activities` and use `date_from`.
- Write serially per user, batch where practical, and never parallelize writes.
- Attribute SimKL wherever its data appears, with a per-item link and a visible
  SimKL badge. Trending section titles must name both SimKL and Trending/Most
  Watched.

## 6. Approaches considered

### A. Public-only discovery

Use only the public Trending files and genre files. No auth, no sync, no user
state.

- Pros: simplest possible app; no token handling; no sync bugs.
- Cons: it is not a SimKL client. For You would be a generic popularity list, and
  the app could not show the user's own library or ratings. It fails the
  "recommendations" goal because nothing is personal.

Rejected.

### B. Hybrid library-aware recommendations (chosen)

Sync the user's library, derive a lightweight taste profile, then compose For You
from `users_recommendations`, `similar`, public genre files, the user's
watchlist, and public Trending. Exclude anything already tracked. Explain every
row.

- Pros: genuinely personal with a free account; uses only documented free data;
  degrades cleanly to trending for a new or empty account; no server.
- Cons: more moving parts (auth, sync, persistence, outbox); recommendation
  quality depends on how much the user has rated/watched; genre data for library
  items must be enriched from detail endpoints.

Chosen because it is the smallest design that still delivers the product the
user asked for.

### C. Server-side recommender

Run a small service that holds the library, computes embeddings or collaborative
filtering, and returns ranked rows.

- Pros: best possible ranking quality; central place to tune.
- Cons: explicitly ruled out (no relay), adds hosting and privacy surface, and
  is far more than a one-device iOS 6 app needs.

Rejected.

## 7. Product shape

### Tabs

Four tabs, matching Matinee's four-tab rhythm:

1. **For You** — recommendations first.
2. **Library** — the synced SimKL library, filterable by type and status.
3. **Search** — SimKL search.
4. **Profile** — account, sync status, recommendation preferences, diagnostics,
   sign out.

Each tab is a `UINavigationController` with a custom-styled navigation bar. The
tab bar is styled by `MRAppearance`, adapted from Matinee's `MTAppearance`.

### Signed-out state

The app is useful before sign-in, but not fake-personal:

- **For You**: a "Connect Simkl" hero card at the top, followed by the public
  "Simkl Trending This Week" row and one or two public "Trending Movies/TV/Anime
  on Simkl" rows. Tapping a card opens its public detail page.
- **Library**: a connect card. No library exists without an account.
- **Search**: a connect card, because AUTH V2 requires a user token for search.
- **Profile**: a connect card, plus About and Diagnostics.

Connect opens the device-flow modal. After success, the app fetches the profile,
performs the initial sync, and For You becomes personalized.

### Signed-in but empty library

- For You shows a "Make For You yours" card with genre chips, then public
  trending rows. The genre picker is optional and can be skipped.
- Once the user picks genres, "Because You Like …" rows appear immediately from
  public genre files, without waiting for a library.
- Library and Profile show zero-state cards that point to Search.

### Signed-in with a library

For You shows the composed feed in §8. Library shows the snapshot. Search and
detail work against the live API. Writes go through the outbox.

## 8. For You

For You is a `UITableView` with a hero section and up to five horizontal rows.
Rows are omitted when empty. No item appears twice on the page, except that
watchlist items only appear in the watchlist row.

### 8.1 Inputs

- **Library snapshot**: all tracked items with type, status, user rating,
  last-watched date, episode counts, and next-episode info.
- **Enriched genres**: `/sync/all-items` does not return genres. After the
  initial sync, Marquee fetches detail records for up to 24 high-signal items
  (completed, watching, or rated; most recent first) to fill `genres`,
  `fanart`, community ratings, and runtime. Detail endpoints are free of the
  daily quota, are cached for 24 hours, and run one at a time in the background.
  Genres learned here are saved into the library snapshot.
- **Manual genres**: up to five `{type, name, slug}` choices from Profile. These
  are a cold-start signal and a correction mechanism.
- **Hidden titles**: local "not interested" entries, stored separately from the
  library.
- **Public caches**: `week_100.json` trending, genre indexes, genre files, and
  detail records.

### 8.2 Taste profile

`MRTasteProfile` is a plain value object built from the snapshot.

For each library item:

```
statusWeight:
  completed   3.0
  watching    2.5
  hold        1.0
  plantowatch 1.2
  dropped    -2.0
  none        0.0

ratingMultiplier:
  rating >= 8 1.5
  rating 6-7  1.1
  rating 1-5  0.6
  unrated     1.0

recencyMultiplier:
  last watched within 90 days  1.2
  within 365 days              1.0
  older or unknown             0.8

signal = statusWeight * ratingMultiplier * recencyMultiplier
```

- Add `signal` to every genre in the item's enriched `genres`.
- Add `max(signal, 0)` to the item's type weight.
- Manual genres add `+4.0` to the genre and `+2.0` to the matching type.
- Normalize genre weights to 0…1 by dividing by the maximum positive weight.
- `favoriteGenres` = the top five with normalized weight > 0.1.
- `typeWeights` are normalized by the maximum type weight.
- `seedItems` = up to three recent completed/watching items, preferring one per
  type and preferring items with a rating of 7 or higher. If there are none, use
  recent completed/watching items without a rating, then highly rated
  hold/plantowatch items.
- If the library is empty, the taste profile is built from manual genres only.

Dropped items have a negative status weight. They lower the affinity of their
genres but do not remove the genres from consideration entirely, because one bad
superhero film should not erase superheroes.

### 8.3 Candidate sources

| Source | How | Base score | Notes |
|---|---|---:|---|
| `users_recommendations` | Detail response for each seed, up to 20 | 1.00 | "Viewers of this also watched" |
| `similar` | Detail response for each seed, up to 20 | 0.85 | Same-genre strip |
| Genre file | Top two favorite genres, up to 30 each | 0.70 | From `data.simkl.in`, free |
| Watchlist | Local `plantowatch` items | 0.60 | Only for the watchlist row |
| Trending | `week_100.json`, combined movies/TV/anime | 0.45 | Public, free |
| Manual genre | Genre file for a manual genre | 0.75 | Cold start |

Genre files are read from the type's `genre/index.json`; slugs are never
hardcoded. Skip the adult slugs `erotica` and `hentai`, and skip the low-signal
`video-game-play` slug. If a favorite genre has no file for the highest-weighted
type, try the next type that has it, then the next favorite genre.

Candidates from `users_recommendations` and `similar` do not carry genres. They
inherit the seed's genres as a proxy, weighted at half strength. Trending and
genre-file items carry their own genres. Detail responses provide genres for the
seeds themselves.

### 8.4 Normalization, exclusion, and scoring

Normalize every candidate to an `MRMediaItem`:

- `simklID` from `ids.simkl` (sync/detail) or `ids.simkl_id` (search/trending).
- Type from the source (`movies` → movie, `tv`/`shows` → show, `anime` → anime).
- Poster path, fanart path, title, year, genres, community ratings, runtime, and
  external IDs where available.

Exclude:

- anything already in the library, except the watchlist row,
- anything in the hidden set,
- anything with an adult genre (`erotica`, `hentai`),
- anything without a title or SimKL ID,
- anything already selected for a higher row.

Score each candidate:

```
genreScore      = average taste weight of its genres (proxy genres at 0.5x)
ratingScore     = clamp((simklRating - 5) / 5, 0, 1), or 0.5 if unknown
recencyScore    = 1.0 if released in the last 5 years
                  0.6 if released in the last 15 years
                  0.3 otherwise
popularityScore = clamp(log10(1 + watchedCount) / 4, 0, 1)
typeScore       = normalized type weight for the candidate's type

score = base
      + 0.35 * genreScore
      + 0.15 * ratingScore
      + 0.10 * recencyScore
      + 0.05 * popularityScore
      + 0.10 * typeScore
```

These constants are a starting point. The builder may tune them against the real
library, but the sources, exclusions, and row structure are fixed by this design.

Tie-break by title, then by SimKL ID, so the feed is deterministic.

### 8.5 Rows and order

1. **Hero** — the highest-scored new recommendation. Full-width fanart (or a
   landscape poster as fallback), title, year, genres, and a one-line reason.
   Tapping opens detail. A small "+ Watchlist" button adds it without leaving
   the page. If signed out or the library is empty, the hero becomes the connect
   or genre-picker card.
2. **Continue Watching** — local `watching` items with a next episode or
   unfinished episodes, most recent first, up to 10. Shows "Next: S2E5 · title"
   or "7 of 10 episodes". Tapping opens detail.
3. **Because You Watched <seed>** — merged `users_recommendations` and `similar`
   for the strongest seed, up to 12. Recommendations come first, then similar.
   If the seed has fewer than 4 candidates left, use the next seed to fill.
4. **Because You Like <genre>** — the top favorite genre's file, up to 12.
5. **From Your Watchlist** — local `plantowatch` items, scored by genre affinity
   and community rating, up to 12. Reason: "On your watchlist".
6. **Simkl Trending This Week** — public trending, filtered against the library,
   up to 12. Title must include both "Simkl" and "Trending".

If a non-hero row has fewer than 3 items, omit it. Continue Watching may show a
single item. If the page would have no rows at all, show an empty-state card
with "Find something on Simkl" and a Search button.

Cold start order:

1. Connect hero (signed out) or "Make For You yours" genre card (signed in,
   empty library).
2. Because You Like <genre> for up to two manual genres.
3. Simkl Trending This Week.
4. Trending Movies/TV/Anime on Simkl, depending on available data.

### 8.6 Explanations and feedback

Every row and the hero have a short, honest reason:

- "Because you watched **Interstellar**"
- "Because you like **Science Fiction**"
- "On your watchlist"
- "Trending this week on Simkl"
- "Popular on Simkl this week"

No fake machine-learning claims. If the feed is trending-only, say so.

A long-press on any card opens an action sheet:

- **Not interested** — signed in only. Adds the item to the account's hidden
  set, removes it from the page, and regenerates the feed locally. Hidden items
  can be unhidden in Profile. The hidden set is per-account, so this action is
  omitted while signed out rather than creating an anonymous store with unclear
  merge semantics.
- **Why this?** — an alert with the row's reason and the seed or genre that
  produced it.
- **Open on Simkl** — opens the per-item SimKL page in Safari.

The detail screen offers the same actions in its overflow menu, with "Not
interested" available only when signed in.

### 8.7 Refresh and caching

- Recompose For You after a successful initial sync, after a sync that changes
  the library, after a successful write, after genre/hidden changes, and on
  pull-to-refresh.
- On foreground, recompose if the cached feed is older than 6 hours. Do not
  recompose more than once every 5 minutes unless the user forces it.
- Cache the composed feed in `recommendations.json` with a fingerprint of
  `library savedAt + trending fetch date + genre fetch dates + manual genres +
  hidden count`. If the fingerprint matches and the feed is under 6 hours old,
  render it immediately and skip the network.
- Trending and genre caches are valid for 24 hours. Seed detail caches are valid
  for 24 hours.
- If recomposition fails and a cached feed exists, keep the cache and show a
  thin "Couldn't refresh recommendations" banner with Retry. If there is no
  cache, show an error card with Retry and a public trending fallback.

## 9. Library

### Data

The Library tab reads `MRLibraryStore`, which is the normalized snapshot. It never
fetches on scroll. Pull-to-refresh triggers the sync engine.

### Layout

- Navigation title "Library".
- A four-segment type control: All, Movies, TV, Anime. `UISegmentedControl`,
  iOS 6 style, 32 pt tall.
- A horizontally scrolling row of six status chips: All, Watching, Plan,
  Completed, Hold, Dropped. Each chip shows a count. Selected chips use a blue
  gradient; unselected chips are white with a hairline border.
- A `UITableView` of white cards with 8 pt side insets, matching Matinee's
  grouped-card look. Each row:
  - poster thumbnail (`_cm`, 42×62 pt),
  - title (14 pt bold),
  - year and type (11 pt muted),
  - a small status pill (Watching blue, Plan gray, Completed green, Hold amber,
    Dropped red),
  - user rating as a compact "★ 8" label, not ten stars,
  - next-episode line for watching items,
  - disclosure indicator.
- Sort by last watched descending, then added date descending, then title.
  Plan-to-watch uses added date. Completed uses last watched.
- Pull-to-refresh shows the standard `UIRefreshControl`. While syncing, the
  navigation bar shows a small spinner and "Syncing…".
- A footer shows "Updated 2m ago", "Offline — showing saved library", or
  "3 changes waiting to sync".
- Empty states are per filter, in a white card, with a Search button.
- Tapping a row opens detail.

### Movie status rules

Movies only support Plan, Completed, and Dropped. The UI must never offer
Watching or Hold for a movie. Shows and anime support all five statuses.

## 10. Search

### Behavior

- `UISearchBar` under the navigation bar, placeholder "Movies, TV, anime".
- Search fires 500 ms after typing stops, with at least 3 characters. Cancel the
  in-flight request when the query changes.
- The request is `GET /search/all?q=<encoded>&extended=full&limit=30&page=N`.
  AUTH V2 requires the bearer token. Results mix types; branch on each item's
  `endpoint_type` (`movies`, `tv`, `anime`).
- Results are cached in memory for 10 minutes per query and page. Recent
  searches (up to 8) are stored per account.
- A "Load more" row appears when a page returns 30 results. It fetches the next
  page on tap; do not auto-load. Cap at 5 pages per query to protect the daily
  quota.
- Empty query shows recent searches; if there are none, show "Try Dune, The
  Bear, or Frieren" and a few public trending suggestions.
- No matches shows a white card with "No matches" and a suggestion to check the
  spelling or try an alternate title.
- Errors show an inline banner. Offline search is disabled with "Search needs a
  connection."
- Signed-out search shows a connect card instead of the search bar.

### Results

White card rows with poster thumbnail, title, year, type pill, and community
rating. Tapping opens detail. A footer says "Search powered by Simkl" with the
SimKL badge and a link to simkl.com.

## 11. Detail

Detail is a `UIScrollView` with stacked cards. It opens immediately from the
library snapshot or search/trending item, then fetches the public detail record
to fill in overview, genres, ratings, fanart, similar titles, and viewer
recommendations.

### Header

- Full-width fanart or landscape poster with a dark gradient at the bottom.
- Title, year, runtime, type, genres, and community rating.
- If tracked: status pill, user rating, episode progress, and next episode.
- "View on Simkl" link and the SimKL badge, with the per-item URL built from the
  numeric SimKL ID and slug.

### Actions

A primary button whose label depends on state:

| State | Primary action |
|---|---|
| Not tracked | Add to Watchlist (Plan) |
| Plan, movie | Mark Watched (Completed) |
| Plan, show/anime | Start Watching (status Watching) |
| Watching, next episode exists | Mark S2E5 Watched |
| Watching, no next episode | Mark All Watched |
| Completed | Change Status |
| Hold/Dropped | Move to Watching |

Secondary actions:

- **Rate** — expands a ten-star control, 1–10, plus "Remove rating". Tapping a
  star sets that rating. A second tap on the same star does not clear it; use
  the explicit Remove action to avoid accidents.
- **Change Status** — an action sheet with only the statuses valid for the
  media type. The current status is checked.
- **Remove from Library** — destructive confirmation. Calls
  `/sync/history/remove` with the whole item, which removes watch history and
  the watchlist entry. This is the canonical SimKL path; do not use the
  undocumented `to: "remove"` value.
- **Not Interested** — hides the title from For You without touching SimKL.

Every action updates the local item optimistically, enqueues an outbox entry,
and shows a small "Saved" toast or a "Will sync when online" toast. When the
write succeeds, reconcile the server's resolved status from the response. If
SimKL downgrades a `completed` write to `watching` because the show is still
airing, show that resolved status and a short note.

### Body

- Overview.
- Info rows: network, country, release date, air status, total episodes, runtime,
  SimKL rating, IMDb/MAL rating.
- For shows/anime: a next-episode card with season, episode, title, and air date.
  No full episode list in v1.
- "More Like This" horizontal row from `similar`.
- "Viewers Also Watched" horizontal row from `users_recommendations`.
- A footer: "Movie, TV and anime data from Simkl" with the badge and a link.

If the detail fetch fails but a snapshot exists, show the snapshot fields and a
"Details unavailable offline" note. If there is no snapshot and no network, show
an error card with Retry.

### Episode writes

For a watching show/anime, use the `next_to_watch_info` from sync exactly as
returned: season, episode, title, date. Send:

```json
{
  "shows": [
    {
      "ids": { "simkl": 12345 },
      "seasons": [
        { "number": 2, "episodes": [ { "number": 5 } ] }
      ]
    }
  ]
}
```

Do not renumber anime. If the write response reports an unexpected episode count,
fall back to "Mark All Watched" or a status change and surface a short note.
Anime may be sent under `shows[]` for history writes; SimKL resolves it.

## 12. Profile

Profile is a grouped settings screen built from white cards on the pinstripe
background.

### Signed in

- **Header card**: avatar, name, account type (Free/PRO/VIP, display only),
  joined date, location, and bio. If the avatar is missing, draw initials.
- **Stats card**: Movies, TV, Anime counts; episodes watched; ratings; watchlist
  count. Computed from the local snapshot, not extra API calls.
- **Sync card**: "Sync now" with last-synced time and state (Syncing, Up to date,
  Offline, N pending). A small "Daily requests" line may live in Diagnostics
  rather than here.
- **For You card**:
  - Favorite genres → genre picker (up to five, grouped by Movies/TV/Anime).
  - Hidden titles → list with Unhide.
  - Reset recommendations → clears the composed feed and regenerates.
- **About card**: View on Simkl (connected apps page), "Data from Simkl" with
  badge, version, and Diagnostics.
- **Sign Out** destructive row.
- **Remove Local Data** destructive row, smaller, with a confirmation.

### Genre picker

A modal navigation controller with Cancel/Done. It fetches the three
`genre/index.json` files (cached 24 hours) and lists genres under Movies, TV,
and Anime. Adult genres and `video-game-play` are hidden. The user may select up
to five total. If the indexes are unavailable and uncached, show an error card
with Retry; do not hardcode slugs.

### Hidden titles

A table of hidden items with poster, title, and an Unhide button. Hidden entries
store enough metadata to render without a network call. Cap at 200.

### Diagnostics

A diagnostics screen for this personal device:

- app version/build, iOS version, device model,
- account ID and name,
- last sync attempt/result,
- pending outbox count,
- today's API request count and the last `X-RateLimit-Remaining`/`Limit`,
- last 20 API errors with method, path, status, and SimKL error code (never
  tokens),
- cache sizes,
- Copy Diagnostics,
- Clear Image Cache,
- Force Full Sync (confirmation; wipes the snapshot and runs phase 1).

### Signed out

Header becomes a Connect Simkl card. Stats and sync cards are hidden. About and
Diagnostics remain. Sign Out and Remove Local Data are hidden.

## 13. Visual system and Matinee reuse

Marquee reuses Matinee's *look*, not its code. `MRAppearance` is a new class
adapted from `MTAppearance`, with the same values and drawing techniques.

### Tab bar

Match Matinee's geometry exactly:

- 49 pt tall, full width, 4 equal items.
- Background: vertical gradient `#4D4D4F` → `#303031` → `#1C1C1F`, with a 1 px
  white highlight at the top (alpha 0.55).
- A `UIView` overlay draws the one-pixel bevels at 1/4, 2/4, and 3/4 width:
  a white hairline at 10% alpha and a black hairline at 65% alpha.
- Selected indicator image is a clear 1×1 image so iOS 6's default glass
  highlight is suppressed.
- Selected glyph: glossy blue gradient `#24BFFF` → `#006BD1`.
- Unselected glyph: gray gradient `#CCCCD1` → `#75757D`.
- Titles: 10 pt bold; normal `#A8A8AD`, selected white; black shadow offset
  (0, -1).
- Use `setFinishedSelectedImage:withFinishedUnselectedImage:`.

Tab icons are drawn in code at 30×30, like Matinee:

- **For You**: a five-point star with a small sparkle.
- **Library**: three offset rounded cards, suggesting a collection.
- **Search**: the same magnifier path as Matinee.
- **Profile**: the same person path as Matinee.

### Navigation bar

Match Matinee:

- 44 pt gradient `#6B8FB3` → `#5C80A6` → `#476B91` → `#3A5C80`, with a
  white 40% highlight at the top.
- Tint `#29476B`.
- Title 17 pt bold white, black shadow offset (0, -1).
- Back and action buttons use the shaped iOS 6 gradient button from Matinee.

### Color and type

| Token | Value | Use |
|---|---|---|
| paper | `#F4F5F7` | grouped-table background |
| groupBackground | `#C8CCD2` | pinstripe base |
| sep | `#C9CCD1` | 1 px separators |
| ink | `#212126` | primary text |
| muted | `#7A7A80` | secondary text |
| placeholder | `#E7E9ED` | poster backing |
| link | `#29598F` | tappable blue |
| green | `#00C753` | stars, completed |
| starEmpty | `#D1D6DB` | empty stars |
| watching | `#2D7DD2` | status pill |
| plan | `#8A8F98` | status pill |
| completed | `#1F9D55` | status pill |
| hold | `#C98A1B` | status pill |
| dropped | `#C0392B` | status pill |

Fonts are the iOS 6 system font: bold 17 for navigation titles, bold 16 for
screen titles, 13 body, 11 small, 11 bold uppercase section headers. No custom
fonts.

### Cards and headers

- White card, 8 pt side inset, 9 pt corner radius, 1 px `#A6ADB5` border, 1 px
  `#D5D8DC` separator. Reuse Matinee's `MTCardBackgroundView` drawing logic.
- Grouped settings use the pinstripe section header: `#C8CCD2` base with a 1 px
  white 34% stripe, uppercase 11 pt bold title.
- For You row headers are lighter: 13 pt bold uppercase, muted, 12 pt left
  inset, 1 px hairline below. The Trending header includes a small SimKL badge.

### For You layout

- `UITableViewStylePlain`, with the grouped background color.
- Hero cell: 320×200 on a 4-inch screen, 320×180 on a 3.5-inch screen. Fanart
  `_medium` via wsrv.nl, or a `_w` poster as fallback. Dark gradient overlay at
  the bottom for text contrast.
- Horizontal row cell: 210 pt tall. A `UIScrollView` with 12 pt side insets, 8 pt
  gaps, 100×150 pt poster cards. Title two lines at 11 pt bold, meta one line at
  10 pt muted.
- Continue Watching cards have a 3 pt progress bar at the bottom of the poster
  and a "S2E5 · title" line.
- Section headers 32 pt tall. No "See All" in v1; rows are capped.
- Pull-to-refresh on the table.
- Skeleton state: a gray hero block and two rows of gray cards with a centered
  spinner. No shimmer animation.

### Status and error banners

A slim banner pinned below the navigation bar, 32 pt tall, with a tinted
background, 11 pt text, and an optional Retry button:

- amber for offline or stale cache,
- red for daily quota or auth failure,
- blue-gray for pending writes,
- neutral for "Updating…".

Success feedback is a small dark toast that fades after 1.5 seconds. Use
`UIAlertView`/`UIActionSheet` for confirmations and choices, never
`UIAlertController`.

### Assets

- **SimKL badge**: bundle the official 192×192 PNG from
  `https://us.simkl.in/img_favicon/v2/favicon-192x192.png` as
  `SimklBadge.png`; display it at 16–18 pt next to "Simkl" in attribution
  footers and the Trending header. This is SimKL attribution, not Marquee
  branding.
- **Poster placeholder**: a light gray field with a simple film-frame glyph
  drawn in code.
- **Launch images**: `Default.png` 320×480, `Default@2x.png` 640×960,
  `Default-568h@2x.png` 640×1136. Plain charcoal `#1E1E20` with "Marquee" in
  white system type. No logo.
- **App icon**: placeholder only: charcoal field with a white "M" in bold
  system type and a thin blue rule. Sizes 57, 114, 72, 144. Replace when the
  logo is approved.
- Do not use the parked brand-board SVGs in the app.

### Motion

Keep it iOS 6: `UIView` fade/slide animations of 0.15–0.25 seconds. No springs,
no parallax, no blurred transitions.

## 14. Authentication

### Registration

Register a new AUTH V2 app at `https://simkl.com/settings/developer/`.

- Client type: **TV, devices & command line**. This registration has no redirect
  URI and no client secret, which matches a device-flow-only app. SimKL permits
  the device flow for any client type, but this type is the cleanest fit because
  Marquee will never run a browser callback.
- The `client_id` is public and lives in `MRConfig.h`.
- There is no `client_secret` anywhere in the app or repo.

If the user later wants the authorization-code + PKCE flow, that requires a new
registration; V2 client types cannot be changed. This is a deliberate v1
trade-off.

### Device flow

1. `POST https://api.simkl.com/oauth2/device` with form fields
   `client_id` and `scope=media:read media:write`. Include the standard query
   parameters and User-Agent.
2. Response:

```json
{
  "device_code": "...",
  "user_code": "BDWP-HQPK",
  "verification_uri": "https://simkl.com/pin",
  "verification_uri_complete": "https://simkl.com/pin?user_code=BDWP-HQPK",
  "expires_in": 900,
  "interval": 5
}
```

3. Show the code exactly as returned, hyphen included, in large type. Provide:
   - "Open simkl.com/pin" (uses `verification_uri_complete` when present,
     otherwise `verification_uri`),
   - "Copy Code" (`UIPasteboard`),
   - a short explanation: "Approve Marquee on SimKL, then come back here."
4. Poll `POST https://api.simkl.com/oauth2/token` every `interval` seconds with
   form fields:
   - `grant_type=urn:ietf:params:oauth:grant-type:device_code`
   - `client_id`
   - `device_code`
5. Poll outcomes:
   - `authorization_pending` (400): keep polling.
   - `slow_down` (400): add 5 seconds to the interval, then wait.
   - `expired_token` (400): stop, show "Code expired", offer Try Again.
   - `invalid_client` (401): stop, show a configuration error, point to
     Diagnostics.
   - Success: store tokens, then fetch `/users/settings`.
6. There is no deny signal. Enforce the 15-minute deadline locally with a timer
   based on the start time. Give up at the deadline even if still pending.
7. Only one poll may be in flight. When the app returns to the foreground, poll
   immediately rather than waiting for the next timer tick.

The connect screen is a modal `UINavigationController` with a scroll view. It
shows the code, the buttons, a spinner, and the current status. It can be
cancelled at any time.

### Token lifecycle

- Access token: 7 days. Refresh token: 180 days, sliding, non-rotating.
- Store tokens in the Keychain, not `NSUserDefaults`:
  - service `com.marquee.app.simkl`,
  - accounts `access_token`, `refresh_token`, `expires_at`, `account_id`,
    `account_name`,
  - accessibility `kSecAttrAccessibleAfterFirstUnlock`.
- Before every authenticated request, if the access token expires within 5
  minutes, refresh it:
  - `POST /oauth2/token` with `grant_type=refresh_token`, `client_id`, and
    `refresh_token`.
  - Serialize refreshes. Requests wait for one refresh rather than each starting
    their own.
  - Store the returned access token and `expires_at`. The refresh token is
    non-rotating, but store whatever comes back.
- On refresh failure with `invalid_grant` or `invalid_client`: clear tokens,
  enter signed-out state, keep local data, and show "Session expired. Reconnect
  to sync."
- If Keychain storage fails, do not proceed with sign-in. Show "Could not
  securely store your session" and a Retry.

### Account identity

After the token exchange, `GET /users/settings` returns `account.id`. Use that
integer as the account directory key. If settings fails after a successful token
exchange, keep the connect screen open with "Signed in, but couldn't load your
profile" and retry. If the app is killed in that window, the next launch sees a
token without an account ID and retries settings before creating the directory.

If a different account signs in, use a different directory. Never send the old
account's outbox to the new account.

### Sign out

Sign Out clears Keychain tokens, stops sync, and switches to the signed-out
state. It keeps the local snapshot and outbox on disk, because pending changes
may still be valuable. If the outbox is non-empty, warn: "N changes haven't
synced. Sign out anyway?" Signing back into the same account resumes the
outbox. "Remove Local Data" deletes the account directory, caches, and Keychain
items.

## 15. API contract

### Common request rules

- Base: `https://api.simkl.com`; public files: `https://data.simkl.in`.
- Every request:
  - `client_id=<MR_SIMKL_CLIENT_ID>`
  - `app-name=marquee`
  - `app-version=1.0`
  - `User-Agent: Marquee/1.0 (iOS 6)`
  - `Accept: application/json`
- User-scoped requests add `Authorization: Bearer <access_token>`.
- POST auth requests use `application/x-www-form-urlencoded`; sync writes use
  `application/json`.
- Use `NSURLRequestReloadIgnoringLocalCacheData`; Marquee manages its own cache.
- Timeout 30 seconds for API, 60 seconds for trending files, 30 seconds for
  images.

### Endpoint summary

| Method | Path | Auth | Counts against quota | Purpose |
|---|---|---|---|---|
| POST | `/oauth2/device` | client_id | assume yes | Start device flow |
| POST | `/oauth2/token` | client_id | assume yes | Poll / refresh |
| GET | `/users/settings` | bearer | yes | Profile, account ID |
| GET | `/sync/activities` | bearer | yes | Sync gate |
| GET | `/sync/all-items/{type}` | bearer | yes | Initial library |
| GET | `/sync/all-items` | bearer | yes | Delta merge |
| GET | `/sync/ratings/{type}` | bearer | yes | Rating delta |
| GET | `/search/all` | bearer | yes | Search |
| GET | `/movies/{id}`, `/tv/{id}`, `/anime/{id}` | no | no | Detail, similar, recommendations |
| GET | `data.simkl.in/discover/trending/…` | no | no | Trending and genre files |
| POST | `/sync/add-to-list` | bearer | yes (1 POST) | Status only |
| POST | `/sync/history` | bearer | yes | Watched events |
| POST | `/sync/ratings` | bearer | yes | Set rating |
| POST | `/sync/ratings/remove` | bearer | yes | Clear rating |
| POST | `/sync/history/remove` | bearer | yes | Remove from library |

The app reads `X-RateLimit-Limit` and `X-RateLimit-Remaining` from bearer
responses and shows them in Diagnostics. It treats `Retry-After` on a daily 429
as seconds from now, not as a timestamp.

### Public data

Trending combined file:

```
https://data.simkl.in/discover/trending/week_100.json?client_id=…&app-name=marquee&app-version=1.0
```

Top-level keys `movies`, `tv`, `anime`; each is an array of items with `title`,
`poster`, `fanart`, `ids.simkl_id`, `ids.slug`, `release_date`, `genres`,
`ratings`, `network`, `url`, `watched`, `plan_to_watch`, and related fields.
When `poster` is null, use the wsrv-proxied placeholder.

Genre index:

```
https://data.simkl.in/discover/trending/<type>/genre/index.json?…
```

Each entry is `{name, slug, count}`, sorted A–Z. Read slugs from the index.

Genre file:

```
https://data.simkl.in/discover/trending/<type>/genre/<slug>_month_500.json?…
```

The file is the array directly. The file is the membership; do not re-check an
item's `genres` array.

Use `Last-Modified`/`If-Modified-Since` and accept `304 Not Modified`. Do not add
cache-busting query parameters.

### Images

Build image URLs with wsrv.nl and always ask wsrv for a JPEG:

```
Poster:  https://wsrv.nl/?url=https://simkl.in/posters/<path>_m.webp&output=jpg&q=90
Fanart:  https://wsrv.nl/?url=https://simkl.in/fanart/<path>_medium.webp&output=jpg&q=90
Hero:    fanart _medium, or poster _w
List:    poster _cm
Detail:  poster _m
```

`output=jpg` is mandatory. Without it wsrv preserves the source WebP and iOS 6
renders a blank image. Use `_w` for a landscape poster fallback (600×338), `_m`
for medium portrait (340×*), `_cm` for compact list thumbnails (84×124), `_c`
for compact cards (170×250), and `_ca` for card grids (190×279). Fanart
`_medium` is the hero image. If fanart is missing, use `_w`; if the poster is
missing, use the wsrv-proxied `poster_no_pic_c.png` with `output=jpg`. Never
request WebP directly from iOS 6.

### User settings

`GET /users/settings` returns:

```json
{
  "user": {
    "name": "username",
    "joined_at": "2018-01-15T00:00:00Z",
    "avatar": "https://simkl.in/avatars/.../user_100.jpg",
    "bio": "...",
    "loc": "...",
    "age": 28
  },
  "account": {
    "id": 12345,
    "timezone": "Europe/Madrid",
    "type": "free"
  }
}
```

`account.type` is `free`, `pro`, or `vip`. Display it but do not gate features
on it; the app only uses free features.

### Search

`GET /search/all?q=<encoded>&extended=full&limit=30&page=1`.

Each result has `title`, `year`, `endpoint_type` (`movies`, `tv`, `anime`),
`poster`, `ids` (`simkl_id`, `slug`, `tmdb`), and, with `extended=full`, a
`ratings` block, `url`, `ep_count`, `status`, and `all_titles`. Search requires
the user token. A movie result uses `endpoint_type: "movies"`, not `"movie"`.

### Detail

`GET /movies/{id}`, `/tv/{id}`, `/anime/{id}`. The default response is complete.
Extract:

- `title`, `year`, `overview`, `genres`, `runtime`, `country`, `network`,
  `status`, `total_episodes`, `first_aired`, `last_aired`,
- `ratings` (`simkl`, `imdb`, `mal`),
- `poster`, `fanart`, `ids` (`simkl`, `slug`, `imdb`, `tmdb`, `tvdb`, `mal`),
- `users_recommendations` and `similar`.

`similar` is omitted entirely when empty. `users_recommendations` is an array of
mini media objects with `title`, `year`, `poster`, `fanart`, `type`, and `ids`.

### Writes

All writes are serialized per user, at most one POST per second, and batched
when several operations of the same kind are ready.

**Status only** — `/sync/add-to-list`:

```json
{
  "shows": [
    { "ids": { "simkl": 123 }, "to": "watching" }
  ]
}
```

Use `movies`, `shows`, and `anime` arrays. Movies accept only `plantowatch`,
`completed`, `dropped`. Inspect `added.<type>` and `not_found.<type>`; the server
may silently downgrade a status (for example, `completed` on an airing show to
`watching`). Read the resolved status from `added.<type>[i].to`.

**Watched event** — `/sync/history`:

Whole movie:

```json
{ "movies": [ { "ids": { "simkl": 123 } } ] }
```

Whole show (or anime):

```json
{ "shows": [ { "ids": { "simkl": 123 }, "status": "completed" } ] }
```

Next episode:

```json
{
  "shows": [
    {
      "ids": { "simkl": 123 },
      "seasons": [
        { "number": 2, "episodes": [ { "number": 5 } ] }
      ]
    }
  ]
}
```

Send anime under `shows[]` for history writes. The response includes
`added.episodes`, `added.statuses`, and `not_found`; inspect all three. Do not
chain a `/sync/add-to-list` call after a history write; the history call already
moves the item.

**Rating** — `/sync/ratings`:

```json
{
  "movies": [ { "ids": { "simkl": 123 }, "rating": 8 } ]
}
```

Ratings are 1–10. 0 and out-of-range values are silently ignored or land in
`not_found`; validate client-side and inspect `not_found`. Rating an untracked
item auto-files it.

**Remove rating** — `/sync/ratings/remove` with the same body minus `rating`.

**Remove from library** — `/sync/history/remove` with the same body shape as
history. A whole item removes watch history and the watchlist entry. Inspect
`deleted` and `not_found`; a `not_found` on an already-absent item may be treated
as success locally.

### Rate limits and errors

| Signal | Meaning | Response |
|---|---|---|
| `429 rate_limit` | Burst limit | Wait about 1 second, retry, slow down |
| `429 user_limit_exceeded` | Daily quota | Stop network, show reset time, keep cache |
| `400 RATE_LIMIT` | 20-second per-user write lock | Serialize and retry shortly; do not back off for minutes |
| `401 user_token_failed` | Token missing/invalid | Refresh once, retry; then sign out |
| `401 invalid_client` | Wrong client / V1 app | Stop, configuration error |
| `412 client_id_failed` | Missing/bad/suspended client | Stop, configuration error |
| `400 max_items` | Library too large for one call | Split by type, then status |
| `500/502/503` | Server error | Exponential backoff 1, 2, 4, 8, 16 s; give up after 5 |
| `400 id_err` / `not_found` | Item couldn't be resolved | Drop the write, trigger a type refresh |

Do not retry validation errors. For GETs, retry transient failures; for writes,
retry because all v1 writes are idempotent (status set, rating set, history add,
remove). Do not use `allow_rewatch`, so a repeated history write cannot create a
second watch session.

## 16. Sync

### Phase 1 — initial full sync

Per account, when there is no valid snapshot:

1. `GET /sync/activities` and keep the whole response as the candidate snapshot.
2. `GET /sync/all-items/shows?next_watch_info=yes&language=en`
3. `GET /sync/all-items/movies?language=en`
4. `GET /sync/all-items/anime?next_watch_info=yes&language=en`

Run these sequentially, never in parallel. Do not use `extended=full`; it adds
episode arrays that v1 does not need and can hit the episode limit. The default
response already includes status, counters, next-watch markers, title, year,
poster, IDs, and runtime.

If every pull succeeds:

- normalize the items and replace the local library,
- increment the generation,
- write `library.json`, then `state.json` with the new activities and matching
  generation,
- post a library-change notification.

If any pull fails, keep the old snapshot and report the error. Never save a
partial library.

If a call returns `400 max_items`, split it by type, then by status bucket
(`watching`, `plantowatch`, `completed`, `hold`, `dropped`; movies skip
`watching` and `hold`) and retry sequentially. If a bucket still fails, surface
"Your library is too large for one sync" and keep the old snapshot.

### Phase 2 — continuous sync

On launch, foreground, pull-to-refresh, and after the outbox drains:

1. `GET /sync/activities`.
2. If `current.all` equals the saved `activities.all`, stop.
3. Compare domains:
   - `tv_shows` ↔ `shows`
   - `movies` ↔ `movies`
   - `anime` ↔ `anime`
4. For each domain whose `all` moved:
   - `GET /sync/all-items/<type>?date_from=<saved top-level all>&next_watch_info=yes&language=en`
   - Replace items by `type:simklID`; update status, rating, counters, and next
     episode. A status move is represented by the item's current status, not by
     a separate removal marker.
5. For each domain whose `rated_at` moved:
   - `GET /sync/ratings/<type>?date_from=<saved top-level all>`
   - Merge `user_rating`; `null` clears the rating.
6. For each domain whose `removed_from_list` moved:
   - `GET /sync/all-items/<type>?extended=simkl_ids_only`
   - Diff against all local IDs of that type and remove missing items; clear
     their ratings and progress.
7. If `settings.all` moved:
   - `GET /users/settings`, update the profile, and save it.
8. Ignore `playback` and `custom_lists` changes in v1. The top-level `all` can
   move because of them; still process the domains that moved and save the new
   activities only after every needed fetch succeeds.

If every fetch succeeds:

- increment the generation,
- write the merged library, then the new activities with the same generation,
- update `lastSyncAt`.

If any fetch fails, keep the old activities and library. The next poll uses the
same `date_from` and picks up what was missed.

`date_from` is always the saved top-level `all`, passed exactly as returned,
including its formatting. For ratings fetches, omit a rating segment so removed
ratings come back as `user_rating: null`.

### Deletions

The deletion diff is the only way to see items removed from the library.
`date_from` does not surface removals. When `removed_from_list` moves, fetch the
ID-only list for that type, diff, and remove local items. Also clear any local
rating for removed items. If the ID-only fetch fails, do nothing and retry next
sync; never remove items on a guess.

### Ratings

Ratings are read on every `/sync/all-items` item as `user_rating`. A rating-only
change does not appear in the all-items delta; it appears when `rated_at` moves
and is fetched from `/sync/ratings`. `user_rating: null` means removed.

### Settings and profile

`/users/settings` is set-and-forget. Fetch it once after sign-in, then only when
`activities.settings.all` changes. Cache it in `state.json`. Do not poll it.

### Throttling and triggers

- No background sync and no polling timers.
- Automatic sync at most once every 15 minutes: launch, foreground, and
  pull-to-refresh. A manual pull still coalesces with an in-flight sync.
- After the outbox drains, run one delta sync, at most once per minute.
- If a sync is already running, set a `needsSync` flag and run once more when it
  finishes; do not start parallel syncs.
- Sync only when signed in. Public trending/detail requests do not require sync.

### Sync status

`MRSyncEngine` exposes `isSyncing`, `lastSyncAt`, `lastSyncError`, and
`pendingCount`. It posts `MRSyncStatusDidChangeNotification`. Library and For You
observe it to update the banner and footer.

## 17. Persistence and outbox

### Why files

The library is small enough to normalize into a single JSON document. File-backed
snapshots are simpler than Core Data, easier to inspect on a jailbroken device,
and avoid a schema/migration toolchain. Images and HTTP caches are separate and
disposable.

### Directory layout

```
Library/Application Support/Marquee/
  Accounts/<accountID>/
    state.json
    library.json
    outbox.json
    preferences.json
    recommendations.json
    diagnostics.json
Library/Caches/Marquee/
  Responses/<hash>.json
  Images/<hash>.jpg
```

`Application Support` is backed up and survives app updates. `Caches` is
disposable. Create the account directory after `/users/settings` returns the
account ID. Set `NSURLIsExcludedFromBackupKey` on the Caches directory.

### `state.json`

```json
{
  "schema": 1,
  "accountID": 12345,
  "generation": 7,
  "savedAt": "2026-11-04T12:34:56Z",
  "activities": { "...": "the full /sync/activities response" },
  "profile": { "...": "normalized /users/settings" },
  "lastSyncAt": "2026-11-04T12:30:00Z",
  "lastFullSyncAt": "2026-11-01T09:00:00Z"
}
```

### `library.json`

```json
{
  "schema": 1,
  "accountID": 12345,
  "generation": 7,
  "savedAt": "2026-11-04T12:34:56Z",
  "items": [
    {
      "simklID": 250822,
      "type": "movie",
      "slug": "interstellar",
      "title": "Interstellar",
      "year": 2014,
      "poster": "20/2052598c2716ef054",
      "fanart": "15/15255183c8d12b92a6",
      "genres": ["Science Fiction", "Drama"],
      "runtime": 169,
      "ratings": { "simkl": 8.6, "imdb": 8.7 },
      "ids": { "imdb": "tt0816692", "tmdb": "157336" },
      "watchStatus": "completed",
      "userRating": 9,
      "lastWatchedAt": "2026-10-20T20:00:00Z",
      "watchedEpisodesCount": 0,
      "totalEpisodes": 0,
      "nextEpisode": null,
      "detailFetchedAt": "2026-11-02T10:00:00Z"
    }
  ]
}
```

Dates are ISO strings on disk and `NSDate` in memory. Unknown keys are ignored.
Missing fields get safe defaults. Only Foundation collection types are used; no
`NSCoding` custom archives.

### Generations and atomicity

`library.json` and `state.json` share a `generation` integer. Write the library
first, then the state, each with `NSDataWritingAtomic`. If the app crashes between
them, the generations differ on load. A mismatch means the snapshot is not
trustworthy: discard it and run phase 1. The outbox is independent and is never
discarded because of a generation mismatch.

Do not save a snapshot until every fetch in that phase has succeeded.

### `outbox.json`

```json
{
  "schema": 1,
  "accountID": 12345,
  "entries": [
    {
      "id": "UUID",
      "createdAt": "2026-11-04T12:40:00Z",
      "kind": "status",
      "type": "show",
      "simklID": 123,
      "title": "The Bear",
      "year": 2022,
      "ids": { "simkl": 123 },
      "status": "watching",
      "rating": null,
      "season": null,
      "episode": null,
      "previousStatus": "plantowatch",
      "previousRating": null,
      "attempts": 0
    }
  ]
}
```

Kinds: `status`, `historyWhole`, `historyEpisode`, `rating`, `ratingRemove`,
`remove`.

Rules:

- Enqueue before sending. Save atomically.
- Drain in FIFO order. At each step, batch up to 20 consecutive entries of the
  same kind that target different items into one request. Never reorder entries
  for the same item. Wait at least 1.1 seconds between POSTs.
- Flush the outbox before a sync. If a write fails transiently, keep the entry,
  stop the flush, and show "N changes waiting to sync". Do not run a sync that
  could overwrite pending local state.
- All v1 writes are idempotent. A crash after the server applies a write but
  before the outbox entry is removed is safe; the retry is a no-op.
- On a permanent failure (`not_found`, `id_err`), drop the entry, show a short
  alert, and trigger a full refresh of that type so local state matches SimKL.
- Coalesce:
  - a newer status for the same item replaces an older pending status,
  - a newer rating replaces an older pending rating,
  - `remove` cancels pending status/history/rating for that item,
  - a whole-item history write cancels pending status writes for that item,
  - duplicate history episodes are dropped.
- On sign-out, keep the outbox for that account. On sign-in to the same account,
  resume it. Never flush another account's outbox.

### `preferences.json`

```json
{
  "schema": 1,
  "accountID": 12345,
  "manualGenres": [
    { "type": "movies", "name": "Science Fiction", "slug": "science-fiction" }
  ],
  "hidden": [
    { "type": "movie", "simklID": 123, "title": "Example", "year": 2014, "poster": "..." }
  ],
  "searchHistory": ["dune", "the bear"]
}
```

Search history is capped at 8, deduplicated case-insensitively. Hidden items are
capped at 200.

### `recommendations.json`

```json
{
  "schema": 1,
  "accountID": 12345,
  "generatedAt": "2026-11-04T12:45:00Z",
  "fingerprint": "…",
  "sections": [
    {
      "kind": "hero",
      "reason": "Because you watched Interstellar",
      "item": { "…": "MRMediaItem snapshot" }
    },
    {
      "kind": "row",
      "title": "Because You Watched Interstellar",
      "reason": "Because you watched Interstellar",
      "source": "seed",
      "items": [ { "…": "MRMediaItem snapshot" } ]
    }
  ]
}
```

Items are stored as snapshots so For You renders offline. On load, verify the
account and schema; otherwise regenerate.

### Recommendations fingerprint

`fingerprint = library.generation + trending.cacheDate + genre.cacheDates +
manualGenres + hidden.count`. If the fingerprint matches and `generatedAt` is
under 6 hours old, skip regeneration. A manual refresh bypasses the age check
but still recomposes once.

### Migrations

V1 has schema 1. If a future schema is newer than the app, discard caches and
recommendations, keep the outbox, and run a full sync. Do not silently migrate
unknown formats.

## 18. Networking and caching

### Request operation

`NSURLSession` does not exist on iOS 6. Use `MRAPIRequestOperation`, an
`NSOperation` subclass that drives `NSURLConnection` on its own run loop:

- create the connection with `startImmediately:NO`,
- schedule it in the operation's current run loop,
- start it,
- run the run loop until the connection finishes or the operation is cancelled,
- collect data in `didReceiveData`, parse JSON on the operation thread,
- call the completion on the main queue.

This gives cancellation, serialization, and predictable threading, which
`sendAsynchronousRequest:queue:` does not.

Two queues:

- `apiQueue`: max 1. User-scoped calls: settings, activities, sync, search,
  writes.
- `catalogQueue`: max 2. Public detail, trending, genre, and image metadata.
  These are cached/free; two is still modest.

Writes have their own serial gate and a minimum 1.1 second gap between POSTs.
Never run a write concurrently with another write for the same user.

### Error mapping

`MRErrorKind`: `offline`, `authExpired`, `clientRejected`, `rateLimitedBurst`,
`dailyLimit`, `writeLocked`, `notFound`, `tooLarge`, `server`, `parse`,
`cancelled`, `unknown`.

Map:

- `NSURLErrorNotConnectedToInternet`, `CannotFindHost`, `TimedOut`,
  `NetworkConnectionLost` → `offline`.
- HTTP 401 `user_token_failed` → refresh once, then `authExpired`.
- HTTP 401 `invalid_client` or 412 `client_id_failed` → `clientRejected`.
- HTTP 429 `rate_limit` → `rateLimitedBurst`.
- HTTP 429 `user_limit_exceeded` → `dailyLimit`.
- HTTP 400 `RATE_LIMIT` → `writeLocked`.
- HTTP 400 `max_items` → `tooLarge`.
- HTTP 400 `id_err`, 404 → `notFound`.
- HTTP 500/502/503 → `server`.
- JSON parse failure → `parse`.

### Retry policy

| Error | Retry? | Wait |
|---|---|---|
| offline | No; wait for connectivity | — |
| authExpired | Refresh once | — |
| clientRejected | No | — |
| rateLimitedBurst | Yes, up to 2 | ~1 s |
| dailyLimit | No; show reset | until `Retry-After` |
| writeLocked | Yes, up to 3 | 2 s, 4 s, 8 s |
| notFound | No; drop write | — |
| tooLarge | Split and retry | — |
| server | Yes, up to 5 | 1, 2, 4, 8, 16 s |
| parse | No | — |

Do not treat `400 RATE_LIMIT` as a daily quota error. It is a short per-user
write lock; backing off for minutes makes the app slower for no reason.

### HTTP cache

`MRResponseCache` stores JSON responses on disk:

```json
{
  "url": "…",
  "fetchedAt": "2026-11-04T12:00:00Z",
  "lastModified": "Wed, 04 Nov 2026 11:55:00 GMT",
  "status": 200,
  "body": { "…": "parsed JSON" }
}
```

- Filenames use a small deterministic FNV-1a hash of the URL; store and verify
  the URL inside the file.
- Callers pass a max age. Trending and genre: 24 hours. Detail: 24 hours.
  Search: memory only, 10 minutes.
- For public files, send `If-Modified-Since` when a `Last-Modified` is stored. On
  304, update `fetchedAt` and reuse the body.
- Cache size cap 50 MB. Prune oldest by `fetchedAt` on launch and when over the
  cap.
- Do not cache auth endpoints, user settings (use `state.json`), or writes.

### Image cache

`MRImageCache` is adapted from Matinee's `MTImageCache`:

- memory `NSCache`, count limit 200, total cost limit 50 MB,
- disk cache in `Library/Caches/Marquee/Images`, 100 MB cap, LRU by
  modification date,
- `NSOperationQueue` max 4,
- cancel the previous request when a card is reused; use a generation token to
  ignore stale completions,
- decode with `UIImage imageWithData:`,
- on memory warning, clear the memory cache only,
- placeholder: a gray field with a film-frame glyph drawn in code.

### Quota tracker

`MRQuotaTracker` stores the last `X-RateLimit-Limit` and
`X-RateLimit-Remaining` per account, plus a `quotaResetAt` when a daily 429
includes `Retry-After`. It posts a notification when the value changes. The
Library/For You banner reads it; Diagnostics shows the full value. It never
fabricates a remaining count when headers are absent.

### Diagnostics log

A 50-entry ring buffer of API errors: timestamp, method, path (without query
values that contain tokens; `client_id` is public and may remain), status,
SimKL `error` code, and a short message. Never log access tokens, refresh
tokens, device codes, or Authorization headers. Persist to `diagnostics.json`.
"Copy Diagnostics" produces a plain-text report for device debugging.

## 19. App structure

### Source layout

Theos-only project at the workspace root:

```
Makefile
control
Marquee/
  main.m
  MRAppDelegate.h/m
  MRAppearance.h/m
  MRRootTabBarController.h/m
  MRConnectViewController.h/m
  MRForYouViewController.h/m
  MRLibraryViewController.h/m
  MRSearchViewController.h/m
  MRProfileViewController.h/m
  MRDetailViewController.h/m
  MRGenrePickerViewController.h/m
  MRDiagnosticsViewController.h/m
  MRPosterCardView.h/m
  MRPosterImageView.h/m
  MRHeroView.h/m
  MRRowHeaderView.h/m
  MRStatusChipsView.h/m
  MRStarRatingView.h/m
  MRStatusPillView.h/m
  MRBannerView.h/m
  MRToastView.h/m
  MRPlaceholderView.h/m
  MRProgressBar.h/m
  MRMediaItem.h/m
  MRWatchStatus.h
  MRRecommendation.h/m
  MRTasteProfile.h/m
  MRAPIClient.h/m
  MRAPIRequestOperation.h/m
  MRSimklAuth.h/m
  MRKeychain.h/m
  MRSyncEngine.h/m
  MRLibraryStore.h/m
  MRRecommendationEngine.h/m
  MRResponseCache.h/m
  MRImageCache.h/m
  MROutbox.h/m
  MRQuotaTracker.h/m
  MRDiagnostics.h/m
  MRURLBuilder.h/m
  MRJSON.h/m
  MRDate.h/m
  MRLog.h/m
  MRConfig.h
  Resources/
    Info.plist
    Icon.png
    Icon@2x.png
    Icon-72.png
    Icon-72@2x.png
    Default.png
    Default@2x.png
    Default-568h@2x.png
    SimklBadge.png
tests/
  fixtures/
  run_tests.sh
docs/
  superpowers/specs/2026-11-04-marquee-design.md
```

Flat source files keep the Theos wildcard simple, matching Matinee's approach.

### Key classes

- `MRAppDelegate` — window, tab bar, account bootstrap, lifecycle triggers.
- `MRAppearance` — colors, fonts, gradients, tab icons, bars, cards, buttons.
- `MRRootTabBarController` — optional thin subclass for tab setup and selected
  tab persistence; `UITabBarController` is enough.
- `MRConnectViewController` — device-flow UI and retry/expiry states.
- `MRForYouViewController` — table of hero and rows; pull-to-refresh; banners.
- `MRLibraryViewController` — type/status filters, table, refresh.
- `MRSearchViewController` — search bar, debounce, results, pagination.
- `MRProfileViewController` — settings cards, sync, genre picker, sign out.
- `MRDetailViewController` — metadata, actions, similar rows.
- `MRAPIRequestOperation` — cancellable `NSURLConnection` operation.
- `MRAPIClient` — URL building, auth headers, JSON parsing, error mapping,
  retries, quota tracking.
- `MRSimklAuth` — device flow, token refresh, Keychain, account identity.
- `MRSyncEngine` — phase 1/2 sync, delta merge, deletions, ratings, throttling.
- `MRLibraryStore` — in-memory snapshot, normalization, atomic persistence,
  notifications.
- `MRRecommendationEngine` — taste profile, candidate fetch, scoring, rows,
  cache.
- `MROutbox` — persistent writes, batching, retry, coalescing.
- `MRResponseCache` / `MRImageCache` — disk/memory caches.
- `MRQuotaTracker` / `MRDiagnostics` — API citizenship and device debugging.
- `MRURLBuilder` / `MRJSON` / `MRDate` — pure helpers, testable on macOS.

### Threading

- UI and model mutations on the main thread.
- Network operations on the two operation queues; callbacks return to main.
- Disk writes on a serial `ioQueue`; snapshots are immutable values passed to the
  writer.
- Recommendation generation on a background queue using a snapshot; publish the
  result on main.
- `MRLibraryStore` posts `MRLibraryDidChangeNotification`.
- `MRSyncEngine` posts `MRSyncStatusDidChangeNotification`.
- `MRRecommendationEngine` posts `MRRecommendationsDidChangeNotification`.
- `MROutbox` posts `MROutboxDidChangeNotification`.
- `MRSimklAuth` posts `MRAuthDidChangeNotification`.

### Lifecycle

`application:didFinishLaunchingWithOptions:`:

1. Register defaults.
2. Create the window and four tabs immediately.
3. Load the Keychain session. If present, load the account snapshot and render
   cached data; start a sync in the background.
4. If absent, render signed-out states.
5. Never block launch on the network.

`applicationDidBecomeActive:`:

- If the connect screen is open, poll immediately.
- If signed in, flush the outbox if needed; trigger a sync if last sync is over
  15 minutes old; recompose For You if its cache is over 6 hours old; refresh
  visible banners.

`applicationDidEnterBackground:`:

- Save pending state; stop timers and nonessential requests. The outbox is
  already persisted per operation, so a kill cannot lose user intent.

No background fetch, no background timers, no silent polling.

### Config

`MRConfig.h`:

```objc
#define MR_SIMKL_CLIENT_ID @"REPLACE_WITH_V2_CLIENT_ID"
#define MR_APP_NAME @"marquee"
#define MR_APP_VERSION @"1.0"
#define MR_USER_AGENT @"Marquee/1.0 (iOS 6)"
#define MR_API_BASE @"https://api.simkl.com"
#define MR_DATA_BASE @"https://data.simkl.in"
```

If the client ID is still the placeholder, the connect screen and Diagnostics
show a clear "SimKL client ID not configured" message. Do not crash and do not
attempt auth.

## 20. Build and packaging

### Theos Makefile

At the workspace root:

```make
TARGET := iphone:clang:11.4:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Marquee
Marquee_FILES = $(wildcard Marquee/*.m)
Marquee_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security SystemConfiguration
Marquee_CFLAGS = -fobjc-arc -mno-thumb -Wno-error=deprecated-module-dot-map
Marquee_CODESIGN_FLAGS = -S
Marquee_INSTALL_PATH = /Applications
Marquee_RESOURCE_FILES = \
  Marquee/Resources/Info.plist \
  Marquee/Resources/Icon.png \
  Marquee/Resources/Icon@2x.png \
  Marquee/Resources/Icon-72.png \
  Marquee/Resources/Icon-72@2x.png \
  Marquee/Resources/Default.png \
  Marquee/Resources/Default@2x.png \
  Marquee/Resources/Default-568h@2x.png \
  Marquee/Resources/SimklBadge.png

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 Marquee || true"
```

If the 6.1 SDK becomes available, build with
`TARGET=iphone:clang:6.1:6.0`; otherwise the 11.4 SDK + 6.0 target is the
supported local build.

### `control`

```
Package: com.marquee.app
Name: Marquee
Version: 1.0
Architecture: iphoneos-arm
Description: An iOS 6 SimKL client with a recommendations-first home.
Homepage: https://github.com/kerthmfy/Marquee-ios6
Maintainer: Kerth Michael Fernandez Yadao <yadaokerthmichael@gmail.com>
Author: Kerth Michael Fernandez Yadao <yadaokerthmichael@gmail.com>
Section: Entertainment
Depends: firmware (>= 6.0)
```

The homepage is a placeholder until a repository exists.

### `Info.plist`

Required keys:

- `CFBundleDisplayName` Marquee
- `CFBundleExecutable` Marquee
- `CFBundleIdentifier` com.marquee.app
- `CFBundleName` Marquee
- `CFBundlePackageType` APPL
- `CFBundleShortVersionString` 1.0
- `CFBundleVersion` 1
- `CFBundleIconFiles` Icon, Icon@2x, Icon-72, Icon-72@2x
- `LSRequiresIPhoneOS` true
- `MinimumOSVersion` 6.0
- `UIRequiredDeviceCapabilities` armv7
- `UISupportedInterfaceOrientations` portrait only
- `UIStatusBarStyle` UIStatusBarStyleBlackOpaque

No `NSMainNibFile`, no storyboard keys, no ATS keys (iOS 6 has no ATS).

### Build

```bash
export THEOS=$HOME/theos
cd "/Users/kerthfyadao/Documents/ios 6 to do"
make clean package FINALPACKAGE=1
ls packages/
```

### Verify the binary

```bash
otool -l .theos/obj/Marquee.app/Marquee | grep -A3 LC_VERSION_MIN_IPHONEOS
otool -L .theos/obj/Marquee.app/Marquee
ldid -S .theos/obj/Marquee.app/Marquee
```

The version min must be 6.0. The linked frameworks should be UIKit, Foundation,
CoreGraphics, QuartzCore, Security, and SystemConfiguration only.

### Install

```bash
scp packages/com.marquee.app_1.0_iphoneos-arm.deb root@DEVICE_IP:/tmp/
ssh root@DEVICE_IP 'dpkg -i /tmp/com.marquee.app_1.0_iphoneos-arm.deb && killall -9 SpringBoard'
```

`dpkg-deb` may not exist on the Mac; `ar` + `tar` can inspect the package.

### iOS 6 API audit

Run a grep over `Marquee/` and fail the build if any of these appear:

```
NSURLSession
UIAlertController
UIStackView
UIVisualEffectView
SFSafariViewController
ASWebAuthenticationSession
WKWebView
UIFeedbackGenerator
NSLayoutAnchor
NSProgress
```

Use `UIAlertView`/`UIActionSheet`, manual frames/autoresizing, `UIWebView` only
if absolutely necessary (prefer no web view), `UIApplication openURL:`,
`NSURLConnection`, and custom progress views.

Also avoid:

- `UIFieldBehavior`, `UIMotionEffect` (iOS 7),
- `NSURLComponents` (iOS 7),
- `NSFileManager` newer error-handling APIs not present on iOS 6,
- `NSJSONWritingWithoutEscapingSlashes` (newer),
- `UITableViewRowAction` (iOS 8),
- `UIAlertController` in any form.

### Implementation order (for the build walkthrough)

The user wants to see the app take shape. Build in this order, with a visible
checkpoint at each step:

1. **Shell**: Theos scaffold, Info.plist, placeholder assets, `MRAppearance`,
   four tabs, empty screens. Build and install. Confirm the tab bar and
   navigation bar match Matinee.
2. **Public For You**: trending fetch, hero, poster cards, image cache. Still
   signed out. This proves the first page early.
3. **Auth**: connect screen, device flow, Keychain, token refresh. Sign in and
   show the profile header.
4. **Read-only sync**: phase 1, library snapshot, Library tab, counts.
5. **Detail**: public detail fetch, metadata, similar/recommendation rows, View
   on Simkl.
6. **Writes**: outbox, status, rating, whole-item watch, next-episode watch,
   remove.
7. **Personalized For You**: taste profile, genre enrichment, seed rows, genre
   rows, watchlist, hidden titles, genre picker.
8. **Search**: debounce, pagination, recent searches.
9. **Phase 2 sync**: deltas, deletions, ratings, settings, throttling.
10. **Polish and verification**: offline states, quota banner, diagnostics,
    device checklist, binary audit.

At each checkpoint: build, install, and describe what changed on screen.

## 21. Failure states

| Situation | What the user sees | What the app does |
|---|---|---|
| Signed out | Connect hero + public trending | Public reads; Library/Search/Profile connect cards |
| Device flow pending | Code, spinner, "Open simkl.com/pin" | Poll every interval; `slow_down` adds 5 s; 15 min deadline |
| Device flow expired | "Code expired" + Try Again | Stop polling; clear code |
| `invalid_client` | "Marquee isn't configured for SimKL" | Stop; point to Diagnostics |
| Token expired, refresh works | No interruption | Refresh before request; retry once |
| Refresh fails | "Session expired. Reconnect." | Clear tokens; keep local data |
| Offline, cache exists | Cached For You/Library + amber banner | Reads from cache; writes queue |
| Offline, no cache | Error card + Retry | No data; connect if signed out |
| Initial sync fails midway | Old snapshot + error banner | Never save partial; retry |
| Delta sync fails | Old snapshot + "Couldn't refresh" | Keep old activities; retry same date_from |
| Deletion diff fails | Old items + banner | Retry next sync; never guess |
| Write pending | Pending dot/banner | Persist outbox; flush before sync |
| Write `not_found` | "Simkl couldn't match this title" | Drop op; refresh that type |
| Write `400 RATE_LIMIT` | "Simkl is still saving your last change" | Retry 2/4/8 s; do not back off for minutes |
| Burst 429 | "Too many requests; retrying" | Retry ~1 s; slow down |
| Daily 429 | "Daily limit reached; resets in 6h 12m" | Stop network; cached browsing; writes queue |
| 500/502/503 | "Simkl is having trouble" | Backoff up to 5 attempts; keep cache |
| 401 on request | No UI unless refresh fails | Refresh once; then sign out |
| 412 client rejected | "SimKL client ID rejected" | Stop; Diagnostics |
| `400 max_items` | "Library too large for one sync" | Split by type/status; retry |
| Corrupt snapshot | "Repairing your library" | Discard snapshot; phase 1; keep outbox |
| Low disk | "Storage almost full" | Stop image cache growth; keep snapshots/outbox |
| Memory warning | No UI | Clear image memory cache |
| Backgrounded during connect | — | Stop timer; poll on foreground; deadline still applies |
| Killed during write | — | Outbox persists; retry idempotent write |
| Sign out with pending writes | "N changes haven't synced" | Sign out; keep outbox for that account |
| Account switch | New account | Use a different directory; never cross-flush |

## 22. Testing and verification

### Pure logic tests

Keep URL building, JSON normalization, date parsing, scoring, row selection, and
outbox coalescing in Foundation-only classes. Add a macOS command-line test
harness in `tests/` with fixtures from the SimKL docs:

- `activities.json`
- `sync-all-items.json`
- `ratings.json`
- `search.json`
- `movie-detail.json`
- `trending.json`
- `genre-index.json`
- `device-flow.json`
- `token.json`
- write responses with `added` and `not_found`

Run:

```bash
clang -fobjc-arc -framework Foundation tests/*.m Marquee/MRMediaItem.m ... -o /tmp/marquee-tests
/tmp/marquee-tests
```

The exact file list is for the plan. Tests cover:

- `simkl` vs `simkl_id` normalization,
- type/status mapping,
- missing/null fields,
- date parsing with and without fractional seconds,
- taste profile weights and negative dropped signals,
- row selection with duplicate filtering and hidden items,
- outbox coalescing and FIFO rules,
- URL encoding of search queries,
- error-body mapping.

### Write tests on the main account

Device write tests use the user's main SimKL account with sacrificial titles.

- Before the first write, save the current library snapshot and record the
  simkl.com counts for watchlist, completed, watching, ratings, and history.
- Choose one sacrificial movie and one sacrificial show that are confirmed
  absent from the account's library and watch history. Record their SimKL IDs
  in the test run notes.
- Only those IDs may receive destructive write tests. Never issue a remove,
  status change, or rating to a title that existed in the library before the
  test.
- Exercise add-to-watchlist, start watching, next-episode watched, mark all
  watched, set rating, clear rating, change status, and remove on the
  sacrificial titles. After each batch, verify the result on simkl.com.
- Clean up by removing both titles from the library and history and clearing
  their ratings. Run a sync and confirm the counts and watchlist match the
  recorded baseline.
- If a real item is touched by mistake, stop the test, correct it on simkl.com,
  resync, and record what happened before continuing.
- If the permanent library is too thin to produce personalized rows after
  cleanup, accept the cold-start and manual-genre behavior rather than leaving
  test history behind.
- Write-test acceptance is complete only when the sacrificial titles are gone
  and the account is back at baseline.

### Device checklist

1. Fresh install; launch signed out; public trending loads; connect hero shows.
2. Connect: code appears; open Safari with the complete URL; approve; return;
   profile loads; initial sync completes.
3. Counts in Profile match simkl.com.
4. For You: hero, Continue Watching, seed row, genre row, watchlist, trending.
   No duplicates. Trending title names Simkl. Posters load.
5. Library: type and status filters; counts; pull-to-refresh; next-episode line.
6. Detail: use the sacrificial titles from the write-test setup. Add to
   watchlist; start watching; mark next episode; mark all; rate; clear rating;
   change status; remove. Recheck on simkl.com, then restore the baseline.
7. Search: debounce, results, pagination, recent searches, no matches.
8. Offline: airplane mode; relaunch; cached For You/Library; queue a status
   change; reconnect; outbox flushes; server state matches.
9. Quota: in a debug build, use `?debug_limit=user` to verify the daily banner
   and reset time. Do not ship the debug flag.
10. Token refresh: unit-test the refresh path with a stub; do not wait 7 days.
11. Memory: scroll For You and Library repeatedly on the target device; no
    crash; image memory stays bounded.
12. Binary audit: `otool`, `ldid`, banned-API grep.
13. Reinstall over the existing app; library, outbox, and preferences persist.
14. Kill the app during a sync; relaunch; no partial snapshot; sync retries.
15. Sign out and back in; outbox resumes only for the same account.

### Manual API checks

Before shipping, use curl or a scratch build to confirm:

- `/oauth2/device` returns the expected fields with the registered client ID.
- `/oauth2/token` polling returns `authorization_pending` then tokens.
- `next_watch_info=yes` returns `next_to_watch_info` without `extended=full` on
  the initial sync. If it does not, fetch the `watching` bucket with
  `extended=full` and document the fallback.
- `/sync/all-items` delta with `date_from` returns only changed items.
- `/sync/all-items/<type>?extended=simkl_ids_only` returns IDs for the deletion
  diff.
- One status, history, rating, and remove write each return the expected
  `added`/`not_found` envelope for a test item.
- A trending file and a genre file return 200 with the expected keys, and a
  repeat request with `If-Modified-Since` returns 304.

## 23. What is left to the builder

- Choose exact class names and split files within the proposed structure.
- Tune the scoring constants against the real library, keeping the sources and
  exclusions fixed.
- Decide exact hero/card dimensions within the stated ranges.
- Implement the outbox batching/coalescing details and the retry state machine.
- Implement the genre index merge and picker UI.
- Implement the diagnostics self-test and copy report.
- Generate the placeholder icon/launch images (no logo work).
- Register the SimKL V2 client ID and paste it into `MRConfig.h` (user action).
- Build, install, and test on the device; adjust for iOS 6 quirks.
- Write the implementation plan with `writing-plans` after this design is
  approved.

## 24. Decisions made in this document, for approval

These are the calls the user should check while reading:

1. **Four tabs**: For You, Library, Search, Profile.
2. **Device flow only**, registered as "TV, devices & command line" (no redirect
   URI, no secret). No PKCE in v1.
3. **For You recipe**: hero, Continue Watching, Because You Watched, Because You
   Like, From Your Watchlist, Simkl Trending This Week; no duplicate items.
4. **Writes in v1**: status, rating, whole-item watched, next-episode watched,
   remove. No episode browser, scrobbling, rewatches, or custom lists.
5. **File-backed JSON snapshots**, not Core Data/SQLite.
6. **Two-phase sync** with activities gating, deltas, deletion diffs, and rating
   deltas. No background timers.
7. **Persistent outbox** for writes, flushed before sync, idempotent retries.
8. **iPhone portrait only**; iPad compatibility mode.
9. **Matinee chrome reused**, but no shared code and no Matinee feature.
10. **Logo remains parked**; temporary icon/launch image only.
11. **No relay, no analytics, no third-party SDKs.**
12. **SimKL badge bundled** for attribution; per-item "View on Simkl" links.

## 25. User actions and dependencies

- Register a V2 app at `https://simkl.com/settings/developer/`:
  - client type "TV, devices & command line",
  - name Marquee,
  - copy the `client_id` into `Marquee/MRConfig.h`.
- Have the device IP and SSH access ready for install.
- For write testing, pick one sacrificial movie and one sacrificial show that
  are not in the main account's library or history. These will be removed and
  the account restored to baseline after testing.
- Approve this design, or change the decisions in §24 before implementation.
- The logo/icon remains parked; a placeholder will be used until the user asks
  to resume that work.
