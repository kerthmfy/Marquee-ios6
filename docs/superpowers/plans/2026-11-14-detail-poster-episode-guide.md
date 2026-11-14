# Detail Poster and Episode Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a portrait poster/key-facts panel, an episode guide, and shared poster edges to Marquee's detail screens.

**Architecture:** Keep the existing `MRDetailViewController` card stack and insert two focused card views: `MRDetailPosterPanelView` and `MRDetailEpisodeGuideView`. Normalize Simkl episode JSON with a pure `MREpisode` model, fetch episodes through `MRAPIClient`, and share one poster-edge helper in `MRAppearance`.

**Tech Stack:** Objective-C/ARC, UIKit/CoreGraphics/QuartzCore, iOS 6.0, Theos.

**Spec:** `docs/superpowers/specs/2026-11-14-detail-poster-episode-guide-design.md`

## Global Constraints

- Objective-C/ARC only; no Swift, CocoaPods, SPM, third-party libraries, storyboards, or nibs.
- iOS 6.0 minimum; iPhone portrait; iPad portrait and landscape through `MRLayout`.
- Read-only detail additions; no new write actions.
- Keep the existing iOS 6 chrome and card stack.
- Do not apply the poster edge treatment to the full-bleed hero.
- Do not push `.superpowers/` or `docs/lessons/`.

## Review Focus

- Episode dates from Simkl include timezone offsets; they must display as the
  intended calendar day, not nil or a day earlier.
- Anime episodes can omit `season` and `img`; they must still appear in season
  1 with a clean still placeholder.
- Very long anime seasons must not create hundreds of rows at once.
- Detail must remain usable when the episode request fails or returns nothing.
- Poster edges must not clip progress bars or distort the hero.

---

### Task 1: Episode model

**Files:**
- Create: `Marquee/MREpisode.h`, `Marquee/MREpisode.m`
- Modify: `tests/run_tests.sh`, `tests/main.m`
- Test: `tests/MREpisodeTests.m`

**Interfaces:**
- Produces:
  - `@interface MREpisode : NSObject`
  - `@property NSInteger season; @property NSInteger number;`
  - `@property NSString *title; @property NSString *summary;`
  - `@property NSInteger runtime; @property NSString *imagePath;`
  - `@property NSDate *airDate; @property BOOL special; @property BOOL aired;`
  - `+ (instancetype)episodeWithDictionary:(NSDictionary *)dictionary type:(MRMediaType)type;`
  - `+ (NSArray *)episodesWithDictionaries:(NSArray *)dictionaries type:(MRMediaType)type;`
  - `- (NSString *)codeText;`

- [ ] **Step 1: Write failing tests**

Cover: full TV parse; anime missing season defaults 1 and missing image is nil;
offset date `2011-04-17T21:00:00-04:00` parses to 17 Apr 2011 UTC; specials sort
after regular seasons; `codeText` returns `S1E2`, `E2`, and `Special 3`; invalid
entries are skipped.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: compile failure for missing `MREpisode`.

- [ ] **Step 3: Implement `MREpisode`**

Parse `season`, `episode`, `title`, `description`, `runtime`, `img`, `date`,
`aired`, and `type`. Treat missing season as 1 for anime and 0 for shows;
`special = [type isEqual:@"special"] || season == 0`. Parse the first ten
`yyyy-MM-dd` characters in UTC. Sort regular seasons ascending, specials last,
then episode number.

- [ ] **Step 4: Register tests and run**

Add `Marquee/MREpisode.m` to `tests/run_tests.sh`, add
`MRRunEpisodeTests` to `tests/main.m`.
Run: `./tests/run_tests.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add Marquee/MREpisode.h Marquee/MREpisode.m tests/MREpisodeTests.m tests/main.m tests/run_tests.sh
git commit -m "feat: add episode model"
```

---

### Task 2: Episode URL and API fetch

**Files:**
- Modify: `Marquee/MRURLBuilder.h`, `Marquee/MRURLBuilder.m`
- Modify: `Marquee/MRAPIClient.h`, `Marquee/MRAPIClient.m`
- Test: `tests/MRURLBuilderTests.m`, `tests/MRAPIClientPublicTests.m`

**Interfaces:**
- Produces:
  - `+ (NSString *)episodeURLForPath:(NSString *)path size:(NSString *)size;`
  - `- (id<MRHTTPTask>)fetchEpisodesForType:(MRMediaType)type simklID:(NSInteger)simklID completion:(void (^)(NSArray *json, NSError *error))completion;`

- [ ] **Step 1: Write failing tests**

Assert the episode image URL is
`https://wsrv.nl/?url=https://simkl.in/episodes/31/318121421ca3e9c34_m.webp&output=jpg&q=90`.
Assert show and anime fetches request
`https://api.simkl.com/tv/episodes/17465?client_id=...` and
`https://api.simkl.com/anime/episodes/39793?client_id=...`, return the parsed
array, and send no Authorization header. Assert a movie returns not-found
without an HTTP request.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: compile failure for the missing methods.

- [ ] **Step 3: Implement**

Build episode images from `https://simkl.in/episodes/` through the existing
JPEG proxy. In `MRAPIClient`, use
`[NSString stringWithFormat:@"%@/episodes/%ld", MRMediaTypeAPIPath(type), (long)simklID]`
and `fetchURL:expectedClass:[NSArray class]`; reject movies and non-positive
IDs on the main queue with `MRErrorKindNotFound`.

- [ ] **Step 4: Run tests**

Run: `./tests/run_tests.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add Marquee/MRURLBuilder.h Marquee/MRURLBuilder.m Marquee/MRAPIClient.h Marquee/MRAPIClient.m tests/MRURLBuilderTests.m tests/MRAPIClientPublicTests.m
git commit -m "feat: fetch episode lists from Simkl"
```

---

### Task 3: Detail facts and poster edge helper

**Files:**
- Modify: `Marquee/MRMediaItem.h`, `Marquee/MRMediaItem.m`
- Modify: `Marquee/MRAppearance.h`, `Marquee/MRAppearance.m`
- Modify: `Marquee/MRPosterCardView.m`, `Marquee/MRLibraryViewController.m`,
  `Marquee/MRSearchViewController.m`, `Marquee/MRHiddenTitlesViewController.m`
- Test: `tests/MRMediaItemTests.m`

**Interfaces:**
- Produces:
  - `@property NSString *certification; @property NSString *director;` on `MRMediaItem`.
  - `+ (void)stylePosterThumbnailView:(UIView *)view;` on `MRAppearance`.

- [ ] **Step 1: Write failing tests**

Extend the detail fixture test to assert `certification` and `director` parse,
survive `itemByMergingDetailDictionary:`, and round-trip through
`dictionaryRepresentation`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: assertions fail for missing fields.

- [ ] **Step 3: Implement**

Add both fields to detail parsing, merge, dictionary round-trip, and copy. Add
the helper: 4 pt radius, masks to bounds, 0.5 pt border with
`[UIColor colorWithWhite:0.0 alpha:0.18]`. Replace the three manual 3 pt
corners in Library/Search/Hidden Titles and the poster card with the helper.

- [ ] **Step 4: Run tests**

Run: `./tests/run_tests.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add Marquee/MRMediaItem.h Marquee/MRMediaItem.m Marquee/MRAppearance.h Marquee/MRAppearance.m Marquee/MRPosterCardView.m Marquee/MRLibraryViewController.m Marquee/MRSearchViewController.m Marquee/MRHiddenTitlesViewController.m tests/MRMediaItemTests.m
git commit -m "feat: add detail facts and poster edges"
```

---

### Task 4: Poster/key-facts panel

**Files:**
- Create: `Marquee/MRDetailPosterPanelView.h`, `Marquee/MRDetailPosterPanelView.m`

**Interfaces:**
- Produces:
  - `- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache;`
  - `- (CGFloat)heightForWidth:(CGFloat)width;`

- [ ] **Step 1: Build the card**

Style the panel with `[MRAppearance styleCardView:self first:YES last:YES]`.
Show an 86x129 pt poster on iPhone and 120x180 on iPad using
`MRPosterImageView` plus `stylePosterThumbnailView:`. Right column: bold
`★ rating · runtime · certification`; then compact lines for director (movies),
network (shows/anime), year, country, episode count, and genres. Hide the poster
column when no poster exists; return 0 height only when there is no poster and
no facts.

- [ ] **Step 2: Build and inspect**

Run: `THEOS=$HOME/theos make clean package FINALPACKAGE=1`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Marquee/MRDetailPosterPanelView.h Marquee/MRDetailPosterPanelView.m
git commit -m "feat: add detail poster panel"
```

---

### Task 5: Episode guide view

**Files:**
- Create: `Marquee/MRDetailEpisodeGuideView.h`, `Marquee/MRDetailEpisodeGuideView.m`

**Interfaces:**
- Produces:
  - `@property (nonatomic, copy) void (^retryHandler)(void);`
  - `- (void)showLoading;`
  - `- (void)showEpisodes:(NSArray *)episodes;`
  - `- (void)showError;`
  - `- (CGFloat)heightForWidth:(CGFloat)width;`

- [ ] **Step 1: Build the card**

Style the guide with the shared card style. Header `EPISODE GUIDE` plus count.
Season chips in a horizontal scroll view when more than one season exists.
Rows contain a 16:9 still, `S1E1 · Title`, runtime/air date, and up to three
summary lines. Render 12 rows initially and a `Show more episodes` button that
adds 12. Loading shows a spinner; error shows a message and Retry; empty returns
0 height. Episode stills use the shared poster edge helper.

- [ ] **Step 2: Build and inspect**

Run: `THEOS=$HOME/theos make clean package FINALPACKAGE=1`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Marquee/MRDetailEpisodeGuideView.h Marquee/MRDetailEpisodeGuideView.m
git commit -m "feat: add detail episode guide"
```

---

### Task 6: Wire detail screen

**Files:**
- Modify: `Marquee/MRDetailViewController.m`

**Interfaces:**
- Consumes: `MRDetailPosterPanelView`, `MRDetailEpisodeGuideView`, `MREpisode`,
  `fetchEpisodesForType:simklID:completion:`.

- [ ] **Step 1: Add views and state**

Add properties for the panel, guide, episode array, fetch task, and a fetch
generation. Build the panel after the hero and the guide after the next-episode
card.

- [ ] **Step 2: Fetch episodes**

Start the episode request alongside the detail request for non-movie items with
a Simkl ID. Guard against stale completions with the generation counter. On
success, normalize with `MREpisode`, call `showEpisodes:`, and request layout.
On failure, call `showError`. Retry re-runs the fetch. Do not start it offline.

- [ ] **Step 3: Reorder layout**

Lay out in this order: hero, offline card, poster panel, overview, actions, next
episode, episode guide, info, related rows, footer. Include the panel and guide
heights only when positive. Hide the guide while offline.

- [ ] **Step 4: Run tests and build**

Run: `./tests/run_tests.sh && THEOS=$HOME/theos make clean package FINALPACKAGE=1`
Expected: all tests pass and exit 0.

- [ ] **Step 5: Commit**

```bash
git add Marquee/MRDetailViewController.m
git commit -m "feat: show poster panel and episode guide on detail"
```

---

### Task 7: Device verification and push

**Files:**
- Modify: `.superpowers/sdd/2026-11-04-marquee/progress.md`

- [ ] **Step 1: Audit the package**

Confirm iOS 6.0 minimum, device families 1+2, iPhone portrait only, iPad
portrait/landscape, system frameworks only, valid signature.

- [ ] **Step 2: Verify on the iPhone 4S**

Install the package. Use a temporary programmatic detail-open/scroll hook to
capture: movie top (hero, poster panel, overview), series top, series episode
guide, and mid-scroll headers. Remove the hook before the final commit.

- [ ] **Step 3: Rebuild clean and confirm launch**

Run the final package, confirm For You and a detail screen open normally, and
confirm no `TEMP(local screenshot hook)` references remain.

- [ ] **Step 4: Push**

Push `feature/marquee` and fast-forward `main` to the same commit. Update the
progress ledger with Task 27 and the verification evidence.
