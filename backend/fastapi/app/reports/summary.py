"""Builds the report summary for a period from the database views. Read-only. Every figure here is an observation or an estimate."""
from datetime import date
from decimal import Decimal

from sqlalchemy import text

from app.reports.periods import Period, previous_period


def _plain(o):
    if isinstance(o, Decimal):
        return float(o)
    if isinstance(o, dict):
        return {k: _plain(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [_plain(v) for v in o]
    return o


def rows(conn, sql, **p):
    return [dict(r) for r in conn.execute(text(sql), p).mappings()]


def one(conn, sql, **p):
    r = rows(conn, sql, **p)
    return r[0] if r else {}


def pct_change(a, b):
    if a is None or b is None or float(a) == 0:
        return None
    return round((float(b) - float(a)) / float(a) * 100, 1)


def data_date_range(conn):
    r = one(conn, """select min(d) as first, max(d) as last from (
        select local_date as d from workout_sessions where deleted_at is null union all select local_date from body_measurements where deleted_at is null
        union all select local_date from daily_checkins where deleted_at is null union all select local_date from sleep_logs where deleted_at is null
        union all select local_date from daily_steps where deleted_at is null union all select local_date from cardio_sessions where deleted_at is null
        union all select local_date from supplement_logs where deleted_at is null union all select local_date from meal_plan_entries where deleted_at is null
        union all select local_date from pain_entries where deleted_at is null) x""")
    return r.get("first"), r.get("last")


def _training(conn, d1, d2):
    t = one(conn, """select count(*) as sessions, coalesce(sum(volume_kg), 0) as volume_kg, coalesce(sum(working_sets), 0) as working_sets,
                            coalesce(sum(total_reps), 0) as total_reps, round(avg(duration_s) / 60.0) as avg_duration_min
                     from v_session_summary where status = 'completed' and local_date between :d1 and :d2""", d1=d1, d2=d2)
    t["weekly"] = rows(conn, """select date_trunc('week', local_date)::date as week_start, count(*) as sessions, sum(volume_kg) as volume_kg
                                from v_session_summary where status = 'completed' and local_date between :d1 and :d2 group by 1 order by 1""", d1=d1, d2=d2)
    a = one(conn, """select count(*) filter (where is_scheduled_training and (is_done or is_missed)) as scheduled,
                            count(*) filter (where is_scheduled_training and is_done) as completed, count(*) filter (where is_missed) as missed,
                            count(*) filter (where is_break_day) as break_days
                     from v_attendance_daily where local_date between :d1 and :d2""", d1=d1, d2=d2)
    a["consistency_pct"] = round(100.0 * a["completed"] / a["scheduled"], 1) if a["scheduled"] else None
    a["weekly"] = rows(conn, """select week_start, scheduled, completed, missed, break_days, consistency_pct from v_consistency_weekly
                                where week_start between date_trunc('week', cast(:d1 as date))::date and :d2 order by week_start""", d1=d1, d2=d2)
    t["attendance"] = a
    return t


def _strength(conn, d1, d2):
    ex = rows(conn, """select e.name as exercise, count(*) as sessions,
                         (array_agg(b.best_e1rm_kg order by b.occurred_at) filter (where b.best_e1rm_kg is not null))[1] as first_e1rm_kg,
                         (array_agg(b.best_e1rm_kg order by b.occurred_at desc) filter (where b.best_e1rm_kg is not null))[1] as last_e1rm_kg,
                         max(b.top_weight_kg) as top_weight_kg, sum(b.volume_kg) as volume_kg
                       from v_exercise_session_best b join exercises e on e.id = b.exercise_id
                       where b.session_status = 'completed' and b.local_date between :d1 and :d2 group by e.id, e.name order by sum(b.volume_kg) desc""", d1=d1, d2=d2)
    for e in ex:
        e["e1rm_change_pct"] = pct_change(e["first_e1rm_kg"], e["last_e1rm_kg"]) if e["sessions"] >= 2 else None
    series = {}
    for r in rows(conn, """select e.name as exercise, b.local_date, b.best_e1rm_kg from v_exercise_session_best b join exercises e on e.id = b.exercise_id
                           where b.session_status = 'completed' and b.best_e1rm_kg is not null and b.local_date between :d1 and :d2 order by e.name, b.occurred_at""", d1=d1, d2=d2):
        series.setdefault(r["exercise"], []).append({"date": r["local_date"], "e1rm_kg": r["best_e1rm_kg"]})
    top = [e["exercise"] for e in ex[:3]]
    records = rows(conn, """select pr.achieved_on, coalesce(e.name, 'Whole workout') as exercise, pr.kind, pr.value, pr.previous_value, pr.weight_kg, pr.reps
                            from personal_records pr left join exercises e on e.id = pr.exercise_id where pr.achieved_on between :d1 and :d2 order by pr.achieved_on, pr.kind""", d1=d1, d2=d2)
    return {"exercises": ex, "e1rm_series": {k: series[k] for k in top if k in series}, "records": records, "value_kind": "estimated"}


def _body(conn, d1, d2):
    m = rows(conn, """select measurement_type, coalesce(custom_label, '') as label,
                        coalesce(custom_unit, case measurement_type when 'weight' then 'kg' when 'body_fat' then '%' when 'muscle_mass' then 'kg' else 'cm' end) as unit,
                        method, count(*) as n, (array_agg(value order by occurred_at))[1] as first_value, (array_agg(value order by occurred_at desc))[1] as last_value
                      from body_measurements where deleted_at is null and local_date between :d1 and :d2
                      group by measurement_type, custom_label, custom_unit, method order by measurement_type, method""", d1=d1, d2=d2)
    for r in m:
        r["change"] = round(r["last_value"] - r["first_value"], 2) if r["n"] >= 2 else None
    weights = rows(conn, "select local_date as date, value from body_measurements where deleted_at is null and measurement_type = 'weight' and local_date between :d1 and :d2 order by occurred_at", d1=d1, d2=d2)
    comp = rows(conn, "select local_date as date, method, body_fat_pct, weight_kg, fat_mass_kg, lean_mass_kg from v_body_composition where local_date between :d1 and :d2 order by local_date, method", d1=d1, d2=d2)
    return {"measurements": m, "weight_series": weights, "composition": comp, "value_kind": "estimated"}


def _muscles(conn, d1, d2):
    ratings = rows(conn, """select m.key as muscle_key, count(*) as assessments, (array_agg(i.level order by a.occurred_at))[1] as first_level,
                              (array_agg(i.level order by a.occurred_at desc))[1] as last_level
                            from muscle_assessment_items i join muscle_assessments a on a.id = i.assessment_id join muscles m on m.id = i.muscle_id
                            where i.deleted_at is null and a.deleted_at is null and a.local_date between :d1 and :d2 group by m.id, m.key order by m.key""", d1=d1, d2=d2)
    for r in ratings:
        r["assessment_change"] = "higher_rating" if r["last_level"] > r["first_level"] else "lower_rating" if r["last_level"] < r["first_level"] else "same_rating"
    priorities = rows(conn, """select m.key as muscle_key, p.priority, pfs_local_date(p.effective_from) as from_date from muscle_priorities p join muscles m on m.id = p.entity_id
                               where p.deleted_at is null and pfs_local_date(p.effective_from) between :d1 and :d2 order by m.key, p.version""", d1=d1, d2=d2)
    exposure = rows(conn, """select m.key as muscle_key, count(*) filter (where em.role = 'primary') as direct_sets, count(*) filter (where em.role in ('secondary', 'indirect')) as indirect_sets
                             from v_working_sets w join exercise_muscles em on em.exercise_id = w.exercise_id and em.deleted_at is null join muscles m on m.id = em.muscle_id
                             where w.session_status = 'completed' and w.session_local_date between :d1 and :d2 group by m.key order by 2 desc, 1""", d1=d1, d2=d2)
    return {"ratings": ratings, "priority_changes": priorities, "training_exposure": exposure, "value_kind": "user_assessment"}


def _injuries(conn, d1, d2):
    inj = rows(conn, """select name, body_region_key, side, status, severity, start_date, resolved_on, latest_pain_level, suggest_professional_review
                        from v_injury_summary where start_date <= :d2 and (resolved_on is null or resolved_on >= :d1) order by start_date""", d1=d1, d2=d2)
    pain = one(conn, "select count(*) as entries, max(level) as max_level, round(avg(level), 1) as avg_level from pain_entries where deleted_at is null and local_date between :d1 and :d2", d1=d1, d2=d2)
    return {"injuries": inj, "pain": pain}


def _recovery(conn, d1, d2):
    c = one(conn, """select count(*) as days, round(avg(energy), 1) as energy, round(avg(sleep_quality), 1) as sleep_quality, round(avg(soreness), 1) as soreness,
                            round(avg(fatigue), 1) as fatigue, round(avg(motivation), 1) as motivation, round(avg(stress), 1) as stress
                     from daily_checkins where deleted_at is null and local_date between :d1 and :d2""", d1=d1, d2=d2)
    s = one(conn, """select count(*) filter (where not is_nap) as nights, round(avg(duration_s) filter (where not is_nap) / 3600.0, 1) as avg_hours,
                            round(avg(quality) filter (where not is_nap), 1) as avg_quality
                     from sleep_logs where deleted_at is null and local_date between :d1 and :d2""", d1=d1, d2=d2)
    return {"checkin_averages": c, "sleep": s}


def _lifestyle(conn, d1, d2):
    steps = one(conn, """select count(*) as days_logged, round(avg(steps)) as avg_steps, max(steps) as max_steps,
                                count(*) filter (where target_steps is not null and steps >= target_steps) as days_on_target
                         from daily_steps where deleted_at is null and local_date between :d1 and :d2""", d1=d1, d2=d2)
    cardio = one(conn, "select count(*) as sessions, round(coalesce(sum(duration_s), 0) / 60.0) as total_minutes, round(coalesce(sum(distance_m), 0) / 1000.0, 1) as total_km from cardio_sessions where deleted_at is null and local_date between :d1 and :d2", d1=d1, d2=d2)
    hyd = one(conn, "select count(*) as days_logged, round(avg(total_ml)) as avg_ml, round(avg(pct_of_target), 1) as avg_pct_of_target from v_daily_hydration where local_date between :d1 and :d2", d1=d1, d2=d2)
    nut = one(conn, """select count(*) as days_planned, round(avg(planned_protein_g), 1) as avg_planned_protein_g, round(avg(eaten_protein_g), 1) as avg_eaten_protein_g,
                              round(avg(protein_target_g), 1) as avg_protein_target_g from v_daily_nutrition where local_date between :d1 and :d2""", d1=d1, d2=d2)
    sup = rows(conn, """select s.name, count(*) filter (where l.outcome = 'taken') as taken, count(*) filter (where l.outcome = 'missed') as missed, count(*) filter (where l.outcome = 'skipped') as skipped
                        from supplement_logs l join supplements s on s.id = l.supplement_id where l.deleted_at is null and l.local_date between :d1 and :d2 group by s.id, s.name order by s.name""", d1=d1, d2=d2)
    for r in sup:
        r["logged_adherence_pct"] = round(100.0 * r["taken"] / (r["taken"] + r["missed"]), 1) if r["taken"] + r["missed"] else None
    return {"steps": steps, "cardio": cardio, "hydration": hyd, "nutrition": nut, "supplements": sup, "value_kind": "estimated"}


def _goals(conn):
    g = rows(conn, "select title, type, goal_status, target_metric, target_value, start_value, current_value, progress_pct, progress_status from v_goal_progress order by title")
    ms = rows(conn, "select g.title as goal, m.title, m.target_value, m.is_reached from v_goal_milestones m join goals g on g.id = m.goal_id order by g.title, m.target_value")
    return {"goals": g, "milestones": ms, "as_of": "report time"}


def _context(conn, d1, d2):
    return {
        "splits": rows(conn, "select name, pattern, start_date, end_date, duration_days, start_reason, end_reason from v_split_periods where start_date <= :d2 and (end_date is null or end_date >= :d1) order by start_date", d1=d1, d2=d2),
        "breaks": rows(conn, """select title, reason, mode, status, start_date, end_date, (least(end_date, :d2) - greatest(start_date, :d1) + 1) as days_in_period
                                from planned_breaks where deleted_at is null and status <> 'cancelled' and start_date <= :d2 and end_date >= :d1 order by start_date""", d1=d1, d2=d2),
        "deloads": rows(conn, "select start_date, end_date, status, reason, changes from deload_periods where deleted_at is null and status <> 'cancelled' and start_date <= :d2 and end_date >= :d1 order by start_date", d1=d1, d2=d2),
    }


def observations(s: dict) -> list:
    """Short, cautious statements taken from the figures. Observations from the records, never advice or a diagnosis."""
    out = []
    add = lambda code, txt: out.append({"code": code, "text": txt})
    t, a = s["training"], s["training"]["attendance"]
    if t["sessions"]:
        add("training_volume", f"{t['sessions']} workouts, {t['working_sets']} working sets and a total volume of {round(t['volume_kg']):,} kg were logged.")
    if a["scheduled"]:
        add("consistency", f"{a['completed']} of {a['scheduled']} scheduled sessions were completed ({a['consistency_pct']}%). Rest days, rescheduled days and planned breaks are not counted as missed.")
    if a["break_days"]:
        add("breaks", f"{a['break_days']} scheduled day(s) fell inside planned breaks and were left out of the attendance figures.")
    recs = s["strength"]["records"]
    if recs:
        add("records", f"{len(recs)} personal record(s) were set in this period.")
    for e in [e for e in s["strength"]["exercises"] if e["e1rm_change_pct"] is not None][:3]:
        add("strength_change", f"Estimated 1RM for {e['exercise']} changed by {e['e1rm_change_pct']:+}% between its first and last session (an estimate, not a measurement).")
    for m in s["body"]["measurements"]:
        if m["change"] is not None and m["measurement_type"] in ("weight", "body_fat", "waist"):
            how = f" ({m['method'].replace('_', ' ')})" if m["method"] else ""
            add("body_" + m["measurement_type"], f"{m['measurement_type'].replace('_', ' ').capitalize()}{how} went from {m['first_value']} to {m['last_value']} {m['unit']}."
                + (" Body weight is one measure among several; compare it with strength and measurements." if m["measurement_type"] == "weight" else ""))
    changed = [r for r in s["muscles"]["ratings"] if r["assessment_change"] != "same_rating"]
    if changed:
        add("assessment", f"Your own muscle ratings changed for {len(changed)} muscle(s). These are changes in your assessment, not measured growth.")
    sl = s["recovery"]["sleep"]
    if sl.get("nights"):
        add("sleep", f"Average sleep was {sl['avg_hours']} hours across {sl['nights']} nights.")
    st = s["lifestyle"]["steps"]
    if st.get("days_logged"):
        add("steps", f"Steps averaged {int(st['avg_steps']):,}; a target was reached on {st['days_on_target']} of {st['days_logged']} logged days.")
    for r in s["lifestyle"]["supplements"]:
        pct = f" ({r['logged_adherence_pct']}% of logged doses taken)" if r["logged_adherence_pct"] is not None else ""
        add("supplement", f"{r['name']}: {r['taken']} taken, {r['missed']} missed, {r['skipped']} skipped on purpose{pct}.")
    inj = s["injuries"]["injuries"]
    if inj:
        add("injuries", f"{len(inj)} injury record(s) were active, recovering or resolved in this period.")
        if any(i["suggest_professional_review"] for i in inj):
            add("injury_review", "At least one injury record is flagged: consider having its symptoms assessed by a professional.")
    if s["context"]["deloads"]:
        add("deload", "A deload period was recorded in this period.")
    return out


def headline(s: dict) -> dict:
    t = s["training"]
    return {"sessions": t["sessions"], "volume_kg": t["volume_kg"], "consistency_pct": t["attendance"]["consistency_pct"],
            "avg_sleep_hours": s["recovery"]["sleep"].get("avg_hours"), "avg_steps": s["lifestyle"]["steps"].get("avg_steps"),
            "personal_records": len(s["strength"]["records"])}


def build_summary(conn, period: Period, compare: bool = False) -> dict:
    d1, d2 = period.start, period.end
    s = {"period": {"kind": period.kind, "label": period.label, "start": d1, "end": d2, "days": period.days},
         "training": _training(conn, d1, d2), "strength": _strength(conn, d1, d2), "body": _body(conn, d1, d2), "muscles": _muscles(conn, d1, d2),
         "injuries": _injuries(conn, d1, d2), "recovery": _recovery(conn, d1, d2), "lifestyle": _lifestyle(conn, d1, d2),
         "goals": _goals(conn), "context": _context(conn, d1, d2)}
    s["observations"] = observations(s)
    if compare:
        prev = previous_period(period)
        ps = build_summary(conn, prev, compare=False)
        cur_h, prev_h = headline(s), headline(ps)
        s["comparison"] = {"previous_period": ps["period"], "metrics": [
            {"key": k, "current": cur_h[k], "previous": prev_h[k], "change_pct": pct_change(prev_h[k], cur_h[k])} for k in cur_h]}
    return _plain(s)
