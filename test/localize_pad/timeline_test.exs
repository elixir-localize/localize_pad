defmodule LocalizePad.TimelineTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Sheet, Timeline}
  alias LocalizePad.Temporal.Window

  doctest LocalizePad.Timeline

  defp timeline(source, options \\ []) do
    locale = Keyword.get(options, :locale, :en)
    [line | _rest] = Sheet.new(source, locale: locale).lines

    Timeline.build(line.value, locale: locale)
  end

  describe "what can be drawn" do
    test "a recurrence set becomes one mark per occurrence" do
      {:ok, timeline} = timeline("every Friday the 13th")

      assert length(timeline.marks) > 1
      assert Enum.all?(timeline.marks, &(&1.start >= 0.0 and &1.start <= 1.0))
    end

    test "a clock span becomes a single mark" do
      {:ok, timeline} = timeline("9am to 5pm")

      assert [%{label: label}] = timeline.marks
      assert label =~ "9:00"
      assert label =~ "5:00"
    end

    test "arithmetic has no place on an axis" do
      assert timeline("19 + 22") == :error
      assert timeline("3 meters to feet") == :error
      assert Timeline.build(nil, locale: :en) == :error
    end
  end

  describe "the axis" do
    test "marks sit in the order their dates do" do
      {:ok, timeline} = timeline("every Monday")

      starts = Enum.map(timeline.marks, & &1.start)
      assert starts == Enum.sort(starts)
    end

    test "evenly spaced dates are evenly spaced on the axis" do
      # The whole point of drawing it: `every Monday` is regular, and the
      # picture has to show that rather than merely list five dates.
      {:ok, timeline} = timeline("every Monday")

      gaps =
        timeline.marks
        |> Enum.map(& &1.start)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> Float.round(b - a, 3) end)

      assert Enum.uniq(gaps) |> length() == 1
    end

    test "an axis carries a readable number of ticks whatever its length" do
      for source <- ["9am to 5pm", "every Monday", "every Friday the 13th"] do
        {:ok, timeline} = timeline(source)

        assert length(timeline.ticks) in 2..9,
               "#{source} produced #{length(timeline.ticks)} ticks"
      end
    end

    test "a lone date is given context rather than filling the axis" do
      # Two ticks describe a length but not a position — a single date snapped
      # to its own day would run edge to edge and say only "somewhere in here".
      {:ok, timeline} = timeline("every Friday the 13th in 2027")

      assert [mark] = timeline.marks
      assert mark.start > 0.0
      assert mark.start + mark.width < 1.0
    end
  end

  describe "granularity" do
    test "whole days are drawn against days, not a clock" do
      # A date has no time of day in it. An hour axis would invent one, and
      # label the answer "12:00 AM".
      {:ok, timeline} = timeline("every Friday the 13th in 2027")

      assert timeline.unit == :day
      assert [%{label: label}] = timeline.marks
      refute label =~ "12:00"
    end

    test "a clock span is drawn against a clock" do
      {:ok, timeline} = timeline("9am to 5pm")

      assert timeline.unit == :hour
    end

    test "a long run of dates coarsens to months" do
      {:ok, timeline} = timeline("every last Friday of the quarter")

      assert timeline.unit in [:month, :day]
    end
  end

  describe "one axis, one clock" do
    test "a span whose ends are in different zones is drawn in a single zone" do
      # The overlap of two working days begins at 9am in New York and ends at
      # 5pm in London. Labelling each end against its own clock makes a
      # three-hour overlap read as eight.
      source = "9am to 5pm London and 9am to 5pm New York"
      [line | _rest] = Sheet.new(source, locale: :en).lines
      {:ok, timeline} = Timeline.build(line.value, locale: :en)

      assert line.formatted == "3 hours"
      assert timeline.zone == "America/New_York"

      assert [%{label: label}] = timeline.marks
      assert label =~ "9:00"
      assert label =~ "12:00"
    end

    test "an unzoned window stays in UTC" do
      {:ok, window} = Window.new(~T[09:00:00], ~T[17:00:00], date: ~D[2026-06-15])
      {:ok, timeline} = Timeline.build(window, locale: :en)

      assert timeline.zone == "Etc/UTC"
    end
  end

  describe "labels follow the locale" do
    # The recurrence phrases themselves are English-only for now, so these
    # build the value in English and draw it in German. That is the split the
    # module is responsible for anyway: positions come from instants and are
    # locale-independent, labels are not.
    defp drawn_in(source, locale) do
      [line | _rest] = Sheet.new(source, locale: :en).lines

      Timeline.build(line.value, locale: locale)
    end

    test "the same dates carry different words in different locales" do
      {:ok, english} = drawn_in("every last Friday of the quarter", :en)
      {:ok, german} = drawn_in("every last Friday of the quarter", :de)

      assert Enum.map(english.marks, & &1.start) == Enum.map(german.marks, & &1.start)
      refute Enum.map(english.ticks, & &1.label) == Enum.map(german.ticks, & &1.label)
    end

    test "each locale's own month abbreviations are used" do
      {:ok, german} = drawn_in("every last Friday of the quarter", :de)
      {:ok, french} = drawn_in("every last Friday of the quarter", :fr)

      assert Enum.any?(german.ticks, &(&1.label =~ ~r/Okt|Dez|Mär|Mai|Aug|Sep/))
      assert Enum.any?(french.ticks, &(&1.label =~ ~r/janv|févr|août|sept|oct|déc/))
    end

    test "a clock axis follows the locale's own time format" do
      {:ok, window} = Window.new(~T[09:00:00], ~T[17:00:00], date: ~D[2026-06-15])
      {:ok, english} = Timeline.build(window, locale: :en)
      {:ok, german} = Timeline.build(window, locale: :de)

      # English uses a 12-hour clock and German a 24-hour one, so the same
      # window is labelled differently without anything here knowing that.
      assert Enum.any?(english.ticks, &(&1.label =~ "PM"))
      refute Enum.any?(german.ticks, &(&1.label =~ "PM"))
    end
  end
end
