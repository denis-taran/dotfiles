#!/usr/bin/env python3

import csv
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

REPORT_DIR = Path.home() / "Desktop"

API_KEY = input("Clockify API key: ").strip()
WORKSPACE_ID = input("Clockify workspace ID: ").strip()
USER_ID = input("Clockify user ID: ").strip()
TIMEZONE = ZoneInfo("Europe/Berlin")
BASE_URL = "https://api.clockify.me/api/v1"


def api_get(path: str) -> list | dict:
    req = Request(
        f"{BASE_URL}{path}",
        headers={"X-Api-Key": API_KEY, "Content-Type": "application/json"},
    )
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


now = datetime.now(TIMEZONE)
current_day = now.day

if current_day < 15:
    first_of_month = now.replace(day=1)
    end_dt = first_of_month - timedelta(seconds=1)
    start_dt = (first_of_month - timedelta(days=1)).replace(
        day=1, hour=0, minute=0, second=0, microsecond=0
    )
    report_month = start_dt.strftime("%Y-%m")
else:
    start_dt = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    next_month = (start_dt + timedelta(days=32)).replace(day=1)
    end_dt = next_month - timedelta(seconds=1)
    report_month = now.strftime("%Y-%m")

start_utc = start_dt.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ")
end_utc = end_dt.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ")

start_enc = quote(start_utc, safe="")
end_enc = quote(end_utc, safe="")

entries = api_get(
    f"/workspaces/{WORKSPACE_ID}/user/{USER_ID}/time-entries"
    f"?start={start_enc}&end={end_enc}&page-size=5000"
)

if isinstance(entries, dict) and "code" in entries:
    print(f"API Error on Time Entries: {json.dumps(entries)}")
    sys.exit(1)

projects = api_get(f"/workspaces/{WORKSPACE_ID}/projects")
project_map = {p["id"]: p["name"] for p in projects}

entries_by_project: dict[str | None, list] = defaultdict(list)
for entry in entries:
    entries_by_project[entry.get("projectId")].append(entry)


def safe_name(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_]", "", name.replace(" ", "_"))


def parse_iso(iso_str: str) -> datetime:
    return datetime.fromisoformat(iso_str.replace("Z", "+00:00"))


for project_id, project_entries in entries_by_project.items():
    if project_id is None:
        project_name = "No_Project"
    else:
        project_name = safe_name(
            project_map.get(project_id, f"Unknown_Project_{project_id}")
        )

    report_file = REPORT_DIR / f"Report_{project_name}_{report_month}.csv"
    print(report_file)

    days: dict[str, list] = defaultdict(list)
    for entry in project_entries:
        ti = entry["timeInterval"]
        start = parse_iso(ti["start"]).astimezone(TIMEZONE)
        local_date = start.strftime("%Y-%m-%d")
        days[local_date].append(entry)

    with open(report_file, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(
            ["Date", "Start_Time", "End_Time", "Total_Hours", "Combined_Descriptions"]
        )

        for day_date in sorted(days):
            day_entries = days[day_date]
            start_times = []
            end_times = []
            total_seconds = 0
            descriptions = set()

            for entry in day_entries:
                ti = entry["timeInterval"]
                start = parse_iso(ti["start"]).astimezone(TIMEZONE)
                start_times.append(start.strftime("%H:%M"))

                if ti.get("end"):
                    end = parse_iso(ti["end"]).astimezone(TIMEZONE)
                    end_times.append(end.strftime("%H:%M"))
                    total_seconds += (end - start).total_seconds()

                desc = entry.get("description")
                if desc:
                    descriptions.add(desc)

            writer.writerow(
                [
                    day_date,
                    min(start_times),
                    max(end_times) if end_times else "",
                    round(total_seconds / 3600, 2),
                    "; ".join(sorted(descriptions)),
                ]
            )
