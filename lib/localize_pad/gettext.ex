defmodule LocalizePad.Gettext do
  @moduledoc """
  The engine's own translation backend, for the words it puts in answers.

  ## Why the engine has one at all

  Almost everything in an answer is already localized, because CLDR supplies
  it: the numbers, the dates, the unit names, the currency symbols. What is
  left is the handful of words this program writes itself — `yes`, `no`, and
  the `N dates` that heads a truncated set. Three strings, and until they went
  through here a German sheet answered a German question with `5 dates`.

  ## Why not the web backend

  `LocalizePadWeb.Gettext` already exists and is correctly configured, and
  reaching for it from `LocalizePad.Value` would have the engine depending on
  the web layer — the wrong way round for the part of this project most likely
  to be extracted as a library. The two share `priv/gettext` and separate by
  domain: `answers` is this one, the generated `errors` is Phoenix's.

  ## MF2, not Gettext plurals

  The interpolation module is `Localize.Gettext.Interpolation`, so messages are
  MessageFormat 2: placeholders are `{$name}` and plurals are a `.match` on a
  `:number` selector inside the translation. That matters here because plural
  categories are not the same shape in every language — a translator writing
  Russian needs `one`/`few`/`many`/`other` where English needs two — and MF2
  lets each locale's `.po` carry its own selector rather than forcing the
  source language's plural structure on all of them.

  """

  use Gettext.Backend,
    otp_app: :localize_pad,
    interpolation: Localize.Gettext.Interpolation
end
