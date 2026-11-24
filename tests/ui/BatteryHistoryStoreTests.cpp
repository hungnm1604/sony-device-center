#include <QtTest>
#include "BatteryHistoryStore.h"
#include "sony/core/BatteryHistory.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QDateTime>
#include <algorithm>
#include <QTemporaryDir>

using namespace sony::devicecenter;
using sony::core::battery::EventKind;

class BatteryHistoryStoreTests : public QObject {
    Q_OBJECT
    QString address{"AA:BB:CC:DD:EE:FF"};
    QString testLocation() const { return QDir(QDir::tempPath()).filePath("sony-battery-history-store-tests"); }
    void feed(BatteryHistoryStore& s, qint64 t, QString a, bool c, int l, bool ch=false) {
        s.feed(t,a,c,l,ch,"noiseCancelling","LDAC");
    }
private slots:
    void initTestCase() {
        QCoreApplication::setOrganizationName("SonyBridge");
        QCoreApplication::setApplicationName("SonyDeviceCenterTests");
        QStandardPaths::setTestModeEnabled(true);
        QDir(testLocation()).removeRecursively();
    }
    void cleanupTestCase() { QDir(testLocation()).removeRecursively(); }
    void identicalSnapshotsDeduplicate() {
        QDir(testLocation()).removeRecursively();
        { BatteryHistoryStore s(nullptr,{},testLocation()); for(int i=0;i<1000;++i) feed(s,1000+i,address,true,80);
          QCOMPARE(s.events(address).size(),size_t(1)); QCOMPARE(s.events(address)[0].kind,EventKind::Connect); }
        BatteryHistoryStore reloaded(nullptr,{},testLocation());
        QSignalSpy loaded(&reloaded,&BatteryHistoryStore::historyLoaded);
        reloaded.loadHistory(address); QTRY_COMPARE_WITH_TIMEOUT(loaded.count(),1,2000);
        QCOMPARE(reloaded.events(address).size(),size_t(1));
    }
    void roundTripsAndExports() {
        QDir(testLocation()).removeRecursively();
        QString path;
        { BatteryHistoryStore s(nullptr,{},testLocation()); path=s.filePathForAddress(address); feed(s,1000,address,true,80); for(int n=1;n<=32;++n) feed(s,1000+n*60000,address,true,80-n); feed(s,1000+32*60000+30000,address,false,-1); }
        { BatteryHistoryStore s(nullptr,{},testLocation()); QSignalSpy loaded(&s,&BatteryHistoryStore::historyLoaded); s.loadHistory(address); QTRY_COMPARE_WITH_TIMEOUT(loaded.count(),1,2000); auto e=s.events(address); QCOMPARE(e.size(),size_t(34)); QCOMPARE(e.front().kind,EventKind::Connect); QCOMPARE(e.back().kind,EventKind::Disconnect); const QString csvPath=QDir(testLocation()).filePath("out.csv"); QVERIFY(s.exportCsv(address,csvPath)); QFile csv(csvPath); QVERIFY(csv.open(QIODevice::ReadOnly)); auto lines=csv.readAll().split('\n'); QCOMPARE(lines[0],QByteArray("date,hours,drop,fullHours,ancShare,valid")); QCOMPARE(lines.size(),3); }
        QVERIFY(QFile::exists(path));
    }
    void gapAndInjectedClock() {
        qint64 now=1000; BatteryHistoryStore s(nullptr,[&]{return now;},testLocation());
        s.feed(address,true,80,false,""," "); now+=120001; s.feed(address,true,80,false,""," ");
        auto e=s.events(address); QVERIFY(std::any_of(e.begin(),e.end(),[](const auto&x){return x.kind==EventKind::Gap;}));
    }
    void corruptMiddleLineSkipped() {
        BatteryHistoryStore s(nullptr,{},testLocation()); const QString path=s.filePathForAddress(address); QVERIFY(QDir().mkpath(QFileInfo(path).path())); QFile f(path); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("{\"v\":1}\n{\"t\":1,\"k\":\"connect\",\"l\":80}\nnot json\n{\"t\":2,\"k\":\"disconnect\"}\n"); f.close();
        QSignalSpy loaded(&s,&BatteryHistoryStore::historyLoaded); s.loadHistory(address); QTRY_COMPARE_WITH_TIMEOUT(loaded.count(),1,2000); QCOMPARE(s.events(address).size(),size_t(2));
    }
    void emptyOrDisconnectedNotRecorded() {
        BatteryHistoryStore s(nullptr,{},testLocation()); feed(s,1,"",true,80); feed(s,2,address,false,-1); QVERIFY(s.events(address).empty());
    }
    void chargingEdgesAndAddressChange() {
        BatteryHistoryStore s(nullptr,{},testLocation()); const QString other="11:22:33:44:55:66";
        feed(s,1,address,true,80); feed(s,2,address,true,80,true); feed(s,3,address,true,79,true); feed(s,4,address,true,79,false); feed(s,5,other,true,78);
        auto e=s.events(address); QVERIFY(std::any_of(e.begin(),e.end(),[](const auto&x){return x.kind==EventKind::ChargeStart;})); QVERIFY(std::any_of(e.begin(),e.end(),[](const auto&x){return x.kind==EventKind::ChargeEnd;})); QVERIFY(std::any_of(e.begin(),e.end(),[](const auto&x){return x.kind==EventKind::Disconnect;}));
    }
    void measuredEstimateFromRecordedHistory() {
        using namespace sony::core::battery;
        QTemporaryDir dir; QVERIFY(dir.isValid());
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        BatteryHistoryStore store(nullptr, [now] { return now; }, dir.path());
        const qint64 hour = 60 * 60 * 1000LL;
        const qint64 start = now - 4*hour;
        store.feed(start, address, true, 80, false, "cancelling", "LDAC");
        for (int minute = 1; minute <= 240; ++minute) {
            const int level = minute < 61 ? 75 : minute < 121 ? 70 : minute < 181 ? 65 : 60;
            store.feed(start + minute*60*1000LL, address, true, level, false, "cancelling", "LDAC");
        }
        const auto intervals = extractIntervals(store.events(address));
        const auto estimate = currentEstimate(intervals, now, std::nullopt);
        QCOMPARE(estimate.source, Estimate::Measured);
        QVERIFY(estimate.sampleDays >= 1);
        const auto full = fullChargeHours(estimate);
        const auto remaining = remainingHours(estimate, 60);
        QVERIFY(full.has_value()); QVERIFY(remaining.has_value());
        QCOMPARE(qRound(*full * 60.0 / 30.0) * 30, 1080);
        QCOMPARE(qRound(*remaining * 60.0 / 30.0) * 30, 600);
    }
};
QTEST_MAIN(BatteryHistoryStoreTests)
#include "BatteryHistoryStoreTests.moc"
