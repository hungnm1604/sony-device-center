#pragma once

#include <sony/protocol/DeviceProfile.h>

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace sony::core::battery {

enum class EventKind { Connect, Level, ChargeStart, ChargeEnd, Disconnect, Gap };
struct Event {
    std::int64_t epochMs{};
    EventKind kind{EventKind::Level};
    int level{-1};
    std::string mode;
    std::string codec;
};
struct Interval { std::int64_t startMs{}, endMs{}; int drop{}; bool anc{}; };
struct DayStat {
    std::string date;
    double hours{};
    int drop{};
    double rate{};
    double fullHours{};
    double ancShare{};
    bool valid{};
};
struct TrendPoint { std::string date; double fullHours{}; double hours{}; };
struct Estimate {
    double ratePerHour{};
    enum Source { None, Spec, Measured } source{None};
    int sampleDays{};
};
using TzOffsetFn = std::function<int(std::int64_t)>;

std::vector<Interval> extractIntervals(const std::vector<Event>& events);
std::vector<DayStat> aggregateDays(const std::vector<Interval>& intervals, TzOffsetFn offset);
std::vector<TrendPoint> rollingTrend(const std::vector<Interval>& intervals, TzOffsetFn offset);
Estimate currentEstimate(const std::vector<Interval>& intervals, std::int64_t nowMs,
                         std::optional<double> specFullHours);
std::optional<double> healthRatio(const std::vector<Interval>& intervals, std::int64_t nowMs,
                                  TzOffsetFn offset);
std::optional<double> fullChargeHours(const Estimate& estimate);
std::optional<double> remainingHours(const Estimate& estimate, int level);
std::optional<double> specFullHours(protocol::SonyModel model, bool ancOn);

} // namespace sony::core::battery
