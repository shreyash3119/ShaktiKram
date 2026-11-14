"""Charts for the PDF report, drawn with matplotlib (no display needed). Each function returns PNG bytes, or None when there is nothing to draw."""
from io import BytesIO

from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.figure import Figure

BLUE, GREY = "#1F4E78", "#888888"


def _png(fig: Figure) -> bytes:
    FigureCanvasAgg(fig)
    buf = BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    return buf.getvalue()


def _base(title, ylabel):
    fig = Figure(figsize=(7.2, 2.6))
    ax = fig.subplots()
    ax.set_title(title, fontsize=10, loc="left")
    ax.set_ylabel(ylabel, fontsize=8)
    ax.tick_params(labelsize=7)
    ax.grid(axis="y", alpha=0.25)
    return fig, ax


def weekly_volume(s):
    w = s["training"]["weekly"]
    if not w:
        return None
    fig, ax = _base("Training volume per week", "kg")
    ax.bar([r["week_start"].strftime("%d %b") for r in w], [r["volume_kg"] or 0 for r in w], color=BLUE)
    return _png(fig)


def weekly_consistency(s):
    w = [r for r in s["training"]["attendance"]["weekly"] if r["consistency_pct"] is not None]
    if not w:
        return None
    fig, ax = _base("Consistency per week (breaks and rest days are not counted as missed)", "%")
    ax.bar([r["week_start"].strftime("%d %b") for r in w], [r["consistency_pct"] for r in w], color=BLUE)
    ax.set_ylim(0, 105)
    return _png(fig)


def weight_trend(s):
    w = s["body"]["weight_series"]
    if len(w) < 2:
        return None
    fig, ax = _base("Body weight (one measure among several)", "kg")
    ax.plot([r["date"] for r in w], [r["value"] for r in w], marker="o", markersize=3, color=BLUE)
    return _png(fig)


def e1rm_trend(s):
    ser = s["strength"]["e1rm_series"]
    if not ser:
        return None
    fig, ax = _base("Estimated 1RM by session (estimates)", "kg")
    for name, pts in ser.items():
        ax.plot([p["date"] for p in pts], [p["e1rm_kg"] for p in pts], marker="o", markersize=3, label=name)
    ax.legend(fontsize=7)
    return _png(fig)
