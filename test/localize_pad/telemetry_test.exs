defmodule LocalizePad.TelemetryTest do
  use ExUnit.Case, async: false

  alias LocalizePad.{Sheet, Telemetry}

  doctest LocalizePad.Telemetry

  setup do
    handler = "test-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      Telemetry.refused_event(),
      fn _event, measurements, metadata, _config ->
        send(parent, {:refused, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok
  end

  defp refusals(source, locale \\ :en) do
    Sheet.new(source, locale: locale)

    collect([])
  end

  defp collect(acc) do
    receive do
      {:refused, _measurements, metadata} -> collect([metadata | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "what is reported" do
    test "a line that will not evaluate reports its category and shape" do
      assert [%{reason: :no_expression, shape: "number operator", locale: "en"}] = refusals("2 +")
    end

    test "the shape describes the grammar without the words" do
      # `in 3 weeks` is recognisable as a phrase form from `keyword number
      # unit` alone, which is the point: enough to act on, not enough to read.
      assert [%{reason: :unexpected, shape: "keyword number unit"}] = refusals("in 3 weeks")
    end

    test "a line that evaluates reports nothing" do
      assert refusals("19 + 22") == []
      assert refusals("jeden Montag", :de) == []
    end

    test "the locale is carried, narrowed to its language" do
      assert [%{locale: "de"}] = refusals("2 +", :de)
      assert [%{locale: "de"}] = refusals("2 +", :"de-AT")
    end

    test "an exception struct reports as its module" do
      assert [%{reason: Localize.UnitConversionError}] = refusals("3 m + 4 kg")
    end

    test "each failing line reports once" do
      assert length(refusals("2 +\n3 *\n19 + 22")) == 2
    end
  end

  describe "what is never reported" do
    # The promise the whole design rests on: the server does not keep what
    # anyone typed. Telemetry is the obvious place for that to stop being true
    # by accident, so it is asserted rather than assumed.
    test "no metadata value contains any word from the line" do
      secret = "supercalifragilistic"

      for metadata <- refusals("#{secret} 2 +") do
        for {_key, value} <- metadata do
          refute to_string(value) =~ secret
        end
      end
    end

    test "the word that stopped the parse is dropped, not passed through" do
      # The error itself is `{:unexpected, "in"}` — the most useful datum here
      # and also, literally, the user's text. Only the category survives.
      sheet = Sheet.new("in 3 weeks", locale: :en)
      assert [%{error: {:unexpected, "in"}}] = sheet.lines

      assert [%{reason: :unexpected} = metadata] = collect([])
      refute Map.has_key?(metadata, :source)
      refute metadata |> Map.values() |> Enum.any?(&(to_string(&1) =~ "in"))
    end

    test "a pasted essay cannot become an unbounded metric label" do
      shape =
        1..50
        |> Enum.map_join(" ", fn n -> "word#{n} #{n}" end)
        |> Kernel.<>(" +")
        |> refusals()
        |> List.last()
        |> Map.fetch!(:shape)

      assert length(String.split(shape, " ")) <= 12
    end
  end
end
