#include <sony/core/BatteryHistory.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <map>
#include <tuple>

namespace sony::core::battery {
namespace {
using namespace std::chrono;
constexpr std::int64_t kMinSegmentMs = 30 * 60 * 1000;
constexpr std::int64_t kDayMs = 24 * 60 * 60 * 1000;
struct Bucket { double hours{}, drop{}, ancHours{}; };
struct TimedInterval { Interval interval; sys_days day; };
bool isAncMode(const std::string& mode) { return mode == "cancelling" || mode == "noiseCancelling"; }

sys_days localDay(std::int64_t ms, const TzOffsetFn& offset) {
    const auto local = milliseconds{ms + (offset ? offset(ms) : 0) * 1000LL};
    return floor<days>(sys_time<milliseconds>{local});
}
std::string dateString(sys_days day) {
    const year_month_day ymd{day};
    char out[11];
    std::snprintf(out, sizeof(out), "%04d-%02u-%02u", int(ymd.year()), unsigned(ymd.month()), unsigned(ymd.day()));
    return out;
}
std::vector<TimedInterval> timed(const std::vector<Interval>& intervals, const TzOffsetFn& offset) {
    std::vector<TimedInterval> result;
    for (const auto& i : intervals) {
        if (i.endMs <= i.startMs || i.drop <= 0) continue;
        const auto mid = i.startMs + (i.endMs - i.startMs) / 2;
        result.push_back({i, localDay(mid, offset)});
    }
    return result;
}
}

std::vector<Interval> extractIntervals(const std::vector<Event>& events) {
    std::vector<Event> sorted = events;
    std::stable_sort(sorted.begin(), sorted.end(), [](const auto& a, const auto& b) { return a.epochMs < b.epochMs; });
    std::vector<Interval> out;
    std::vector<Event> points;
    bool connected = false, charging = false;
    int previousLevel = -1;
    auto finish = [&] {
        if (points.size() >= 2 && points.back().epochMs - points.front().epochMs >= kMinSegmentMs) {
            for (std::size_t n = 1; n < points.size(); ++n) {
                const auto& a = points[n - 1]; const auto& b = points[n];
                if (a.level > b.level && b.epochMs > a.epochMs)
                    out.push_back({a.epochMs, b.epochMs, a.level - b.level, isAncMode(b.mode)});
            }
        }
        points.clear();
    };
    for (const auto& e : sorted) {
        switch (e.kind) {
        case EventKind::Connect:
            finish(); connected = true; charging = false; previousLevel = e.level; break;
        case EventKind::Disconnect: case EventKind::Gap:
            finish(); connected = false; charging = false; previousLevel = -1; break;
        case EventKind::ChargeStart:
            if (connected) finish(); charging = true; break;
        case EventKind::ChargeEnd:
            charging = false; previousLevel = -1; break;
        case EventKind::Level:
            if (!connected || e.level < 0 || e.level > 100) break;
            if (charging) { previousLevel = e.level; break; }
            if (previousLevel >= 0 && e.level > previousLevel) finish();
            if (previousLevel >= 0 && e.level < previousLevel) points.push_back(e);
            previousLevel = e.level;
            break;
        }
    }
    finish();
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) { return a.startMs < b.startMs; });
    return out;
}

std::vector<DayStat> aggregateDays(const std::vector<Interval>& intervals, TzOffsetFn offset) {
    std::map<sys_days, Bucket> buckets;
    for (const auto& ti : timed(intervals, offset)) {
        auto& b = buckets[ti.day];
        const double h = (ti.interval.endMs - ti.interval.startMs) / 3'600'000.0;
        b.hours += h; b.drop += ti.interval.drop; if (ti.interval.anc) b.ancHours += h;
    }
    std::vector<DayStat> out;
    for (const auto& [day, b] : buckets) {
        if (b.hours <= 0) continue;
        const double rate = b.drop / b.hours;
        out.push_back({dateString(day), b.hours, static_cast<int>(std::lround(b.drop)), rate,
                       90.0 / rate, b.ancHours / b.hours, b.hours >= 1.0 && b.drop >= 10.0});
    }
    return out;
}

std::vector<TrendPoint> rollingTrend(const std::vector<Interval>& intervals, TzOffsetFn offset) {
    std::map<sys_days, Bucket> buckets;
    for (const auto& ti : timed(intervals, offset)) {
        auto& b = buckets[ti.day]; b.hours += (ti.interval.endMs-ti.interval.startMs)/3'600'000.0; b.drop += ti.interval.drop;
    }
    std::vector<TrendPoint> out;
    for (const auto& [day, ignored] : buckets) {
        (void)ignored; double h = 0, drop = 0;
        for (auto it = buckets.lower_bound(day - days{6}); it != buckets.end() && it->first <= day; ++it) { h += it->second.hours; drop += it->second.drop; }
        if (h >= 2.0 && drop > 0) out.push_back({dateString(day), 90.0 / (drop / h), h});
    }
    return out;
}

Estimate currentEstimate(const std::vector<Interval>& intervals, std::int64_t nowMs, std::optional<double> prior) {
    double h = 0, drop = 0; std::map<std::int64_t, bool> daysSeen;
    for (const auto& i : intervals) {
        if (i.endMs <= i.startMs || i.drop <= 0 || i.endMs > nowMs || i.endMs < nowMs - 14*kDayMs) continue;
        h += (i.endMs-i.startMs)/3'600'000.0; drop += i.drop;
        daysSeen[(i.startMs + (i.endMs - i.startMs) / 2) / kDayMs] = true;
    }
    if (h >= 3.0 && drop > 0) return {drop/h, Estimate::Measured, static_cast<int>(daysSeen.size())};
    if (prior && *prior > 0) return {100.0 / *prior, Estimate::Spec, 0};
    return {};
}

std::optional<double> healthRatio(const std::vector<Interval>& intervals, std::int64_t nowMs, TzOffsetFn offset) {
    auto all = timed(intervals, offset); if (all.empty()) return std::nullopt;
    std::map<sys_days, Bucket> dayBuckets;
    for (const auto& ti : all) { auto& b=dayBuckets[ti.day]; b.hours+=(ti.interval.endMs-ti.interval.startMs)/3'600'000.0; b.drop+=ti.interval.drop; }
    const auto first=dayBuckets.begin()->first, last=dayBuckets.rbegin()->first;
    const auto nowDay=localDay(nowMs, offset);
    if (nowDay-first < days{60}) return std::nullopt;
    double baseH=0,baseDrop=0,recentH=0,recentDrop=0;
    for (const auto& [day,b] : dayBuckets) {
        if (day >= first && day < first+days{30}) { baseH+=b.hours; baseDrop+=b.drop; }
        if (day > last-days{30} && day <= last) { recentH+=b.hours; recentDrop+=b.drop; }
    }
    if (first+days{29} >= last-days{29} || baseH < 10 || recentH < 10 || baseDrop<=0 || recentDrop<=0) return std::nullopt;
    const double baseline=baseDrop/baseH, recent=recentDrop/recentH;
    return baseline/recent;
}

std::optional<double> fullChargeHours(const Estimate& e) { if (e.source == Estimate::None || e.ratePerHour <= 0) return std::nullopt; return 90.0/e.ratePerHour; }
std::optional<double> remainingHours(const Estimate& e, int level) { if (e.source == Estimate::None || e.ratePerHour <= 0) return std::nullopt; return level <= 10 ? 0.0 : (level-10)/e.ratePerHour; }
std::optional<double> specFullHours(protocol::SonyModel model, bool ancOn) {
    using protocol::SonyModel;
    switch (model) {
    case SonyModel::WH1000XM4: return ancOn ? 30.0 : 38.0;
    case SonyModel::WH1000XM5: case SonyModel::WH1000XM6: return ancOn ? 30.0 : 40.0;
    default: return std::nullopt;
    }
}
} // namespace sony::core::battery
