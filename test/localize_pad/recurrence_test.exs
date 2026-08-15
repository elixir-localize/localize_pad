defmodule LocalizePad.RecurrenceTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet
  alias LocalizePad.Temporal.Recurrence

  doctest LocalizePad.Temporal.Recurrence

  defp rule(source, locale \\ :en) do
    {:ok, tokens} = LocalizePad.Tokenizer.tokenize(source, locale: locale)
    {:ok, {:recurrence, rule, _from}} = Recurrence.match(tokens, locale: locale)
    rule
  end

  defp dates(source, options \\ []) do
    [line] = Sheet.new(source, Keyword.put_new(options, :locale, :en)).lines

    case line.value do
      %Tempo.IntervalSet{} = set ->
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&(&1 |> Tempo.Interval.from() |> Tempo.to_date() |> elem(1)))

      other ->
        other
    end
  end

  describe "compiling phrases to RFC 5545 rules" do
    # Nothing about recurrence is implemented here — the whole job is turning
    # English into a rule Tempo already understands.
    test "a weekly weekday" do
      assert rule("every Monday") == "FREQ=WEEKLY;BYDAY=MO;COUNT=5"
    end

    test "a day of the month that must fall on a weekday" do
      # `BYDAY` filters rather than selects once `BYMONTHDAY` is present, which
      # is what makes this "the 13th, but only Fridays".
      assert rule("every Friday the 13th") == "FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;COUNT=5"
    end

    test "an ordinal weekday of a named month" do
      assert rule("4th Thursday of November") == "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=5"
    end

    test "a spelled ordinal reads the same as a written one" do
      assert rule("fourth Thursday of November") == rule("4th Thursday of November")
    end

    test "the last weekday of the month" do
      assert rule("last weekday of every month") ==
               "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=5"
    end

    test "a stated year bounds the rule instead of counting occurrences" do
      assert rule("every Friday the 13th in 2027") =~ "UNTIL=2027-12-31"
    end
  end

  describe "where the ordinal sits decides what it means" do
    # `4th Thursday` puts the ordinal before the weekday and means the fourth
    # one; `Friday the 13th` puts it after and means the 13th day of the month.
    test "before the weekday is a position" do
      assert rule("2nd Tuesday of every month") == "FREQ=MONTHLY;BYDAY=2TU;COUNT=5"
    end

    test "after the weekday is a day of the month" do
      assert rule("every Friday the 13th") =~ "BYMONTHDAY=13"
    end
  end

  describe "the dates themselves" do
    test "Friday the 13th in 2027 happens exactly once" do
      assert dates("every Friday the 13th in 2027") == [~D[2027-08-13]]
    end

    test "Thanksgiving" do
      assert [~D[2026-11-26], ~D[2027-11-25] | _rest] = dates("4th Thursday of November")
    end
  end

  describe "not everything with a number is a recurrence" do
    test "ordinary arithmetic is untouched" do
      assert dates("2 + 2") == 4
    end

    test "a single date is not a recurrence" do
      assert dates("10 June") |> is_struct(Tempo)
    end

    test "date arithmetic is not a recurrence" do
      assert dates("June 12, 2026 + 3 weeks") |> is_struct(Tempo)
    end
  end

  describe "rendering a set of dates" do
    test "the margin gets the dates and a count when there are more" do
      formatted = Sheet.new("every Monday", locale: :en).lines |> hd() |> Map.fetch!(:formatted)

      # The count leads, because a margin truncates from the right and "how
      # many" is the part worth keeping when the list is cut short.
      assert formatted =~ "5 dates"
      assert formatted =~ "…"
    end

    test "a set that fits is listed without a count" do
      formatted =
        Sheet.new("every Friday the 13th in 2027", locale: :en).lines
        |> hd()
        |> Map.fetch!(:formatted)

      assert formatted == "Aug 13, 2027"
    end
  end
end
