#!/usr/bin/env python3
"""Generate deterministic synthetic battery history for UI evaluation."""
import argparse
import datetime as dt
import json
import random
from pathlib import Path


def generate(out: Path, end: dt.date) -> None:
    rng = random.Random(20261124)
    start = end - dt.timedelta(days=119)
    rows = [{"v": 1}]
    base = dt.datetime.combine(start, dt.time(8), tzinfo=dt.timezone.utc)
    for day in range(120):
        date = start + dt.timedelta(days=day)
        if day not in (19, 47, 88, 107) and rng.random() > 0.055:
            sessions = rng.randint(1, 3)
            runtime = 29.0 - 3.0 * day / 119.0
            for session in range(sessions):
                start_minutes = session * 7 * 60 + rng.randint(0, 55)
                stamp = base + dt.timedelta(days=day, minutes=start_minutes)
                level = rng.randint(76, 92)
                rows.append({"t": int(stamp.timestamp() * 1000), "k": "connect", "l": level})
                rows.append({"t": int(stamp.timestamp() * 1000), "k": "level", "l": level, "m": "cancelling", "c": "LDAC"})
                step_minutes = max(55, round((5 / (90 / runtime)) * 60))
                steps = rng.randint(3, 6)
                for step in range(1, steps + 1):
                    level -= 5
                    event_time = stamp + dt.timedelta(minutes=step * step_minutes)
                    rows.append({"t": int(event_time.timestamp() * 1000), "k": "level", "l": level, "m": "cancelling", "c": "LDAC"})
                if rng.random() < 0.28:
                    charge_time = stamp + dt.timedelta(minutes=(steps * step_minutes) + 5)
                    rows.append({"t": int(charge_time.timestamp() * 1000), "k": "chargeStart"})
                    rows.append({"t": int((charge_time + dt.timedelta(minutes=25)).timestamp() * 1000), "k": "chargeEnd"})
                if day in (23, 56, 94) and session == 0:
                    gap_time = stamp + dt.timedelta(minutes=steps * step_minutes + 8)
                    rows.append({"t": int(gap_time.timestamp() * 1000), "k": "gap"})
                finish = stamp + dt.timedelta(minutes=steps * step_minutes + 30)
                rows.append({"t": int(finish.timestamp() * 1000), "k": "disconnect"})
    cutoff = int(dt.datetime.combine(end, dt.time(21), tzinfo=dt.datetime.now().astimezone().tzinfo).timestamp() * 1000)
    for row in rows[1:]:
        row["t"] = min(row["t"], cutoff)
    rows[1:] = sorted(rows[1:], key=lambda item: item["t"])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--end", type=dt.date.fromisoformat, required=True)
    args = parser.parse_args()
    generate(args.out, args.end)


if __name__ == "__main__":
    main()
