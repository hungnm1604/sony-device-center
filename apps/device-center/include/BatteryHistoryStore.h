#pragma once

#include <sony/core/BatteryHistory.h>

#include <QMutex>
#include <QObject>
#include <QThread>
#include <QHash>
#include <QString>
#include <functional>
#include <memory>
#include <vector>

namespace sony::devicecenter {

class BatteryHistoryRecorder {
public:
    using Event = sony::core::battery::Event;
    std::vector<Event> feed(qint64 nowMs, const QString& address, bool connected,
                            int level, bool charging, const QString& mode, const QString& codec);
    void reset();
private:
    QString _address;
    bool _connected{false}, _charging{false};
    int _level{-1};
    qint64 _lastSnapshotMs{-1};
};

class BatteryHistoryStore : public QObject {
    Q_OBJECT
public:
    using Clock = std::function<qint64()>;
    explicit BatteryHistoryStore(QObject* parent = nullptr, Clock clock = {}, QString dataLocation = {});
    ~BatteryHistoryStore() override;
    int feed(qint64 nowMs, const QString& address, bool connected, int level,
              bool charging, const QString& mode, const QString& codec);
    int feed(const QString& address, bool connected, int level, bool charging,
              const QString& mode, const QString& codec);
    void loadHistory(const QString& address);
    std::vector<sony::core::battery::Event> events(const QString& address) const;
    void clearHistory(const QString& address);
    bool exportCsv(const QString& address, const QString& path) const;
    QString filePathForAddress(const QString& address) const;
signals:
    void historyLoaded(const QString& address);
private:
    class Writer;
    void append(const QString& address, const sony::core::battery::Event& event);
    mutable QMutex _mutex;
    BatteryHistoryRecorder _recorder;
    QString _recordingAddress;
    Clock _clock;
    QString _dataLocation;
    QHash<QString, std::vector<sony::core::battery::Event>> _events;
    QThread _thread;
    Writer* _writer{};
};

} // namespace sony::devicecenter
