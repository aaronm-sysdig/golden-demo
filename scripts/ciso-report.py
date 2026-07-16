#!/usr/bin/env python3
"""
ciso-report.py

Generates a timestamped CISO cluster security posture report from
golden-sample-ciso.tmpl.html and writes:
  /tmp/ciso-report-latest.html  (browser-ready)

Usage:
  python3 scripts/ciso-report.py                     # anchor = now
  python3 scripts/ciso-report.py 2026-07-14T05:30Z   # explicit UTC anchor

Token -> value mapping:
  {{GENERATED_AT}}   "2026-07-14 05:30 UTC"  (report generation time)
  {{INCIDENT_TIME}}  "05:22 UTC"             (active incident time, 8 min before generation)
  {{TREND_DAYS}}     14 stacked day-bars ending on the anchor date; the last
                     bar is "today" (active incident), with prior bursts at
                     7 and 9 days back - so the graph always tracks the
                     generation date instead of being pinned to the 14th.
"""
import sys
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
TEMPLATE   = SCRIPT_DIR / "golden-sample-ciso.tmpl.html"
OUT_HTML   = Path("/tmp/ciso-report-latest.html")


def parse_utc(s: str) -> datetime:
    s = s.strip().rstrip("Z").replace("+00:00", "")
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    raise ValueError(f"Cannot parse datetime: {s!r}")


# Runtime-detection bursts, keyed by how many days before the anchor ("today")
# they occurred. Mirrors the original golden-sample story: a quiet cluster with
# three bursts against customer-portal, the last one being today's live incident.
BURSTS = {
    0: {"high": 4, "medium": 3, "active": True},   # today - active incident
    7: {"high": 4, "medium": 3},                    # one week ago
    9: {"high": 0, "medium": 10},                   # nine days ago
}
PX_PER_COUNT = 9  # bar pixel height per detection (max daily total = 10 -> 90px)


def build_trend_days(anchor: datetime) -> str:
    """Render 14 stacked day-bars ending on the anchor date."""
    today = anchor.date()
    rows = []
    for days_back in range(13, -1, -1):
        d = today - timedelta(days=days_back)
        dl = d.strftime("%d")
        burst = BURSTS.get(days_back)

        if not burst:
            rows.append(
                f'<div class="day"><div class="cnt">&nbsp;</div>'
                f'<div class="stack"></div><div class="dl">{dl}</div></div>'
            )
            continue

        high, medium = burst.get("high", 0), burst.get("medium", 0)
        total = high + medium
        active = burst.get("active", False)

        segs = ""
        if high:
            segs += f'<div class="b h" style="height:{high * PX_PER_COUNT}px" title="High: {high}"></div>'
        if medium:
            segs += f'<div class="b m" style="height:{medium * PX_PER_COUNT}px" title="Medium: {medium}"></div>'

        parts = ([f"{high} high"] if high else []) + ([f"{medium} medium"] if medium else [])
        label = d.strftime("%d %b")
        title = f"{label} (today): {', '.join(parts)} (active incident)" if active \
            else f"{label}: {', '.join(parts)}"

        rows.append(
            f'<div class="day" title="{title}">'
            f'<div class="cnt">{total}</div>'
            f'<div class="stack">{segs}</div>'
            f'<div class="dl">{dl}</div></div>'
        )
    return "\n        ".join(rows)


def fill(content: str, anchor: datetime) -> str:
    incident_time = anchor - timedelta(minutes=8)
    tokens = {
        "{{GENERATED_AT}}":  anchor.strftime("%Y-%m-%d %H:%M UTC"),
        "{{INCIDENT_TIME}}": incident_time.strftime("%H:%M UTC"),
        "{{TREND_DAYS}}":    build_trend_days(anchor),
    }
    for token, value in tokens.items():
        content = content.replace(token, value)
    return content


def main():
    anchor = parse_utc(sys.argv[1]) if len(sys.argv) > 1 else datetime.now(timezone.utc).replace(microsecond=0)

    content = TEMPLATE.read_text()
    filled  = fill(content, anchor)

    OUT_HTML.write_text(filled)

    ts = anchor.strftime("%Y-%m-%dT%H:%MZ")
    print(f"  Anchor: {ts} UTC")
    print(f"  Open:   file://{OUT_HTML}")
    subprocess.run(["open", "-a", "Google Chrome", f"file://{OUT_HTML}"], check=False)


if __name__ == "__main__":
    main()
