# How much of the localized expression is CLDR, and how much is a hand-authored lexicon

The thesis behind LocalizePad is that a locale can be added for a page of operator words rather than a translation project, because everything *except* those words comes from CLDR. This is the measurement of that claim.

## The answer

Roughly **330 to 1**. CLDR supplies around fourteen thousand strings per locale; the pad authors about forty words and four translated sentences.

| | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| CLDR strings supplied | 14,725 | 14,987 | 14,186 | 13,913 | 13,749 |
| hand-authored input vocabulary | 46 | 47 | 41 | 37 | 39 |
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
| recurrence — `every`, workday, `last` | 11 | 14 | 15 | 13 | 17 |
| preference targets — `preferred`, `local` | 3 | 7 | 7 | 6 | 3 |
| usages — `height`, `weight`, `fluid`, `currency` | 9 | 8 | 8 | 7 | 6 |
| totals — `sum`, `summe`, `somme`, `合計` | 3 | 5 | 3 | 3 | 3 |
| **total** | **46** | **47** | **41** | **37** | **39** |

The deictics table is gone entirely — `today`, `tomorrow`, `yesterday` and `now` are read from CLDR's relative day and second fields. The spelled ordinals are gone too, generated from the locale's RBNF rule sets; German recurrence fell from 29 entries to 14 without a reader losing a single form they could type before.

What the ordinals table still holds is what no rule set spells. `last` — `letzte`, `dernier`, `última` — is a position rather than an ordinal number, so every locale needs it and none supplies it. French keeps `second`, which is a synonym for `deuxième` rather than a form of it. Japanese keeps `第1` through `第5`: the rule sets spell `第一` and its siblings, but a reader typing digits writes the other.

## What translation actually costs

Four MF2 messages, in the `answers` domain: `yes`, `no`, the `{$count} dates` plural summary, and the refusal that asks for a tax rate to be declared. Three carry a translation in each of `de`, `fr`, `es` and `ja`; English falls back to the msgid.

Everything else the reader sees — every date, every unit name, every currency, every number — is CLDR rendering, not a translated string.

## The derived index, for scale

`LocalizePad.Units` builds a name-to-identifier index per locale entirely from CLDR display names, with no authoring at all. It is ten times the size of the whole hand-written lexicon:

| | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| unit names indexed | 479 | 463 | 524 | 575 | 417 |

That is what `3 Wochen`, `3 mètres` and `100キロメートル` resolve through, and it is why adding a locale does not mean writing down what a week is called.

## What is now derived rather than written

Every row here was authored once and is not any more. The counts are what each locale actually recognises at runtime.

| derived at runtime | en | de | fr | es | ja |
|---|---:|---:|---:|---:|---:|
| currency names | 598 | 515 | 636 | 544 | 307 |
| zone city names | 60 | 60 | 60 | 60 | 60 |
| spelled ordinals | 6 | 28 | 17 | 24 | 12 |
| relative day names | 4 | 6 | 6 | 6 | 6 |
| day-of-week phrases | 2 | 1 | 1 | 1 | 2 |

The authored vocabulary fell by about a fifth, and German by more than a quarter. That is the less interesting half. What changed more is coverage.

German ordinals went from 18 written forms to **28** recognised, because the RBNF sets carry the whole case paradigm and a hand list carried what somebody thought of: `erstem` and `erstes` are understood now and were not. French relative days gained `après-demain` and `avant-hier`, German `übermorgen` and `vorgestern` — words the table never had, which now resolve to the days they name. Zone names work in the reader's language, so `Tokio`, `Londres`, `Nueva York` and `東京` all find their clock. And currency conversion accepts any of five hundred–odd names per locale without a word of it being written down.

`LocalizePad.Temporal.Zones` used to carry 233 hand-authored English names and now carries 20. Those 20 are not names CLDR could supply: `beijing` means `Asia/Shanghai`, `boston` means `America/New_York`, and `bogota` is what someone types when they will not reach for the accent. Which zones are worth naming is still a product judgement, and 60 identifiers say so; what they are *called* is CLDR's.

## What stays authored, and why

* **The operator lexicon** — `to`, `per`, `of`, `after`, `before`, `every`. CLDR has no table of the words people write when they mix arithmetic with prose, and this is the whole reason the project exists.

* **Working-day words** — `Werktag`, `Arbeitstag`, `ouvrable`. CLDR models *which days are the weekend*, per territory, and the pad uses that; it does not name the concept. `Werktag` appears zero times in the entire `common/` tree.

* **`last`** — `letzte`, `dernier`, `última`. A position, not an ordinal number; no rule set spells it.

* **Preference and usage targets** — `preferred`, `local`, `height`, `weight`, `currency`. These name what the reader wants the answer expressed *in*, which is a question about this application rather than a fact about the language.

* **Twenty everyday English words that are also units** (`cup`, `stone`, `point`, `night`) and three tax names (`vat`, `gst`, `sales tax`). Judgements about English prose, which is why CLDR does not have them and should not.

* **28 airport codes.** Genuinely not CLDR data.

## What could still be derived

* **`yes` and `no`.** CLDR carries them as `<messages><yesstr>ja:j</yesstr>`, documented in tr35-general as a colon-separated list of recognised responses — richer than a single string, so it would give answer *matching* as well as rendering. Localize does not currently ship that section: the locale data has 22 top-level keys and `messages` is not among them. It would take the MF2 count from four to two.

* **The remaining inflections.** A Unicode inflector library is expected in September and would act as a morphological analyser. What is left to inflect is now small — the ordinals came out with the RBNF rule sets — but the recurrence block still lists `jeden`, `jede`, `jedes` and `alle` for one idea, and the working-day words carry their own plurals. An analyser would take those too.

## Method

The CLDR counts walk each locale's loaded data and count distinct binaries under the named key. The authored counts parse `lib/localize_pad/lexicon.ex` as an Elixir AST and count distinct string literals under each locale key, which is why they cannot be fooled by the nesting that an earlier regex-based count got wrong. The derived counts are taken at runtime from the functions that build them, so they measure what a reader can actually type rather than what the source suggests.

All are reproducible against the CLDR version the locale files were downloaded for; the figures above are CLDR 48.2.2 via `localize` 1.2.0.
