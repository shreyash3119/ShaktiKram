from datetime import date, datetime
from io import BytesIO

from openpyxl import load_workbook
from pypdf import PdfReader
from sqlalchemy import text

from app.reports.excel import SHEETS, build_workbook
from app.reports.pdf import build_pdf
from app.reports.periods import resolve_period
from app.reports.summary import build_summary

SEP = resolve_period("monthly", year=2026, month=9)


def _workbook(conn, period):
    return load_workbook(BytesIO(build_workbook(conn, period, build_summary(conn, period))))


def test_workbook_has_every_sheet_with_units_and_filters(conn):
    wb = _workbook(conn, SEP)
    assert wb.sheetnames == ["Summary"] + [name for name, _ in SHEETS]
    ws = wb["Workout sessions"]
    headers = [c.value for c in ws[1]]
    assert "Volume (kg)" in headers and "Duration (min)" in headers
    assert ws.max_row - 1 == 9 and ws.auto_filter.ref and ws.freeze_panes == "A2"
    assert isinstance(ws.cell(row=2, column=1).value, (date, datetime))
    for name, _ in SHEETS:
        assert wb[name].auto_filter.ref, f"{name} has no filter"


def test_sheet_rows_match_the_database(conn):
    wb = _workbook(conn, SEP)
    sets = conn.execute(text("select count(*) from sets where deleted_at is null and local_date between :a and :b"), {"a": SEP.start, "b": SEP.end}).scalar()
    assert wb["Exercise sets"].max_row - 1 == sets
    steps = conn.execute(text("select count(*) from daily_steps where deleted_at is null and local_date between :a and :b"), {"a": SEP.start, "b": SEP.end}).scalar()
    assert wb["Steps"].max_row - 1 == steps


def test_estimates_are_labelled_in_the_headings(conn):
    wb = _workbook(conn, SEP)
    assert any("estimated" in str(c.value) for c in wb["Body composition (est.)"][1])
    assert any("estimate" in str(c.value) for c in wb["Strength progression"][1])


def test_pdf_has_pages_period_and_disclaimer(conn):
    pdf = build_pdf(build_summary(conn, SEP, compare=True))
    assert pdf.startswith(b"%PDF")
    reader = PdfReader(BytesIO(pdf))
    text_all = " ".join(p.extract_text() for p in reader.pages)
    assert len(reader.pages) >= 3 and "September 2026" in text_all and "not medical advice" in text_all


def test_empty_period_still_builds_both_files(conn):
    p = resolve_period("yearly", year=2020)
    s = build_summary(conn, p)
    wb = load_workbook(BytesIO(build_workbook(conn, p, s)))
    assert wb["Workout sessions"].max_row == 1
    pdf = PdfReader(BytesIO(build_pdf(s)))
    assert "No records in this period" in " ".join(pg.extract_text() for pg in pdf.pages)
