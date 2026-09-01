# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first version. Nothing has been tagged yet, so everything below is what 0.1.0 will be — see the [README](README.md) for what the project is and how to run it, and [plans/localize_pad.md](plans/localize_pad.md) for the design.

### Highlights

* **A sheet reads the reader's language rather than formatting in it.** `1.234,5 Meter in Kilometer`, `20 % von 700`, `10 juin + 3 semaines` — and changing the locale re-parses the whole sheet rather than restyling its answers.

* **The locale is a language tag, not a language.** `3/4/2026` is 3 April to an `en-AU` reader and March 4 to an `en-US` one, and `42.195 km in local units` answers in kilometres or miles accordingly.

* **A document model in plain text.** Headings, comments, labels, declarations, `@n` line references and a dependency graph, all in text that survives being pasted into a chat window and back.

* **Aggregates you type.** `sum`, `average`, `median`, `count`, `min` and `max`, each in the reader's own language — `Summe`, `moyenne`, `mediana`, `平均` — and several may stand together over one block.

* **Tags.** `#food` on a line, and `sum #food` or `average #food` reports on the lines carrying it, back to the previous heading.

* **Trip planning.** `trip from 3 March 2026` with `3 nights in Tokyo` under it gives every stop its own dates and says whether the itinerary fits the time budgeted — and `Reise ab 3.3.2026` with `3 Nächte in Tokio` does the same in German.

* **Units and money.** Around 2,760 units with conversion and unit arithmetic, currencies with live exchange rates, sales tax, and the financial phrases — loan repayment, present value, compound interest.

* **Temporal questions.** Dates across 18 calendars, durations, time zones and overlap windows, recurrence (`every Friday the 13th`), territory-aware workdays, and uncertainty.

* **Sun and moon.** Sunrise, sunset, moonrise, moonset and the phase of the moon, for a named place or for wherever the reader is, computed rather than looked up, and asked for as `Sonnenaufgang`, `lever du soleil`, `amanecer` or `日の出`.

* **A two-column editor.** Syntax highlighting drawn from the engine's own tokens, a gutter numbering every line, and answers aligned line for line with the text that produced them.

* **Sheets that travel.** Stored in the browser rather than on the server, shared through the URL fragment, exported as Markdown that can be opened again, nine worked examples in four languages, and a first sheet written natively in each of the five.

* **Every word you type is your own.** Operators, aggregates, trips, the almanac, sales taxes, the financial phrases and the qualifier on an approximate year all read the reader's language: `monatliche Rate auf 10.000 € über 6 Jahre zu 6 %` answers to the cent, as `MwSt`, `TVA`, `IVA` and `消費税` all do.
