defmodule LocalizePad.Examples do
  @moduledoc """
  The sheets that ship with the application.

  ## The documentation is the pad

  Each example is a working sheet whose own comments explain what it is doing.
  That is not a saving of effort — it is the only form of documentation for
  this program that cannot go stale unnoticed, because the examples are
  evaluated by the test suite and a claim that stops being true stops the build.

  A reader also gets to edit the explanation. Prose about a notepad calculator
  is a poor substitute for a notepad you can immediately change a number in.

  ## They are files, not literals

  `priv/examples/*.md` in the export format, so every one of them can be
  downloaded, re-opened and shared like anything else a person writes here, and
  so adding one needs no code. `priv` travels into the release, which is what
  makes them available to a deployment rather than only to a checkout.

  ## Metadata comes from the file

  The locale is the `Locale:` line the exporter writes, and the title is the
  sheet's first heading. Nothing about an example is recorded in this module,
  because a second place to state the title is a second place for it to
  disagree with the sheet.

  """

  alias LocalizePad.Sheet

  @directory "examples"

  @type t :: %{
          id: String.t(),
          title: String.t(),
          source: String.t(),
          locale: atom() | nil
        }

  @doc """
  Lists the bundled examples, in the order their filenames give.

  ### Returns

  * A list of maps with `:id`, `:title`, `:source` and `:locale`. A file that
    cannot be read or holds no sheet is skipped rather than raising — an
    example is content, and bad content must not take the page down.

  ### Examples

      iex> LocalizePad.Examples.all() |> Enum.map(& &1.id) |> Enum.member?("01-a-trip")
      true

  """
  @spec all() :: [t()]
  def all do
    case File.ls(directory()) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.sort()
        |> Enum.map(&load/1)
        |> Enum.reject(&is_nil/1)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Fetches one example by its id, which is its filename without the extension.

  ### Arguments

  * `id` - the example's id.

  ### Returns

  * `{:ok, example}`, or `:error` when there is no such example.

  ### Examples

      iex> {:ok, example} = LocalizePad.Examples.fetch("01-a-trip")
      iex> example.locale
      :en

      iex> LocalizePad.Examples.fetch("../../etc/passwd")
      :error

  """
  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(id) when is_binary(id) do
    # Matched against the listing rather than joined onto a path. The id
    # reaches this from a URL, and a path built from user input is how a
    # directory traversal starts.
    case Enum.find(all(), &(&1.id == id)) do
      nil -> :error
      example -> {:ok, example}
    end
  end

  def fetch(_id), do: :error

  defp directory do
    :localize_pad |> :code.priv_dir() |> Path.join(@directory)
  end

  defp load(entry) do
    with {:ok, contents} <- File.read(Path.join(directory(), entry)),
         {:ok, source, locale} <- Sheet.from_markdown(contents) do
      %{
        id: Path.rootname(entry),
        title: title(source, entry),
        source: source,
        locale: locale
      }
    else
      _unreadable -> nil
    end
  end

  # The sheet's own first heading, so the name in the picker is the name at the
  # top of the pad.
  defp title(source, entry) do
    source
    |> String.split("\n")
    |> Enum.find_value(Path.rootname(entry), fn line ->
      case Regex.run(~r/^\s*#\s+(.+)$/, line) do
        [_whole, heading] -> String.trim(heading)
        nil -> nil
      end
    end)
  end
end
