# Lyrics from several providers, scored together, synced only

The notch's lyrics used to come from LRCLIB alone, which has little of the Chinese catalogue we listen to. We now search NetEase Cloud Music, Kugou, LRCLIB and LrcApi (api.lrc.cx) at once and score every candidate together on title, artist and, most of all, song length. This is a port of bragi's `server/lyrics.ts` (https://github.com/kebot/bragi), which has already shown that NetEase and Kugou find far more. Only synced (LRC) lyrics count: the notch is built around the current line under the camera, so a song with plain-text lyrics shows none.

## Considered Options

- **LRCLIB only**: official and keyless, but it misses most Chinese songs, and its exact `/get` match fails whenever Spotify's album name or length differs from LRCLIB's.
- **Spotify's own lyrics**: AppleScript doesn't expose them, and the web player's lyrics endpoint needs the user's `sp_dc` cookie and isn't public.
- **Trusting each provider's top result**: NetEase's and Kugou's first hit is often a live take, a cover or a backing track, so we score on length instead. A candidate more than 20 s off is dropped, or more than 3 s off when the artist doesn't match (a romanized artist, or another song with the same title).
- **Showing plain-text lyrics**: this would need a second layout in the notch for an unsynced block of text. We left it out until it's missed.

## Consequences

- NetEase and Kugou are unofficial APIs. They can change or block us without notice, and then that provider's search just fails. The other providers still answer, and a lookup is only cached when at least one of them did.
- Every track's title and artist go to four third-party services, two of them in China.
- Kugou's song search is http-only, so the bundled app carries an App Transport Security exception for `mobilecdn.kugou.com` in `assets/Info.plist`.
- NetEase and Kugou lyrics often begin with timed credit lines ("作词 : …"), and instrumentals can come back with credits only ("纯音乐，请欣赏"); the notch shows them as lyrics.
