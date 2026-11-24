import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BatteryFixtureTests(unittest.TestCase):
    def test_generator_output_is_valid_sorted_and_spans_100_days(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "history.jsonl"
            today = dt.date.today()
            subprocess.run([sys.executable, str(ROOT / "tests/fixtures/make_battery_history.py"),
                            "--out", str(out), "--end", today.isoformat()], check=True)
            rows = [json.loads(line) for line in out.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(rows[0], {"v": 1})
            events = rows[1:]
            self.assertTrue(events)
            times = [row["t"] for row in events]
            self.assertEqual(times, sorted(times))
            first = dt.datetime.fromtimestamp(times[0] / 1000, dt.timezone.utc).date()
            last = dt.datetime.fromtimestamp(times[-1] / 1000, dt.timezone.utc).date()
            self.assertGreaterEqual((last - first).days, 100)


if __name__ == "__main__":
    unittest.main()
