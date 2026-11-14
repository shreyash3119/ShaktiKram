"""Report summary against backend/tests/sample_data.sql. The expected numbers follow from how that data is built:
September 2026 has 13 Monday/Wednesday/Friday entries; 3 fall in the exam break, 1 was missed, 9 were completed."""
from datetime import date

import pytest

from app.reports.periods import resolve_period
from app.reports.summary import build_summary, data_date_range


@pytest.fixture
def sep(conn):
    return build_summary(conn, resolve_period("monthly", year=2026, month=9))


def test_training_and_attendance_exclude_breaks(sep):
    assert sep["training"]["sessions"] == 9
    a = sep["training"]["attendance"]
    assert (a["scheduled"], a["completed"], a["missed"], a["break_days"], a["consistency_pct"]) == (10, 9, 1, 3, 90.0)


def test_body_measurements_keep_methods_apart(sep):
    m = {(r["measurement_type"], r["method"]): r for r in sep["body"]["measurements"]}
    assert m[("weight", None)]["n"] == 4
    assert m[("body_fat", "smart_scale_bia")]["n"] == 2
    assert all(c["method"] == "smart_scale_bia" for c in sep["body"]["composition"])


def test_supplements_injuries_and_plan_changes(sep):
    s = sep["lifestyle"]["supplements"][0]
    assert s["taken"] + s["missed"] == 23 and s["skipped"] == 0       # no doses were logged inside the exam break
    assert sep["injuries"]["pain"]["entries"] == 3 and sep["injuries"]["pain"]["max_level"] == 4
    assert sep["context"]["breaks"][0]["days_in_period"] == 7
    assert len(sep["context"]["deloads"]) == 1


def test_observations_are_cautious_and_include_consistency(sep):
    codes = {o["code"] for o in sep["observations"]}
    assert {"consistency", "training_volume", "breaks"} <= codes
    text = " ".join(o["text"].lower() for o in sep["observations"])
    assert "diagnos" not in text and "you should" not in text


def test_muscle_rating_changes_are_assessment_changes(conn):
    s = build_summary(conn, resolve_period("custom", date_from=date(2026, 8, 1), date_to=date(2026, 9, 30)))
    rear = next(r for r in s["muscles"]["ratings"] if r["muscle_key"] == "rear_delts")
    assert (rear["first_level"], rear["last_level"], rear["assessment_change"]) == (1, 2, "higher_rating")
    assert any(o["code"] == "assessment" and "not measured growth" in o["text"] for o in s["observations"])


def test_comparison_uses_the_previous_period(conn):
    s = build_summary(conn, resolve_period("monthly", year=2026, month=10), compare=True)
    assert s["comparison"]["previous_period"]["label"] == "September 2026"
    sessions = next(m for m in s["comparison"]["metrics"] if m["key"] == "sessions")
    assert sessions["previous"] == 9 and sessions["current"] == s["training"]["sessions"]


def test_complete_history_starts_at_the_first_record(conn):
    first, last = data_date_range(conn)
    assert first == date(2026, 8, 3) and last >= date(2026, 10, 25)
    s = build_summary(conn, resolve_period("complete", data_first=first, data_last=last))
    assert s["period"]["label"] == "Complete history" and s["training"]["sessions"] >= 30


def test_a_period_without_records_gives_empty_sections(conn):
    s = build_summary(conn, resolve_period("yearly", year=2020))
    assert s["training"]["sessions"] == 0 and s["strength"]["exercises"] == [] and s["observations"] == []
