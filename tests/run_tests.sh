#!/bin/sh
set -e
cd "$(dirname "$0")/.."
clang -fobjc-arc -framework Foundation -framework CoreGraphics -I Marquee \
  Marquee/MRJSON.m Marquee/MRDate.m Marquee/MRMediaType.m \
  Marquee/MRWatchStatus.m Marquee/MRMediaItem.m Marquee/MRClock.m Marquee/MRLayout.m \
  Marquee/MRURLBuilder.m Marquee/MRError.m \
  Marquee/MRHTTPRequest.m Marquee/MRHTTPResponse.m Marquee/MRAPIRequestOperation.m \
  Marquee/MRResponseCache.m Marquee/MRQuotaTracker.m Marquee/MRDiagnostics.m \
  Marquee/MRStorage.m Marquee/MRUserProfile.m Marquee/MRLibraryStore.m \
  Marquee/MRSyncEngine.m Marquee/MRAPIClient.m Marquee/MRLibraryFilter.m \
  Marquee/MRFeedSection.m Marquee/MRPublicFeedBuilder.m \
  Marquee/MRTokenSession.m Marquee/MRDeviceCode.m \
  Marquee/MRDeviceFlow.m Marquee/MRSimklAuth.m \
  tests/*.m -o /tmp/marquee-tests
/tmp/marquee-tests
