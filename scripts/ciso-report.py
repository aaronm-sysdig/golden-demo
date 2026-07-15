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


def fill(content: str, anchor: datetime) -> str:
    incident_time = anchor - timedelta(minutes=8)
    tokens = {
        "{{GENERATED_AT}}":  anchor.strftime("%Y-%m-%d %H:%M UTC"),
        "{{INCIDENT_TIME}}": incident_time.strftime("%H:%M UTC"),
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
