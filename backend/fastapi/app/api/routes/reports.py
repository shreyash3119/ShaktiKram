import re
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Response

from app.core.auth import require_owner
from app.core.vocabulary import report_periods
from app.database.connection import engine
from app.reports import periods
from app.reports.excel import build_workbook
from app.reports.pdf import build_pdf
from app.reports.summary import build_summary, data_date_range

router = APIRouter(prefix="/reports", tags=["Reports"], dependencies=[Depends(require_owner)])


def period_from_query(period: str = Query("monthly"), year: int | None = None, month: int | None = None, quarter: int | None = None,
                      half: int | None = None, day: date | None = None, week_start: date | None = None,
                      date_from: date | None = None, date_to: date | None = None) -> periods.Period:
    try:
        first = last = None
        if period == "complete":
            with engine.connect() as conn:
                first, last = data_date_range(conn)
        return periods.resolve_period(period, year=year, month=month, quarter=quarter, half=half, day=day, week_start=week_start,
                                      date_from=date_from, date_to=date_to, data_first=first, data_last=last)
    except periods.PeriodError as e:
        raise HTTPException(status_code=422, detail=str(e))


def _filename(p: periods.Period, ext: str) -> str:
    return "fitness-report-" + re.sub(r"[^a-z0-9]+", "-", p.label.lower()).strip("-") + "." + ext


@router.get("/periods")
def list_periods():
    return {"periods": report_periods()}


@router.get("/summary")
def summary(p: periods.Period = Depends(period_from_query), compare: bool = False):
    with engine.connect() as conn:
        return build_summary(conn, p, compare=compare)


@router.get("/export")
def export(p: periods.Period = Depends(period_from_query), format: str = Query("xlsx", pattern="^(xlsx|pdf)$"), compare: bool = False):
    with engine.connect() as conn:
        s = build_summary(conn, p, compare=compare)
        body, media = (build_workbook(conn, p, s), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") if format == "xlsx" else (build_pdf(s), "application/pdf")
    return Response(content=body, media_type=media, headers={"Content-Disposition": f'attachment; filename="{_filename(p, format)}"'})
