#include <sony/core/BatteryHistory.h>
#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

using namespace sony::core::battery;
using Catch::Approx;
namespace {
constexpr std::int64_t hour = 3'600'000;
constexpr std::int64_t day = 24*hour;
TzOffsetFn utc = [](std::int64_t) { return 0; };
Event ev(std::int64_t t, EventKind k, int level=-1, std::string mode={}) { return {t,k,level,std::move(mode),{}}; }
Interval iv(std::int64_t a,std::int64_t b,int d,bool anc=false) { return {a,b,d,anc}; }
}

TEST_CASE("battery-history extracts discharge segments", "[battery-history]") {
    SECTION("initial quantized reading is not a segment start") {
        auto v=extractIntervals({ev(0,EventKind::Connect,80),ev(0,EventKind::Level,75),ev(3*hour,EventKind::Level,70,"noiseCancelling")});
        REQUIRE(v.size()==1); CHECK(v[0].drop==5); CHECK(v[0].endMs-v[0].startMs==3*hour);
    }
    SECTION("app noise mode cancelling counts as ANC") {
        auto v=extractIntervals({ev(0,EventKind::Connect,80),ev(0,EventKind::Level,75),ev(3*hour,EventKind::Level,70,"cancelling")});
        REQUIRE(v.size()==1); CHECK(v[0].anc);
    }
    SECTION("disconnect and gap split segments") {
        auto e={ev(0,EventKind::Connect,90),ev(hour,EventKind::Level,85),ev(2*hour,EventKind::Level,80),ev(3*hour,EventKind::Disconnect),ev(4*hour,EventKind::Connect,78),ev(5*hour,EventKind::Level,73),ev(6*hour,EventKind::Level,68),ev(7*hour,EventKind::Gap),ev(8*hour,EventKind::Connect,67),ev(9*hour,EventKind::Level,62),ev(10*hour,EventKind::Level,57)};
        auto v=extractIntervals(e); REQUIRE(v.size()==3); CHECK(v[0].startMs==hour); CHECK(v[1].startMs==5*hour); CHECK(v[2].startMs==9*hour);
    }
    SECTION("charging readings ignored and new decrease begins after charge end") {
        auto v=extractIntervals({ev(0,EventKind::Connect,90),ev(hour,EventKind::Level,85),ev(2*hour,EventKind::Level,80),ev(2*hour,EventKind::ChargeStart),ev(3*hour,EventKind::Level,95),ev(4*hour,EventKind::ChargeEnd),ev(5*hour,EventKind::Level,90),ev(6*hour,EventKind::Level,85),ev(7*hour,EventKind::Level,80)});
        REQUIRE(v.size()==2); CHECK(v[0].endMs==2*hour); CHECK(v[1].startMs==6*hour);
    }
    SECTION("increase recalibrates; short and one point segments drop") {
        auto v=extractIntervals({ev(0,EventKind::Connect,90),ev(hour,EventKind::Level,85),ev(2*hour,EventKind::Level,88),ev(3*hour,EventKind::Level,83),ev(4*hour,EventKind::Level,78)});
        REQUIRE(v.size()==1); CHECK(v[0].startMs==3*hour);
        CHECK(extractIntervals({ev(0,EventKind::Connect,90),ev(0,EventKind::Level,85),ev(20*60*1000,EventKind::Level,80)}).empty());
        CHECK(extractIntervals({ev(0,EventKind::Connect,90),ev(0,EventKind::Level,85),ev(hour,EventKind::Level,80)}).size()==1);
    }
    SECTION("dual battery invalid levels ignored") {
        CHECK(extractIntervals({ev(0,EventKind::Connect,90),ev(hour,EventKind::Level,-1),ev(2*hour,EventKind::Level,85)}).empty());
    }
}

TEST_CASE("battery-history attributes and summarizes intervals", "[battery-history]") {
    SECTION("midpoint determines local day") {
        auto d=aggregateDays({iv(23*hour,25*hour,4)},utc); REQUIRE(d.size()==1); CHECK(d[0].date=="1970-01-02"); CHECK(d[0].hours==2);
    }
    SECTION("daily validity thresholds are inclusive") {
        auto d=aggregateDays({iv(0,hour,10,true)},utc); REQUIRE(d.size()==1); CHECK(d[0].valid); CHECK(d[0].ancShare==1.0);
        CHECK_FALSE(aggregateDays({iv(0,hour-1,10)},utc)[0].valid);
    }
    SECTION("trend is time weighted") {
        auto trend=rollingTrend({iv(0,2*hour,10),iv(day,day+hour,10)},utc);
        REQUIRE(trend.size()==2); CHECK(trend[1].hours==3); CHECK(trend[1].fullHours==Approx(13.5));
    }
}

TEST_CASE("battery-history estimates and health", "[battery-history]") {
    SECTION("measured threshold then spec then none") {
        auto now=20*day; auto ints=std::vector<Interval>{iv(now-4*hour,now-2*hour,7),iv(now-2*hour,now,7)};
        auto e=currentEstimate(ints,now,40.0); CHECK(e.source==Estimate::Measured); CHECK(e.sampleDays==1);
        e=currentEstimate({iv(now-2*hour,now-hour,4)},now,40.0); CHECK(e.source==Estimate::Spec); CHECK(e.ratePerHour==2.5);
        e=currentEstimate({},now,std::nullopt); CHECK(e.source==Estimate::None);
    }
    SECTION("remaining time boundaries") {
        Estimate e{3.33,Estimate::Measured,4}; CHECK(remainingHours(e,10)==0); CHECK(remainingHours(e,5)==0); CHECK(remainingHours(e,70)==Approx(18.018));
    }
    SECTION("health needs separated windows and reflects runtime ratio") {
        CHECK_FALSE(healthRatio({iv(0,day,10)},100*day,utc));
        std::vector<Interval> data;
        // Baseline: 9% per 10h. Recent: 10% per 10h, so runtime is ~90%.
        for(int n=0;n<30;++n) data.push_back(iv(n*day,n*day+10*hour,9));
        for(int n=70;n<100;++n) data.push_back(iv(n*day,n*day+10*hour,10));
        auto ratio=healthRatio(data,100*day,utc); REQUIRE(ratio); CHECK(*ratio==Approx(0.9).margin(0.01));
        data.clear();
        for(int n=0;n<30;++n) data.push_back(iv(n*day,n*day+10*hour,10));
        for(int n=70;n<100;++n) data.push_back(iv(n*day,n*day+10*hour,9));
        ratio=healthRatio(data,100*day,utc); REQUIRE(ratio); CHECK(*ratio>1.0);
    }
}

TEST_CASE("battery-history Sony spec priors", "[battery-history]") {
    CHECK(specFullHours(sony::protocol::SonyModel::WH1000XM5,true)==30.0);
    CHECK(specFullHours(sony::protocol::SonyModel::WH1000XM6,false)==40.0);
    CHECK_FALSE(specFullHours(sony::protocol::SonyModel::Unknown,true));
    const auto estimate=currentEstimate({},0,specFullHours(sony::protocol::SonyModel::WH1000XM5,true));
    CHECK(fullChargeHours(estimate)==Approx(27.0));
    CHECK(remainingHours(estimate,70)==Approx(18.0));
}
