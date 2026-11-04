#!/bin/sh
set -e
cd "$(dirname "$0")/.."
clang -fobjc-arc -framework Foundation -I Marquee \
  Marquee/MRJSON.m Marquee/MRDate.m Marquee/MRMediaType.m \
  Marquee/MRWatchStatus.m Marquee/MRMediaItem.m Marquee/MRClock.m \
  Marquee/MRURLBuilder.m Marquee/MRError.m \
  Marquee/MRHTTPRequest.m Marquee/MRHTTPResponse.m Marquee/MRAPIRequestOperation.m \
  tests/*.m -o /tmp/marquee-tests
/tmp/marquee-tests
