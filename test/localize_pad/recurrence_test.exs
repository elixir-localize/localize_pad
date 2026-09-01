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

  describe "a stated month" do
    # `every Monday in June 2026` answered with the next five Mondays from
    # today, ignoring both the month and the year. It was not empty and it did
    # not raise — it was five plausible dates answering a question nobody had
    # asked, which is the kind that goes unnoticed.
    test "bounds the recurrence to that month" do
      assert dates("every Monday in June 2026") == [
               ~D[2026-06-01],
               ~D[2026-06-08],
               ~D[2026-06-15],
               ~D[2026-06-22],
               ~D[2026-06-29]
             ]
    end

    test "and its year comes with it, even though the scanner claimed both" do
      # `June 2026` reaches the rule builder as one temporal token rather than
      # as a month word beside a number, which is why the year was invisible.
      assert [~D[2027-03-02] | _rest] = dates("every Tuesday in March 2027")
    end

    test "a month with no year means the next one" do
      assert [%Date{month: 6} | _rest] = dates("every Monday in June")
    end

    test "and a phrase naming no month still counts from today" do
      # The repair must not reach the phrases it was not written for.
      assert [first | _rest] = dates("every Monday")
      assert Date.compare(first, Date.utc_today()) in [:gt, :eq]
    end

    test "in the reader's language too" do
      assert [~D[2026-06-01] | _rest] = dates("jeden Montag im Juni 2026", locale: :de)
    end
  end

  describe "the day the question is asked on" do
    # A rule naming its own month is the same rule whichever day it is read on,
    # and these pin that rather than leaving it to whatever date the suite
    # happens to run. Both of these answered *nothing at all* before: the
    # expansion built each candidate from the starting day of the month, so a
    # question asked on the 31st looked for the 31st of November.
    defp occurrences_on(source, reference) do
      {:ok, tokens} = LocalizePad.Tokenizer.tokenize(source, locale: :en)

      {:ok, {:recurrence, rule, from}} =
        Recurrence.match(tokens, locale: :en, reference_date: reference)

      {:ok, set} = Recurrence.occurrences(rule, from)

      set
      |> Tempo.IntervalSet.to_list()
      |> Enum.map(&(&1 |> Tempo.Interval.from() |> Tempo.to_date() |> elem(1)))
    end

    test "a November rule is answerable on the 31st of a month" do
      assert [~D[2026-11-26] | _rest] = occurrences_on("4th Thursday of November", ~D[2026-08-31])
      assert [~D[2026-11-26] | _rest] = occurrences_on("4th Thursday of November", ~D[2026-01-31])
    end

    test "and a February rule on the 29th, 30th and 31st alike" do
      # February is the strict case: every day past the 28th breaks it, so this
      # was wrong on three days a month rather than one.
      for reference <- [~D[2026-03-29], ~D[2026-03-30], ~D[2026-03-31]] do
        assert [~D[2027-02-09] | _rest] = occurrences_on("2nd Tuesday of February", reference)
      end
    end

    test "while a rule with no month of its own still counts from the day asked" do
      # The repair must not reach rules it was not written for: a weekly rule
      # starts on the day the reader asked, not three days earlier.
      assert [~D[2026-08-31] | _rest] = occurrences_on("every Monday", ~D[2026-08-31])
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

  describe "recurrence phrases in every lexicon locale" do
    defp weekdays(source, locale) do
      source
      |> dates(locale: locale)
      |> Enum.map(&Date.day_of_week/1)
      |> Enum.uniq()
    end

    test "`every Monday` is recognised in each locale's own words" do
      # The day names come from CLDR, so the only thing authored per locale is
      # the word that marks the phrase as recurring.
      assert weekdays("every Monday", :en) == [1]
      assert weekdays("jeden Montag", :de) == [1]
      assert weekdays("chaque lundi", :fr) == [1]
      assert weekdays("cada lunes", :es) == [1]
      assert weekdays("毎週月曜日", :ja) == [1]
    end

    test "a plural weekday works where the language uses one" do
      # `tous les lundis` is how a French speaker says it, and CLDR holds only
      # `lundi`.
      assert weekdays("tous les lundis", :fr) == [1]
      assert weekdays("every Mondays", :en) == [1]
    end

    test "spelled ordinals are recognised in each locale, inflections included" do
      # `letzten`, `dernière` and `última` are the same position in three
      # languages, and each is written several ways depending on what it
      # agrees with.
      for {source, locale} <- [
            {"last Friday of the month", :en},
            {"jeden letzten Freitag", :de},
            {"dernier vendredi du mois", :fr},
            {"último viernes del mes", :es}
          ] do
        assert weekdays(source, locale) == [5], "#{source} in #{locale}"
      end
    end

    test "an ordinal positions the occurrence, not just the day" do
      # `第二火曜日` is the *second* Tuesday, so consecutive dates are a month
      # apart rather than a week.
      assert [first, second | _rest] = dates("毎月第二火曜日", locale: :ja)

      assert Date.day_of_week(first) == 2
      assert Date.diff(second, first) > 21
    end

    test "one locale's vocabulary is not another's" do
      # The lexicons do not pool. `jeden` is not an English word and reading it
      # as one would make an English sheet quietly accept German.
      assert Sheet.new("jeden Montag", locale: :en).lines |> hd() |> Map.get(:value) == nil
      assert Sheet.new("every Monday", locale: :de).lines |> hd() |> Map.get(:value) == nil
    end

    test "a regional tag reads its language's lexicon" do
      # `de-AT` has no lexicon of its own and must not fall all the way back to
      # English.
      assert weekdays("jeden Montag", :"de-AT") == [1]
    end
  end
end
