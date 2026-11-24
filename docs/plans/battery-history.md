# Plan: battery runtime estimate and history chart

Status: phases 1–4 implemented and reviewed on 2026-11-24 (161/161 CTest,
fixture checked visually in Midnight, Ice and Amber with `sonyd --simulated`).
Phase 5 hardware evaluation is pending. Owner of review and
evaluation: Claude. Implementer: Codex. Branch: `feat/home-dashboard-macos`.

## Goal

The headset only reports a battery percentage and a charging flag (no runtime
or elapsed time; see `BatteryState` in
`libs/sony-protocol/include/sony/protocol/SemanticTypes.h`). The app learns the
drain rate itself, so it can show:

1. **Full-charge runtime**: `T_full = 90 / r` hours (100 % → 10 %).
2. **Remaining to 10 %**: `T_rem = (p − 10) / r` hours, where `p` is the
   current level. If `p ≤ 10`, show "below 10 %".
3. **History chart** of the daily full-charge runtime, used to track battery
   wear over months.

`r` is the drain rate in percent per hour.

## Rules for measuring the rate (do not change without review)

- Record a raw event only when something changes: connect, a level change,
  charging start/stop, disconnect, or a gap. Never record every snapshot. The
  GUI receives snapshots every 0.5–1 s; the device service reads the battery
  every 30 s and on notifications.
- **Session**: from connect to disconnect. A new session also starts when
  snapshots stop arriving for more than **120 s** (Mac sleep, app hang, app
  quit). Record that as a `gap` event once snapshots resume. Never join data
  across sessions.
- **Discharge segment**: inside one session, starts at the **first observed
  level decrease**. The first reading after connect is quantized (a reported
  80 may be 80–84.9), so it is never a segment start. A segment ends at
  charging start, disconnect, gap, or a level increase while not charging (a
  recalibration). A level increase restarts the segment from the next decrease.
- Data recorded while `charging == true` is never used for rates.
- A **segment** contributes only when it has at least 2 decrease points and
  lasts at least **30 min**. Its contribution is `drop = L_first − L_last` and
  `hours = t_last − t_first`.
- Attribute each interval between consecutive decrease points to the local
  calendar day containing the interval's midpoint.
- **Daily aggregate**: `rate = Σdrop / Σhours`; `fullHours = 90 / rate`.
  `valid = Σhours ≥ 1.0 && Σdrop ≥ 10`.
- **Rolling trend**: for day `d`, window `[d−6, d]`.
  `rate = Σdrop / Σhours` over all intervals in the window (time-weighted by
  construction). Emit it only when the window has `Σhours ≥ 2`.
- **Current rate for live estimates**: intervals from the last 14 days, if
  `Σhours ≥ 3`. Otherwise use the model spec prior below. Otherwise report
  unknown.
- **Battery health**: `health = rate_baseline / rate_recent`, i.e. the ratio of
  full-charge runtimes. Baseline is the first 30 calendar days that contain
  data; recent is the last 30 days. Report it only when both windows have
  `Σhours ≥ 10`, they do not overlap, and the first recorded day is at least
  60 days ago. Otherwise report "not enough data".
- Each level event records the noise-control mode and codec. A day stores
  `ancShare`: the share of interval time in which the mode was
  `cancelling` (the app snapshot value; legacy `noiseCancelling` is also
  accepted), using the mode at the interval's end point. This is for
  display and for a later per-mode filter; rates are not split by mode in v1.
- Dual-battery models (WF, LinkBuds): use `min(left, right)` when `main` is
  absent; ignore the case battery.

### Spec prior (full-charge hours, NC on / NC off), from Sony published specs

| Model | NC on | NC off |
| --- | --- | --- |
| WH-1000XM4 | 30 | 38 |
| WH-1000XM5 | 30 | 40 |
| WH-1000XM6 | 30 | 40 |

`specFullHours()` returns these raw Sony hours unchanged (100 → 0). Convert to
a rate: `r = 100 / hours`; `fullChargeHours()` then yields `90 / r = 0.9 × hours`
(XM5 NC on: 27 h). Apply the 0.9 factor exactly once. Choose the column by the current mode
(`cancelling` → NC on, otherwise NC off; legacy `noiseCancelling` is also
recognized). Other models have no prior.
The UI must label prior-based numbers as "(spec)".

## Phase 1: pure algorithm in sony-core (no Qt)

Files:
- `libs/sony-core/include/sony/core/BatteryHistory.h`
- `libs/sony-core/src/BatteryHistory.cpp` (add to `libs/sony-core/CMakeLists.txt`)
- `tests/core/BatteryHistoryTests.cpp` (add to `sony-core-tests` in `tests/CMakeLists.txt`)

API (names may be refined, but keep the shape):

```cpp
namespace sony::core::battery {
enum class EventKind { Connect, Level, ChargeStart, ChargeEnd, Disconnect, Gap };
struct Event {
    std::int64_t epochMs; EventKind kind; int level{-1};   // level for Level/Connect
    std::string mode;  std::string codec;                  // optional, Level events
};
struct Interval { std::int64_t startMs, endMs; int drop; bool anc; };
struct DayStat  { std::string date /*YYYY-MM-DD local*/; double hours; int drop;
                  double rate; double fullHours; double ancShare; bool valid; };
struct TrendPoint { std::string date; double fullHours; double hours; };
struct Estimate { double ratePerHour; enum Source { None, Spec, Measured } source;
                  int sampleDays; };

std::vector<Interval> extractIntervals(const std::vector<Event>&);          // rules above
std::vector<DayStat>  aggregateDays(const std::vector<Interval>&, TzOffsetFn);
std::vector<TrendPoint> rollingTrend(const std::vector<Interval>&, TzOffsetFn);
Estimate currentEstimate(const std::vector<Interval>&, std::int64_t nowMs,
                         std::optional<double> specFullHours);
std::optional<double> healthRatio(const std::vector<Interval>&, std::int64_t nowMs, TzOffsetFn);
std::optional<double> fullChargeHours(const Estimate&);                    // 90 / r
std::optional<double> remainingHours(const Estimate&, int level);          // (p−10)/r, 0 if p≤10
std::optional<double> specFullHours(protocol::SonyModel, bool ancOn);
}
```

`TzOffsetFn` maps an epoch to a local UTC offset so tests are deterministic.
Pass UTC (offset 0) in tests.

Required tests (Catch2, tag `[battery-history]`):
1. The first reading after connect is not a segment start: Connect 80, then
   Level 75 @t0, 70 @t0+3h, so `drop = 5`, `hours = 3`.
2. Disconnect splits segments; nothing spans the gap.
3. A `Gap` event splits like a disconnect.
4. Charging: levels during charging are ignored, and a new segment starts after
   ChargeEnd at the first decrease.
5. A level increase without charging restarts the segment.
6. A segment shorter than 30 min, or with fewer than 2 points, is dropped.
7. Day attribution across midnight uses the interval midpoint.
8. Daily `valid` flag thresholds (exactly 1 h and 10 % is valid).
9. Rolling trend weights by time, not by day count.
10. Estimate falls back to the spec, then to None. Measured requires ≥ 3 h in
    14 days.
11. `remainingHours` at p = 10 and p = 5 returns 0; at p = 70 with 3.33 %/h it
    returns ≈ 18 h.
12. Health: insufficient data gives nullopt. Wear means the battery drains
    FASTER: baseline drops 9 % per 10 h, recent drops 10 % per 10 h (runtime
    10 % shorter), which gives ≈ 0.9 ± 0.01. A recent drain slower than the
    baseline gives a value > 1 (not clamped). `health = rate_baseline / rate_recent`.
13. Dual battery and level −1 events are ignored, with no crash.

Acceptance: `ctest -R battery-history` passes; there is no Qt dependency in
sony-core; the existing tests still pass.

## Phase 2: recording and persistence (app, Qt)

Files: `apps/device-center/include/BatteryHistoryStore.h` and
`apps/device-center/src/BatteryHistoryStore.cpp`, added to both the app and the
`sony-ui-tests` targets.

- Storage: `QStandardPaths::AppDataLocation` + `/battery-history/<MAC>.jsonl`.
  Use one JSON object per line: `{"t":epochMs,"k":"level","l":75,"m":"cancelling","c":"LDAC"}`.
  Sanitize the MAC for the filename (`:` → `-`, uppercase). An empty address
  means nothing is recorded.
- Append-only writes. A corrupt line is skipped on load and does not abort the
  load. Add a header line `{"v":1}` in new files and keep loading files that
  lack it.
- File I/O never runs on the GUI thread. The store owns a `QThread` with a
  writer QObject. Appends are queued; loading happens there and the result is
  emitted back to the GUI thread.
- A recorder (in the store or a small class) is fed from
  `DeviceCenterController::_applySnapshot` with
  `(nowMs, address, connected, level, charging, mode, codec)`. It derives the
  events. It tracks `lastSnapshotMs`; a gap greater than 120 s emits `Gap`
  before the next event. It deduplicates, so it writes only on change.
- It keeps the events in memory per device for computation (the file is the
  source of truth; days and the trend are recomputed from the events).
- `clearHistory(address)` deletes the file and the memory.
  `exportCsv(address, path)` writes the daily aggregates:
  `date,hours,drop,fullHours,ancShare,valid`.

Tests (QtTest, extend `tests/ui/DeviceControllerTests.cpp` or add a new test
file in the same target, using `QStandardPaths::setTestModeEnabled(true)` and
an injected clock):
- Feeding 1000 identical snapshots writes one event.
- A connect → level changes → disconnect sequence round-trips through the file.
- The gap rule works with an injected clock.
- A corrupt line in the middle of the file is skipped.
- Nothing is written for an empty address or while disconnected.

## Phase 3: controller API and live estimate on Home

Add to `DeviceCenterController` (NOTIFY `batteryHistoryChanged`):
- `int estimatedFullMinutes` (−1 for unknown)
- `int estimatedRemainingMinutes` (−1 for unknown, 0 for ≤ 10 %)
- `QString estimateSource` ("none" | "spec" | "measured")
- `int estimateSampleDays`
- `QVariantList batteryHistoryDays`: maps with
  `{date, fullHours, hours, ancShare, valid}`
- `QVariantList batteryTrend`: `{date, fullHours}`
- `double batteryHealth` (−1 for not enough data)
- `Q_INVOKABLE` `clearBatteryHistory()` and `exportBatteryHistory(QUrl)`

Round the minutes to 30. Hide the remaining value while charging. Recompute on
each new event, not on every snapshot.

Home card (`Main.qml`, device and battery card near line 1819): under the
battery value, add two compact lines, "Remaining to 10 %: ~18 h" and
"Full charge: ~27 h · measured, 3 days" (or "(spec)"). Clicking opens the
history popup from phase 4. Add i18n keys in `I18nManager.cpp`: English is
required, and the other languages fall back to English.

## Phase 4: history chart popup

- New file `apps/device-center/qml/BatteryHistoryChart.qml` (add to
  `qml.qrc`). Do not add Qt Charts or Qt Graphs. Draw with `Canvas` or `Shape`.
- Show the daily points: filled when valid, hollow when not. Draw the 7-day
  trend line, and a dashed spec line when a prior exists. The Y axis is hours,
  the X axis is dates. Leave missing days blank and do not connect across them.
- Add a range selector (30 d / 90 d / all), a health summary
  ("Battery health ≈ 92 %" or "Not enough data yet"), an Export CSV button
  (save dialog), and Clear history with a confirmation.
- Hovering or tapping a point shows the date, the hours, the observed time and
  the ANC share.
- Colours come from the theme tokens already used in `Main.qml`
  (Midnight, Ice, Graphite). The chart must read in light and dark.
- Keep the new QML out of the monolithic file as much as possible (issue #21).

## Phase 5: evaluation (Claude)

After each phase:
1. Review the diff against this plan, especially the measurement rules.
2. `cmake --build build-macos --parallel 2` and
   `ctest --test-dir build-macos --output-on-failure --no-tests=error`.
3. After phases 3 and 4: launch the app. Check the chart with a seeded
   `.jsonl` fixture of about 120 days of synthetic data with a 10 % decline
   (`tests/fixtures/battery-history-sample.jsonl`), in all three themes.
4. Hardware (user): use an XM5 for several days. Compare the measured
   full-charge runtime with the spec (~30 h with ANC). Record the model,
   firmware, macOS version and commit.

Known limitations to state in the UI help text: the app only measures while it
is running and connected. Use with a phone is not counted, but the level read
on reconnect is still correct.
