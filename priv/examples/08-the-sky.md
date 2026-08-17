Locale: `en`

```
# The sky

// The sun and the moon, worked out rather than looked
// up. Astro does the arithmetic; this sheet supplies
// the place and the day.

// Leave the place off and the answer is for wherever
// you are. Your browser tells the page its timezone —
// nothing else can, since no web request carries one.
sunrise
sunset

// Name a place and the answer comes back on *its*
// clock rather than yours. The city becomes a timezone
// exactly as it does in `6pm Sydney in Chicago`, and
// IANA's own table gives the coordinates that go with
// it. No map, no lookup service, no key.
sunrise tomorrow in Chicago
sunset today in Tokyo
moonrise in Cairo on December 24, 2026
moonset in London on December 24, 2026

# The longest day, and the shortest

// One date, two hemispheres. Midsummer in Reykjavik is
// midwinter in Sydney, and the sheet does not have to
// be told which is which.
sunrise in Reykjavik on June 21, 2026
sunset in Reykjavik on June 21, 2026
sunrise in Sydney on June 21, 2026
sunset in Sydney on June 21, 2026

// Iceland in December, six months and a whole world
// away: up at twenty past eleven, down before half
// past three.
sunrise in Reykjavik on December 21, 2026
sunset in Reykjavik on December 21, 2026

// Further north still and it does not rise at all.
// That is a fact about Svalbard rather than a failure,
// so the line says so instead of going quietly blank.
sunrise in Longyearbyen on December 21, 2026

# The moon

// A phase is an angle — 274.3° is a number nobody
// wanted. So the answer is the name of the phase, the
// picture Unicode has for it, and the part people are
// really asking about: how much of it is lit.
moon phase
moon phase on December 24, 2026

// A phase needs no place. It is the same moon from
// everywhere it is up, which is why this one line
// never asks where you are.
```
