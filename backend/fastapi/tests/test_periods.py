from datetime import date

import pytest

from app.reports.periods import PeriodError, previous_period, resolve_period


def test_monthly_handles_leap_years():
    assert resolve_period("monthly", year=2028, month=2).end == date(2028, 2, 29)
    assert resolve_period("monthly", year=2027, month=2).end == date(2027, 2, 28)
    p = resolve_period("monthly", year=2026, month=9)
    assert (p.start, p.end, p.label, p.days) == (date(2026, 9, 1), date(2026, 9, 30), "September 2026", 30)


def test_quarter_half_and_year_boundaries():
    q = resolve_period("quarterly", year=2026, quarter=4)
    assert (q.start, q.end, q.label) == (date(2026, 10, 1), date(2026, 12, 31), "Q4 2026")
    h = resolve_period("half_yearly", year=2026, half=1)
    assert (h.start, h.end) == (date(2026, 1, 1), date(2026, 6, 30))
    assert resolve_period("half_yearly", year=2026, half=2).start == date(2026, 7, 1)
    y = resolve_period("yearly", year=2026)
    assert (y.start, y.end, y.days) == (date(2026, 1, 1), date(2026, 12, 31), 365)


def test_weekly_starts_on_monday_and_daily_is_one_day():
    w = resolve_period("weekly", week_start=date(2026, 9, 9))          # a Wednesday
    assert (w.start, w.end) == (date(2026, 9, 7), date(2026, 9, 13))
    d = resolve_period("daily", day=date(2026, 9, 2))
    assert d.start == d.end == date(2026, 9, 2) and d.days == 1


def test_custom_and_complete():
    c = resolve_period("custom", date_from=date(2026, 8, 1), date_to=date(2026, 9, 30))
    assert c.days == 61 and c.label == "2026-08-01 to 2026-09-30"
    k = resolve_period("complete", data_first=date(2026, 8, 3), data_last=date(2026, 10, 25))
    assert (k.start, k.end, k.label) == (date(2026, 8, 3), date(2026, 10, 25), "Complete history")


@pytest.mark.parametrize("kwargs", [
    dict(kind="monthly", year=2026, month=13), dict(kind="monthly", year=2026, month=0), dict(kind="monthly", year=2026),
    dict(kind="quarterly", year=2026, quarter=5), dict(kind="half_yearly", year=2026, half=3), dict(kind="yearly"),
    dict(kind="yearly", year=1500), dict(kind="weekly"), dict(kind="daily"), dict(kind="custom", date_from=date(2026, 9, 2)),
    dict(kind="custom", date_from=date(2026, 9, 2), date_to=date(2026, 9, 1)),
    dict(kind="custom", date_from=date(2000, 1, 1), date_to=date(2026, 1, 1)),
    dict(kind="complete"), dict(kind="fortnightly"),
])
def test_invalid_inputs_are_rejected(kwargs):
    with pytest.raises(PeriodError):
        resolve_period(**kwargs)


def test_previous_period_for_named_periods():
    assert previous_period(resolve_period("monthly", year=2026, month=1)).label == "December 2025"
    assert previous_period(resolve_period("quarterly", year=2026, quarter=1)).label == "Q4 2025"
    assert previous_period(resolve_period("half_yearly", year=2026, half=1)).label == "H2 2025"
    assert previous_period(resolve_period("half_yearly", year=2026, half=2)).label == "H1 2026"
    assert previous_period(resolve_period("yearly", year=2026)).label == "2025"
    assert previous_period(resolve_period("weekly", week_start=date(2026, 9, 7))).start == date(2026, 8, 31)
    assert previous_period(resolve_period("daily", day=date(2026, 3, 1))).start == date(2026, 2, 28)


def test_previous_period_for_custom_ranges_has_the_same_length():
    p = resolve_period("custom", date_from=date(2026, 9, 11), date_to=date(2026, 9, 20))
    prev = previous_period(p)
    assert prev.days == p.days == 10 and prev.end == date(2026, 9, 10)
