# LocalizePad

A notepad calculator — type a problem the way you'd write it on paper, get the answer in the
margin — built on the Localize stack and deployed as a Phoenix/LiveView app.

The concept is [Soulver](https://soulver.app)'s. What makes this one different is two things
Soulver structurally cannot do:

* **It reads your language, it doesn't merely format in it.** `1.234,5 Meter in Kilometer`,
  `20 % von 700`, `10 juin + 3 semaines`. Switching locale re-parses *and* re-formats the whole
  sheet, across 500+ CLDR locales and 18 calendars.

* **It answers the temporal questions people actually get stuck on.** Not just "what date is
  three weeks from Tuesday", but "when are London, New York and Tokyo all at work"
  (they never are), "every Friday the 13th from 2027", "when am I free on Tuesday given this
  `.ics`", "is Friday a workday" (yes in the US, no in Saudi Arabia).

See [plans/localize_pad.md](plans/localize_pad.md) for the full design and delivery plan.

## The stack

| Library | Role |
|---|---|
| [`localize`](https://hex.pm/packages/localize) | CLDR formatting, locale-aware number parsing, MF2 messages |
| [`calendrical`](https://hex.pm/packages/calendrical) | Locale-aware date/time/interval parsing across 18 calendars |
| [`ex_tempo`](https://hex.pm/packages/ex_tempo) | The temporal value type — intervals, set algebra, recurrence, scheduling |
| [`unity`](https://hex.pm/packages/unity) | The unit engine — ~2,760 units and unit arithmetic |
| [`ex_money`](https://hex.pm/packages/ex_money) | Currencies, exchange rates, financial functions |
| [`localize_web`](https://hex.pm/packages/localize_web) | Locale discovery plugs, localized routes, HTML helpers |
| [`unicode_string`](https://hex.pm/packages/unicode_string) | UAX #29 word segmentation, with ICU dictionaries for scripts written without spaces |

## Getting started

```bash
mix setup
```

That fetches dependencies, downloads CLDR locale data for the configured
`:supported_locales` and the Unicode word-break dictionaries, creates the
database, and builds assets. Then:

```bash
mix phx.server
```

The app runs at [`localhost:4000`](http://localhost:4000).

## Development

```bash
mix test
```

```bash
mix precommit
```

`mix precommit` compiles with warnings as errors, checks for unused deps, formats, and runs the
suite — the same ground CI covers.

### Pre-commit hook

The repository ships a `mix format` pre-commit hook. It is wired automatically for this working
copy; on a fresh clone, enable it with:

```bash
git config core.hooksPath .githooks
```

### Requirements

Elixir 1.17+ on **OTP 27 or later** — Tempo does not support OTP 26. The canonical development
toolchain is Elixir 1.20 on OTP 29, which is also CI's lint row.

## Configuration

Locale behaviour is configured in `config/config.exs` under `:localize`. The application-wide
default locale can be overridden at deploy time with the `LOCALIZE_DEFAULT_LOCALE` environment
variable.

Currency conversion needs an [Open Exchange Rates](https://openexchangerates.org) app id, set
via `OPEN_EXCHANGE_RATES_APP_ID`. Without it the app runs normally; currency *conversion* is
simply unavailable.

## License

Not yet chosen. The libraries this app is built on are Apache-2.0, but LocalizePad is an
application rather than a library and its licensing is a separate decision.
