#!/usr/bin/env python3
"""
aiworkload-report.py

Generates a timestamped investigation report from golden-sample-aiworkload.tmpl.md,
anchored to the current time (or a provided UTC time), and writes:
  /tmp/aiworkload-investigation-latest.md
  /tmp/aiworkload-investigation-latest.html  (browser-ready, Mermaid-capable)

Usage:
  python3 ai-workload/scripts/aiworkload-report.py                     # anchor = now
  python3 ai-workload/scripts/aiworkload-report.py 2026-06-25T14:30Z   # explicit UTC anchor

Token -> original value mapping:
  {{DATE}}   2026-06-25   (attack date)
  {{T_APP}}  06:38:58     (Python app.py start, ~13m 35s before attack)
  {{T0}}     06:52:33     (attack anchor - first shell spawned)
  {{T0_R}}   06:52:34     (id && hostname recon, T+1s)
  {{T0_S}}   06:52:35     (env secret harvest, T+2s)
  {{T0_L}}   06:52:36     (OPENAI/ANTHROPIC key exfil, T+3s)
  {{T0_F}}   06:52:37     (find .aws/credentials, T+4s)
  {{T0_C}}   06:52:38     (cat /root/.aws/credentials, T+5s)
  {{T0_I}}   06:52:39     (IMDS curl, T+6s)
  {{HM}}     06:52        (HH:MM prose reference)
"""
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
TEMPLATE   = SCRIPT_DIR / "golden-sample-aiworkload.tmpl.md"
OUT_MD     = Path("/tmp/aiworkload-investigation-latest.md")
OUT_HTML   = Path("/tmp/aiworkload-investigation-latest.html")

VENDOR = Path(__file__).parent.parent.parent / "scripts" / "vendor"


def parse_utc(s: str) -> datetime:
    s = s.strip().rstrip("Z").replace("+00:00", "")
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    raise ValueError(f"Cannot parse datetime: {s!r}")


def fill(content: str, anchor: datetime) -> str:
    t_app = anchor - timedelta(minutes=13, seconds=35)

    tokens = {
        "{{DATE}}":   anchor.strftime("%Y-%m-%d"),
        "{{T_APP}}":  t_app.strftime("%H:%M:%S"),
        "{{T0}}":     anchor.strftime("%H:%M:%S"),
        "{{T0_R}}":   (anchor + timedelta(seconds=1)).strftime("%H:%M:%S"),
        "{{T0_S}}":   (anchor + timedelta(seconds=2)).strftime("%H:%M:%S"),
        "{{T0_L}}":   (anchor + timedelta(seconds=3)).strftime("%H:%M:%S"),
        "{{T0_F}}":   (anchor + timedelta(seconds=4)).strftime("%H:%M:%S"),
        "{{T0_C}}":   (anchor + timedelta(seconds=5)).strftime("%H:%M:%S"),
        "{{T0_I}}":   (anchor + timedelta(seconds=6)).strftime("%H:%M:%S"),
        "{{HM}}":     anchor.strftime("%H:%M"),
    }

    for token, value in tokens.items():
        content = content.replace(token, value)

    return content


HTML_SHELL = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Sysdig Runtime Investigation - ai-workload ({ts})</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", sans-serif; max-width: 1200px; margin: 2em auto; padding: 0 1.5em; line-height: 1.55; color: #1f2328; }}
  h1, h2, h3, h4 {{ color: #1f2328; line-height: 1.25; margin-top: 1.6em; }}
  h1 {{ border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }}
  h2 {{ border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }}
  code {{ background: #f6f8fa; padding: 2px 6px; border-radius: 4px; font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: 0.92em; }}
  pre {{ background: #f6f8fa; padding: 1em; border-radius: 6px; overflow-x: auto; }}
  pre code {{ background: transparent; padding: 0; }}
  table {{ border-collapse: collapse; width: 100%; margin: 1em 0; }}
  th, td {{ border: 1px solid #d0d7de; padding: 6px 12px; text-align: left; vertical-align: top; }}
  th {{ background: #f6f8fa; font-weight: 600; }}
  blockquote {{ border-left: 4px solid #d0d7de; color: #57606a; padding: 0 1em; margin: 1em 0; }}
  .mermaid {{ text-align: center; margin: 1.5em 0; background: #fafbfc; padding: 1em; border-radius: 6px; }}
  @media (prefers-color-scheme: dark) {{
    body {{ background: #0d1117; color: #c9d1d9; }}
    h1, h2, h3, h4 {{ color: #c9d1d9; }}
    h1, h2 {{ border-bottom-color: #30363d; }}
    code, pre {{ background: #161b22; }}
    th {{ background: #161b22; }}
    th, td {{ border-color: #30363d; }}
    blockquote {{ border-left-color: #30363d; color: #8b949e; }}
    .mermaid {{ background: #161b22; }}
  }}
</style>
</head>
<body>
<div id="rendered"></div>

<script id="md" type="text/markdown">
{content}
</script>

<script>{marked_js}</script>
<script>{mermaid_js}</script>
<script>
  (async function() {{
    const src = document.getElementById('md').textContent;
    document.getElementById('rendered').innerHTML = marked.parse(src);

    document.querySelectorAll('pre code.language-mermaid').forEach((el) => {{
      const div = document.createElement('div');
      div.className = 'mermaid';
      div.textContent = el.textContent;
      el.parentElement.replaceWith(div);
    }});

    mermaid.initialize({{
      startOnLoad: false,
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
      flowchart: {{ curve: 'basis', useMaxWidth: true }},
    }});
    await mermaid.run();
  }})();
</script>
</body>
</html>
"""


def main():
    anchor = parse_utc(sys.argv[1]) if len(sys.argv) > 1 else datetime.now(timezone.utc).replace(microsecond=0)

    marked_js  = (VENDOR / "marked.min.js").read_text()
    mermaid_js = (VENDOR / "mermaid.min.js").read_text()

    content = TEMPLATE.read_text()
    filled  = fill(content, anchor)

    OUT_MD.write_text(filled)

    ts   = anchor.strftime("%Y-%m-%dT%H:%MZ")
    html = HTML_SHELL.format(ts=ts, content=filled, marked_js=marked_js, mermaid_js=mermaid_js)
    OUT_HTML.write_text(html)

    print(f"  Anchor: {ts} UTC")
    print(f"  Open:   file://{OUT_HTML}")


if __name__ == "__main__":
    main()
