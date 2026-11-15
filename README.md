# Marquee - Simkl client for iOS 6

Marquee is a standalone, native SimKL client for iOS 6.

<p align="center">
  <img src="screenshots/attachment-2.png" width="220" alt="first bar">
  <img src="screenshots/attachment-1.png" width="220" alt="second bar">
  <img src="screenshots/attachment-0.png" width="220" alt="profile bar">
</p>


- iOS 6.0 or later, armv7.

## Install from Cydia

Marquee is published in my repo: `http://kerthmfy.github.io/repo/`


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


## SimKL client ID

Marquee signs in with the SimKL device flow. Register an OAuth application with
SimKL, then put its client ID in `Marquee/MRConfig.h`:

```objc
#define MR_SIMKL_CLIENT_ID @"your-client-id"
```

The device flow shows a code and opens `simkl.com/pin` for approval. Tokens are
stored in the Keychain; account data and the write outbox are stored as JSON
files under the app's Library directory.


## future implementations

- SimKL PRO/VIP features: rewatches, custom lists, and PRO-only data.
- scrobbling, playback sessions, or real-time progress.
-  calendar, DVD releases, trailers, comments, social features, or imports.
- No push notifications, background sync, widgets, analytics, or crash
  reporting.
-  app icon and launch image are temporary placeholders.

