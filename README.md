# Marquee

Marquee is a standalone, native SimKL client for iOS 6. It is written in
Objective-C with ARC and talks directly to the SimKL API. There is no relay
server, third-party SDK, CocoaPods/SPM dependency, storyboard, or nib.

## Platform support

- iOS 6.0 or later, armv7.
- iPhone and iPod touch: portrait only.
- iPad 2/3/4 and iPad mini: native iPad layout in portrait and both
  landscape orientations.
- Free SimKL accounts only. Marquee does not use PRO/VIP-only endpoints.

## Build

Prerequisites:

- macOS with a compatible Xcode/iOS SDK toolchain.
- [Theos](https://theos.dev) with an iOS 6 SDK.
- `ldid` for signing.

```sh
export THEOS=$HOME/theos
make package FINALPACKAGE=1
```

The installable package is written to `packages/`. To build without packaging:

```sh
make FINALPACKAGE=1
```

## Install

With a jailbroken device reachable over SSH:

```sh
scp packages/com.kerthmfy.marquee.app_1.0_iphoneos-arm.deb \
  root@DEVICE_IP:/tmp/marquee.deb
ssh root@DEVICE_IP \
  'dpkg -i /tmp/marquee.deb; su mobile -c /usr/bin/uicache'
```

Launch with `sblaunch -p com.marquee.app`; quit with
`sbquit com.marquee.app` (or `killall Marquee`).

If `THEOS_DEVICE_IP` is configured, `make install` performs the Theos install
and killall step.

## Tests

The Foundation-only test suite covers models, networking helpers, persistence,
sync, writes, recommendations, Search, diagnostics, and error presentation:

```sh
./tests/run_tests.sh
```

UIKit screens are compile-verified and are checked on a device because the test
binary links only Foundation and CoreGraphics.

## SimKL client ID

Marquee signs in with the SimKL device flow. Register an OAuth application with
SimKL, then put its client ID in `Marquee/MRConfig.h`:

```objc
#define MR_SIMKL_CLIENT_ID @"your-client-id"
```

The device flow shows a code and opens `simkl.com/pin` for approval. Tokens are
stored in the Keychain; account data and the write outbox are stored as JSON
files under the app's Library directory.

## Images

iOS 6 cannot decode the WebP posters served by SimKL. Marquee requests every
poster and fanart image through `wsrv.nl` with `output=jpg`; do not remove that
parameter or request WebP directly.

## Write testing

All write checks use sacrificial titles on the real account. Before testing a
status, history, rating, or remove action, choose a title that can be changed
back, and restore the account to its baseline afterward. Pending writes are
persisted in `outbox.json` and resume only for the same SimKL account.

## Known limitations

- No SimKL PRO/VIP features: rewatches, custom lists, and PRO-only data.
- No scrobbling, playback sessions, or real-time progress.
- No full season/episode browser; Marquee marks the next episode or the whole
  title.
- No calendar, DVD releases, trailers, comments, social features, or imports.
- No push notifications, background sync, widgets, analytics, or crash
  reporting.
- No Core Data or SQLite; persistence is file-backed JSON.
- The app icon and launch image are temporary placeholders.
- iPad layout can be checked only when iPad hardware is available; the
  universal metrics and bundle metadata are covered by tests and package
  inspection.
