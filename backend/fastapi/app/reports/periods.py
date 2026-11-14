"""Report periods. One rule set for every period kind (the list of kinds lives in shared/vocabulary/statuses.json)."""
import calendar
from dataclasses import dataclass
from datetime import date, timedelta

from app.core.vocabulary import report_periods

MAX_CUSTOM_DAYS = 3660


class PeriodError(ValueError):
    pass


@dataclass(frozen=True)
class Period:
    kind: str
    start: date
    end: date
    label: str

    @property
    def days(self) -> int:
        return (self.end - self.start).days + 1


def _need(value, name, kind):
    if value is None:
        raise PeriodError(f"{name} is required for a {kind} report")
    return value


def _month_end(y: int, m: int) -> date:
    return date(y, m, calendar.monthrange(y, m)[1])


def resolve_period(kind, *, year=None, month=None, quarter=None, half=None, day=None, week_start=None,
                   date_from=None, date_to=None, data_first=None, data_last=None) -> Period:
    if kind not in report_periods():
        raise PeriodError(f"unknown period kind: {kind}")
    if kind == "daily":
        d = _need(day, "day", kind)
        return Period(kind, d, d, d.isoformat())
    if kind == "weekly":
        ws = _need(week_start, "week_start", kind)
        start = ws - timedelta(days=ws.weekday())          # weeks start on Monday
        return Period(kind, start, start + timedelta(days=6), f"Week of {start.isoformat()}")
    if kind == "custom":
        a, b = _need(date_from, "date_from", kind), _need(date_to, "date_to", kind)
        if b < a:
            raise PeriodError("date_to must not be before date_from")
        if (b - a).days + 1 > MAX_CUSTOM_DAYS:
            raise PeriodError(f"a custom range can cover at most {MAX_CUSTOM_DAYS} days")
        return Period(kind, a, b, f"{a.isoformat()} to {b.isoformat()}")
    if kind == "complete":
        if data_first is None or data_last is None:
            raise PeriodError("there are no records yet")
        return Period(kind, data_first, data_last, "Complete history")
    y = _need(year, "year", kind)
    if not 1900 <= y <= 2200:
        raise PeriodError("year is out of range")
    if kind == "yearly":
        return Period(kind, date(y, 1, 1), date(y, 12, 31), str(y))
    if kind == "monthly":
        m = _need(month, "month", kind)
        if not 1 <= m <= 12:
            raise PeriodError("month must be 1 to 12")
        return Period(kind, date(y, m, 1), _month_end(y, m), f"{calendar.month_name[m]} {y}")
    if kind == "quarterly":
        q = _need(quarter, "quarter", kind)
        if not 1 <= q <= 4:
            raise PeriodError("quarter must be 1 to 4")
        first = 3 * (q - 1) + 1
        return Period(kind, date(y, first, 1), _month_end(y, first + 2), f"Q{q} {y}")
    h = _need(half, "half", kind)
    if h not in (1, 2):
        raise PeriodError("half must be 1 or 2")
    first = 1 if h == 1 else 7
    return Period(kind, date(y, first, 1), _month_end(y, first + 5), f"H{h} {y}")


def _shift_months(d: date, months: int) -> date:
    idx = d.year * 12 + (d.month - 1) + months
    return date(idx // 12, idx % 12 + 1, 1)


def previous_period(p: Period) -> Period:
    """The period before this one: the same kind for named periods, the same number of days for custom and complete ranges."""
    if p.kind in ("monthly", "quarterly", "half_yearly", "yearly"):
        months = {"monthly": 1, "quarterly": 3, "half_yearly": 6, "yearly": 12}[p.kind]
        s = _shift_months(p.start, -months)
        if p.kind == "monthly":
            return resolve_period("monthly", year=s.year, month=s.month)
        if p.kind == "quarterly":
            return resolve_period("quarterly", year=s.year, quarter=(s.month - 1) // 3 + 1)
        if p.kind == "half_yearly":
            return resolve_period("half_yearly", year=s.year, half=1 if s.month == 1 else 2)
        return resolve_period("yearly", year=s.year)
    if p.kind == "weekly":
        return resolve_period("weekly", week_start=p.start - timedelta(days=7))
    if p.kind == "daily":
        return resolve_period("daily", day=p.start - timedelta(days=1))
    end = p.start - timedelta(days=1)
    start = end - timedelta(days=p.days - 1)
    return Period("custom", start, end, f"{start.isoformat()} to {end.isoformat()}")
