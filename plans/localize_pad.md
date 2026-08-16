# LocalizePad — a conversational, localized notepad calculator

A plan for a Soulver-style notepad calculator built on Unity, Localize, Money and Tempo, deployed as a Phoenix/LiveView app.

Status: research + design. No code written yet. Decisions marked **[DECIDE]** need your call.

---

## 1. What Soulver actually is

Stripped of the Mac-app furniture, Soulver is four things layered on top of each other:

1. **A document model.** A sheet is a list of lines. Each line is text; each line may produce an answer shown in a right-hand gutter. Lines can be headings (`#`), comments (`//`, labels, parentheses, quotes), variable declarations, subtotals, or expressions. There is a running total, and subtotals that sum back to the previous subtotal or heading.

2. **A dependency graph.** Lines reference earlier lines' answers (spreadsheet-style, but positional rather than by cell). Variables are declared with `=` and may be redefined, incremented (`+=`), or assigned conditionally. Edit a line and everything downstream recalculates. References only point *upward*.

3. **A forgiving, phrase-oriented language.** This is the actual product. It is not an NLP system — it is a hand-tuned lexicon plus a large table of phrase patterns, with the crucial property that *unrecognised words are discarded rather than fatal*:

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

The vocabulary spans: percentages, units, currencies, rates, dates, clock times, time zones, workdays, compound interest, mortgages, sales tax, conditionals, proportions, bases and bitwise, permutations, random numbers.

4. **An answer-formatting policy.** Locale-correct number formatting, currency rounding rules, large-number symbols (`3k`, `5M`), scientific notation on request, unit pluralisation, duration rendering (`8 hours 35 min`).

Note what Soulver *does not* do: its input keywords are English-only. Its "region settings" only change how numbers are read and written (`.` vs `,`) — you cannot type `20 % von 700` or `10 juin + 3 semaines`. That is the opening.

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
| `agenda` | — | 0.1.0 | Resource-constrained scheduling on top of Tempo. Resources with attributes, places as a tree (travel time derived), requirements, programmes, a ledger with holds, preferences, minimal-conflict reporting, and a solver bridge. **Not a line-level engine** — see §7a |
| `calendrical` | 1.2.0 | 1.2.0 | **A complete locale-aware date/time/datetime/interval parser** (see below), 18 calendars, k-day functions, calendar intervals, timezone resolution, fiscal years, era handling |

Four specific primitives are worth calling out because they change the design:

* **`Localize.Number.Parser.scan/2`** splits an arbitrary string into numbers and text runs, locale-aware (correct decimal/grouping separators, digit transliteration for non-Latin number systems). `scan("The prize is 23") → ["The prize is ", 23]`. This is precisely the "scavenge the calculable bits out of prose" primitive Soulver's tokenizer needs, and it already exists.

* **`Calendrical.parse/2`** is a unified locale-aware parser that dispatches to date, time, datetime, or interval sub-parsers and returns the first success. It is driven by the locale's CLDR patterns for all four widths, so field order follows the locale by construction (`M/d/yy` in `en`, `dd.MM.y` in `de`, `Gy年M月d日` in Japanese imperial). It handles lenient separators via CLDR's `lenient-scope-date` equivalence classes, 2-digit year pivoting, non-Latin digit transliteration, era markers across 18 calendars, quarters (`Q2 2026`, `2nd quarter 2026`), week-of-year (`week 20 of 2026`), weekday prefixes (`Saturday, May 16, 2026`), and ranges split on CLDR's `intervalFormatFallback` separator.

Crucially it supports **`as: :map`, returning partial field maps** — `parse("May 5", as: :map)` yields `%{month: 5, day: 5}` with no year. That is precisely what Soulver's "dates with unspecified years" behaviour needs, and it means the nearest-year heuristic is ours to apply rather than something we must reverse-engineer out of a fully-resolved date.

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

* **`Localize.Number.to_parts/2`** returns ECMA-402-tagged segments (`:integer`, `:group`, `:currency`, `:percent_sign`, `:compact`, …). The answer gutter can style each part individually without re-parsing the formatted string.

Also free from CLDR via Localize: compact notation (`:short` → `3K`), scientific notation, currency display names and symbols, timezone exemplar city names, unit display names with plural forms, locale measurement-system preference.

---

## 3. Gap analysis

What we'd have to build, honestly assessed.

**Already covered — no work**

* Arithmetic, precedence, parentheses, functions, rationals, hex/octal/binary literals — Unity.
* Unit conversion and unit arithmetic — Unity + `Localize.Unit`. Our ~2,760 units against Soulver's "200+"; this is a straight win.
* Locale-correct number reading and writing, compact and scientific notation — Localize.
* Currency values, arithmetic, rounding, formatting, 190+ currencies plus crypto — Money.
* Live and historical exchange rates — `Money.ExchangeRates` (needs an `:open_exchange_rates_app_id`; free tier is USD-base only, which forces triangulation).
* Compound interest, present/future value, NPV, IRR, loan payment — `Money.Financial`.
* Calendar arithmetic, intervals, "days between", inclusive intervals, week numbers — Tempo. Materially *better* than Soulver: its docs hedge about month ambiguity, Tempo models it.
* Recurrence (`every Friday the 13th`, `4th Thursday of November`) — `Tempo.RRule`, full RFC 5545. Soulver has no recurrence at all.
* Set algebra over time — union, intersection, difference, complement, and the `overlaps?`/`contains?`/`subset?` predicates — cross-zone and cross-calendar. Underpins every availability question in §4b. Soulver has nothing comparable.
* Workday arithmetic with **territory-correct working weeks** — `Tempo.workday?/2`, `add_working_days/3`, `working_days_in/2`. Soulver hardcodes Monday–Friday; we get Sun–Thu for Saudi Arabia and Sat–Wed for Iran from CLDR.
* `.ics` import with metadata surviving set operations — `Tempo.ICal.from_ical/2`.
* Dependency scheduling and critical path — `Tempo.Schedule`. Constraint reasoning over partially-known intervals with a plain-English trace — `Tempo.Network`.
* Uncertain and approximate dates, masked years, open-ended intervals — ISO 8601-2 / EDTF, with the full `edtf-validate` corpus passing.
* **Reading dates, times, datetimes and date ranges in any locale** — `Calendrical.parse/2`. This is the single biggest correction to my first pass: I had it down as the largest thing to build and as an upstream contribution to Localize. It already exists, it is CLDR-pattern driven, and it covers 500+ locales and 18 calendars out of the box.
* `days in Q3`, `days in February 2020`, week and quarter spans — `Calendrical.Interval` returns `Date.Range` for year/quarter/month/week/day.
* `next Thursday`, `second Monday of March`, and the stepping primitive underneath workday arithmetic — `Calendrical.Kday` (`kday_after/before/nearest`, `nth_kday`, `first_kday`, `last_kday`).
* Timezone resolution from ISO offsets, `GMT±HH:MM`, IANA names, common abbreviations (`PST`, `JST`), **and CLDR localized zone names** (`Pacific Time`, `Mitteleuropäische Zeit` → `Europe/Berlin` under `:de`) — `Calendrical.TimeZone.resolve/3`, which also uses the wall-clock instant to pick between standard and daylight offsets.

**Must build — the real work**

* **The document layer.** Lines, classification (heading/comment/label/declaration/subtotal/ expression), line references, running total, subtotals scoped to the previous heading, dependency graph, incremental recalculation. None of this exists anywhere in the stack.
* **The conversational grammar.** Phrase forms (`X% of Y`, `A is what % off B`, `N is to M as P is to what`, `monthly repayment on … over … at …`, `time in Paris`, `3 weeks after March 14`). Noise tolerance. Unity's grammar is strict and fails the whole line on an unknown token.
* **A percentage value type.** Contextual semantics (`200 + 10%` = 220, but `10% + 20%` = 30%, and `50% × 30` = 15 as a plain number). This is Soulver's most-praised feature and the subtlest thing in the whole design. Deserves its own truth table.
* **A rate value type** carrying money or unitless numerators (`$99/week`, `30 bottles/week`). `Localize.Unit` handles unit-per-unit compounds; money-per-unit and number-per-unit are new.
* **Relative and deictic date phrases** — `yesterday`, `today`, `3 days ago`, `4 days from now`, `next Thursday`, `2 months 3 days after June 5`. `Calendrical` parses *absolute* dates; the relative vocabulary and the arithmetic phrasing around it are ours. The pieces underneath (`Kday` for weekday stepping, Tempo for the arithmetic) exist — this is lexicon plus phrase rules, not date engineering.
* **Nearest-year resolution** for partial dates. `Calendrical.parse("May 5", as: :map)` gives us `%{month: 5, day: 5}`; deciding whether that means this year or next (Soulver looks backwards a little and forwards a lot) is our policy to write.
* **City and airport-code → timezone mapping.** `Calendrical.TimeZone.resolve/3` handles zone names and abbreviations, but `6pm Sydney in Chicago` needs city→zone, and `7:30am LAX` needs an IATA table. CLDR's timezone exemplar-city data (reachable through `Localize.DateTime.Timezone`) covers the city half in every locale; IATA is a static table.
* **The localized keyword lexicon** — `of`, `off`, `on`, `per`, `to`, `in`, `after`, `ago`, `each`, `what`, `is`, `at`, `over`, `between`. CLDR has none of this. Roughly 120 entries per locale, hand-authored. This is the main new content cost and the core of the differentiator.
* **Public holiday plumbing** — fetching and caching, not the data. Tempo's holidays guide routes officeholidays.com `.ics` feeds (every UN-recognised country, updated weekly) through the same `Tempo.ICal.from_ical/1` we already need for calendar import, yielding an `IntervalSet` with holiday names on `:metadata`. So this is an HTTP fetch plus a cache, and it reuses one code path rather than adding a holiday library. Better than the `holidefs` route I first suggested.
* **Sales tax** — thin: a percentage plus a per-territory default table plus four phrase forms. `$300 - VAT` divides by 1.15, it does not subtract 15%; easy to get wrong.
* **Conditionals**, bitwise operators, video timecode, IATA airport codes, fraction/multiplier display forms, `min`/`max`/`midpoint`/`random` phrase forms. Each small.
* **The LiveView UI**, sheet persistence, export.

**Out of scope for v1**

* Inflation calculations (needs a CPI data source with licensing).
* Stock prices, weather, Wolfram|Alpha (API keys, ToS, cost).
* Soulver Studio equivalents, native integrations.

---

## 4. Product thesis

The concept is Soulver's. The expression is ours, and it rests on two things this stack does that Soulver structurally cannot.

### 4a. It speaks your language, it doesn't merely format in it

```
de   1.234,5 Meter in Kilometer      →  1,2345 Kilometer
de   20 % von 700                    →  140
fr   10 juin + 3 semaines            →  1 juillet
ja   100 ドル を ユーロ で            →  €88.80
en   3 hours 15 min after 9:45am     →  1:00 pm
```

Switching the locale re-parses *and* re-formats the entire document. Dates come localized for free, because `Calendrical.parse/2` is CLDR-pattern driven (§2).

### 4b. It answers the temporal questions people actually get stuck on

Soulver's date support answers **"when"** questions: what date is three weeks after this one, how many days between these two. Those are the easy ones, and it does them well.

Tempo answers **"which"**, **"how many"**, **"when am I free"**, and **"could these both be true"** — questions people currently solve by opening a spreadsheet, a calendar, and three browser tabs. This is the part of the product that gets written about.

Results marked ✓ were run against Tempo 1.2.0 rather than assumed; the rest are shape, not promised output.

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

The London/Tokyo and New York/Tokyo results are worth dwelling on: for a team split across those cities there is **no shared working hour at all**, and that is exactly the sort of thing people currently work out wrongly on the back of an envelope. Answering it in one typed line is a product, not a feature.

Every line above is a direct expression over Tempo's existing API — set algebra, `RRule.parse!/2`, `select/2`, `Schedule`, `Network`, ISO 8601-2 uncertainty, 18 calendars. None of it is speculative capability.

### 4c. Why the two halves reinforce each other

They come from the same root: this stack **models** locale and time where Soulver **approximates** them. Territory-aware weekends are simultaneously a temporal feature and a localization feature. Cross-calendar dates matter most to exactly the users who want to type in Persian, Hebrew or Thai. The unit engine is a distant third differentiator (~2,760 units against Soulver's ~200), but it is free.

---

## 5. Architecture

### 5.1 The value lattice

The evaluator is dynamically typed over a small union. Getting this right up front matters more than anything else in the design.

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

Stage 2 is where `Calendrical.parse/2` earns its keep. Because it is whole-string anchored, we cannot throw the raw line at it — but a *candidate span* of tokens can be re-joined and offered to it, with `as: :map` so a partial match (`May 5`, `11 am`, `2026`) succeeds and returns whatever fields it found. Greedy longest-span-first over candidate windows gives the noise-tolerance we need without writing a date grammar. The one thing to watch: date parsing is locale-*sensitive* by design — `3/4/26` is 3 April under `en-GB` and 4 March under `en-US` (verified) — so the sheet's locale must be threaded into every parse call and re-parsing on locale switch is mandatory, not cosmetic.

**[DECIDE] Parser technology.** My recommendation is to *not* extend Unity's NimbleParsec grammar. NimbleParsec's committed-choice semantics fight two things this language needs: noise-skipping recovery, and a lexicon that varies at runtime by locale (NimbleParsec combinators are built at compile time). A hand-written tokenizer feeding a Pratt parser over a token list gives us:

* runtime-swappable locale lexicons,
* trivial "ignore what you don't understand" recovery,
* phrase rules as ordinary Elixir pattern matches on token lists,
* per-token source spans for free, which the editor needs for highlighting and hover-to-peek.

Cost: we do not reuse Unity's `Unity.Parser` — perhaps 600 lines we re-derive. We *do* reuse Unity's unit alias tables, GNU Units importer, unit math, and formatter, which is the expensive part. Given `Localize.Unit` does the real unit work, the loss is smaller than it looks.

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

Deliberately **not** Gettext/MF2: these are input alternatives (many surface forms → one role), not output messages (one msgid → one rendering). A plain data file with a validated shape is the right vehicle. Everything derivable from CLDR is derived at runtime rather than duplicated here.

The lexicon is **operator words only**. Month names, weekday names, era markers, day periods, date field order, timezone names and unit display names all come from CLDR at runtime — via `Calendrical.parse/2` for the date side and `Localize.Unit` / `Localize.Currency` for the rest. That is what keeps the per-locale authoring cost at roughly 120 entries rather than thousands.

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
* Editing line *N* recomputes *N* plus its transitive dependents, not the whole sheet. At 200 lines full recompute is also cheap — but the graph is needed anyway for unlink and rename, so build it once.
* **Library-code rule applies**: the engine returns `{:ok, value}` / `{:error, reason}` on every path. A malformed line renders as a line with no answer, never as a crash. No `{:ok, _} = …` anywhere near evaluation. This is a render path.

### 5.5 The temporal surface — and the one place we must diverge from Soulver

Tempo is the largest single source of capability in the app, and it brings a design problem Soulver never had to solve: **its answers are frequently sets, not scalars.**

`every Friday the 13th in 2027` is two dates. `free on Tuesday` is three windows. `workdays in Q3` is 63 discrete days that each carry identity. `last weekday of every month` is a stream. A single answer-gutter cell — Soulver's entire output model — cannot hold any of these honestly, and flattening them to a count (`2 dates`) throws away the thing the user asked for.

This is the point where "our own expression of the concept" has to mean something concrete. Options, roughly in increasing ambition:

* **Collapsed summary + expansion.** The gutter shows `2 dates`, `3 windows · 3h 45m`, `63 workdays`; clicking expands an inline panel beneath the line. Cheap, honest, and keeps the notepad rhythm intact. *Recommended for v1.*
* **Spill into following lines**, spreadsheet-style — the set materialises as read-only rows the user can reference individually. Powerful, but it fights the "one line, one answer" model and complicates the dependency graph.
* **A second pane.** A calendar/timeline strip that renders whatever the focused line evaluated to. This is the version people would screenshot, and the natural home for availability windows and recurrence. Right answer eventually; wrong thing to build first.

Two Tempo features to exploit deliberately:

* **`Tempo.explain/1`** returns a *structured* explanation with semantic part tags (`:headline`, `:span`, `:qualification`, `:metadata`) and a `to_iodata/1` formatter aimed at HTML. That is exactly the "why did I get this answer" affordance listed as a mitigation in §9 — already built, and it renders straight into LiveView.
* **Metadata survives set operations.** `Tempo.ICal.from_ical/2` carries each event's summary, location and attendees through intersection and difference. Intersect a schedule with work hours and you get back *which meetings* — so the expansion panel has something worth showing.

`.ics` import deserves a specific call-out as a product feature: *paste your calendar, ask when you're free.* It is one function call (`Tempo.ICal.from_ical/2`), it needs no API key or OAuth, and no notepad calculator on the market does it.

---

## 6. Phoenix / LiveView design

### 6.1 Shape

**[DECIDE] Project shape.** The current `localize_pad` is a bare `mix new` scaffold (`lib/localize_pad.ex` with `hello/0`). Options:

* **(a) Single Phoenix app, engine as an isolated context** — `lib/localize_pad/` stays pure (no Phoenix deps, its own test suite), `lib/localize_pad_web/` holds the UI. Extract to a hex package later if it earns it. *Recommended* — least ceremony, keeps the seam visible.
* (b) Umbrella with `localize_pad` and `localize_pad_web` apps. More ceremony, same outcome.
* (c) Engine as a standalone hex library now, Phoenix app in a sibling repo. Right if the engine is the product and the web app is a demo — mirrors how `localize_playground` relates to `localize`.

If (a): regenerate with `mix phx.new localize_pad --live` over the existing directory.

Also note: this directory is **not currently a git repository**, so the mandatory `.githooks/pre-commit` mix-format hook and the CI workflow cannot be set up yet. Both are definition-of-done items once `git init` happens.

### 6.2 The editor

Soulver's interaction is two synchronised columns: editable text left, answers right, recalculating on every keystroke with no equals key.

* **v1 — `<textarea>` + mirrored answer column.** Locked line-height between columns, answers rendered from the engine's per-line results. `phx-change` with `phx-debounce="150"`. Gets 90% of the feel for 10% of the work. Ship this first and use it to shake out the language.
* ~~**v2 — CodeMirror 6 via `phx-hook`.**~~ **Superseded.** Syntax highlighting shipped without it, as a coloured layer *beneath* the textarea rather than a replacement for it. See below.

**Why not CodeMirror after all.** The plan assumed highlighting required an editor component. It required token spans, which is a different thing — and once those existed, the cheapest way to draw them was a `<pre>` behind a transparent textarea.

That keeps the property this whole layout rests on: the answer column is aligned against the textarea's own line boxes, and an editor that renders lines its own way puts that at risk. It also keeps IME, mobile keyboards, native undo and selection, all of which a custom editor re-implements imperfectly. What it gives up — bracket matching, inline chips, line-level diffs — is not what this language needs. CodeMirror remains available on top of the spans if a later feature earns it.

**Spans came from a problem the plan had written off.** `Localize.Number.Parser.scan/2` returns numbers already parsed, so `"02"` and `"2"` both arrive as `2` and the source text is unrecoverable. The tokenizer's moduledoc said as much and deferred offsets indefinitely.

The text is unrecoverable; the *span* is not. The text runs between numbers come back verbatim, so locating the next one leaves a gap, and the gap is exactly the number consumed there. `"02"` ends up with a token whose value is `2` and whose span is two bytes wide — which is what an editor wants, and what reconstructing the text from the value would have got wrong.

**Line numbers came last and are the smallest change with the clearest reason.** `@3` is the answer on line 3, and without a gutter the only way to find the number is to count. They number *every* physical line — blanks, headings, comments — because that is what `@n` counts; numbering only the lines with answers would look tidier and would be a lie the reader cannot catch, since `@3` would quietly resolve to something other than the row labelled 3. The gutter follows the text vertically and stays pinned horizontally, which is the one way it differs from the highlight layer.

**Highlighting is the engine's opinion, not a second one.** A highlighter that parses independently drifts, and a wrong colour is indistinguishable from a right one until the answer disagrees. Segments come from the same tokens the sheet was evaluated from. The fidelity is to the tokenizer, one stage short of the whole truth: `a` in "just a thought" colours as a keyword because it is CLDR's abbreviation for `year`, and the parser then discards it. The colour is a shade keener than the reading, and it errs towards showing what the engine considered rather than inventing a reading it never had.

Latency is the risk. Every keystroke round-trips to the server. Mitigations, in order:

1. Debounce at ~150ms.
2. Send only the changed line index plus a document version, not the whole buffer.
3. Keep answers in their own assign so LiveView diffs only the gutter.
4. Stream results per line so a slow line (an FX lookup) does not block the rest.

If that is not enough on mobile networks, the fallback is a WASM-compiled engine — which we do not have and should not plan for. State the constraint honestly: this is a desktop-web-first app.

### 6.3 Localization plumbing

`localize_web` does essentially all of it: locale discovery plugs in the browser pipeline, session persistence into the LiveView socket, `~q` verified localized routes, and `Localize.HTML.Locale` for the locale picker. Changing locale re-runs stages 2–5 for the whole document — the differentiator, and about ten lines of LiveView code.

The Gettext backend for UI chrome must use `interpolation: Localize.Gettext.Interpolation`, with `~t` in Elixir and `t/1,2` in HEEx, MF2 msgids throughout.

### 6.4 Persistence

Ecto + Postgres from the start; sheets are the product, not an afterthought.

* `sheets` — id, user_id, title, locale, body (text), position, updated_at.
* `sheetbooks` — optional grouping, matching Soulver's model.
* Anonymous use writes to session/localStorage; sign-in migrates the working sheet.
* Export: Markdown and CSV first (trivial), PDF later.

---

## 7a. Where Agenda fits

`agenda` sits one layer above Tempo: Tempo answers *when is this free*, Agenda answers *what should I book, and where*. It is the right engine for real-world scheduling, and it is the wrong engine for a notepad *line*.

The reason is that its questions need a world that a sheet does not have. "Which rooms seat at least eight and have video conferencing" presupposes a resource database, attributes, and a place tree; declaring one on a notepad line would turn the notepad into a booking app. `Tempo.Schedule` is the fit for the §4b scheduling line, which is dependency scheduling — durations and prerequisites, no resources — and Agenda's own README draws exactly that distinction.

Where Agenda *does* belong is a **scheduling sheet**: a second surface where a document declares resources and sessions and gets an arrangement back. That is a product direction rather than a feature, and the case for it is strong — `conflict/3` returning a *minimal* set ("any two of these three fit; choose which one moves") is the kind of answer no calendar app gives.

Two of its design principles are already this project's, which is worth noting because it means the two would compose rather than argue:

* **A failed match is a sentence, not a `false`.** `Agenda.explain/2` returns "Meeting room 2: seats is 4 — needs at least 8". That is the same instinct as rendering a masked year as "A masked year spanning the 1560s" rather than an ISO string.

* **Refusing to guess.** Unmeasured travel returns `{:error, :unknown}` rather than an estimate, and `expire/2` takes the moment as an argument rather than reading a clock — because arranging the same programme twice must not give different answers. That is the rule this engine has applied at every turn: a bare zone, a bare calendar, a missing exchange rate and a month-to-day conversion all decline rather than invent.

## 7. What belongs upstream

Following the house rule that a gap at the leaf usually belongs at the root:

* **Calendrical — relative-date vocabulary.** `Calendrical.parse/2` handles absolute dates completely. Whether `yesterday` / `today` / `next Thursday` belong there (they are locale-vocabulary questions with CLDR backing in `dateFields`, so arguably yes) or in LocalizePad's lexicon is worth deciding once rather than twice. **[DECIDE]**
* **Calendrical — city and IATA resolution** alongside `TimeZone.resolve/3`. The CLDR exemplar-city half is locale data and sits naturally next to the existing zone resolver; the IATA table is ours and probably does not belong upstream.
* **Localize — currency symbol → code resolution keyed by locale** (`$` → AUD in `en-AU`). `Localize.Number.Parser.resolve_currency/2` exists; confirm it covers the ambiguous-symbol case before duplicating logic here.
* **Unity — make the unit-name resolution surface public.** LocalizePad needs `Unity.Aliases` and the GNU Units registry as a library API, decoupled from `Unity.Parser`.
* **Money — nothing.** `Money.Financial` covers the finance surface already.
* **Tempo — a constructor from a Calendrical field map.** `Calendrical.parse(…, as: :map)` yields partial field maps and Tempo's whole model is resolution-bearing intervals; a `Tempo.from_fields/2` that turns `%{year: 2026, month: 5}` into the May-2026 interval is the natural seam between the two, and better than round-tripping through an ISO string.

Everything else — the document model, phrase grammar, percentage type, rate type, lexicon — belongs in LocalizePad. It is application language design, not i18n infrastructure.

---

## 8. Delivery plan

Each milestone ends with something demonstrable.

**M0 — Foundations. ✅ Done.** `git init`, `.githooks/pre-commit`, CI workflow with the standard matrix and OTP-versioned cache keys, `mix phx.new`, dependency wiring, Gettext backend with the Localize interpolator. Deliverable: an empty app that boots and passes CI.

Landed beyond the original scope, because they were cheap and foundational: the `localize_web` locale-discovery plugs in the browser pipeline, a `RestoreLocale` `on_mount` hook so the locale survives into the LiveView process, and six tests covering discovery, precedence and session persistence. The CI matrix has **no OTP 25/26 rows** — Tempo requires OTP 27+ — which is a deliberate deviation from the reference workflow.

**M1 — Engine skeleton, English only. ✅ Done.** Value lattice, tokenizer over `Localize.Number.Parser.scan/2`, Pratt expression parser, numbers + units + arithmetic + conversion. Line classification, variables, line references, dependency graph, subtotals. Deliverable: `LocalizePad.Sheet.eval/2` handling Unity's example set line by line.

Built as `Tokenizer` → `Parser` → `Evaluator` → `Line` → `Sheet`. Two findings worth carrying forward. First, the ambiguity of `in` (conversion keyword vs `inch`) cannot be settled lexically, so tokens carry *both* readings and the parser picks by position — and the tiebreak that makes `12 ft + 3 in` work is whether an operand follows. Second, treating a unit as an ordinary operand meaning "one of these" collapses quantity, compound-unit and juxtaposition nodes out of the AST entirely: `3 meters` is just `3 × meter`, and `m/s` is a division.

**M2 — The LiveView. ✅ Done.** Two-column textarea editor, debounced recalculation, running total, locale picker via `localize_web`. Deliverable: the app is usable and shareable.

Column alignment is load-bearing and fragile: the text column must not soft-wrap, or a wrapped line takes two rows on the left and one on the right and every answer below it drifts. Both columns therefore share one font stack and line height, set from the same custom properties.

Deferred: styling the answer gutter from `Localize.Number.to_parts/2`. It is cosmetic until the value lattice is richer, and worth doing when money and temporal answers need visual structure.

**M3 — Time, foundations. ✅ Done.** Moved ahead of money, because time is now the headline. Wire `Calendrical.parse/2` into stage 2 with span-candidate windows; adopt `Tempo.t()` as *the* temporal value; relative-date vocabulary, nearest-year resolution, clock-time semantics (including Soulver's ambiguous `5pm - 7pm`), durations, `Calendrical.Interval` for quarter/month/week spans, `Kday` for weekday phrases, `TimeZone.resolve/3` plus the city/IATA table. Deliverable: Soulver's dates and time pages pass — **and, because `Calendrical.parse/2` is CLDR-pattern driven, they pass in every locale at the same time**, not just English.

Landed: the temporal scanner (candidate windows over raw text, offered to `Calendrical.parse/2` with `as: :map`), `Tempo` as the temporal value, the nearest-year rule, date ± duration, the span between two dates, `after`/`before` phrasing, and localized rendering of both dates and durations. Durations needed no new machinery at all — `3 weeks` is already a `Localize.Unit` quantity, so the unit engine supplies them and one small adapter turns them into `Tempo.Duration`.

The shape filter turned out to be the whole game. `Calendrical.parse/2` will read `2026` as a year and `11` as an hour, so an unfiltered scanner turns every number in every sheet into a date. Two rounds of tightening were needed: the first version claimed `9.8` and `0.5` because digit-separator-digit matches a decimal point. A separated date now requires *two* separators. The cost is that `3/4` is not read as a date — correct, since it is genuinely indistinguishable from division.

Clock-time spans landed too, and they resolve Soulver's documented ambiguity the same way it does: `to` and `-` between two clock times both measure the gap, so `5pm - 7pm` and `5pm - 2pm` agree at two hours, and a second time earlier on the clock means the following day (`4pm to 3am` is eleven hours).

Timezone conversion works across cities, countries, airport codes and abbreviations — `9am New York in London`, `6pm Sydney in Chicago`, `7:30am LAX in Japan`, `2am PST to GMT`. Two findings shaped it. First, `Calendrical.parse/2` already captures a trailing zone string in its field map without resolving it, so honouring that field got abbreviations and IANA names for free. Second, and more important: **a zone is never a value on its own**. Were `Paris` a value, every note mentioning a city would sprout a clock reading in the margin, so a bare zone is declined and only `6pm Sydney` or `… in Chicago` means anything. The city table is curated rather than derived from all 597 IANA zones, for the same reason — the derived tail is full of names that collide with ordinary words.

Still outstanding in M3: `Calendrical.Interval` for quarter and week spans (currently declined rather than guessed), and `Kday` weekday phrases (`next Thursday`).

**M4 — Percentages and money. ✅ Done.** The `Percentage` type against its truth table, `Rate`, `Money` values, currency conversion with `Money.ExchangeRates`, sales tax, the `Money.Financial` phrase forms. Deliverable: Soulver's percentage, currency, rates and finance pages pass as tests.

Landed: the full percentage truth table — every row of it, including `30% + 0.4 = 70%` and `50% × 30 = 15` — plus the `of`/`off`/`on` phrases, money recognition, money arithmetic, and percentages applied to money and to quantities.

The governing decision on money mirrors the one on dates and zones. `Money.parse("19")` returns nineteen US dollars, so using it would turn every number in every sheet into money; currency is therefore only recognised when it is *written*, as a symbol or a code. And codes must appear in capitals, because `ALL`, `TRY` and `CUP` are all ISO currencies as well as ordinary words — which is what keeps `2 cup to mL` a volume rather than Cuban pesos.

`$` follows the reader: `Localize.Currency.currency_from_locale/1` gives USD for `en`, AUD for `en-AU`, EUR for `de`. That is Soulver's region-settings behaviour, free from CLDR and working for every locale rather than a handful.

Rates landed too, and they turned out to need far less than expected: `Localize.Unit` already models a quantity over a unit, so `90 km / 3 day` is a `kilometer-per-day` with no help from us, and only *money* over a unit needed a type — money not being a unit.

That work did surface one place where the right answer is a convention rather than a fact. `Localize.Unit.convert/2` refuses `month → day` and `year → day`, correctly: a month has no fixed length. But `$30/day in €/month` is a reasonable question that a notepad has to answer, or rates are useless for pay, rent and subscriptions — the domain people actually use them for. So `LocalizePad.Rate` states the Gregorian mean (365.2425 days a year, one twelfth of that a month) *in the application*, where the assumption belongs, rather than pushing it into Localize where it would become a claim CLDR does not make. The table agrees exactly with the conversions Localize does allow, so using it uniformly introduces no disagreement.

Sales tax landed, and it forced a small but structural change. Taking tax *off* a price is division by 1.15, not subtraction of 15% — £300 gross at 15% is £260.87 net, and subtracting would give £255. More awkwardly, `VAT on $300` ($45, treating the amount as net) and `VAT of $300` ($39.13, treating it as gross) are different answers to nearly the same sentence.

The operands cannot recover that distinction, so the preposition now survives into the AST as a `{:phrase, preposition, left, right}` node rather than being lowered to arithmetic in the parser. That is the right shape for a phrase language generally, and the percentage phrases moved onto it too.

The financial phrases landed last, and they needed the phrase-matching stage the plan called "stage 3" but nothing had yet required. `monthly repayment on $10,000 over 6 years at 6%` has three slots joined by `on`/`of`/`for`/`after`/`over`/`at`/`@` in any order — a grammar for which would be a large table of near-duplicates.

The way out is that the slots are unambiguous *by type*: exactly one money amount, one duration, one percentage, with no reading that could confuse them. So `LocalizePad.Finance` identifies the phrase from its noun and then takes each slot by type, ignoring the connectives entirely. It is the same forgiveness the rest of the language relies on, applied one level up — and it means phrasings nobody wrote down work anyway.

Every figure agrees with Soulver to the cent, loan repayments included.

Currency *conversion* remains wired but inert until an `OPEN_EXCHANGE_RATES_APP_ID` is configured; it reports the missing rate rather than inventing a number.

**M5 — The temporal differentiator. 🔨 In progress.** The `TemporalSet` value and the set-answer UI from §5.5 (collapsed summary + expansion). Then, in rough order of ratio of appeal to effort: timezone overlap and "when are we all awake"; `.ics` paste-and-ask-when-I'm-free; recurrence (`every Friday the 13th`, `4th Thursday of November`); territory-aware workdays and holidays; `Tempo.explain/1` wired to the answer panel; dependency scheduling with critical path; uncertainty and cross-calendar. Deliverable: the questions in §4b, answered, in a notepad.

Recurrence landed first — the clearest case of a question people ask that no notepad calculator has ever answered. `every Friday the 13th`, `4th Thursday of November`, `2nd Tuesday of every month`, `last weekday of every month`. Nothing about recurrence is implemented: phrases compile to RFC 5545 rule strings and Tempo does the work, so the module is mostly tables.

Weekday and month names come from CLDR through `Localize.Calendar`, which means the recurrence vocabulary is already localized — `jeden Freitag` will need only the operator words in M6, not a second list of weekday names.

One nice piece of disambiguation fell out: **where the ordinal sits decides what it means**. `4th Thursday` puts it before the weekday and means the fourth one; `Friday the 13th` puts it after and means the 13th day of the month. Position, not vocabulary — the same principle that settles `in` as keyword-or-inches.

Set answers render as a collapsed summary with the count *first* (`5 dates · Nov 13, 2026, …`), because the margin truncates from the right and "how many" is the part worth keeping.

The expansion is now built, and §5.5's three options resolved differently than expected. Neither "spill into following lines" nor a popover was needed: clicking an answer opens a panel *below* the sheet. Expanding in place would have been the obvious choice and the wrong one — the two columns are aligned line for line, and growing one row pushes every answer beneath it out of step with its text. A panel underneath cannot do that, and it generalises: it already shows the value's kind, and it is where `Tempo.explain/1` output and `.ics` event metadata will go.

Timezone overlap followed, and it is the §4b line: `9am to 5pm London and 9am to 5pm New York` answers "3 hours", and the Tokyo pairings answer "no overlap" — which is what a distributed team needs to know and currently works out wrongly on the back of an envelope.

Getting there needed one change of representation. A clock span was a duration; it is now an interval that *renders* as its length. The familiar answer is untouched — `7:30 to 20:45` is still "13 hours, 15 minutes" — but the endpoints survive, and comparing two spans becomes possible. Attaching a zone re-reads the same wall-clock times in that zone rather than shifting the instants, because 9am London moved to New York is New York's 9am, not 4am.

An empty overlap renders as "no overlap" rather than "0 hours": the question being asked is whether they meet at all, and a zero is too easily read as a rounding artefact.

The `and` operator required renumbering every binding power to make room beneath `to`, so that both operands are whole spans.

Workdays came next, and they are the clearest single case of §4c — the two halves of the product being the same thing. Soulver defines a workday as Monday to Friday, which is true in most of the world and wrong in a great deal of it. CLDR knows every territory's working week, Tempo reads it, and the territory comes from the sheet's own locale, so `is Friday a workday` answers **yes** for a reader in `en-US` and **no** for one in `ar-SA` with nothing configured. Sunday is the mirror image. A temporal feature that is only correct because it is localized.

`workdays from April 12 to June 15` counts 45, agreeing with Soulver. `December 24 + 2 workdays` gives December 28 where Soulver gives December 30, because Soulver counts Christmas and we do not yet have holidays — that gap has its own test so it cannot be forgotten.

Two smaller things fell out. The value lattice gained booleans and text, because `is Friday a workday` deserves a word rather than `true` and a weekday's name is an answer like any other. And the sheet's locale now travels *in the AST node* rather than being read from the process at evaluation time, which is what makes `day of the week on 24.01.1984` answer "Dienstag" under `:de` rather than "Tuesday".

Cross-calendar dates landed next, and they cost almost nothing because Calendrical implements all eighteen: `2026-06-15 in Hebrew` is "30 Sivan 5786", `in Coptic` is "Paona 8, 1742 AM", `in Julian` is thirteen days back. The answers are *localized* rather than transliterated — the same date on a `:ja` sheet reads `令和8年6月15日`, imperial era and all, because `Localize.Date` formats through CLDR's patterns for that calendar.

A calendar, like a zone, is never a value on its own: `Chinese`, `Indian` and `Japanese` are ordinary words, and `trip to Chinese restaurant` must stay a note.

Two findings worth carrying. Reading a date *written* in a non-Gregorian calendar works for Hebrew (`29 Kislev 5786` parses) but not for any of the Islamic variants, whose CLDR patterns Calendrical does not match against those month names — an upstream question rather than something to work around. And `Calendrical` **raises** rather than returning an error for dates outside the installed JPL ephemeris, which on a render path is a crash; the conversion is wrapped, and there is a test pinning it.

Uncertainty came next, and it brought `Tempo.explain/1` with it. `the 1560s` compiles to the masked year `156X`, `circa 600 BCE` to `-0600~`, and Tempo does the rest. Because a masked year has no single date to display, these render *as a description* — "A masked year spanning the 1560s." — which is more useful than any date could be, and is the "why did I get this answer" affordance §9 asked for, arriving as a side effect rather than as a feature.

The qualification is read from the struct rather than from Tempo's prose, which is written for a terminal and should not be parsed.

One collision worth recording: `s` is the CLDR abbreviation for `second`, so `the 1560s` arrived as the number 1560 beside a *unit* and rendered as "1,560 seconds". The decade matcher accepts either classification, and there is a test that `3 s to ms` is still 3,000 milliseconds.

**Deferred out of M5, deliberately.** `.ics` import with public holidays needs HTTP, a cache and an upload surface; dependency scheduling needs the Sheet to gather several lines and solve them together, which is the first document-*level* feature rather than a line-level one. Both are more temporal features on an already-strong temporal story, and M6 — half the product — was entirely unstarted. They come back after it.

**M6 — The localization thesis. ✅ Five locales.** Localized operator lexicon for `de`, `fr`, `es`, `ja`. Locale switch re-parses the document. Deliverable: the other demo no notepad calculator can do.

German first, as §9 said it should be. The whole sheet works:

```
1.234,5 Meter in Kilometer            1,2345 Kilometer
100 Kilometer in Meilen              62,137119 Meilen
3 Meter zu Fuß                          9,84252 Fuß
20 % von 700                                     140
10. Juni 2026 + 3 Wochen              1. Juli 2026
7:30 bis 20:45                 13 Stunden, 15 Minuten
99 EUR pro Woche                       99,00 €/Woche
```

**One gap had to be filled, and CLDR filled it.** `Localize.Unit` identifiers are English — `Localize.Unit.new(1, "Woche")` fails — so a German sheet could read `1.234,5` correctly and then be unable to say what it was 1234.5 *of*. But CLDR knows what a week is called in every locale, and turning `display_name/2` around gives a name-to-identifier index per locale built entirely from shipped data. `LocalizePad.Units` is that index. No German vocabulary is authored in it.

The only thing written by hand for German is a page of operator words. That is the claim, and it holds.

**Three findings.**

The index must *not* be consulted for English. Unity's alias table is the English vocabulary and is still narrower than CLDR — 95 of the index's English display names have no Unity alias, `kilocalories` and `arcminutes` among them — and consulting CLDR for English silently widened the vocabulary on every English sheet. Caught by the test written two milestones ago.

Names collide within a locale: `week` and `week-person` are both "Wochen". The index is built simplest-identifier-first and never overwrites, so the word resolves to what someone writing it means.

**Unity 1.1 derived plurals from the CLDR unit list, and the hand-written table of calendar plurals went with it.** `months`, `weeks` and `days` resolve on their own now, and the workaround that used to fill those gaps is deleted.

It widened the English vocabulary considerably as a side effect, and that is worth stating plainly rather than burying: `nights`, `cups`, `points`, `bars`, `stones`, `knots`, `drops`, `parts`, `bits` and `items` are all units now, where before only their singulars were. `hotel * 3 nights` is 360 nights rather than 360, and a quantity does not add into a plain subtotal.

The singulars were always units — what changed is that people write plurals, so the missing plurals had been accidentally protecting the "unrecognised words are noise" rule. The rule is narrower than it was.

This is recorded rather than worked around. The vocabulary is Unity's to define, and a table here second-guessing it is precisely what the last workaround was. If the reach turns out to be too wide in practice, the fix belongs upstream — an "everyday word" exclusion list in Unity, not a second opinion in this repo. The sample sheet was reworded off `3 nights` in the meantime.

And English `in` turns out to be *three* words, not two — the conversion keyword, the unit `inch`, and an ordinary preposition. All three parse, so nothing before evaluation can choose between them, and the guesses that had accumulated were wrong in both directions: `in 3 weeks` answered "3 inch-weeks" and `19 + 22 in cash` answered nothing at all.

Two rules settle it. A bare unit is not an expression, so the `inch` reading is unavailable where nothing can multiply it — which is exactly the line-leading position. And when the unit reading *does* parse but the units then disagree, the line is read again with the ambiguous words demoted to prose. `12 ft + 3 in total` keeps its inches because feet and inches agree; `19 + 22 in cash` gives them up because inches and a bare number do not.

This is the same lesson as the five CLDR collisions above, in its sharpest form: the reading that type-checks is the one that was meant, and that is knowable only after the arithmetic is attempted. A parser guessing alone will be wrong, and its wrong answers look like answers.

And the limit the plan predicted is real and now visible. `nach` is both "in" (conversion) and "after" (relative date); the lexicon maps one surface form to one role, so German keeps `nach` for "after" and uses `in` for conversion. Word *order* is the larger version — `20 is 10% of what` has no word-for-word German form — and that will need phrase rules per locale rather than vocabulary per locale.

**Recurrence phrases were the last English-only corner, and are now localized too.** `jeden Montag`, `chaque lundi`, `cada lunes` and `毎週月曜日` all answer. The day and month names were never the problem — CLDR had those all along. What was hardcoded was the word marking a phrase as recurring, the spelled ordinals, and the word for a working day; all three now live in the lexicon beside the operators.

The lists are longer than the operator ones because of inflection. A German ordinal agrees with its noun (`letzter`/`letzte`/`letzten`) and a French one with gender (`dernier`/`dernière`), and a lexicon that matches surface forms carries every form a person might type. That is dull and it is also the whole job: there is no morphological analyser here, and adding one to save thirty words would be a much larger thing to get wrong.

Two things fell out of it worth recording. Japanese needed no special handling at the phrase level at all — `毎週月曜日` segments into 毎週 and 月曜日 against the locale's own vocabulary, and from there it is ordinary tokens. And French forced one narrow exception to "names come from CLDR": `tous les lundis` is the natural phrasing and CLDR holds only `lundi`, so each day name also answers to itself plus an `s`. That is the same trailing-`s` heuristic that went badly wrong on units, kept safe by scope — seven entries added to a table of seven, inside a line already known to be a recurrence, rather than a retry against thousands of aliases.

**Japanese dates worked in Calendrical all along; this program was never handing it the string.** The candidate windows the scanner offers were split on whitespace, which is the entire story for a language that writes spaces and none of it for one that does not: `2026年7月3日は平日` arrives as a single run that is a date *and* a question, and no parser can be expected to take that. CJK dates are now carved out as candidates of their own before the whitespace split.

The shape filter needed a second rule rather than a wider one. The Latin rule demands *two* separators because `9.8` and `100/5` are ambiguous with arithmetic; 年月日 are not arithmetic in any language, so one marker already settles it and demanding two would have rejected `7月3日`. Two rules for two situations, rather than one rule stretched until it fits neither.

An earlier note here called this a gap in Japanese date *support*. That was the wrong shape of claim — the support existed, the plumbing did not.

**Still English-only: the answers.** A German sheet reads `jeden Montag` and answers `5 dates · 17.08.2026, …` — the dates are localized and the word "dates" is not. Fixing it means routing that summary through the Gettext backend (already configured with `Localize.Gettext.Interpolation`) as an MF2 message with a plural selector, and writing the catalogues. Not done here.

**French, Spanish and Japanese followed, and each tested something German could not.**

*French* needed the prefixed units German had got away without. `Localize.Unit.display_name/2` answers for prefixed identifiers — `kilometer` is "kilomètres" — but the prefixed forms are not in CLDR's unit list, so they have to be asked for by name. German hid this: "Kilometer" is the identifier `kilometer` but for its capital, and resolved through Unity's table by accident. `1234,5 mètres en kilomètres` failed until the index generated the prefixes people write against the units people prefix.

*Spanish* is where a word carries two meanings that are both legitimate: `mañana` is "tomorrow" and "morning". It is read as the date, which is what a calculation wants; the other reading needs context a single line does not carry.

*Japanese* broke the tokenizer outright — it has no word spaces, so whitespace splitting yields one enormous token. The first fix was a greedy longest-match against the vocabulary this program already knew, which worked on the example and was wrong in principle: an unknown word would be shattered a character at a time.

`unicode_string` is the real answer — UAX #29 word breaking with ICU's dictionaries for exactly the scripts that need them (Chinese, Japanese, Thai, Khmer, Lao, Burmese). It finds *actual* words rather than familiar ones. It is now a dependency, and the dictionaries are a download step in `mix setup` and a cache in CI.

It also had a bug, and a harmful one here. `Unicode.String.split("Japanese", break: :word, locale: "ja")` returned eight single letters, while the same call under `locale: "en"` correctly returned one word — the dictionary break was applied to the whole string rather than to the runs that need it. Single letters are disastrous in this engine because `J` is joule and `s` is second in Unity's abbreviation table, so `2026-06-15 → Japanese` produced a *wrong answer* rather than no answer.

**Fixed upstream in `unicode_string` 2.3.1**, and the script-partitioning workaround is deleted — `segment/2` calls `Unicode.String.split/2` directly and mixed-script text keeps each run's own boundaries without anything here knowing which script is which. The tests written against the workaround stay, because the failure they guard is the worst kind this program has: a plausible answer to a question nobody asked.

M5 and M6 are the two thesis milestones; **their order is decision 3 below.** M5 is more demonstrable and easier to write about; M6 compounds — every locale added multiplies the addressable audience for everything built before it.

**M7 — Product. 🔨 Everything but accounts.** Persistence, Markdown export, sharing, keyboard shortcuts, the timeline pane, syntax highlighting and the line-number gutter are done. **Deployed** at <https://pad.elixir-localize.com>. Outstanding: accounts, sheet persistence across devices, and sheetbooks.

**Windows of one session move together, and LiveView does not do that for you.** Every browser window is its own process with its own assigns; a shared session cookie changes nothing. Cross- window sync is always explicit — a PubSub topic per session, published to by every event that changes the document.

The topic is derived from a signed session cookie so it cannot be forged, and a request without an id publishes *nothing* rather than falling back to a shared topic. That default would have put strangers on one channel, which is the kind of bug that only shows up in production with real users on it.

**It costs a claim, and the docs were changed rather than the claim quietly dropped.** The server now sees sheet contents in transit where before it never did. It still stores none, and the sharing link is still a fragment the server never receives — but "a sheet never reaches the server" was true and is not any more.

Conflicts are last-write-wins with one rule on top: a window whose textarea has focus ignores incoming changes, because the person typing is the better authority for that moment. Without it the last window to render wins an argument with the one being used. Concurrent editing of the same line is not solved and would need a CRDT.

**Calendrical 1.2.1 made the failed-parse cost disappear.** The upstream fix landed after the measurements above were handed over: a failing parse went from ~15ms + 3.5ms per character to ~1.9ms flat, and `9am` — which pays a failed *date* parse before the time parser succeeds — went from 15.8ms to 1.8ms. The temporal example pad went from 1846ms to **293ms**.

The three scanner heuristics stayed. The prediction here was that they could come out once the upstream cost fell; measured, they should not. Each is a statement about dates rather than a speed trick — no date begins with `the`, none spans a `+`, and five words is the longest real date phrase — so removing them would cost speed and buy no correctness.

**Sheets open as well as save.** `Sheet.from_markdown/1` undoes what the exporter does — the answers are written as an aligned `//` column, and keeping them on the way in would mean the next export wrote them twice and the one after three times. The column is matched by the separator the exporter uses; a comment somebody typed with exactly that spacing is absorbed, and that is stated in the docs rather than hidden. A file with no fenced block is taken whole, because somebody pasting sums into a `.txt` has made a sheet.

The file is read in the browser and arrives as text, so an upload is an ordinary edit by the time the server sees it. No `allow_upload`, nothing in a temporary directory, and the promise that the server never receives a sheet survives a feature that looks like it should break it.

**The "is what" family closed the last gap against Soulver's documented examples.** These state the value and ask for a piece of the expression, which is the reverse of every other line in a sheet — `what` marks the hole, and which hole it is decides the arithmetic:

* `180 is what % of 200` → 90%, `180 is what % off 200` → 10%, `220 is what % more than 200` → 10%. The same two numbers, three answers, which is precisely why each is matched separately and a line naming none of the prepositions is refused rather than given a default. Guessing here would produce a confident wrong number, and these phrasings exist *because* people are unsure which way the operation goes.

* `20 is 10% of what` → 200. Same preposition as the first case; only the position of `what` separates asking for the share from asking for the whole.

* `$30/day is what per year` → $10,957.28/year, matching Soulver to the cent, because rate conversion already existed and this only had to ask it.

* `6 is to 60 as 8 is to what` → 80.

**And it is where vocabulary-per-locale finally stops being enough.** The words live in the lexicon like everything else, but the *order* — value, `is`, hole, preposition, value — does not carry, and swapping the vocabulary alone will not make `20 ist 10% von was` work. §6 predicted this limit; this is the feature that reaches it. Localizing these needs phrase rules per locale, which is a different and larger piece of work than adding words to a table.

**The example pads were also the first real performance measurement.** Loading the temporal one took six seconds, warm — and since every keystroke re-evaluates the whole sheet, typing in it would have been worse than loading it. All of the cost was in `LocalizePad.Temporal.Scanner`, none in parsing or evaluation.

The cause: a *failed* `Calendrical.parse/2` costs around 40ms where a successful one costs 2ms — it tries date, then time, then datetime, then interval, and builds a report of all four. The scanner was making dozens of failing calls per line.

Three rules cut it to under 2 seconds, and each is a real statement about dates rather than only an optimisation:

* **A window must *start* with something that can start a date** — a digit, a month or weekday name, a quarter marker, Han. The shape filter only asked whether a window *contained* one, so in `what day of the week is January 24, 1984` the windows beginning at `what`, `day`, `of` and `the` all reached far enough to include `January` and all got parsed. No date begins with `the`.

* **A window that spans a standalone operator is not a date.** `June 12, 2026 + 3 weeks` is a date and then some arithmetic. Requiring spaces around the operator is what keeps `2026-06-15` and `12/02/1988` intact.

* **The window cap dropped from six words to five.** Five is not arbitrary: `3 de julio de 2026` is the longest legitimate date phrase across the supported locales, and the suite says so — four broke Spanish. Every word above the true maximum is a wasted failed parse at every starting position of every line.

The remaining second is still failed parses, and the largest single lever now sits upstream: if a failed parse in Calendrical were as cheap as a successful one, this scanner would be roughly free.

**Six example pads ship in `priv/examples`, and the documentation is the pad.** Each is a working sheet whose own comments explain it, which is the only form of documentation here that cannot rot unnoticed: the suite evaluates every line of every example and fails the build when a claim stops being true. Writing them found two Soulver phrasings that do not work — `180 is what % off 200` and `$30/day is what per year`, both of the "is what" family — so they are absent rather than aspirational.

They also found the cost of Unity 1.1's wider vocabulary in practice. The first draft opened with `$240 for two nights at the hotel`, which fails: `nights` is a unit now, and money times a night is not a quantity that adds. The example was reworded; the vocabulary question stands.

Metadata comes from the files — locale from the `Locale:` line, title from the first heading — so there is no second place for an example's name to disagree with the sheet.

**The answers are now localized too, not just the numbers in them.** Almost everything in an answer comes from CLDR and was already right. What was left was the three strings this program writes itself — `yes`, `no`, and the `N dates` heading a truncated set — and a German sheet answering a German question with `5 dates` undercut the whole claim in one word.

They go through `LocalizePad.Gettext`, which is the engine's own backend rather than the web layer's: `LocalizePadWeb.Gettext` exists and is correctly configured, but reaching for it from `LocalizePad.Value` would point the engine at the web layer, the wrong way round for the part of this project most likely to be extracted as a library. The two share `priv/gettext` and separate by domain.

Three things fell out of doing it.

*Plural structure belongs to the locale, not to the source language.* The `~t` sigil stores an MF2 msgid, so each `.po` carries its own `.match` on a `:number` selector. English needs two branches, Japanese one, and Russian would need four — none of which the English source has to anticipate. Worth noting the branches for `one` cannot currently fire in any of the five: the summary only appears once the set exceeds the four dates the margin shows. They are kept because the count they gate is a translator's business rather than this file's, and because a locale with a `few` category would fire at counts this one never reaches.

*The count is formatted before it reaches the message.* Passing the integer would let the message format it a second time, in whatever locale Gettext resolved rather than the sheet's.

*Gettext does no parent-locale fallback.* A sheet in `de-AT` finds no `de-AT` catalogue and would answer in English, so the lookup narrows to the language subtag.

**Deployment: Fly.io, live.** What it implied concretely, none of it exotic but all of it easy to discover the hard way:

* **The generated `runtime.exs` raises on a missing `DATABASE_URL` in production**, and the repository sits in the supervision tree — so an app that never touches the database still refuses to boot without one. Nothing here reads or writes it until accounts arrive, so a missing database is now a configuration rather than a fault: the repository is configured when the variable is present and simply not started when it is not. This reverts when accounts land, and the comment in `runtime.exs` says so.

* `mix phx.gen.release --docker` for the release and Dockerfile, then `fly launch`.

* **Postgres** — `fly postgres create` and attach. Note the sheet does not currently use the database at all; it is there for the accounts work and can be skipped until then.

* **The word-break dictionaries must be downloaded at image build time.** They are not vendored, and `mix unicode.string.download.dictionaries` is already a step in `mix setup` and a cache in CI. Miss it in the Dockerfile and Japanese and Thai sheets silently fall back to reading a whole line as one token — the segmentation degrades rather than failing, which is the worst way to find out.

* **The JPL ephemeris that `astro` wants** turned out to need nothing: it ships inside the package at `deps/astro/priv/de440s-astro.bsp` (8.8MB), so Mix copies it into the release like any other `priv` file. It is cached in CI only because CI does not keep `deps/`.

* **`ca-certificates` is not in the generated Dockerfile's package list**, and both downloads are over HTTPS. Without it they fail and the image is quietly short of its data.

* `LOCALIZE_DEFAULT_LOCALE` and `PHX_HOST` are set in `fly.toml`; `SECRET_KEY_BASE` and `DATABASE_URL` are secrets set with `fly secrets set`.

* Sharing needs no session affinity — the sheet lives in the URL fragment and `localStorage` — so a single small machine is enough to start and scaling out needs no sticky sessions. It also makes `min_machines_running = 0` safe: nothing is lost when the last machine stops, so a cold start costs a few seconds and nothing else.

* **The image is large for a web app**, roughly 25MB of it CLDR data, ICU dictionaries and the ephemeris. That is data the app reads at runtime, not build leftovers, so it cannot be pruned from the runner stage.

**Sharing puts the whole sheet in the URL fragment.** No account, no row in a table, no record to rot — and a fragment is never sent in an HTTP request, so a shared sheet does not pass through the server's logs or a referrer header. Gzip plus URL-safe base64 gets a forty-line sheet into a 419-character link. The locale travels with the text, because `1.234,5` is a different number in `de` than in `en` and a link carrying only the characters would show the recipient different answers from the sender.

**The timeline pane draws whatever the selected line placed in time** — recurrence sets, clock spans, dates, zoned instants. Three decisions worth keeping:

* *The axis is snapped, not padded.* Rounding outwards to whole hours, days, months or years gives clean tick labels and honest breathing room at both ends from one decision.

* *Granularity follows the data, not the span.* A set of whole days is drawn against days even when it is only 24 hours long. An hour axis there would invent precision the answer does not have and label a date "12:00 AM".

* *An axis has one clock.* The overlap of two working days begins at 9am in New York and ends at 5pm in London; both instants are right, and drawing each against its own clock makes a three-hour overlap read as eight. Every instant is shifted into one zone before any label is written, and the pane says which.

**Session-only persistence, in `localStorage`.** A reload no longer loses the sheet, and no account is needed to start. The trade is that a sheet does not follow you between devices, which is the honest cost of not asking for an account before the first calculation. The session cookie would have been the smaller change and the wrong one: it caps at about 4 KB, which a working sheet exceeds sooner than anyone expects, and it fails by silently truncating.

**Markdown download**, and the format turned out better than a table. Answers are written as `//` comments — the sheet's *own* syntax for text the engine ignores — so the exported block pastes straight back in and evaluates to exactly what it says. A download is a save, and a save that cannot be reopened is a screenshot. There is a test that round-trips it.

Two details matter. The locale is recorded in the header, because `1.234,5` is a different number in `de` than in `en` and a sheet without its locale is ambiguous rather than portable. And sets are exported *whole* rather than as the margin's truncated summary — the margin has one line, a file does not.

A conformance suite modelled on Unity's `guides/conformance.md` — every documented Soulver example as an executable test, marked pass/fail/won't-do — is the honest way to track progress and worth building during M1.

---

## 9. Risks and open questions

* **Ambiguity is the whole game.** `5pm - 7pm` means "2 hours" but `5 - 7` means `-2`. Soulver's own docs concede the minus operator is ambiguous with clock times. Every phrase rule added raises the chance of mis-parsing a line that used to work. Mitigation: the conformance suite, a "why did I get this answer" affordance showing the token classification, and `Tempo.explain/1` for the temporal half (§5.5).
* **Localized phrase order is not a translation of English phrase order.** `20 is 10% of what` has no word-for-word German form. The lexicon abstraction (keyword → role) handles vocabulary but not word order; some locales will need their own phrase rules, not just their own words. This is the deepest unknown in the plan and M6 should start with one non-English locale end-to-end before committing to four.
* **Tempo's surface is larger than any notepad should expose.** ISO 8601-2 masks, EDTF qualification, IXDTF annotations, RRULE, cron, chronological networks, constraint solving. The temptation is to surface all of it because it exists; the discipline is to expose only what answers a question someone actually types. Every temporal feature should enter through a phrase a user would write unprompted, not through an API we happen to have. §4b is that filter — if a capability cannot be written as a plausible notepad line, it stays internal.
* **Set-valued answers do not fit a Soulver-shaped gutter** (§5.5). This is a design problem, not an implementation one, and it needs resolving before M5 rather than during it.
* **Date parsing is locale-sensitive by design, and that will surprise people.** `3/4/26` is 4 March under `en-GB` and 3 April under `en-US`; the same sheet shared between two users computes different answers. Correct, and the only defensible behaviour for a localized product — but the UI has to make the active locale visible rather than ambient, and shared sheets should carry their authoring locale.
* **Greedy date-span matching versus arithmetic.** Stage 2 offers candidate token windows to `Calendrical.parse/2`, which is whole-string anchored. `12/02/1988 + 32 years` must not have `12/02/1988 + 32` swallowed as a range, and `100/5` must not become a date. Window selection order and a cheap shape pre-filter matter here.
* **Read `cldr_locale_id`, never `language`, when deciding how to parse or format.** Localize is deliberately permissive: any *syntactically valid* language tag is accepted, and the returned `LanguageTag` carries two different things. `:language` preserves what the user asked for; `:cldr_locale_id` is the configured locale that actually supplies the data. So `validate_locale("not-a-locale")` succeeds with `language: :not` (a real ISO 639-3 code) but `cldr_locale_id: :en`, and `"pt-BR"` gives `language: :pt` with `cldr_locale_id: :en` when `pt` is not in `:supported_locales`. Only a genuinely invalid tag — `"zz-junk"` — is rejected.

The consequence for us is good: a crafted `?locale=` cannot make a sheet parse under a locale we never configured, because the data always comes from a configured one. The trap is ours to avoid — any code that branches on the locale must read `cldr_locale_id`, since `language` may name a locale we have no data for.
* **LiveView keystroke latency** on poor connections (§6.2).
* **FX data**: Open Exchange Rates' free tier is USD-base only and rate-limited; historical rates and crypto may need a paid tier. Budget or scope decision.
* **Public holidays** depend on a third-party `.ics` feed (officeholidays.com). Fine, but it is an external runtime dependency on someone else's uptime and terms — cache aggressively, degrade to weekend-only workdays when the fetch fails, and check the terms before shipping commercially.
* **The local `unity` checkout (0.7.0) is behind hex (1.0.0).** Pull before building against it.

---

## 10. Decisions needed

1. **Project shape** — single Phoenix app with an isolated engine context (recommended), umbrella, or engine-as-library plus separate app?
2. **Parser technology** — hand-written tokenizer + Pratt parser (recommended), or extend Unity's NimbleParsec grammar?
3. **Which thesis leads?** M5 (temporal) or M6 (localization) first — see §8. My inclination is M5, because it is the more demonstrable of the two and the §4b lines are what a landing page is built from; but M6 compounds, and it is the one that is genuinely unassailable.
4. ~~**Set-answer presentation** (§5.5)~~ — **resolved.** Collapsed summary in the margin, full value in a panel below the sheet. Not in place, because in-place expansion breaks the line-for-line column alignment the whole editor depends on.
5. **Relative-date vocabulary placement** — `yesterday` / `next Thursday` in Calendrical (CLDR has `dateFields` backing) or in LocalizePad's lexicon?
6. ~~**Persistence and accounts in v1**~~ — **resolved: session-only.** `localStorage`, plus a Markdown download that round-trips. Accounts and server-side sheets remain open.

**Resolved:** Tempo is in, and not as a fallback for what Calendrical cannot do — it is the temporal value type and the second pillar of the product (§4b, §5.5).
