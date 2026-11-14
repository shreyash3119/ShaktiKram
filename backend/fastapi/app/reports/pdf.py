"""PDF report. Observations and estimates only: nothing here is medical advice."""
from datetime import datetime
from io import BytesIO
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.reports import charts

NAVY = colors.HexColor("#1F4E78")
_ss = getSampleStyleSheet()
H1 = ParagraphStyle("h1", parent=_ss["Title"], fontSize=22, textColor=NAVY, spaceAfter=4)
H2 = ParagraphStyle("h2", parent=_ss["Heading2"], textColor=NAVY, spaceBefore=12, spaceAfter=4)
BODY = ParagraphStyle("body", parent=_ss["BodyText"], fontSize=9, leading=12)
SMALL = ParagraphStyle("small", parent=BODY, fontSize=8, textColor=colors.HexColor("#555555"))
CELL = ParagraphStyle("cell", parent=BODY, fontSize=8, leading=10)
NOTE = "These are observations from your own records and estimates. They are not medical advice and not a diagnosis."


def _f(v, nd=1):
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:,.{nd}f}".rstrip("0").rstrip(".") if nd else f"{v:,.0f}"
    return str(v)


def _words(s):
    return str(s).replace("_", " ").capitalize() if s else "-"


def _table(rows, widths=None):
    head = [Paragraph(f'<font color="white"><b>{escape(str(c))}</b></font>', CELL) for c in rows[0]]
    data = [head] + [[Paragraph(escape(str(c)), CELL) for c in r] for r in rows[1:]]
    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), NAVY), ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#BBBBBB")),
                           ("VALIGN", (0, 0), (-1, -1), "TOP"), ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F3F6FA")])]))
    return t


def _img(png):
    return Image(BytesIO(png), width=175 * mm, height=63 * mm) if png else None


def _section(title, *parts):
    parts = [p for p in parts if p is not None]
    head = Paragraph(escape(title), H2)
    if not parts:
        return [head]
    return [KeepTogether([head, parts[0]])] + parts[1:]


def _footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawString(15 * mm, 9 * mm, "Personal fitness report - observations from your own records, not medical advice")
    canvas.drawRightString(195 * mm, 9 * mm, f"Page {doc.page}")
    canvas.restoreState()


def build_pdf(s: dict) -> bytes:
    p, t, a = s["period"], s["training"], s["training"]["attendance"]
    story = [Paragraph("Personal fitness report", H1), Paragraph(escape(f"{p['label']}  ({p['start']} to {p['end']})"), BODY),
             Paragraph(f"Generated {datetime.now():%Y-%m-%d}", SMALL), Spacer(1, 6)]
    kpi = [["Measure", "This period"] + (["Previous", "Change"] if "comparison" in s else [])]
    labels = {"sessions": "Workouts", "volume_kg": "Total volume (kg)", "consistency_pct": "Consistency (%)", "avg_sleep_hours": "Average sleep (h)",
              "avg_steps": "Average steps", "personal_records": "Personal records"}
    if "comparison" in s:
        for m in s["comparison"]["metrics"]:
            kpi.append([labels[m["key"]], _f(m["current"], 0 if m["key"] in ("volume_kg", "avg_steps") else 1), _f(m["previous"], 0 if m["key"] in ("volume_kg", "avg_steps") else 1),
                        "-" if m["change_pct"] is None else f"{m['change_pct']:+}%"])
    else:
        kpi += [["Workouts", t["sessions"]], ["Working sets", t["working_sets"]], ["Total volume (kg)", _f(t["volume_kg"], 0)], ["Consistency (%)", _f(a["consistency_pct"])],
                ["Personal records", len(s["strength"]["records"])], ["Average sleep (h)", _f(s["recovery"]["sleep"].get("avg_hours"))],
                ["Average steps", _f(s["lifestyle"]["steps"].get("avg_steps"), 0)]]
    story += _section("Overview", _table(kpi, [70 * mm, 35 * mm] + ([35 * mm, 25 * mm] if "comparison" in s else [])))

    story += _section("Training consistency",
        _table([["Scheduled", "Completed", "Missed", "Days inside planned breaks", "Consistency"],
                [a["scheduled"], a["completed"], a["missed"], a["break_days"], f"{_f(a['consistency_pct'])}%" if a["consistency_pct"] is not None else "-"]]),
        Paragraph("Planned breaks, rest days and rescheduled days are not counted as missed.", SMALL), _img(charts.weekly_consistency(s)), _img(charts.weekly_volume(s)))

    ex = s["strength"]["exercises"][:10]
    str_parts = [_table([["Exercise", "Sessions", "First 1RM (kg)", "Last 1RM (kg)", "Change", "Top weight (kg)"]] +
                        [[e["exercise"], e["sessions"], _f(e["first_e1rm_kg"]), _f(e["last_e1rm_kg"]), "-" if e["e1rm_change_pct"] is None else f"{e['e1rm_change_pct']:+}%", _f(e["top_weight_kg"])] for e in ex])] if ex else [Paragraph("No workouts in this period.", BODY)]
    recs = s["strength"]["records"][:12]
    if recs:
        str_parts += [Spacer(1, 4), _table([["Date", "Exercise", "Record", "Value", "Previous"]] + [[r["achieved_on"], r["exercise"], _words(r["kind"]), _f(r["value"]), _f(r["previous_value"])] for r in recs]),
                      Paragraph(f"{len(s['strength']['records'])} record(s) in total; the first 12 are shown.", SMALL) if len(s["strength"]["records"]) > 12 else None]
    story += _section("Strength (estimated 1RM is an estimate)", *str_parts, _img(charts.e1rm_trend(s)))

    ms = s["body"]["measurements"]
    body_parts = [_table([["Measurement", "Unit", "First", "Last", "Change", "Readings"]] +
                         [[_words(m["measurement_type"]) + (f" ({m['method'].replace('_', ' ')})" if m["method"] else ""), m["unit"], _f(m["first_value"], 2), _f(m["last_value"], 2),
                           "-" if m["change"] is None else f"{m['change']:+}", m["n"]] for m in ms])] if ms else [Paragraph("No measurements in this period.", BODY)]
    comp = s["body"]["composition"][:8]
    if comp:
        body_parts += [Spacer(1, 4), _table([["Date", "Method", "Body fat (%)", "Weight (kg)", "Fat mass (kg, est.)", "Lean mass (kg, est.)"]] +
                       [[c["date"], _words(c["method"]), _f(c["body_fat_pct"]), _f(c["weight_kg"]), _f(c["fat_mass_kg"]), _f(c["lean_mass_kg"])] for c in comp]),
                       Paragraph("Readings from different methods are not directly comparable.", SMALL)]
    story += _section("Body measurements and composition", *body_parts, _img(charts.weight_trend(s)))

    rt = s["muscles"]["ratings"]
    mus = [_table([["Muscle", "First rating", "Last rating", "Change in your assessment"]] + [[_words(r["muscle_key"]), r["first_level"], r["last_level"], _words(r["assessment_change"])] for r in rt])] if rt else [Paragraph("No assessments in this period.", BODY)]
    ex_t = s["muscles"]["training_exposure"][:8]
    if ex_t:
        mus += [Spacer(1, 4), _table([["Muscle", "Direct sets", "Indirect sets"]] + [[_words(r["muscle_key"]), r["direct_sets"], r["indirect_sets"]] for r in ex_t])]
    story += _section("Muscle self-assessment and training exposure", *mus,
                      Paragraph("Ratings are your own judgement (1 to 5). A change is a change in your assessment, not measured growth. Training exposure is shown separately and does not measure development.", SMALL))

    r, lf = s["recovery"], s["lifestyle"]
    c = r["checkin_averages"]
    story += _section("Recovery and lifestyle",
        _table([["Check-in averages (1-5)", "Energy", "Sleep quality", "Soreness", "Fatigue", "Motivation", "Stress"],
                [f"{c.get('days', 0)} days", _f(c.get("energy")), _f(c.get("sleep_quality")), _f(c.get("soreness")), _f(c.get("fatigue")), _f(c.get("motivation")), _f(c.get("stress"))]]),
        Spacer(1, 4),
        _table([["Area", "Figures"],
                ["Sleep", f"{_f(r['sleep'].get('avg_hours'))} h average over {r['sleep'].get('nights', 0)} nights; rating {_f(r['sleep'].get('avg_quality'))}"],
                ["Steps", f"{_f(lf['steps'].get('avg_steps'), 0)} average; target reached on {lf['steps'].get('days_on_target', 0)} of {lf['steps'].get('days_logged', 0)} days"],
                ["Cardio", f"{lf['cardio'].get('sessions', 0)} sessions, {_f(lf['cardio'].get('total_minutes'), 0)} min, {_f(lf['cardio'].get('total_km'))} km"],
                ["Water", f"{_f(lf['hydration'].get('avg_ml'), 0)} ml average per logged day ({_f(lf['hydration'].get('avg_pct_of_target'))}% of target)"],
                ["Protein (estimated)", (f"planned {_f(lf['nutrition'].get('avg_planned_protein_g'))} g, eaten {_f(lf['nutrition'].get('avg_eaten_protein_g'))} g, target {_f(lf['nutrition'].get('avg_protein_target_g'))} g per planned day"
                                         if lf["nutrition"].get("days_planned") else "no meal plan entries in this period")]],
               [40 * mm, 140 * mm]))
    inj = s["injuries"]["injuries"]
    if inj:
        story += _section("Injury and pain records", _table([["Injury", "Region", "Side", "Status", "Severity", "Latest pain (0-10)"]] +
                          [[i["name"], _words(i["body_region_key"]), _words(i["side"]), _words(i["status"]), _words(i["severity"]), _f(i["latest_pain_level"], 0)] for i in inj]),
                          Paragraph("Pain and injury records are kept apart from ordinary muscle soreness. This report does not assess or diagnose them.", SMALL))
    sup = lf["supplements"]
    if sup:
        story += _section("Supplements (as you recorded them)", _table([["Supplement", "Taken", "Missed", "Skipped on purpose", "Logged adherence"]] +
                          [[x["name"], x["taken"], x["missed"], x["skipped"], "-" if x["logged_adherence_pct"] is None else f"{x['logged_adherence_pct']}%"] for x in sup]))
    g = s["goals"]["goals"]
    if g:
        story += _section("Goals (as of the report)", _table([["Goal", "Start", "Current", "Target", "Progress", "Status"]] +
                          [[x["title"], _f(x["start_value"], 2), _f(x["current_value"], 2), _f(x["target_value"], 2), "-" if x["progress_pct"] is None else f"{x['progress_pct']}%", _words(x["progress_status"])] for x in g]))
    cx = s["context"]
    ctx = [["Split periods"] + [f"{x['name']}: {x['start_date']} to {x['end_date'] or 'now'}" for x in cx["splits"]]] if cx["splits"] else []
    ctx += [["Breaks"] + [f"{x['title']} ({x['days_in_period']} days)" for x in cx["breaks"]]] if cx["breaks"] else []
    ctx += [["Deloads"] + [f"{x['start_date']} to {x['end_date']}" for x in cx["deloads"]]] if cx["deloads"] else []
    if ctx:
        story += _section("Plan changes in this period", *[Paragraph(escape(f"{row[0]}: " + "; ".join(row[1:])), BODY) for row in ctx])
    story += _section("Key observations", *[Paragraph("&bull; " + escape(o["text"]), BODY) for o in s["observations"]] or [Paragraph("No records in this period.", BODY)])
    story += [Spacer(1, 8), Paragraph(NOTE, SMALL)]

    buf = BytesIO()
    SimpleDocTemplate(buf, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm, topMargin=15 * mm, bottomMargin=16 * mm,
                      title="Personal fitness report", author="Personal Fitness System").build(story, onFirstPage=_footer, onLaterPages=_footer)
    return buf.getvalue()
