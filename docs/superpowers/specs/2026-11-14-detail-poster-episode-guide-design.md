# Detail Poster and Episode Guide Design

## Goal

Make movie and series detail screens feel worth opening: a cinematic hero built
from Simkl's wide poster artwork, a real portrait poster, key facts and summary
above the actions, and a read-only episode guide for shows and anime. Give every
poster thumbnail a subtle rounded edge with a dark hairline.

## Constraints

- Objective-C/ARC, iOS 6.0, iPhone portrait and iPad portrait/landscape.
- No new dependencies, storyboards, nibs, write actions, or touch/system tweaks.
- Keep the existing iOS 6 card stack and chrome.
- Keep the full-bleed hero artwork square-edged.

## Detail layout

Top to bottom:

1. Existing hero, now preferring the wide Simkl poster crop with fanart as the
   fallback.
2. Offline card when detail loading failed.
3. New poster/key-facts card: portrait Simkl poster on the left; on the right a
   rating/runtime/certification line plus compact facts (director, network,
   first aired/released year, country, episode count, genres).
4. Overview card.
5. Existing actions card.
6. Existing next-episode card.
7. New episode guide card for shows and anime.
8. Existing info card.
9. Existing related rows.
10. Existing Simkl footer.

The detail response now also merges `certification` and `director` into
`MRMediaItem` for the key-facts card.

## Episode guide

- Fetches `GET /tv/episodes/{id}` for shows and `GET /anime/episodes/{id}` for
  anime, in parallel with the detail request.
- `MREpisode` normalizes season, episode number, title, summary, runtime, still
  image path, air date, aired flag, and specials.
- Anime entries without `season` default to season 1. Specials keep season 0
  and sort after regular seasons.
- A horizontal season-chip row appears only when more than one season exists.
- Each row shows a 16:9 still, `S1E1 · Title`, runtime/air date, and up to three
  lines of summary. Rows are read-only.
- Twelve episodes render at first; a `Show more episodes` row adds twelve more.
- States: loading spinner, unavailable message with Retry, empty guide hidden.
- Episode fetch failure never blocks the rest of the detail screen.

## Poster edge

Shared `MRAppearance` helper: 4 pt corner radius, masks to bounds, 0.5 pt dark
hairline border. Applied to poster cards, Library/Search/Hidden Titles
thumbnails, the detail poster, and episode stills. Never applied to the hero.

## Non-goals

- No episode write actions, progress marking, trailers, or new tabs.
- No visual changes outside the detail screen and poster thumbnails.
