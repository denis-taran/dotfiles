#!/usr/bin/env python3

import csv
import json
import os
import sys
from datetime import date
from pathlib import Path
from urllib.request import Request, urlopen

os.umask(0o077)

CRED_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
API_KEY = (CRED_DIR / "clockify-api-key").read_text().strip()
WORKSPACE_ID = (CRED_DIR / "clockify-workspace-id").read_text().strip()
USER_ID = (CRED_DIR / "clockify-user-id").read_text().strip()
BACKUP_DIR = Path.home() / "Backups" / "Clockify"
BASE_URL = "https://api.clockify.me/api/v1"

today = date.today().isoformat()
json_file = BACKUP_DIR / f"backup_{today}.json"
csv_file = BACKUP_DIR / f"backup_{today}.csv"

BACKUP_DIR.mkdir(parents=True, exist_ok=True)
BACKUP_DIR.chmod(0o700)

if json_file.exists() and csv_file.exists():
    sys.exit(0)

req = Request(
    f"{BASE_URL}/workspaces/{WORKSPACE_ID}/user/{USER_ID}/time-entries?page-size=200",
    headers={"X-Api-Key": API_KEY, "Content-Type": "application/json"},
)
with urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read())

if isinstance(data, dict) and "code" in data:
    error_log = BACKUP_DIR / "error.log"
    with open(error_log, "a", encoding="utf-8") as f:
        f.write(f"[{today}] API Error: {json.dumps(data)}\n")
    sys.exit(1)

tmp_json = json_file.with_suffix(".json.tmp")
tmp_csv = csv_file.with_suffix(".csv.tmp")

tmp_json.write_text(json.dumps(data, indent=2), encoding="utf-8")


def parse_time(iso_str: str | None) -> str:
    if not iso_str:
        return "RUNNING"
    return iso_str.split("T")[1].rstrip("Z").split(".")[0]


def parse_date(iso_str: str) -> str:
    return iso_str.split("T")[0]


with open(tmp_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["Date", "Start", "End", "Description", "Duration"])
    for entry in data:
        ti = entry["timeInterval"]
        writer.writerow(
            [
                parse_date(ti["start"]),
                parse_time(ti["start"]),
                parse_time(ti.get("end")),
                entry.get("description", ""),
                ti.get("duration", ""),
            ]
        )

tmp_json.rename(json_file)
tmp_csv.rename(csv_file)

print(f"Backed up {today}")
