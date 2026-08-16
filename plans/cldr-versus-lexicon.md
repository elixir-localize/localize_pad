# How much of the localized expression is CLDR, and how much is a hand-authored lexicon

The thesis behind LocalizePad is that a locale can be added for a page of operator words rather than a translation project, because everything *except* those words comes from CLDR. This is the measurement of that claim.

## The answer

Roughly **300 to 1**. CLDR supplies around fourteen thousand strings per locale; the pad authors about fifty words and four translated sentences.

| | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| CLDR strings supplied | 14,725 | 14,987 | 14,186 | 13,913 | 13,749 |
| hand-authored input vocabulary | 54 | 65 | 49 | 52 | 47 |
| MF2 messages needing translation | 4 | 4 | 4 | 4 | 4 |

## What CLDR supplies, by area

Counted as distinct strings reachable under each key of the locale's own data, via `Localize.Locale.get/3`.

| area | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| dates — calendars and zone names | 10,081 | 9,811 | 9,669 | 9,708 | 10,306 |
| units | 2,298 | 3,120 | 2,329 | 2,224 | 1,604 |
| currencies | 1,182 | 952 | 1,071 | 943 | 735 |
| languages | 690 | 649 | 660 | 584 | 658 |
| territories | 316 | 310 | 311 | 309 | 311 |
| number formats | 108 | 95 | 96 | 95 | 89 |
| list formats | 36 | 36 | 36 | 36 | 32 |
| lenient parse | 14 | 14 | 14 | 14 | 14 |

Month names, weekday names, era markers, unit display names and their plurals, currency names and symbols, decimal and grouping separators, date field order, plural rules and list formats are all in there. None of it is authored here.

## What the pad authors

`LocalizePad.Lexicon`, counted as distinct surface forms per locale.

| table | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| operators — `to`, `per`, `of`, `after`, `before` | 20 | 13 | 8 | 8 | 10 |
| recurrence — `every`, spelled ordinals, workday | 16 | 29 | 21 | 25 | 22 |
| deictics — `today`, `tomorrow`, `yesterday`, `now` | 4 | 4 | 4 | 4 | 4 |
| preference targets — `preferred`, `local` | 3 | 7 | 7 | 6 | 3 |
| usages — `height`, `weight`, `fluid`, `road` | 8 | 7 | 6 | 6 | 5 |
| totals — `sum`, `summe`, `somme`, `合計` | 3 | 5 | 3 | 3 | 3 |
| **total** | **54** | **65** | **49** | **52** | **47** |

Recurrence dominates outside English because inflection has to be listed rather than derived: a German ordinal agrees with its noun and a French one with its gender, so `erster`, `erste` and `ersten` are three entries for one idea. There is no morphological analyser, and adding one to save thirty words would be a far larger thing to get wrong.

## What translation actually costs

Four MF2 messages, in the `answers` domain: `yes`, `no`, the `{$count} dates` plural summary, and the refusal that asks for a tax rate to be declared. Three carry a translation in each of `de`, `fr`, `es` and `ja`; English falls back to the msgid.

Everything else the reader sees — every date, every unit name, every currency, every number — is CLDR rendering, not a translated string.

## The derived index, for scale

`LocalizePad.Units` builds a name-to-identifier index per locale entirely from CLDR display names, with no authoring at all. It is ten times the size of the whole hand-written lexicon:

| | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| unit names indexed | 479 | 463 | 524 | 575 | 417 |

That is what `3 Wochen`, `3 mètres` and `100キロメートル` resolve through, and it is why adding a locale does not mean writing down what a week is called.

## Where the ratio breaks

`LocalizePad.Temporal.Zones` carries **233 hand-authored English names** — 135 cities, 50 countries, 48 airports — and none of them are localized. That single table is more than four times the entire operator lexicon across all five languages, and it is the reason `9:00 Tokio in London` fails on a German sheet while `9:00 Tokyo in London` works.

It is also avoidable. CLDR ships exemplar cities in the locale data already downloaded — German alone carries 418 of them — under `dates.time_zone_names.zone`. Reaching them turns the largest authored table in the application into derived data, and localizes zone names as a side effect.

Two smaller authored lists are deliberate and stay: `Units.everyday?/1` holds 20 English words that are also unit names (`cup`, `stone`, `point`, `night`), and `LocalizePad.SalesTax` holds 3 (`vat`, `gst`, `sales tax`). Both are judgements about English prose rather than facts about units, which is why CLDR does not have them and should not.

## What could still be derived

Measured against CLDR 48.2.2 — none of this is authored today, and all of it could be.

**Deictics are fully derivable.** `date_fields.day.standard.relative_ordinal` carries the relative day names per locale: German gives `heute`, `gestern`, `morgen` and also `vorgestern` and `übermorgen`, which the hand table does not have. That is 4 authored words per locale replaced by data, with better coverage than we wrote.

**Spelled ordinals are derivable through RBNF**, but only by enumerating the inflected rule sets rather than calling `:spellout_ordinal`. German has `spellout_ordinal` plus `_m`, `_n`, `_r` and `_s`; French has masculine, feminine and their plurals; Spanish has no plain set at all, only `_masculine`, `_feminine` and `_masculine_adjective`. Generating 1..5 across a locale's sets reproduces almost the whole authored table, and for German produces 25 forms where 18 were written by hand — `erstem` and `erstes` are recognised by generation and missed today.

What generation cannot supply is `last` — `letzte`, `dernier`, `última` — which is not an ordinal number but a positional word, and French `second`/`seconde` as a synonym for `deuxième`. Those stay authored, at roughly three words per locale instead of twenty.

**Zone names are derivable** through `Localize.DateTime.Timezone.exemplar_city/3`, which implements the CLDR fallback: the locale's exemplar city, else the name derived from the IANA identifier. That retires the 233-name table described above.

Taken together these would take the authored lexicon to roughly 45 words per locale from 50, while *widening* what each locale recognises — the reduction is smaller than the coverage gain, which is the more interesting number.

**A Unicode inflector library is expected in September** and would act as a morphological analyser. That changes the calculus behind the inflection lists directly: `LocalizePad.Lexicon` currently notes that listing German case endings by hand is dull but correct, because "there is no morphological analyser here, and adding one to save thirty words would be a far larger thing to get wrong". With one available, the remaining inflected forms — and the recurrence table that is the largest authored block outside English — become generated rather than written.

## Method

The CLDR counts walk each locale's loaded data and count distinct binaries under the named key. The lexicon counts parse `lib/localize_pad/lexicon.ex` as an Elixir AST and count distinct string literals under each locale key, which is why they cannot be fooled by the nesting that an earlier regex-based count got wrong. Both are reproducible against the CLDR version the locale files were downloaded for; the figures above are CLDR 48.2.2 via `localize` 1.2.0.
