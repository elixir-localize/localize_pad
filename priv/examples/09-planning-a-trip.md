Locale: `en`

```
# Two weeks in Japan

// A trip is a start date and a run of stops. Each
// stop answers with the dates you are there, and
// the line that opens the trip adds them up.
trip from March 3, 2026 to March 22, 2026
3 nights in Tokyo
5 nights in Kyoto
4 nights in Osaka
5 nights in Sapporo

// Seventeen nights of the nineteen you have. Change
// a number above and every date below it moves, and
// so does what is left over.
//
// `Kyoto: 5 nights` works just as well, and so does
// writing the finish on its own line as `trip ends
// March 22, 2026`.

# What it costs

// A `#tag` says what kind of thing a line is.
// Nothing else about the line changes: the label is
// still a label and the money is still money.
Flights: $1,850 #transport
Rail pass: $435 #transport
Tokyo hotel: $620 #stay
Kyoto ryokan: $890 #stay
Osaka hotel: $410 #stay
Sapporo hotel: $500 #stay
Food and drink: $1,200 #food

// Any of the six functions can then report on a tag
// instead of on the block above it.
sum #stay
sum #transport
average #stay
count #stay

// Untagged, they still report on the block — every
// line under this heading, tagged or not.
sum

// A tag reaches back to the previous heading and no
// further, so `#stay` under another heading would be
// a separate question with a separate answer.
```
