#include "BatteryHistoryStore.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QStandardPaths>
#include <algorithm>
#include <iterator>
#include <tuple>

namespace sony::devicecenter {
using namespace sony::core::battery;

namespace {
QString kindName(EventKind kind) {
    switch (kind) {
    case EventKind::Connect: return "connect";
    case EventKind::Level: return "level";
    case EventKind::ChargeStart: return "chargeStart";
    case EventKind::ChargeEnd: return "chargeEnd";
    case EventKind::Disconnect: return "disconnect";
    case EventKind::Gap: return "gap";
    }
    return "level";
}

bool parseKind(const QString& name, EventKind& kind) {
    if (name == "connect") kind = EventKind::Connect;
    else if (name == "level") kind = EventKind::Level;
    else if (name == "chargeStart") kind = EventKind::ChargeStart;
    else if (name == "chargeEnd") kind = EventKind::ChargeEnd;
    else if (name == "disconnect") kind = EventKind::Disconnect;
    else if (name == "gap") kind = EventKind::Gap;
    else return false;
    return true;
}

QJsonObject eventJson(const Event& event) {
    return {{"t", double(event.epochMs)},
            {"k", kindName(event.kind)},
            {"l", event.level},
            {"m", QString::fromStdString(event.mode)},
            {"c", QString::fromStdString(event.codec)}};
}

std::vector<Event> parseFile(const QString& path) {
    std::vector<Event> events;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return events;

    while (!file.atEnd()) {
        const auto line = file.readLine().trimmed();
        if (line.isEmpty()) continue;

        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) continue;

        const auto object = document.object();
        if (object.contains("v")) continue; // Version header, absent in older files.
        EventKind kind;
        if (!parseKind(object.value("k").toString(), kind) || !object.value("t").isDouble()) continue;

        events.push_back({qint64(object.value("t").toDouble()), kind,
                          object.value("l").toInt(-1),
                          object.value("m").toString().toStdString(),
                          object.value("c").toString().toStdString()});
    }
    return events;
}

bool sameEvent(const Event& left, const Event& right) {
    return left.epochMs == right.epochMs && left.kind == right.kind && left.level == right.level;
}
auto eventKey(const Event& event) { return std::tuple{event.epochMs, static_cast<int>(event.kind), event.level}; }
} // namespace

std::vector<BatteryHistoryRecorder::Event> BatteryHistoryRecorder::feed(
    qint64 nowMs, const QString& address, bool connected, int level, bool charging,
    const QString& mode, const QString& codec) {
    std::vector<Event> events;

    if (_connected && (!connected || address != _address)) {
        events.push_back({nowMs, EventKind::Disconnect});
        _connected = false;
        _charging = false;
        _level = -1;
    }
    if (!connected || address.isEmpty()) {
        _lastSnapshotMs = nowMs;
        return events;
    }

    if (_connected && nowMs - _lastSnapshotMs > 120'000) {
        events.push_back({nowMs, EventKind::Gap});
        events.push_back({nowMs, EventKind::Connect, level});
        _level = level;
        _charging = false;
    }
    if (!_connected) {
        _address = address;
        _connected = true;
        events.push_back({nowMs, EventKind::Connect, level});
        _level = level;
    }
    if (charging != _charging) {
        events.push_back({nowMs, charging ? EventKind::ChargeStart : EventKind::ChargeEnd});
        _charging = charging;
    }
    if (level >= 0 && level != _level) {
        events.push_back({nowMs, EventKind::Level, level, mode.toStdString(), codec.toStdString()});
        _level = level;
    }
    _lastSnapshotMs = nowMs;
    return events;
}

void BatteryHistoryRecorder::reset() {
    _address.clear();
    _connected = _charging = false;
    _level = -1;
    _lastSnapshotMs = -1;
}

class BatteryHistoryStore::Writer : public QObject {
public:
    void append(const QString& path, const QJsonObject& object) {
        QDir().mkpath(QFileInfo(path).path());
        const bool newFile = !QFileInfo::exists(path);
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) return;
        if (newFile) file.write("{\"v\":1}\n");
        file.write(QJsonDocument(object).toJson(QJsonDocument::Compact) + "\n");
    }

    void load(const QString& address, const QString& path, QObject* receiver) {
        auto loaded = parseFile(path);
        QMetaObject::invokeMethod(receiver, [receiver, address, loaded = std::move(loaded)]() mutable {
            auto* store = qobject_cast<BatteryHistoryStore*>(receiver);
            if (!store) return;
            {
                QMutexLocker lock(&store->_mutex);
                auto& current = store->_events[address];
                auto byKey = [](const Event& a, const Event& b) { return eventKey(a) < eventKey(b); };
                std::stable_sort(current.begin(), current.end(), byKey);
                std::stable_sort(loaded.begin(), loaded.end(), byKey);
                std::vector<Event> merged;
                merged.reserve(current.size() + loaded.size());
                std::merge(current.begin(), current.end(), loaded.begin(), loaded.end(),
                           std::back_inserter(merged), byKey);
                merged.erase(std::unique(merged.begin(), merged.end(), sameEvent), merged.end());
                current = std::move(merged);
            }
            emit store->historyLoaded(address);
        }, Qt::QueuedConnection);
    }

    void clear(const QString& path) { QFile::remove(path); }

    bool writeFile(const QString& path, const QByteArray& contents) {
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        return file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate) &&
               file.write(contents) == contents.size();
    }
};

BatteryHistoryStore::BatteryHistoryStore(QObject* parent, Clock clock, QString dataLocation)
    : QObject(parent),
      _clock(clock ? std::move(clock) : Clock([] { return QDateTime::currentMSecsSinceEpoch(); })),
      _dataLocation(dataLocation.isEmpty()
                        ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                        : std::move(dataLocation)),
      _writer(new Writer) {
    _writer->moveToThread(&_thread);
    connect(&_thread, &QThread::finished, _writer, &QObject::deleteLater);
    _thread.start();
}

BatteryHistoryStore::~BatteryHistoryStore() {
    if (_thread.isRunning()) QMetaObject::invokeMethod(_writer, [] {}, Qt::BlockingQueuedConnection);
    _thread.quit();
    _thread.wait();
}

QString BatteryHistoryStore::filePathForAddress(const QString& address) const {
    auto filename = address.toUpper();
    filename.replace(':', '-');
    return QDir(_dataLocation).filePath("battery-history/" + filename + ".jsonl");
}

void BatteryHistoryStore::append(const QString& address, const Event& event) {
    QMetaObject::invokeMethod(_writer, [writer = _writer, path = filePathForAddress(address),
                                        object = eventJson(event)] {
        writer->append(path, object);
    }, Qt::QueuedConnection);
}

int BatteryHistoryStore::feed(qint64 nowMs, const QString& address, bool connected, int level,
                               bool charging, const QString& mode, const QString& codec) {
    const QString previousAddress = _recordingAddress;
    const auto newEvents = _recorder.feed(nowMs, address, connected, level, charging, mode, codec);
    for (const auto& event : newEvents) {
        const QString target = (event.kind == EventKind::Disconnect || event.kind == EventKind::Gap)
                                   ? previousAddress : address;
        if (target.isEmpty()) continue;
        {
            QMutexLocker lock(&_mutex);
            _events[target].push_back(event);
        }
        append(target, event);
    }
    _recordingAddress = connected ? address : QString();
    return static_cast<int>(newEvents.size());
}

int BatteryHistoryStore::feed(const QString& address, bool connected, int level, bool charging,
                               const QString& mode, const QString& codec) {
    return feed(_clock(), address, connected, level, charging, mode, codec);
}

void BatteryHistoryStore::loadHistory(const QString& address) {
    if (address.isEmpty()) return;
    QMetaObject::invokeMethod(_writer, [writer = _writer, address, path = filePathForAddress(address), this] {
        writer->load(address, path, this);
    }, Qt::QueuedConnection);
}

std::vector<Event> BatteryHistoryStore::events(const QString& address) const {
    QMutexLocker lock(&_mutex);
    return _events.value(address);
}

void BatteryHistoryStore::clearHistory(const QString& address) {
    if (address.isEmpty()) return;
    {
        QMutexLocker lock(&_mutex);
        _events.remove(address);
    }
    QMetaObject::invokeMethod(_writer, [writer = _writer, path = filePathForAddress(address)] {
        writer->clear(path);
    }, Qt::QueuedConnection);
}

bool BatteryHistoryStore::exportCsv(const QString& address, const QString& path) const {
    const auto intervals = extractIntervals(events(address));
    const auto days = aggregateDays(intervals, [](std::int64_t epochMs) {
        return QDateTime::fromMSecsSinceEpoch(epochMs).offsetFromUtc();
    });
    QString csv = "date,hours,drop,fullHours,ancShare,valid\n";
    for (const auto& day : days) {
        csv += QString::fromStdString(day.date) + ',' + QString::number(day.hours, 'f', 3) + ',' +
               QString::number(day.drop) + ',' + QString::number(day.fullHours, 'f', 3) + ',' +
               QString::number(day.ancShare, 'f', 3) + ',' + (day.valid ? "true" : "false") + '\n';
    }

    bool success = false;
    QMetaObject::invokeMethod(_writer, [writer = _writer, path, data = csv.toUtf8(), &success] {
        success = writer->writeFile(path, data);
    }, Qt::BlockingQueuedConnection);
    return success;
}

} // namespace sony::devicecenter
