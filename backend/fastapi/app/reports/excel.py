"""Excel export: one worksheet per kind of record, with units in the headings, filters and the original records, plus a summary sheet."""
import json
from datetime import date, datetime
from decimal import Decimal
from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from sqlalchemy import text

from app.reports.periods import Period

SHEETS = [
    ("Workout sessions", """select local_date as "Date", name as "Workout", status as "Status", (started_at at time zone pfs_tz()) as "Started (local time)",
        round(duration_s / 60.0) as "Duration (min)", exercises_done as "Exercises done", exercises_skipped as "Exercises skipped",
        working_sets as "Working sets", total_reps as "Total reps", volume_kg as "Volume (kg)", array_to_string(muscles_trained, ', ') as "Muscles trained"
        from v_session_summary where local_date between :d1 and :d2 order by started_at"""),
    ("Exercise sets", """select st.local_date as "Date", ws.name as "Workout", e.name as "Exercise", st.set_type as "Set type", st.set_number as "Set no.",
        st.weight_kg as "Weight (kg)", st.reps as "Reps", st.rir as "RIR", st.rpe as "RPE", st.rest_s as "Rest (s)", st.completed as "Completed", st.notes as "Notes"
        from sets st join session_exercises se on se.id = st.session_exercise_id join workout_sessions ws on ws.id = se.session_id join exercises e on e.id = se.exercise_id
        where st.deleted_at is null and se.deleted_at is null and ws.deleted_at is null and st.local_date between :d1 and :d2 order by st.occurred_at, st.set_type, st.set_number"""),
    ("Strength progression", """select b.local_date as "Date", e.name as "Exercise", b.top_weight_kg as "Top weight (kg)", b.max_reps as "Most reps in a set",
        b.best_e1rm_kg as "Best estimated 1RM (kg, estimate)", b.volume_kg as "Volume (kg)"
        from v_exercise_session_best b join exercises e on e.id = b.exercise_id
        where b.session_status = 'completed' and b.local_date between :d1 and :d2 order by e.name, b.occurred_at"""),
    ("Personal records", """select pr.achieved_on as "Date", coalesce(e.name, 'Whole workout') as "Exercise", pr.kind as "Record type", pr.value as "Value",
        pr.previous_value as "Previous value", pr.weight_kg as "Weight (kg)", pr.reps as "Reps"
        from personal_records pr left join exercises e on e.id = pr.exercise_id where pr.achieved_on between :d1 and :d2 order by pr.achieved_on, 2, pr.kind"""),
    ("Body measurements", """select local_date as "Date", measurement_type as "Measurement", value as "Value",
        coalesce(custom_unit, case measurement_type when 'weight' then 'kg' when 'body_fat' then '%' when 'muscle_mass' then 'kg' else 'cm' end) as "Unit",
        custom_label as "Custom label", method as "Method", side as "Side", source as "Source", notes as "Notes"
        from body_measurements where deleted_at is null and local_date between :d1 and :d2 order by occurred_at"""),
    ("Body composition (est.)", """select local_date as "Date", method as "Body-fat method", body_fat_pct as "Body fat (%)", weight_kg as "Weight (kg)",
        fat_mass_kg as "Fat mass (kg, estimated)", lean_mass_kg as "Lean mass (kg, estimated)"
        from v_body_composition where local_date between :d1 and :d2 order by local_date, method"""),
    ("Muscle assessments", """select a.local_date as "Date", m.group_key as "Group", m.label as "Muscle", i.level as "Your rating (1-5)",
        pfs_muscle_category(i.level) as "Category from your rating", a.notes as "Assessment notes"
        from muscle_assessment_items i join muscle_assessments a on a.id = i.assessment_id join muscles m on m.id = i.muscle_id
        where i.deleted_at is null and a.deleted_at is null and a.local_date between :d1 and :d2 order by a.local_date, m.group_key, m.label"""),
    ("Injury history", """select * from (
        select i.start_date as "Date", 'Injury recorded' as "Entry", i.name as "Injury", br.key as "Body region", i.side as "Side", i.severity as "Severity",
               i.status as "Status", null::int as "Pain level (0-10)", null::text as "Effect on training", i.description as "Note"
          from injuries i join body_regions br on br.id = i.body_region_id where i.deleted_at is null and i.start_date between :d1 and :d2
        union all
        select u.local_date, 'Update', i.name, br.key, i.side, u.severity, u.status, null, null, u.note
          from injury_updates u join injuries i on i.id = u.injury_id join body_regions br on br.id = i.body_region_id where u.deleted_at is null and u.local_date between :d1 and :d2
        union all
        select p.local_date, 'Pain entry', coalesce(i.name, ''), br.key, p.side, null, null, p.level, p.effect_on_training, p.notes
          from pain_entries p join body_regions br on br.id = p.body_region_id left join injuries i on i.id = p.injury_id where p.deleted_at is null and p.local_date between :d1 and :d2
        union all
        select i.resolved_on, 'Resolved', i.name, br.key, i.side, i.severity, i.status, null, null, null
          from injuries i join body_regions br on br.id = i.body_region_id where i.deleted_at is null and i.resolved_on between :d1 and :d2) t order by 1, 2"""),
    ("Recovery and sleep", """select days.d as "Date", c.energy as "Energy (1-5)", c.sleep_quality as "Sleep quality (1-5)", c.soreness as "Soreness (1-5)", c.fatigue as "Fatigue (1-5)",
        c.motivation as "Motivation (1-5)", c.stress as "Stress (1-5)", c.pain_flag as "Pain or discomfort", sl.hours as "Sleep (h)", sl.quality as "Sleep rating (1-5)", sl.nap_hours as "Naps (h)"
        from (select local_date as d from daily_checkins where deleted_at is null and local_date between :d1 and :d2
              union select local_date from sleep_logs where deleted_at is null and local_date between :d1 and :d2) days
        left join daily_checkins c on c.local_date = days.d and c.deleted_at is null
        left join lateral (select round(sum(duration_s) filter (where not is_nap) / 3600.0, 1) as hours, round(avg(quality) filter (where not is_nap), 1) as quality,
                                  round(sum(duration_s) filter (where is_nap) / 3600.0, 1) as nap_hours from sleep_logs where local_date = days.d and deleted_at is null) sl on true
        order by days.d"""),
    ("Supplements", """select l.local_date as "Date", s.name as "Supplement", l.outcome as "Outcome", l.quantity as "Quantity", l.unit as "Unit", p.status as "Phase status", l.notes as "Notes"
        from supplement_logs l join supplements s on s.id = l.supplement_id left join supplement_phases p on p.id = l.phase_id
        where l.deleted_at is null and l.local_date between :d1 and :d2 order by l.occurred_at"""),
    ("Meal plan", """select p.local_date as "Date", p.slot as "Slot", m.title as "Meal", p.status as "Status", p.servings as "Servings", r.title as "Replaced by",
        round(n.protein_g * p.servings, 1) as "Protein (g, estimated)", round(n.calories_kcal * p.servings, 0) as "Energy (kcal, estimated)"
        from meal_plan_entries p join meals m on m.id = p.meal_id left join meals r on r.id = p.replaced_by_meal_id left join v_meal_nutrition n on n.meal_id = p.meal_id
        where p.deleted_at is null and p.local_date between :d1 and :d2 order by p.local_date, p.slot"""),
    ("Nutrition and hydration", """select days.d as "Date", n.planned_protein_g as "Planned protein (g, estimated)", n.eaten_protein_g as "Eaten protein (g, estimated)",
        n.planned_calories_kcal as "Planned energy (kcal, estimated)", n.eaten_calories_kcal as "Eaten energy (kcal, estimated)", n.protein_target_g as "Protein target (g)",
        h.total_ml as "Water (ml)", h.target_ml as "Water target (ml)", h.pct_of_target as "Water vs target (%)"
        from (select local_date as d from v_daily_nutrition where local_date between :d1 and :d2 union select local_date from v_daily_hydration where local_date between :d1 and :d2) days
        left join v_daily_nutrition n on n.local_date = days.d left join v_daily_hydration h on h.local_date = days.d order by days.d"""),
    ("Cardio", """select local_date as "Date", coalesce(custom_activity, activity) as "Activity", round(duration_s / 60.0, 1) as "Duration (min)", round(distance_m / 1000.0, 2) as "Distance (km)",
        round(avg_speed_mps * 3.6, 1) as "Average speed (km/h)", incline_pct as "Incline (%)", calories_kcal as "Energy (kcal, device or estimate)", avg_heart_rate_bpm as "Average heart rate (bpm)",
        max_heart_rate_bpm as "Max heart rate (bpm)", intensity as "Intensity", source as "Source", notes as "Notes"
        from cardio_sessions where deleted_at is null and local_date between :d1 and :d2 order by occurred_at"""),
    ("Steps", """select local_date as "Date", steps as "Steps", target_steps as "Target", source as "Source" from daily_steps
        where deleted_at is null and local_date between :d1 and :d2 order by local_date"""),
    ("Goals", """select title as "Goal", type as "Type", goal_status as "Status", target_metric as "Metric", target_value as "Target", start_value as "Start value",
        current_value as "Current value", progress_pct as "Progress (%)", progress_status as "Progress status", start_date as "Start date", target_date as "Target date"
        from v_goal_progress order by title"""),
    ("Milestones", """select g.title as "Goal", m.title as "Milestone", m.target_value as "Target value", m.is_reached as "Reached"
        from v_goal_milestones m join goals g on g.id = m.goal_id order by g.title, m.target_value"""),
]

_HEAD = PatternFill("solid", fgColor="1F4E78")


def _cell(v):
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (dict, list)):
        return json.dumps(v, default=str)
    if isinstance(v, datetime) and v.tzinfo is not None:
        return v.replace(tzinfo=None)
    return v if v is None or isinstance(v, (str, int, float, bool, date, datetime)) else str(v)


def _write_table(ws, headers, data):
    ws.append(headers)
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = _HEAD
        c.alignment = Alignment(wrap_text=True, vertical="center")
    for row in data:
        ws.append([_cell(v) for v in row])
    for ci, h in enumerate(headers, 1):
        width = max([len(str(h))] + [len(str(r[ci - 1])) for r in data[:200] if r[ci - 1] is not None]) + 2
        ws.column_dimensions[get_column_letter(ci)].width = min(max(width, 10), 45)
    for row in ws.iter_rows(min_row=2):
        for c in row:
            if isinstance(c.value, datetime):
                c.number_format = "yyyy-mm-dd hh:mm"
            elif isinstance(c.value, date):
                c.number_format = "yyyy-mm-dd"
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions


def _summary_sheet(ws, period: Period, s: dict):
    ws.append(["Personal fitness report"]); ws["A1"].font = Font(bold=True, size=16)
    ws.append(["Period", period.label]); ws.append(["From", period.start]); ws.append(["To", period.end]); ws.append([])
    ws.append(["Key figures", "Value"]); ws["A6"].font = Font(bold=True); ws["B6"].font = Font(bold=True)
    t, a = s["training"], s["training"]["attendance"]
    for label, v in [("Workouts completed", t["sessions"]), ("Working sets", t["working_sets"]), ("Total volume (kg)", t["volume_kg"]),
                     ("Scheduled sessions", a["scheduled"]), ("Completed sessions", a["completed"]), ("Missed sessions", a["missed"]),
                     ("Days inside planned breaks", a["break_days"]), ("Consistency (%)", a["consistency_pct"]), ("Personal records", len(s["strength"]["records"])),
                     ("Average sleep (h)", s["recovery"]["sleep"].get("avg_hours")), ("Average steps", s["lifestyle"]["steps"].get("avg_steps"))]:
        ws.append([label, v])
    ws.append([]); ws.append(["Key observations"]); ws.cell(ws.max_row, 1).font = Font(bold=True)
    for o in s["observations"]:
        ws.append([o["text"]])
    ws.append([]); ws.append(["These are observations from your own records and estimates. They are not medical advice and not a diagnosis."])
    ws.column_dimensions["A"].width = 34; ws.column_dimensions["B"].width = 24


def build_workbook(conn, period: Period, summary: dict) -> bytes:
    wb = Workbook()
    _summary_sheet(wb.active, period, summary)
    wb.active.title = "Summary"
    for name, sql in SHEETS:
        params = {"d1": period.start, "d2": period.end} if ":d1" in sql else {}
        result = conn.execute(text(sql), params)
        headers = list(result.keys())
        data = [list(r) for r in result.fetchall()]
        _write_table(wb.create_sheet(name), headers, data)
    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()
