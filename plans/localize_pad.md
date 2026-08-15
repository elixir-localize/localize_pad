# LocalizePad — a conversational, localized notepad calculator

A plan for a Soulver-style notepad calculator built on Unity, Localize, Money and Tempo,
deployed as a Phoenix/LiveView app.

Status: research + design. No code written yet. Decisions marked **[DECIDE]** need your call.

---

## 1. What Soulver actually is

Stripped of the Mac-app furniture, Soulver is four things layered on top of each other:

1. **A document model.** A sheet is a list of lines. Each line is text; each line may produce
   an answer shown in a right-hand gutter. Lines can be headings (`#`), comments (`//`, labels,
   parentheses, quotes), variable declarations, subtotals, or expressions. There is a running
   total, and subtotals that sum back to the previous subtotal or heading.

2. **A dependency graph.** Lines reference earlier lines' answers (spreadsheet-style, but
   positional rather than by cell). Variables are declared with `=` and may be redefined,
   incremented (`+=`), or assigned conditionally. Edit a line and everything downstream
   recalculates. References only point *upward*.

3. **A forgiving, phrase-oriented language.** This is the actual product. It is not an NLP
   system — it is a hand-tuned lexicon plus a large table of phrase patterns, with the crucial
   property that *unrecognised words are discarded rather than fatal*:

   ```
   $19 for breakfast + $22 for the uber        → $41.00
   30% of 700                                  → 210
   180 is what % off 200                       → 10%
   June 12 + 3 weeks                           → 3 July
   6pm Sydney in Chicago                       → 1:00 am
   $30/day is what per year                    → $10,957.28/year
   monthly repayment on $10,000 over 6 years at 6%  → $165.73
   6 is to 60 as 8 is to what                  → 80
   ```

   The vocabulary spans: percentages, units, currencies, rates, dates, clock times, time zones,
   workdays, compound interest, mortgages, sales tax, conditionals, proportions, bases and
   bitwise, permutations, random numbers.

4. **An answer-formatting policy.** Locale-correct number formatting, currency rounding rules,
   large-number symbols (`3k`, `5M`), scientific notation on request, unit pluralisation,
   duration rendering (`8 hours 35 min`).

Note what Soulver *does not* do: its input keywords are English-only. Its "region settings" only
change how numbers are read and written (`.` vs `,`) — you cannot type `20 % von 700` or
`10 juin + 3 semaines`. That is the opening.

Source: <https://documentation.soulver.app/llms.txt> and the syntax-reference pages beneath it.

---

## 2. What we already have

Verified against the local checkouts and hex on 2026-08-15.

| Library | Hex | Local | What it gives us |
|---|---|---|---|
| `unity` | 1.0.0 | 0.7.0 (**stale**) | NimbleParsec expression grammar, interpreter, ~2,760 units (155 CLDR + ~2,440 GNU Units + ~250 constants + ~75 nonlinear scales), 36 math functions, variables, `to`/`in`/`->` conversion, mixed-unit decomposition (`h;min;s`), measurement-system targets, unit aliases, fuzzy "did you mean", a REPL and a CLI |
| `localize` | 1.1.0 | 1.1.0+ | CLDR everything: number format/parse, unit format, date/time/duration/interval/relative format, currency data, list format, territory + measurement-system preference, collation, MF2 messages, 500+ locales |
| `ex_money` | 6.2.1 | 6.2.1 | `Money.t()` (Decimal + ISO 4217 / ISO 24165 crypto), locale-aware formatting with per-currency rounding, string parsing, live + historical exchange rates, `Money.Financial` (present/future value, NPV, IRR, `interest_rate`, `periods`, `payment`), subscriptions |
| `localize_web` | 1.1.0 | 1.1.0 | Locale discovery plugs (header/param/path/session/cookie/TLD), session persistence into LiveView, compile-time localized routes + `~q` sigil, HTML select helpers for currencies/territories/locales/units/months |
| `ex_tempo` | 1.2.0 | 1.2.0 | **The second pillar** (§4b). One interval type at any resolution; set algebra and Allen relations cross-zone and cross-calendar; RRULE recurrence; `select/2`; territory-aware workdays; `.ics` import with metadata that survives set operations; dependency scheduling with critical path; constraint networks; ISO 8601-1/-2, EDTF and IXDTF; `explain/1` |
| `calendrical` | 1.2.0 | 1.2.0 | **A complete locale-aware date/time/datetime/interval parser** (see below), 18 calendars, k-day functions, calendar intervals, timezone resolution, fiscal years, era handling |

Four specific primitives are worth calling out because they change the design:

* **`Localize.Number.Parser.scan/2`** splits an arbitrary string into numbers and text runs,
  locale-aware (correct decimal/grouping separators, digit transliteration for non-Latin number
  systems). `scan("The prize is 23") → ["The prize is ", 23]`. This is precisely the "scavenge
  the calculable bits out of prose" primitive Soulver's tokenizer needs, and it already exists.

* **`Calendrical.parse/2`** is a unified locale-aware parser that dispatches to date, time,
  datetime, or interval sub-parsers and returns the first success. It is driven by the locale's
  CLDR patterns for all four widths, so field order follows the locale by construction
  (`M/d/yy` in `en`, `dd.MM.y` in `de`, `Gy年M月d日` in Japanese imperial). It handles lenient
  separators via CLDR's `lenient-scope-date` equivalence classes, 2-digit year pivoting,
  non-Latin digit transliteration, era markers across 18 calendars, quarters (`Q2 2026`,
  `2nd quarter 2026`), week-of-year (`week 20 of 2026`), weekday prefixes
  (`Saturday, May 16, 2026`), and ranges split on CLDR's `intervalFormatFallback` separator.

  Crucially it supports **`as: :map`, returning partial field maps** — `parse("May 5", as: :map)`
  yields `%{month: 5, day: 5}` with no year. That is precisely what Soulver's
  "dates with unspecified years" behaviour needs, and it means the nearest-year heuristic is
  ours to apply rather than something we must reverse-engineer out of a fully-resolved date.

  Verified against the local checkout:

  ```
  Calendrical.parse("May 5",        locale: :en,    as: :map)  → {:ok, %{month: 5, day: 5}}
  Calendrical.parse("2026",         locale: :en,    as: :map)  → {:ok, %{year: 2026}}
  Calendrical.parse("11 am",        locale: :en,    as: :map)  → {:ok, %{hour: 11}}
  Calendrical.parse("6pm",          locale: :en,    as: :map)  → {:ok, %{hour: 18}}
  Calendrical.parse("3/4/26",       locale: :"en-GB")          → {:ok, ~D[2026-04-03]}
  Calendrical.parse("3/4/26",       locale: :"en-US")          → {:ok, ~D[2026-03-04]}
  Calendrical.parse("16.05.2026",   locale: :de)               → {:ok, ~D[2026-05-16]}
  Calendrical.parse("10 juin 2026", locale: :fr)               → {:ok, ~D[2026-06-10]}
  Calendrical.parse("Q2 2026",      locale: :en)               → {:ok, ~D[2026-04-01]}
  ```

* **`Localize.Number.to_parts/2`** returns ECMA-402-tagged segments (`:integer`, `:group`,
  `:currency`, `:percent_sign`, `:compact`, …). The answer gutter can style each part
  individually without re-parsing the formatted string.

Also free from CLDR via Localize: compact notation (`:short` → `3K`), scientific notation,
currency display names and symbols, timezone exemplar city names, unit display names with
plural forms, locale measurement-system preference.

---

## 3. Gap analysis

What we'd have to build, honestly assessed.

**Already covered — no work**

* Arithmetic, precedence, parentheses, functions, rationals, hex/octal/binary literals — Unity.
* Unit conversion and unit arithmetic — Unity + `Localize.Unit`. Our ~2,760 units against
  Soulver's "200+"; this is a straight win.
* Locale-correct number reading and writing, compact and scientific notation — Localize.
* Currency values, arithmetic, rounding, formatting, 190+ currencies plus crypto — Money.
* Live and historical exchange rates — `Money.ExchangeRates` (needs an
  `:open_exchange_rates_app_id`; free tier is USD-base only, which forces triangulation).
* Compound interest, present/future value, NPV, IRR, loan payment — `Money.Financial`.
* Calendar arithmetic, intervals, "days between", inclusive intervals, week numbers — Tempo.
  Materially *better* than Soulver: its docs hedge about month ambiguity, Tempo models it.
* Recurrence (`every Friday the 13th`, `4th Thursday of November`) — `Tempo.RRule`, full
  RFC 5545. Soulver has no recurrence at all.
* Set algebra over time — union, intersection, difference, complement, and the
  `overlaps?`/`contains?`/`subset?` predicates — cross-zone and cross-calendar. Underpins every
  availability question in §4b. Soulver has nothing comparable.
* Workday arithmetic with **territory-correct working weeks** — `Tempo.workday?/2`,
  `add_working_days/3`, `working_days_in/2`. Soulver hardcodes Monday–Friday; we get Sun–Thu for
  Saudi Arabia and Sat–Wed for Iran from CLDR.
* `.ics` import with metadata surviving set operations — `Tempo.ICal.from_ical/2`.
* Dependency scheduling and critical path — `Tempo.Schedule`. Constraint reasoning over
  partially-known intervals with a plain-English trace — `Tempo.Network`.
* Uncertain and approximate dates, masked years, open-ended intervals — ISO 8601-2 / EDTF,
  with the full `edtf-validate` corpus passing.
* **Reading dates, times, datetimes and date ranges in any locale** — `Calendrical.parse/2`.
  This is the single biggest correction to my first pass: I had it down as the largest thing to
  build and as an upstream contribution to Localize. It already exists, it is CLDR-pattern
  driven, and it covers 500+ locales and 18 calendars out of the box.
* `days in Q3`, `days in February 2020`, week and quarter spans — `Calendrical.Interval`
  returns `Date.Range` for year/quarter/month/week/day.
* `next Thursday`, `second Monday of March`, and the stepping primitive underneath workday
  arithmetic — `Calendrical.Kday` (`kday_after/before/nearest`, `nth_kday`, `first_kday`,
  `last_kday`).
* Timezone resolution from ISO offsets, `GMT±HH:MM`, IANA names, common abbreviations
  (`PST`, `JST`), **and CLDR localized zone names** (`Pacific Time`,
  `Mitteleuropäische Zeit` → `Europe/Berlin` under `:de`) — `Calendrical.TimeZone.resolve/3`,
  which also uses the wall-clock instant to pick between standard and daylight offsets.

**Must build — the real work**

* **The document layer.** Lines, classification (heading/comment/label/declaration/subtotal/
  expression), line references, running total, subtotals scoped to the previous heading,
  dependency graph, incremental recalculation. None of this exists anywhere in the stack.
* **The conversational grammar.** Phrase forms (`X% of Y`, `A is what % off B`, `N is to M as
  P is to what`, `monthly repayment on … over … at …`, `time in Paris`, `3 weeks after March 14`).
  Noise tolerance. Unity's grammar is strict and fails the whole line on an unknown token.
* **A percentage value type.** Contextual semantics (`200 + 10%` = 220, but `10% + 20%` = 30%,
  and `50% × 30` = 15 as a plain number). This is Soulver's most-praised feature and the
  subtlest thing in the whole design. Deserves its own truth table.
* **A rate value type** carrying money or unitless numerators (`$99/week`, `30 bottles/week`).
  `Localize.Unit` handles unit-per-unit compounds; money-per-unit and number-per-unit are new.
* **Relative and deictic date phrases** — `yesterday`, `today`, `3 days ago`, `4 days from now`,
  `next Thursday`, `2 months 3 days after June 5`. `Calendrical` parses *absolute* dates; the
  relative vocabulary and the arithmetic phrasing around it are ours. The pieces underneath
  (`Kday` for weekday stepping, Tempo for the arithmetic) exist — this is lexicon plus phrase
  rules, not date engineering.
* **Nearest-year resolution** for partial dates. `Calendrical.parse("May 5", as: :map)` gives us
  `%{month: 5, day: 5}`; deciding whether that means this year or next (Soulver looks backwards
  a little and forwards a lot) is our policy to write.
* **City and airport-code → timezone mapping.** `Calendrical.TimeZone.resolve/3` handles zone
  names and abbreviations, but `6pm Sydney in Chicago` needs city→zone, and `7:30am LAX` needs
  an IATA table. CLDR's timezone exemplar-city data (reachable through
  `Localize.DateTime.Timezone`) covers the city half in every locale; IATA is a static table.
* **The localized keyword lexicon** — `of`, `off`, `on`, `per`, `to`, `in`, `after`, `ago`,
  `each`, `what`, `is`, `at`, `over`, `between`. CLDR has none of this. Roughly 120 entries per
  locale, hand-authored. This is the main new content cost and the core of the differentiator.
* **Public holiday plumbing** — fetching and caching, not the data. Tempo's holidays guide
  routes officeholidays.com `.ics` feeds (every UN-recognised country, updated weekly) through
  the same `Tempo.ICal.from_ical/1` we already need for calendar import, yielding an
  `IntervalSet` with holiday names on `:metadata`. So this is an HTTP fetch plus a cache, and
  it reuses one code path rather than adding a holiday library. Better than the `holidefs`
  route I first suggested.
* **Sales tax** — thin: a percentage plus a per-territory default table plus four phrase forms.
  `$300 - VAT` divides by 1.15, it does not subtract 15%; easy to get wrong.
* **Conditionals**, bitwise operators, video timecode, IATA airport codes, fraction/multiplier
  display forms, `min`/`max`/`midpoint`/`random` phrase forms. Each small.
* **The LiveView UI**, sheet persistence, export.

**Out of scope for v1**

* Inflation calculations (needs a CPI data source with licensing).
* Stock prices, weather, Wolfram|Alpha (API keys, ToS, cost).
* Soulver Studio equivalents, native integrations.

---

## 4. Product thesis

The concept is Soulver's. The expression is ours, and it rests on two things this stack does
that Soulver structurally cannot.

### 4a. It speaks your language, it doesn't merely format in it

```
de   1.234,5 Meter in Kilometer      →  1,2345 Kilometer
de   20 % von 700                    →  140
fr   10 juin + 3 semaines            →  1 juillet
ja   100 ドル を ユーロ で            →  €88.80
en   3 hours 15 min after 9:45am     →  1:00 pm
```

Switching the locale re-parses *and* re-formats the entire document. Dates come localized for
free, because `Calendrical.parse/2` is CLDR-pattern driven (§2).

### 4b. It answers the temporal questions people actually get stuck on

Soulver's date support answers **"when"** questions: what date is three weeks after this one,
how many days between these two. Those are the easy ones, and it does them well.

Tempo answers **"which"**, **"how many"**, **"when am I free"**, and **"could these both be
true"** — questions people currently solve by opening a spreadsheet, a calendar, and three
browser tabs. This is the part of the product that gets written about.

Results marked ✓ were run against Tempo 1.2.0 rather than assumed; the rest are shape, not
promised output.

```
# Availability — the distributed-team question
9–5 London ∩ 9–5 New York                    ✓ 3 hours (13:00–16:00 UTC)
9–5 London ∩ 9–5 Tokyo                       ✓ no overlap at all
9–5 New York ∩ 9–5 Tokyo                     ✓ no overlap at all
9am–5pm − lunch 12–1                         ✓ 2 windows: 09:00–12:00, 13:00–17:00
free on Tuesday = 9am–5pm − meetings.ics       every gap, with the meeting names attached

# Recurrence
every Friday the 13th from 2027              ✓ 13 Aug 2027 — and not again until 13 Oct 2028
last weekday of every month in Q1 2027       ✓ 29 Jan, 26 Feb, 31 Mar
4th Thursday of November                       Thanksgiving, as a rule rather than a lookup

# Working time, with the world's actual working weeks
is Friday a workday?                         ✓ yes in the US, no in Saudi Arabia
is Sunday a workday?                         ✓ no in the US, yes in Saudi Arabia
workdays in Q3 2026 minus public holidays      holiday names carried through from the .ics feed

# Dependency scheduling, in four lines
design = 5 days
build  = 10 days after design
test   = 3 days after build
launch                                         earliest finish + the critical path

# Uncertainty and history
circa 600 BCE                                  approximate, -0600
the 1560s                                      1560–1569, iterable
could these two reigns have overlapped         Allen relations over partially-known intervals

# Other calendars, first-class
15 Ramadan 1448 as a date
2026-06-15 in Hebrew
```

The London/Tokyo and New York/Tokyo results are worth dwelling on: for a team split across those
cities there is **no shared working hour at all**, and that is exactly the sort of thing people
currently work out wrongly on the back of an envelope. Answering it in one typed line is a
product, not a feature.

Every line above is a direct expression over Tempo's existing API — set algebra, `RRule.parse!/2`,
`select/2`, `Schedule`, `Network`, ISO 8601-2 uncertainty, 18 calendars. None of it is
speculative capability.

### 4c. Why the two halves reinforce each other

They come from the same root: this stack **models** locale and time where Soulver
**approximates** them. Territory-aware weekends are simultaneously a temporal feature and a
localization feature. Cross-calendar dates matter most to exactly the users who want to type in
Persian, Hebrew or Thai. The unit engine is a distant third differentiator (~2,760 units against
Soulver's ~200), but it is free.

---

## 5. Architecture

### 5.1 The value lattice

The evaluator is dynamically typed over a small union. Getting this right up front matters more
than anything else in the design.

| Type | Backing | Notes |
|---|---|---|
| `Number` | integer / float / `Decimal` | Decimal when money-adjacent, float for scientific |
| `Quantity` | `Localize.Unit.t()` | value + unit, including `-per-` compounds |
| `Money` | `Money.t()` | Decimal + currency code |
| `Percentage` | `%Percentage{value: Decimal}` | **contextual arithmetic — see below** |
| `Rate` | `%Rate{numerator: value, per: unit}` | `$99/week`, `30/week`, `90 km/day` |
| `Temporal` | `Tempo.t()` | **one type for dates, clock times, spans, masked and uncertain values, at any resolution and any of 18 calendars** |
| `TemporalSet` | `Tempo.IntervalSet.t()` | the result of recurrence, selection, and set algebra — *many* intervals, carrying metadata |
| `Duration` | `Tempo.Duration.t()` | `8 hours 35 min`; `Localize.Duration` formats it |
| `Boolean` | `true` / `false` | conditionals and comparisons |
| `Text` | binary | labels, comments, unparsed remainder |

`Percentage` truth table (from Soulver's documented behaviour — worth encoding as tests first):

| Expression | Result | Rule |
|---|---|---|
| `200 + 10%` | `220` | percent is relative to the left operand |
| `200 - 10%` | `180` | ditto |
| `10% + 20%` | `30%` | percent + percent stays percent |
| `30% + 0.4` | `70%` | a bare number is coerced to percent (1.0 = 100%) |
| `50% × 30` | `15` | multiplication always yields a plain number |
| `30 × 50%` | `15` | order-independent |
| `10% of 200` | `20` | phrase form |
| `10% off 200` | `180` | phrase form |
| `10% on 200` | `220` | phrase form |
| `20 is 10% of what` | `200` | inverse |
| `180 is 10% off what` | `200` | inverse — divide by 0.9, not add 10% |
| `50 to 75 is what %` | `50%` | change |
| `20% as dec` | `0.2` | coercion out |

### 5.2 The evaluation pipeline

Five stages per line. Only stages 2–4 are new language work.

```
raw line
  │
  ├─ 1. classify ────────► heading | comment | label+expr | declaration | subtotal | expression
  │
  ├─ 2. tokenize ────────► Localize.Number.Parser.scan/2 splits locale-correct numbers
  │                        from text runs; text runs matched against lexicons:
  │                          units (Unity.Aliases + Localize.Unit.Parser)
  │                          currencies (Money + Localize.Currency, locale-aware `$`)
  │                          dates/times/intervals (Calendrical.parse/2, as: :map)
  │                          timezones (Calendrical.TimeZone.resolve/3 + city/IATA table)
  │                          operator keywords (our lexicon, per locale)
  │                          document variables and line refs
  │                          → everything else becomes :noise
  │
  ├─ 3. phrase match ────► ordered rule table over the token stream, noise-skipping
  │                        e.g. [pct, :of, value] | [value, :is, :what, :pct, :off, value]
  │
  ├─ 4. expression parse ► Pratt / precedence-climbing over remaining tokens
  │
  └─ 5. evaluate + format ► value lattice → Localize/Money/Tempo formatters
```

Stage 2 is where `Calendrical.parse/2` earns its keep. Because it is whole-string anchored, we
cannot throw the raw line at it — but a *candidate span* of tokens can be re-joined and offered
to it, with `as: :map` so a partial match (`May 5`, `11 am`, `2026`) succeeds and returns
whatever fields it found. Greedy longest-span-first over candidate windows gives the
noise-tolerance we need without writing a date grammar. The one thing to watch: date parsing is
locale-*sensitive* by design — `3/4/26` is 3 April under `en-GB` and 4 March under `en-US` (verified) — so
the sheet's locale must be threaded into every parse call and re-parsing on locale switch is
mandatory, not cosmetic.

**[DECIDE] Parser technology.** My recommendation is to *not* extend Unity's NimbleParsec
grammar. NimbleParsec's committed-choice semantics fight two things this language needs:
noise-skipping recovery, and a lexicon that varies at runtime by locale (NimbleParsec
combinators are built at compile time). A hand-written tokenizer feeding a Pratt parser over a
token list gives us:

* runtime-swappable locale lexicons,
* trivial "ignore what you don't understand" recovery,
* phrase rules as ordinary Elixir pattern matches on token lists,
* per-token source spans for free, which the editor needs for highlighting and hover-to-peek.

Cost: we do not reuse Unity's `Unity.Parser` — perhaps 600 lines we re-derive. We *do* reuse
Unity's unit alias tables, GNU Units importer, unit math, and formatter, which is the expensive
part. Given `Localize.Unit` does the real unit work, the loss is smaller than it looks.

### 5.3 The lexicon

```
priv/lexicon/en.exs
priv/lexicon/de.exs
…
%{
  of:    ["of"],
  off:   ["off"],
  on:    ["on"],
  per:   ["per", "a", "each", "/"],
  to:    ["to", "in", "as", "->"],
  after: ["after", "from now"],
  ago:   ["ago", "before"],
  what:  ["what"],
  …
}
```

Deliberately **not** Gettext/MF2: these are input alternatives (many surface forms → one role),
not output messages (one msgid → one rendering). A plain data file with a validated shape is the
right vehicle. Everything derivable from CLDR is derived at runtime rather than duplicated here.

The lexicon is **operator words only**. Month names, weekday names, era markers, day periods,
date field order, timezone names and unit display names all come from CLDR at runtime — via
`Calendrical.parse/2` for the date side and `Localize.Unit` / `Localize.Currency` for the rest.
That is what keeps the per-locale authoring cost at roughly 120 entries rather than thousands.

Seed `en`. Then `de`, `fr`, `es`, `ja` as proof of the thesis.

### 5.4 Document model and recalculation

```elixir
%LocalizePad.Sheet{
  locale: :en,
  lines: [%Line{index: 0, source: "...", kind: :expression, tokens: [...],
                value: ..., error: nil, deps: MapSet.new([...])}],
  bindings: %{"cost" => %Money{}},
  graph: %{0 => MapSet.new([3, 7])}   # line → dependents
}
```

* Variables must be declared before use (Soulver 3 semantics). Redefinition shadows forward.
* Line references point only upward. Renaming a variable rewrites its referencing lines.
* Editing line *N* recomputes *N* plus its transitive dependents, not the whole sheet. At
  200 lines full recompute is also cheap — but the graph is needed anyway for unlink and
  rename, so build it once.
* **Library-code rule applies**: the engine returns `{:ok, value}` / `{:error, reason}` on every
  path. A malformed line renders as a line with no answer, never as a crash. No `{:ok, _} = …`
  anywhere near evaluation. This is a render path.

### 5.5 The temporal surface — and the one place we must diverge from Soulver

Tempo is the largest single source of capability in the app, and it brings a design problem
Soulver never had to solve: **its answers are frequently sets, not scalars.**

`every Friday the 13th in 2027` is two dates. `free on Tuesday` is three windows.
`workdays in Q3` is 63 discrete days that each carry identity. `last weekday of every month`
is a stream. A single answer-gutter cell — Soulver's entire output model — cannot hold any of
these honestly, and flattening them to a count (`2 dates`) throws away the thing the user
asked for.

This is the point where "our own expression of the concept" has to mean something concrete.
Options, roughly in increasing ambition:

* **Collapsed summary + expansion.** The gutter shows `2 dates`, `3 windows · 3h 45m`,
  `63 workdays`; clicking expands an inline panel beneath the line. Cheap, honest, and keeps
  the notepad rhythm intact. *Recommended for v1.*
* **Spill into following lines**, spreadsheet-style — the set materialises as read-only rows
  the user can reference individually. Powerful, but it fights the "one line, one answer" model
  and complicates the dependency graph.
* **A second pane.** A calendar/timeline strip that renders whatever the focused line evaluated
  to. This is the version people would screenshot, and the natural home for availability
  windows and recurrence. Right answer eventually; wrong thing to build first.

Two Tempo features to exploit deliberately:

* **`Tempo.explain/1`** returns a *structured* explanation with semantic part tags
  (`:headline`, `:span`, `:qualification`, `:metadata`) and a `to_iodata/1` formatter aimed at
  HTML. That is exactly the "why did I get this answer" affordance listed as a mitigation in
  §9 — already built, and it renders straight into LiveView.
* **Metadata survives set operations.** `Tempo.ICal.from_ical/2` carries each event's summary,
  location and attendees through intersection and difference. Intersect a schedule with work
  hours and you get back *which meetings* — so the expansion panel has something worth showing.

`.ics` import deserves a specific call-out as a product feature: *paste your calendar, ask when
you're free.* It is one function call (`Tempo.ICal.from_ical/2`), it needs no API key or OAuth,
and no notepad calculator on the market does it.

---

## 6. Phoenix / LiveView design

### 6.1 Shape

**[DECIDE] Project shape.** The current `localize_pad` is a bare `mix new` scaffold
(`lib/localize_pad.ex` with `hello/0`). Options:

* **(a) Single Phoenix app, engine as an isolated context** — `lib/localize_pad/` stays pure
  (no Phoenix deps, its own test suite), `lib/localize_pad_web/` holds the UI. Extract to a hex
  package later if it earns it. *Recommended* — least ceremony, keeps the seam visible.
* (b) Umbrella with `localize_pad` and `localize_pad_web` apps. More ceremony, same outcome.
* (c) Engine as a standalone hex library now, Phoenix app in a sibling repo. Right if the engine
  is the product and the web app is a demo — mirrors how `localize_playground` relates to
  `localize`.

If (a): regenerate with `mix phx.new localize_pad --live` over the existing directory.

Also note: this directory is **not currently a git repository**, so the mandatory
`.githooks/pre-commit` mix-format hook and the CI workflow cannot be set up yet. Both are
definition-of-done items once `git init` happens.

### 6.2 The editor

Soulver's interaction is two synchronised columns: editable text left, answers right, recalculating
on every keystroke with no equals key.

* **v1 — `<textarea>` + mirrored answer column.** Locked line-height between columns, answers
  rendered from the engine's per-line results. `phx-change` with `phx-debounce="150"`. Gets 90%
  of the feel for 10% of the work. Ship this first and use it to shake out the language.
* **v2 — CodeMirror 6 via `phx-hook`.** Buys syntax highlighting (token spans come free from
  stage 2), line references rendered as inline chips, hover-to-peek on variables, click-an-answer
  to insert a reference. Sends line-level diffs rather than whole-document changes.

Latency is the risk. Every keystroke round-trips to the server. Mitigations, in order:

1. Debounce at ~150ms.
2. Send only the changed line index plus a document version, not the whole buffer.
3. Keep answers in their own assign so LiveView diffs only the gutter.
4. Stream results per line so a slow line (an FX lookup) does not block the rest.

If that is not enough on mobile networks, the fallback is a WASM-compiled engine — which we do
not have and should not plan for. State the constraint honestly: this is a desktop-web-first app.

### 6.3 Localization plumbing

`localize_web` does essentially all of it: locale discovery plugs in the browser pipeline,
session persistence into the LiveView socket, `~q` verified localized routes, and
`Localize.HTML.Locale` for the locale picker. Changing locale re-runs stages 2–5 for the whole
document — the differentiator, and about ten lines of LiveView code.

The Gettext backend for UI chrome must use `interpolation: Localize.Gettext.Interpolation`, with
`~t` in Elixir and `t/1,2` in HEEx, MF2 msgids throughout.

### 6.4 Persistence

Ecto + Postgres from the start; sheets are the product, not an afterthought.

* `sheets` — id, user_id, title, locale, body (text), position, updated_at.
* `sheetbooks` — optional grouping, matching Soulver's model.
* Anonymous use writes to session/localStorage; sign-in migrates the working sheet.
* Export: Markdown and CSV first (trivial), PDF later.

---

## 7. What belongs upstream

Following the house rule that a gap at the leaf usually belongs at the root:

* **Calendrical — relative-date vocabulary.** `Calendrical.parse/2` handles absolute dates
  completely. Whether `yesterday` / `today` / `next Thursday` belong there (they are
  locale-vocabulary questions with CLDR backing in `dateFields`, so arguably yes) or in
  LocalizePad's lexicon is worth deciding once rather than twice. **[DECIDE]**
* **Calendrical — city and IATA resolution** alongside `TimeZone.resolve/3`. The CLDR exemplar-city
  half is locale data and sits naturally next to the existing zone resolver; the IATA table is
  ours and probably does not belong upstream.
* **Localize — currency symbol → code resolution keyed by locale** (`$` → AUD in `en-AU`).
  `Localize.Number.Parser.resolve_currency/2` exists; confirm it covers the ambiguous-symbol
  case before duplicating logic here.
* **Unity — make the unit-name resolution surface public.** LocalizePad needs `Unity.Aliases`
  and the GNU Units registry as a library API, decoupled from `Unity.Parser`.
* **Money — nothing.** `Money.Financial` covers the finance surface already.
* **Tempo — a constructor from a Calendrical field map.** `Calendrical.parse(…, as: :map)`
  yields partial field maps and Tempo's whole model is resolution-bearing intervals; a
  `Tempo.from_fields/2` that turns `%{year: 2026, month: 5}` into the May-2026 interval is the
  natural seam between the two, and better than round-tripping through an ISO string.

Everything else — the document model, phrase grammar, percentage type, rate type, lexicon —
belongs in LocalizePad. It is application language design, not i18n infrastructure.

---

## 8. Delivery plan

Each milestone ends with something demonstrable.

**M0 — Foundations. ✅ Done.** `git init`, `.githooks/pre-commit`, CI workflow with the standard
matrix and OTP-versioned cache keys, `mix phx.new`, dependency wiring, Gettext backend with the
Localize interpolator. Deliverable: an empty app that boots and passes CI.

Landed beyond the original scope, because they were cheap and foundational: the `localize_web`
locale-discovery plugs in the browser pipeline, a `RestoreLocale` `on_mount` hook so the locale
survives into the LiveView process, and six tests covering discovery, precedence and session
persistence. The CI matrix has **no OTP 25/26 rows** — Tempo requires OTP 27+ — which is a
deliberate deviation from the reference workflow.

**M1 — Engine skeleton, English only. ✅ Done.** Value lattice, tokenizer over
`Localize.Number.Parser.scan/2`, Pratt expression parser, numbers + units + arithmetic +
conversion. Line classification, variables, line references, dependency graph, subtotals.
Deliverable: `LocalizePad.Sheet.eval/2` handling Unity's example set line by line.

Built as `Tokenizer` → `Parser` → `Evaluator` → `Line` → `Sheet`. Two findings worth carrying
forward. First, the ambiguity of `in` (conversion keyword vs `inch`) cannot be settled
lexically, so tokens carry *both* readings and the parser picks by position — and the tiebreak
that makes `12 ft + 3 in` work is whether an operand follows. Second, treating a unit as an
ordinary operand meaning "one of these" collapses quantity, compound-unit and juxtaposition
nodes out of the AST entirely: `3 meters` is just `3 × meter`, and `m/s` is a division.

**M2 — The LiveView. ✅ Done.** Two-column textarea editor, debounced recalculation, running
total, locale picker via `localize_web`. Deliverable: the app is usable and shareable.

Column alignment is load-bearing and fragile: the text column must not soft-wrap, or a wrapped
line takes two rows on the left and one on the right and every answer below it drifts. Both
columns therefore share one font stack and line height, set from the same custom properties.

Deferred: styling the answer gutter from `Localize.Number.to_parts/2`. It is cosmetic until the
value lattice is richer, and worth doing when money and temporal answers need visual structure.

**M3 — Time, foundations. ✅ Done.** Moved ahead of money, because time is now the
headline. Wire
`Calendrical.parse/2` into stage 2 with span-candidate windows; adopt `Tempo.t()` as *the*
temporal value; relative-date vocabulary, nearest-year resolution, clock-time semantics
(including Soulver's ambiguous `5pm - 7pm`), durations, `Calendrical.Interval` for
quarter/month/week spans, `Kday` for weekday phrases, `TimeZone.resolve/3` plus the city/IATA
table. Deliverable: Soulver's dates and time pages pass — **and, because `Calendrical.parse/2`
is CLDR-pattern driven, they pass in every locale at the same time**, not just English.

Landed: the temporal scanner (candidate windows over raw text, offered to `Calendrical.parse/2`
with `as: :map`), `Tempo` as the temporal value, the nearest-year rule, date ± duration, the
span between two dates, `after`/`before` phrasing, and localized rendering of both dates and
durations. Durations needed no new machinery at all — `3 weeks` is already a `Localize.Unit`
quantity, so the unit engine supplies them and one small adapter turns them into
`Tempo.Duration`.

The shape filter turned out to be the whole game. `Calendrical.parse/2` will read `2026` as a
year and `11` as an hour, so an unfiltered scanner turns every number in every sheet into a
date. Two rounds of tightening were needed: the first version claimed `9.8` and `0.5` because
digit-separator-digit matches a decimal point. A separated date now requires *two* separators.
The cost is that `3/4` is not read as a date — correct, since it is genuinely indistinguishable
from division.

Clock-time spans landed too, and they resolve Soulver's documented ambiguity the same way it
does: `to` and `-` between two clock times both measure the gap, so `5pm - 7pm` and `5pm - 2pm`
agree at two hours, and a second time earlier on the clock means the following day
(`4pm to 3am` is eleven hours).

Timezone conversion works across cities, countries, airport codes and abbreviations —
`9am New York in London`, `6pm Sydney in Chicago`, `7:30am LAX in Japan`, `2am PST to GMT`. Two
findings shaped it. First, `Calendrical.parse/2` already captures a trailing zone string in its
field map without resolving it, so honouring that field got abbreviations and IANA names for
free. Second, and more important: **a zone is never a value on its own**. Were `Paris` a value,
every note mentioning a city would sprout a clock reading in the margin, so a bare zone is
declined and only `6pm Sydney` or `… in Chicago` means anything. The city table is curated
rather than derived from all 597 IANA zones, for the same reason — the derived tail is full of
names that collide with ordinary words.

Still outstanding in M3: `Calendrical.Interval` for quarter and week spans (currently declined
rather than guessed), and `Kday` weekday phrases (`next Thursday`).

**M4 — Percentages and money. ✅ Partly done.** The `Percentage` type against its truth table,
`Rate`, `Money` values, currency conversion with `Money.ExchangeRates`, sales tax, the
`Money.Financial` phrase forms. Deliverable: Soulver's percentage, currency, rates and finance
pages pass as tests.

Landed: the full percentage truth table — every row of it, including `30% + 0.4 = 70%` and
`50% × 30 = 15` — plus the `of`/`off`/`on` phrases, money recognition, money arithmetic, and
percentages applied to money and to quantities.

The governing decision on money mirrors the one on dates and zones. `Money.parse("19")` returns
nineteen US dollars, so using it would turn every number in every sheet into money; currency is
therefore only recognised when it is *written*, as a symbol or a code. And codes must appear in
capitals, because `ALL`, `TRY` and `CUP` are all ISO currencies as well as ordinary words —
which is what keeps `2 cup to mL` a volume rather than Cuban pesos.

`$` follows the reader: `Localize.Currency.currency_from_locale/1` gives USD for `en`, AUD for
`en-AU`, EUR for `de`. That is Soulver's region-settings behaviour, free from CLDR and working
for every locale rather than a handful.

Still outstanding in M4: the `Rate` type (`$99/week`), sales tax, and the `Money.Financial`
phrase forms (compound interest, mortgage repayments). Currency *conversion* is wired but
inert until an `OPEN_EXCHANGE_RATES_APP_ID` is configured; it reports the missing rate rather
than inventing a number.

**M5 — The temporal differentiator.** The `TemporalSet` value and the set-answer UI from §5.5
(collapsed summary + expansion). Then, in rough order of ratio of appeal to effort: timezone
overlap and "when are we all awake"; `.ics` paste-and-ask-when-I'm-free; recurrence
(`every Friday the 13th`, `4th Thursday of November`); territory-aware workdays and holidays;
`Tempo.explain/1` wired to the answer panel; dependency scheduling with critical path;
uncertainty and cross-calendar. Deliverable: the questions in §4b, answered, in a notepad.

**M6 — The localization thesis.** Localized operator lexicon for `de`, `fr`, `es`, `ja`. Locale
switch re-parses the document. Dates arrive already localized from M3, so this is purely about
operator vocabulary and phrase word-order — narrower than it first looked. Deliverable: the
other demo no notepad calculator can do.

M5 and M6 are the two thesis milestones; **their order is decision 3 below.** M5 is more
demonstrable and easier to write about; M6 compounds — every locale added multiplies the
addressable audience for everything built before it.

**M7 — Product.** Accounts, sheet persistence, sheetbooks, export, sharing, keyboard shortcuts,
CodeMirror editor, the timeline pane from §5.5. Deliverable: something deployable.

A conformance suite modelled on Unity's `guides/conformance.md` — every documented Soulver
example as an executable test, marked pass/fail/won't-do — is the honest way to track progress
and worth building during M1.

---

## 9. Risks and open questions

* **Ambiguity is the whole game.** `5pm - 7pm` means "2 hours" but `5 - 7` means `-2`. Soulver's
  own docs concede the minus operator is ambiguous with clock times. Every phrase rule added
  raises the chance of mis-parsing a line that used to work. Mitigation: the conformance suite,
  a "why did I get this answer" affordance showing the token classification, and
  `Tempo.explain/1` for the temporal half (§5.5).
* **Localized phrase order is not a translation of English phrase order.** `20 is 10% of what`
  has no word-for-word German form. The lexicon abstraction (keyword → role) handles vocabulary
  but not word order; some locales will need their own phrase rules, not just their own words.
  This is the deepest unknown in the plan and M6 should start with one non-English locale
  end-to-end before committing to four.
* **Tempo's surface is larger than any notepad should expose.** ISO 8601-2 masks, EDTF
  qualification, IXDTF annotations, RRULE, cron, chronological networks, constraint solving.
  The temptation is to surface all of it because it exists; the discipline is to expose only
  what answers a question someone actually types. Every temporal feature should enter through
  a phrase a user would write unprompted, not through an API we happen to have. §4b is that
  filter — if a capability cannot be written as a plausible notepad line, it stays internal.
* **Set-valued answers do not fit a Soulver-shaped gutter** (§5.5). This is a design problem,
  not an implementation one, and it needs resolving before M5 rather than during it.
* **Date parsing is locale-sensitive by design, and that will surprise people.** `3/4/26` is
  4 March under `en-GB` and 3 April under `en-US`; the same sheet shared between two users
  computes different answers. Correct, and the only defensible behaviour for a localized
  product — but the UI has to make the active locale visible rather than ambient, and shared
  sheets should carry their authoring locale.
* **Greedy date-span matching versus arithmetic.** Stage 2 offers candidate token windows to
  `Calendrical.parse/2`, which is whole-string anchored. `12/02/1988 + 32 years` must not have
  `12/02/1988 + 32` swallowed as a range, and `100/5` must not become a date. Window selection
  order and a cheap shape pre-filter matter here.
* **Read `cldr_locale_id`, never `language`, when deciding how to parse or format.** Localize is
  deliberately permissive: any *syntactically valid* language tag is accepted, and the returned
  `LanguageTag` carries two different things. `:language` preserves what the user asked for;
  `:cldr_locale_id` is the configured locale that actually supplies the data. So
  `validate_locale("not-a-locale")` succeeds with `language: :not` (a real ISO 639-3 code) but
  `cldr_locale_id: :en`, and `"pt-BR"` gives `language: :pt` with `cldr_locale_id: :en` when `pt`
  is not in `:supported_locales`. Only a genuinely invalid tag — `"zz-junk"` — is rejected.

  The consequence for us is good: a crafted `?locale=` cannot make a sheet parse under a locale
  we never configured, because the data always comes from a configured one. The trap is
  ours to avoid — any code that branches on the locale must read `cldr_locale_id`, since
  `language` may name a locale we have no data for.
* **LiveView keystroke latency** on poor connections (§6.2).
* **FX data**: Open Exchange Rates' free tier is USD-base only and rate-limited; historical
  rates and crypto may need a paid tier. Budget or scope decision.
* **Public holidays** depend on a third-party `.ics` feed (officeholidays.com). Fine, but it is
  an external runtime dependency on someone else's uptime and terms — cache aggressively, degrade
  to weekend-only workdays when the fetch fails, and check the terms before shipping commercially.
* **The local `unity` checkout (0.7.0) is behind hex (1.0.0).** Pull before building against it.

---

## 10. Decisions needed

1. **Project shape** — single Phoenix app with an isolated engine context (recommended),
   umbrella, or engine-as-library plus separate app?
2. **Parser technology** — hand-written tokenizer + Pratt parser (recommended), or extend
   Unity's NimbleParsec grammar?
3. **Which thesis leads?** M5 (temporal) or M6 (localization) first — see §8. My inclination is
   M5, because it is the more demonstrable of the two and the §4b lines are what a landing page
   is built from; but M6 compounds, and it is the one that is genuinely unassailable.
4. **Set-answer presentation** (§5.5) — collapsed-summary-plus-expansion (recommended for v1),
   spill-into-lines, or go straight to the second pane?
5. **Relative-date vocabulary placement** — `yesterday` / `next Thursday` in Calendrical
   (CLDR has `dateFields` backing) or in LocalizePad's lexicon?
6. **Persistence and accounts in v1**, or session-only until the language is good?

**Resolved:** Tempo is in, and not as a fallback for what Calendrical cannot do — it is the
temporal value type and the second pillar of the product (§4b, §5.5).
