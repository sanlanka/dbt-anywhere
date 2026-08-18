#!/usr/bin/env python3
"""Snapshot GitHub Traffic (views + clones) and accumulate history.

These metrics aren't publicly visible — reading them needs Administration:read
(here, a short-lived GitHub App installation token). GitHub keeps traffic for
only 14 days, so we merge each day's numbers by date into CSVs to build
unlimited history, and write a readable SUMMARY.md.

Env:
  REPO      "owner/name"
  GH_TOKEN  GitHub App installation token with Administration:read
"""
import csv, json, os, sys, urllib.request, urllib.error, datetime

REPO = os.environ["REPO"]
TOKEN = os.environ["GH_TOKEN"]
STATS = os.environ.get("STATS_DIR", "stats")   # target dir (a checkout of the stats branch)
os.makedirs(STATS, exist_ok=True)


def gh(kind):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/traffic/{kind}",
        headers={"Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28",
                 "Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            sys.exit(f"ERROR {e.code} on /traffic/{kind}: token can't read traffic. "
                     f"Ensure the GitHub App has Administration:read and is installed on {REPO}.")
        raise


def merge(kind):
    """Merge the API's rolling 14-day window into the CSV; newest wins per date."""
    path = os.path.join(STATS, f"{kind}.csv")
    rows = {}
    if os.path.exists(path):
        with open(path) as f:
            for r in csv.DictReader(f):
                rows[r["date"]] = (int(r["count"]), int(r["uniques"]))
    for e in gh(kind).get(kind, []):
        rows[e["timestamp"][:10]] = (e["count"], e["uniques"])
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "count", "uniques"])
        for day in sorted(rows):
            w.writerow([day, rows[day][0], rows[day][1]])
    return sum(c for c, _ in rows.values()), sum(u for _, u in rows.values()), len(rows)


def badge(name, label, value, color="blue"):
    """Write a shields.io endpoint-badge JSON so the count can render on main."""
    with open(os.path.join(STATS, f"{name}.json"), "w") as f:
        json.dump({"schemaVersion": 1, "label": label,
                   "message": f"{value:,}", "color": color}, f)


v_total, v_uniq, v_days = merge("views")
c_total, c_uniq, c_days = merge("clones")

badge("views", "page views", v_total, "blue")
badge("visitors", "unique visitors", v_uniq, "blueviolet")
badge("clones", "clones", c_total, "green")

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
with open(os.path.join(STATS, "SUMMARY.md"), "w") as f:
    f.write(f"""# Traffic — {REPO}

_Last updated: {now}. Accumulated daily from the GitHub Traffic API (which keeps
only 14 days). "Unique" is the sum of per-day uniques, so it slightly
over-counts visitors who return on different days._

| Metric | All-time | Days |
|---|--:|--:|
| 📈 Page views | {v_total} | {v_days} |
| 🧍 Unique visitors (Σ daily) | {v_uniq} | {v_days} |
| ⬇️ Clones | {c_total} | {c_days} |
| 🧍 Unique cloners (Σ daily) | {c_uniq} | {c_days} |

History: [`views.csv`](views.csv) · [`clones.csv`](clones.csv)
""")

print(f"views={v_total} over {v_days}d | clones={c_total} over {c_days}d")
