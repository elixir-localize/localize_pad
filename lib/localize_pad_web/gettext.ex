defmodule LocalizePadWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext), your module compiles translations
  that you can use in your application. To use this Gettext backend module,
  call `use Gettext` and pass it as an option:

      use Gettext, backend: LocalizePadWeb.Gettext

  Messages are written in [MessageFormat 2](https://messageformat.unicode.org),
  not Gettext's legacy interpolation. Placeholders are `{$name}` rather than
  `%{name}`, inline markup is `{#tag}…{/tag}`, and plural or select behaviour
  uses an MF2 `.match`. The `interpolation: Localize.Gettext.Interpolation`
  option below is what routes messages through Localize, so CLDR plural rules
  and locale-aware number and date formatting apply inside a translation.

  Prefer the sigil and macro over the raw Gettext functions:

  * `~t` from `Localize.Message.Sigils` for translatable strings in Elixir
    code. Activate it with `use Localize.Message.Sigils, backend:
    LocalizePadWeb.Gettext` in the calling module.

  * `t/1,2` from `Localize.HTML` for translatable body content in HEEx.

  Both extract canonical MF2 msgids at compile time and look them up through
  the interpolator configured here.

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext.Backend,
    otp_app: :localize_pad,
    interpolation: Localize.Gettext.Interpolation
end
