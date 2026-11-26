# Marquee Handover

## Project

Marquee is a native, standalone SimKL client for iOS 6 (Objective-C / UIKit,
armv7). It has no modern runtime dependencies and is built with Theos.

- Repository: https://github.com/kerthmfy/Marquee-ios6
- Active branch: `main` at `cba61c1` (same commit as `feature/marquee`)
- Design reference: `/Users/kerthfyadao/Downloads/Marquee — iOS 6 UI concept.pdf`
- Catalog/site repo is separate and out of scope for app UI work.

## Current status

The iOS 6 UI revamp is complete and installed on the test device.

- Dark pinstripe canvas, charcoal grouped cards, glossy charcoal bars.
- Mustard-yellow primary action buttons; blue links/progress; gold stars.
- Grouped Library/Search/Profile rows, stats-grid dividers, dark filter chips,
  dark segmented controls, white scroll indicators.
- Stray light/white hairlines removed, including the default etched separators
  in Diagnostics.
- Verified on an iPhone 4S with on-device screenshots of For You, Details,
  Search, Library, Profile, Hidden Titles, and Diagnostics.
- iPad layouts inherit the same appearance tokens but have not been
  screenshot-verified on iPad hardware.

## Build

```sh
export THEOS=$HOME/theos
make package FINALPACKAGE=1
```

- Theos is expected at `~/theos` with the iOS 6.1 SDK.
- Package output:
  `packages/com.kerthmfy.marquee.app_1.0.1_iphoneos-arm.deb`
- Version fields live in `control` and `Marquee/Resources/Info.plist`.

## Tests

```sh
./tests/run_tests.sh
```

Expected result: `All tests passed.`

## Install on device

Test device: iPhone 4S, iOS 6.1.3, `root@192.168.100.110`.

```sh
scp packages/com.kerthmfy.marquee.app_1.0.1_iphoneos-arm.deb \
    root@192.168.100.110:/tmp/marquee.deb
ssh root@192.168.100.110 \
    "dpkg -i /tmp/marquee.deb; killall Marquee; sblaunch -p com.marquee.app"
```

## UI architecture

`MRAppearance` is the single source of truth for chrome and colour:

- `Marquee/MRAppearance.h` / `.m` — palette, pinstripe background, navigation
  bar, tab bar and selection, icons, action/danger buttons, bar buttons, cards,
  section headers, segmented control, search field, poster borders.
- `Marquee/MRRowHeaderView.m` — dark section bars.
- `Marquee/MRStatusChipsView.m` — filter chips.
- `Marquee/MRHeroView.m` — For You hero card.
- `Marquee/MRPosterImageView.m` — dark poster placeholder.
- `MRLibraryViewController`, `MRSearchViewController`,
  `MRProfileViewController`, `MRDetailViewController`,
  `MRForYouViewController` — screen-specific grouping/layout.

Core tokens currently in use:

- Canvas: `#17171a` pinstripe; paper `#1c1c1f`
- Card fill: `#232327`; raised fill: `#333338`
- Separators/outlines: `#2c2c31`
- Ink: `#f2f2f5`; muted: `#9d9da5`; link: `#72a9ff`
- Stars: `#f0c94a`; empty: `#606068`
- Action gradient: `#f4d56c` → `#dfb74d` → `#c69a2e`; title `#3a2c08`

Keep new screens on these tokens rather than adding one-off colours.

## QA / screenshots

Screenshot and touch tooling was installed on the 4S for verification:
Activator, Cycript, SimulateTouch, and adv-cmds.

```sh
ssh root@192.168.100.110 "sblaunch -p com.marquee.app"
ssh root@192.168.100.110 \
    "activator send libactivator.system.take-screenshot"
```

Screenshots land in `/var/mobile/Media/DCIM/101APPLE/` and can be pulled with
`scp`. Tabs can be changed through Cycript, e.g.
`cycript -p Marquee /tmp/select1.cy` where the script calls
`setSelectedIndex:` on `MRRootTabBarController`.

Remove those packages if a clean device is needed before shipping.

## Publishing to Cydia

Publishing is separate from normal app development and expects the distribution
repo as a sibling checkout (`../repo`). See the README for the full flow:

```sh
./tools/publish-cydia.sh --no-push   # review locally
./tools/publish-cydia.sh --push      # publish to the KMY repo
```

Bump `control` and the Info.plist versions before a real publish.

## Known limitations

- SimKL PRO/VIP features, rewatches, custom lists.
- No scrobbling, playback sessions, or real-time progress.
- No calendar, DVD releases, trailers, comments, social features, or imports.
- No push notifications, background sync, widgets, analytics, or crash reports.
- App icon and launch image are temporary placeholders.
- No iPad hardware/screenshot verification yet.
