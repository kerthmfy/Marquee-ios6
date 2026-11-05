# Marquee Universal / iPad Design

**Status:** Proposed supplement to `2026-11-04-marquee-design.md`
**Date:** 2026-11-05
**Decision:** Native universal app. One adaptive Objective-C codebase, not separate iPad screens.

This document supersedes the original non-goal:

> No iPad-native layout and no landscape. iPhone portrait only; iPad runs in compatibility mode.

Everything else in the original design remains binding.

## 1. Intent

Marquee should be a real iPad app, not a scaled iPhone app. The iPad version
uses the larger screen for more visible recommendation cards, larger artwork,
and a layout that remains usable in both portrait and landscape. The iPhone
version stays focused and portrait-only.

The app remains a free SimKL client for iOS 6, built with Theos from
Objective-C/ARC source. There is no new backend, relay, or third-party
dependency.

## 2. Goals

1. Install and run natively on iPad 2, iPad 3, iPad 4, and iPad mini on iOS 6.
2. Keep the existing iPhone 4S experience and portrait-only behavior.
3. Use one set of view controllers and shared behavior on both device classes.
4. Show more content on iPad instead of stretching a 320 pt column.
5. Support iPad portrait and landscape; rotate without clipped or misplaced
   chrome, cards, banners, or tab selection.
6. Preserve the Matinee-derived navigation bar, charcoal tab bar, card language,
   and SimKL branding.
7. Make the universal metrics testable without UIKit or a physical device.

## 3. Non-goals

- No iPad 1 / iOS 5.1 support. The deployment target stays iOS 6.0.
- No separate iPad view-controller classes or a second UI implementation.
- No `UISplitViewController`, popovers, drag-and-drop, multitasking, or
  iPad-only navigation model in v1.
- No new SimKL features, PRO/VIP APIs, or changes to recommendations.
- No storyboard, nib, Auto Layout, size classes, or Swift.
- No upside-down iPad orientation in v1.
- No redesign of the iPhone layout beyond making its existing fixed values come
  from one metrics source.

## 4. Anti-goals

- A full-screen iPad app that is just the 320 pt iPhone layout centered with
  large empty margins.
- Two drifting UI implementations selected by idiom.
- iPad-only crashes caused by fixed 320 pt frames, fixed image sizes, or
  hard-coded tab-selection widths.
- Rotating to landscape and leaving rows, the hero, or the tab bar in portrait
  geometry.
- Breaking the iPhone feed while adding iPad metrics.

## 5. Constraints

- iOS 6.0 deployment target, armv7 only.
- iPhone 3.5-inch, iPhone 4-inch, iPad 2 (1x), iPad 3/4 and mini (2x).
- UIKit, manual frames, autoresizing masks, and `layoutSubviews`.
- No `NSURLSession`, `NSURLComponents`, Auto Layout, size classes, or other
  banned iOS 7+ APIs from the original plan.
- `UIDeviceFamily` must include both iPhone (1) and iPad (2).
- iPhone supports portrait only. iPad supports portrait, landscape-left, and
  landscape-right.
- Poster URLs remain `_m` (340x510) through wsrv with `output=jpg&q=90`.
  iPad cards use larger display sizes but the same source asset.
- All existing auth, sync, caching, and write rules remain unchanged.

## 6. Approaches Considered

### A. Universal adaptive codebase (chosen)

One view-controller per screen. A pure `MRLayout` metrics class translates
device class, orientation, and available width into card sizes, gaps, hero
height, row heights, and content insets. UIKit code reads those values.

- Pros: one implementation, consistent behavior, no divergence.
- Cons: every UI task after this point must use metrics, and the existing For
  You/tab-bar chrome needs a focused adaptation pass.

### B. Separate iPad screens

Share models, networking, and stores, but maintain iPad-specific controllers.

- Pros: iPad layouts can be tuned independently.
- Cons: duplicates most UI code, doubles later work, and two implementations
  will drift.

### C. iPhone-first, iPad pass at the end

Finish the 24 iPhone tasks, then adapt the whole UI.

- Pros: shortest path to the current iPhone app.
- Cons: accumulates fixed 320 pt assumptions and forces rework across every
  completed screen. Rejected.

## 7. Metrics Design

Add a Foundation/CoreGraphics-only `MRLayout` class. It must not import UIKit,
so the macOS test harness can test it.

```objc
typedef NS_ENUM(NSInteger, MRDeviceClass) {
    MRDeviceClassPhone = 0,
    MRDeviceClassTablet
};

typedef NS_ENUM(NSInteger, MRLayoutOrientation) {
    MRLayoutOrientationPortrait = 0,
    MRLayoutOrientationLandscape
};

@interface MRLayout : NSObject
+ (MRDeviceClass)deviceClassForIdiom:(NSInteger)idiom;
+ (MRLayoutOrientation)orientationForSize:(CGSize)size;
+ (CGFloat)heroSideInsetForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)rowSideInsetForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardImageHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardGapForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterRowHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)heroHeightForDeviceClass:(MRDeviceClass)deviceClass
                         orientation:(MRLayoutOrientation)orientation
                     availableHeight:(CGFloat)availableHeight;
+ (CGFloat)rowHeaderHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)contentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)modalContentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)tabBarSelectionWidthForWidth:(CGFloat)width itemCount:(NSInteger)count;
@end
```

The exact values live in one table in the implementation and are covered by
tests. Initial values:

| Metric | iPhone | iPad portrait | iPad landscape |
|---|---:|---:|---:|
| Hero side inset | 8 | 16 | 16 |
| Row side inset | 12 | 16 | 16 |
| Poster card width | 100 | 150 | 150 |
| Poster image height | 150 | 225 | 225 |
| Card height / row height | 210 | 315 | 315 |
| Card gap | 8 | 12 | 12 |
| Hero height | 180 (480 pt tall) / 200 (568 pt tall) | 300 | 260 |
| Row header height | 32 | 40 | 40 |
| Text content max width | none | 720 | 720 |
| Modal content max width | 320 | 540 | 540 |

The iPhone has two side insets because the hero uses 8 pt and the horizontal
rows use 12 pt; that is the shipped Task 7 geometry, not a new choice. The
iPhone 3.5-inch and 4-inch screens are both 320 pt wide, so width alone cannot
tell them apart. `heroHeightForDeviceClass:orientation:availableHeight:`
takes the actual view height (480 or 568) and returns 180 or 200. No helper
infers the device from a stored screen size.

`MRLayout` returns device-class values; the view controller supplies the
orientation and available height from its bounds. The helper must never read
`UIDevice` or `UIScreen` itself.

## 8. Screen Behavior

### For You

- Full-width table on both device classes.
- iPhone geometry is preserved exactly: 12 pt row inset, 100 pt cards, 8 pt
  gaps. At 320 pt that shows two full cards and the first 92 pt of a third;
  the third card is clipped, not a fourth card. The hero is 304 pt wide
  (320 − 8 pt each side). Task 8.5 parameterizes these pixels; it does not
  redesign them.
- iPad shows four full cards plus part of a fifth in portrait (768 pt) and six
  full cards plus part of a seventh in landscape (1024 pt), with the same
  horizontal scrolling rows.
- Hero, skeleton, row headers, and retry placeholder use `MRLayout`.
- The existing round-robin feed composition and 12-item row cap are unchanged.
- Poster cards use the same `_m` source on both classes.

### Library

- Full-width list with larger artwork on iPad.
- Status chips and counts stay on one line in portrait and landscape.
- No split view in v1; selecting a row pushes the existing detail screen.

### Detail

- Hero/fanart may use the full width, but body text, metadata, and action groups
  are capped at 720 pt and centered on iPad.
- Fanart keeps the existing `_medium` source. A live SimKL asset measured
  1920×1080, which covers the iPad 3/4 landscape width (2048 px) with only a
  six-percent upscale and downscales cleanly everywhere else. No new fanart
  variant or URL-builder change is needed in v1; the existing dark bottom
  gradient protects text contrast.
- Actions remain reachable in landscape without scrolling past a fixed-height
  header.

### Search

- Search bar spans the content width; results are capped at 720 pt and centered
  on iPad so lines do not become unreadably long.

### Profile

- Grouped settings table is capped at 720 pt and centered on iPad.
- Sign-in, account, genre, hidden-title, and diagnostics rows keep the same
  behavior and order.

### Tab bar and navigation chrome

- Tab bar stays 49 pt at the bottom.
- The tab background is generated for the actual bar width, not a fixed 320 pt.
- The selection panel width is `barWidth / itemCount`; four tabs remain.
- Selected and unselected icons keep the current iOS 6 blue/gray treatment.
- Navigation bar stays 44 pt with the same title treatment.

### Modal screens

- `MRConnectViewController` presents full-screen on both device classes. Its
  scroll content is capped at 540 pt and centered on iPad; the iPhone is
  narrower, so the cap has no effect there. It already lays out from its
  bounds in `viewDidLayoutSubviews`, so the same code handles rotation.
- The genre picker uses `UIModalPresentationFormSheet` on iPad and the default
  full-screen presentation on iPhone. The form sheet's system-defined bounds
  feed the same width-aware table layout.
- No popovers. No separate iPad modal classes.

## 9. Orientation and Rotation

- iPhone: portrait only.
- iPad: portrait, landscape-left, landscape-right. No upside-down.
- `MRRootTabBarController` restyles the tab bar after the view appears and
  after an orientation change.
- Table-based screens reload or re-layout visible cells when the width changes;
  horizontal row offsets should reset only when the row is reused, as today.
- `layoutSubviews` remains the source of truth for custom views; controllers
  update table row heights after rotation.
- Rotation is owned per screen as that screen lands, not retrofitted at the
  end. Task 8.5 establishes the pattern for the tab bar, For You, and Connect.
  Every later UI task (10–22) must use `MRLayout`, lay out from its bounds, and
  include an iPad portrait/landscape check in its own definition of done.
  Task 23 is polish and edge-case verification, not the first rotation pass.

## 10. Assets and Packaging

`Marquee/Resources/Info.plist`:

- Add `UIDeviceFamily` = `[1, 2]`.
- Keep `UISupportedInterfaceOrientations` = portrait for iPhone.
- Add `UISupportedInterfaceOrientations~ipad` = portrait, landscape-left,
  landscape-right.
- Keep `MinimumOSVersion` 6.0 and `UIRequiredDeviceCapabilities` armv7.

`tools/MRMakeAssets.m` and `Marquee/Resources/`:

- Add iPad launch images:
  - `Default-Portrait.png` 768x1024
  - `Default-Portrait@2x.png` 1536x2048
  - `Default-Landscape.png` 1024x768
  - `Default-Landscape@2x.png` 2048x1536
- Add them to `Marquee_RESOURCE_FILES` in the Makefile.
- Keep the existing iPhone launch images.
- Existing `Icon-72.png` and `Icon-72@2x.png` cover the iPad home-screen icon;
  no new icon art is required for v1.

## 11. Testing and Acceptance

Automated:

- `MRLayout` metric tests for iPhone, iPad portrait, and iPad landscape,
  including both iPhone hero heights (480 and 568 pt), both iPhone side insets
  (8 pt hero, 12 pt rows), and the 540 pt Connect content cap.
- Tab selection width test for four items at 320, 768, and 1024 pt.
- Existing Foundation test suite stays green; no UIKit import in tests.

Build:

- Universal Theos package builds armv7 for iOS 6.
- `Info.plist` in the installed bundle reports both device families and the
  correct per-idiom orientations.

Device acceptance:

- iPhone 4S: existing portrait feed, tab bar, and posters still work.
- iPad on iOS 6, if available:
  - installs as a native app, not compatibility mode;
  - For You loads in portrait and landscape;
  - tab selection panel fills the correct quarter and the bar spans the screen;
  - posters are sharp, not the 84x124 `_cm` assets;
  - rotation does not clip the hero, cards, headers, or banners;
  - Library, Search, Profile, and Detail layouts are checked as they land in
    their tasks.
- If no iPad is available, the design is build- and metric-verified, and the
  iPad visual checklist is recorded as pending human verification.

## 12. Plan Impact

Insert a new task after Task 8 and before Task 9:

**Task 8.5: Universal app foundation and iPad-adaptive existing chrome**

It starts from the committed Task 7 polish (the `_m` poster and tab-bar work),
not from `b4eaafc` alone. That polish must be installed and visually verified
on the iPhone 4S before Task 8.5 begins. It adds `MRLayout` and tests, universal
Info.plist/orientations, iPad launch assets, dynamic tab-bar images, and adapts
the current For You skeleton, hero, poster cards, row cells, placeholder
chrome, and the Connect modal. It must not change auth or sync behavior.

Every later task that creates or modifies UI must consume `MRLayout` instead of
adding new fixed 320 pt dimensions. Task 23 adds the iPad rotation/offline
polish, and Task 24 verifies both iPhone and iPad.

## 13. Builder-Check Decisions

The builder check raised six questions. All are resolved here; none need a
separate user decision.

1. **iPhone row geometry.** The old "three cards plus a partial fourth" line
   was arithmetically wrong. The shipped geometry is two full cards plus
   92 pt of a third at 320 pt, with a 304 pt hero. Task 8.5 preserves those
   pixels; only the source of the numbers changes. It starts after the Task 7
   polish commit so it parameterizes the final chrome, not an intermediate
   state.
2. **Dual iPhone values.** The metrics API now has separate hero/row insets and
   takes `availableHeight` for the 180/200 pt hero choice. Tests pin 480 and
   568 pt. This avoids silently shrinking the 4-inch hero or overflowing the
   3.5-inch one.
3. **iPad modals.** Connect is full-screen with a 540 pt content cap; the genre
   picker is a form sheet. This keeps Task 8's auth screen usable without a
   separate iPad class.
4. **Fanart sharpness.** `_medium` is 1920×1080, so it stays. No URL-builder or
   image-cache change is needed in Task 8.5.
5. **Rotation ownership.** Each screen owns its rotation as it lands; Task 8.5
   sets the pattern for For You and Connect, and Task 23 is polish, not a
   retrofit.
6. **Plan insertion.** The plan gets "Task 8.5" verbatim with no renumbering,
   so existing references to Tasks 9–24 stay valid. The SDD ledger gets a
   matching Task 8.5 entry, and unstarted work continues with Task 9 after it.

No design questions remain open. The only unresolved external dependency is
iPad hardware for final visual verification; the plan records that as a device
checkpoint rather than a code dependency.
