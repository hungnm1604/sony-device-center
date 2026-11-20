#include "DesktopIntegration.h"

#include "DesktopNative.h"
#include "DeviceCenterController.h"

#include <algorithm>

#include <QAction>
#include <QActionGroup>
#include <QGuiApplication>
#include <QFont>
#include <QFontMetricsF>
#include <QIcon>
#include <QImage>
#include <QLoggingCategory>
#include <QMenu>
#include <QPainter>
#include <QPainterPath>
#include <QPixmap>
#include <QSettings>
#include <QSystemTrayIcon>

namespace sony::devicecenter {

namespace {

constexpr int kAlertThresholds[] = {20, 10};

QSettings settings() { return QSettings("SonyBridge", "SonyDeviceCenter"); }

// Menu bar glyph: a wide headphone outline with the battery level set inside
// the arch (number only: a "%" at this size crowds the cups, and the menu
// and tooltip spell out "72%"). Drawn as a mask so the menu bar tints it for
// light, dark and highlighted states. A small bolt under the band marks
// charging. 25 x 18 pt at every level, so the item never changes width.
QImage glyphImage(int level, bool charging, int scale) {
    constexpr qreal W = 25, H = 18, cupW = 3.0, cupH = 7.6, cupY = 9.6, edge = 1.0;
    QImage img(int(W * scale), int(H * scale), QImage::Format_ARGB32_Premultiplied);
    img.setDevicePixelRatio(scale);
    // Fixed 96 dpi so point sizes below map to the same pixels on every
    // platform (a macOS QImage otherwise defaults to 72 dpi).
    img.setDotsPerMeterX(3780);
    img.setDotsPerMeterY(3780);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::TextAntialiasing);

    QPainterPath band;
    band.moveTo(edge + cupW / 2, cupY + 1.0);
    band.cubicTo(edge + cupW / 2, 0.6, W - edge - cupW / 2, 0.6, W - edge - cupW / 2, cupY + 1.0);
    p.setPen(QPen(Qt::black, 1.5, Qt::SolidLine, Qt::RoundCap));
    p.drawPath(band);
    p.setPen(Qt::NoPen);
    p.setBrush(Qt::black);
    p.drawRoundedRect(QRectF(edge, cupY, cupW, cupH), 1.5, 1.5);
    p.drawRoundedRect(QRectF(W - edge - cupW, cupY, cupW, cupH), 1.5, 1.5);

    if (level >= 0) {
        QFont f = QGuiApplication::font();
        f.setWeight(QFont::Bold);
        // Point sizes on a 96-dpi QImage: 0.75 pt per logical pixel.
        f.setPointSizeF((level >= 100 ? 7.6 : 9.0) * 0.75);
        f.setLetterSpacing(QFont::AbsoluteSpacing, -0.2);
        const QString text = QString::number(std::clamp(level, 0, 100));
        const QFontMetricsF fm(f);
        p.setFont(f);
        p.setPen(Qt::black);
        p.drawText(QPointF((W - fm.horizontalAdvance(text)) / 2, cupY + cupH - 0.3), text);
    }
    if (charging) {
        constexpr qreal bx = W / 2, by = 3.0;
        QPainterPath bolt;
        bolt.moveTo(bx + 0.9, by - 0.4); bolt.lineTo(bx - 2.0, by + 3.0); bolt.lineTo(bx - 0.1, by + 3.0);
        bolt.lineTo(bx - 0.9, by + 5.6); bolt.lineTo(bx + 2.0, by + 2.1); bolt.lineTo(bx + 0.1, by + 2.1);
        bolt.closeSubpath();
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawPath(bolt);
    }
    p.end();
    return img;
}

QIcon trayGlyph() {
    QIcon icon;
    for (int scale : {1, 2}) icon.addPixmap(QPixmap::fromImage(glyphImage(-1, false, scale)));
    icon.setIsMask(true);
    return icon;
}

} // namespace

struct DesktopIntegration::Native {
    native::Handle hotkey{};
    native::Handle motionObserver{};
    native::Handle statusItem{};  // macOS menu bar item; null elsewhere
    QString lastGlyphKey;  // level|charging the status item image was drawn for
};

DesktopIntegration::DesktopIntegration(DeviceCenterController* controller, QObject* parent)
    : QObject(parent), _controller(controller), _native(std::make_unique<Native>()) {
    auto s = settings();
    _menuBarIcon = s.value("menuBarIcon", true).toBool();
    _globalShortcut = s.value("globalShortcut", true).toBool();
    _batteryAlerts = s.value("batteryAlerts", true).toBool();
    _menuBarPercent = s.value("menuBarPercent", true).toBool();

    _reduceMotion = native::reduceMotion();
    _native->motionObserver = native::observeReduceMotion([this](bool value) { _setReduceMotion(value); });

    if (trayAvailable()) _buildTray();
    _applyHotkey();

    connect(controller, &DeviceCenterController::stateChanged, this, [this] { _refreshTray(); _checkBattery(); });
    connect(controller, &DeviceCenterController::capabilitiesChanged, this, &DesktopIntegration::_refreshTray);
    connect(controller, &DeviceCenterController::languageChanged, this, &DesktopIntegration::_refreshTray);
    connect(controller, &DeviceCenterController::pairedDevicesChanged, this, &DesktopIntegration::_refreshDevices);
    _refreshTray();
}

DesktopIntegration::~DesktopIntegration() {
    // Before _menu goes: the status item still references its NSMenu.
    native::destroyStatusItem(_native->statusItem);
    native::unregisterHotkey(_native->hotkey);
    native::stopObservingReduceMotion(_native->motionObserver);
}

bool DesktopIntegration::trayAvailable() const {
    return native::statusItemSupported() || QSystemTrayIcon::isSystemTrayAvailable();
}
bool DesktopIntegration::menuBarPercentAvailable() const { return native::statusItemSupported(); }
bool DesktopIntegration::_hasIcon() const { return _tray != nullptr || _native->statusItem != nullptr; }
bool DesktopIntegration::globalShortcutAvailable() const { return native::hotkeySupported(); }
QString DesktopIntegration::globalShortcutLabel() const { return native::hotkeyLabel(); }

bool DesktopIntegration::keepsRunningInBackground() const { return _hasIcon() && _menuBarIcon; }

void DesktopIntegration::setMenuBarIcon(bool enabled) {
    if (_menuBarIcon == enabled) return;
    _menuBarIcon = enabled;
    settings().setValue("menuBarIcon", enabled);
    if (_tray) _tray->setVisible(enabled);
    native::setStatusItemVisible(_native->statusItem, enabled);
    // Without the icon there is no way back to a hidden window, so the app
    // returns to quitting when its window closes.
    QGuiApplication::setQuitOnLastWindowClosed(!keepsRunningInBackground());
    emit preferencesChanged();
}

void DesktopIntegration::setMenuBarPercent(bool enabled) {
    if (_menuBarPercent == enabled) return;
    _menuBarPercent = enabled;
    settings().setValue("menuBarPercent", enabled);
    _refreshTray();
    emit preferencesChanged();
}

void DesktopIntegration::setGlobalShortcut(bool enabled) {
    if (_globalShortcut == enabled) return;
    _globalShortcut = enabled;
    settings().setValue("globalShortcut", enabled);
    _applyHotkey();
    emit preferencesChanged();
}

void DesktopIntegration::setBatteryAlerts(bool enabled) {
    if (_batteryAlerts == enabled) return;
    _batteryAlerts = enabled;
    settings().setValue("batteryAlerts", enabled);
    emit preferencesChanged();
}

void DesktopIntegration::toggleNoiseMode() {
    if (!_controller || !_controller->isConnected() || _controller->busy()) return;
    const QString mode = _controller->noiseControlMode();
    if (mode == QLatin1String("cancelling") && _controller->hasAmbient()) {
        // 0 makes the controller fall back to the last ambient level it sent.
        _controller->setAmbient(0, _controller->focusOnVoice());
    } else if (_controller->hasAnc()) {
        _controller->setAnc(true);
    }
}

void DesktopIntegration::_applyHotkey() {
    native::unregisterHotkey(_native->hotkey);
    _native->hotkey = {};
    if (_globalShortcut && native::hotkeySupported()) {
        _native->hotkey = native::registerHotkey([this] { toggleNoiseMode(); });
        if (!_native->hotkey)
            qWarning("Global shortcut %s is unavailable (another app may own it)", qPrintable(native::hotkeyLabel()));
    }
}

void DesktopIntegration::_setReduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    emit reduceMotionChanged();
}

void DesktopIntegration::_buildTray() {
    _menu = std::make_unique<QMenu>();
    _status = _menu->addAction(QString());
    _status->setEnabled(false);
    _menu->addSeparator();

    _modes = new QActionGroup(this);
    _modes->setExclusive(true);
    _anc = _menu->addAction(QString(), this, [this] { if (_controller) _controller->setAnc(true); });
    _ambient = _menu->addAction(QString(), this, [this] {
        if (_controller) _controller->setAmbient(0, _controller->focusOnVoice());
    });
    _off = _menu->addAction(QString(), this, [this] { if (_controller) _controller->setNoiseControlOff(); });
    for (QAction* a : {_anc, _ambient, _off}) { a->setCheckable(true); _modes->addAction(a); }

    _menu->addSeparator();
    _powerOff = _menu->addAction(QString(), this, [this] { if (_controller) _controller->powerOffHeadphones(); });
    // Paired headsets, so switching does not need the window either.
    _devices = _menu->addMenu(QString());
    // Refresh in the background when the menu opens; the list updates in
    // place once discovery answers.
    connect(_menu.get(), &QMenu::aboutToShow, this, [this] { if (_controller) _controller->refreshDiscoveredDevices(); });
    _menu->addSeparator();
    _open = _menu->addAction(QString(), this, &DesktopIntegration::showWindowRequested);
    _quit = _menu->addAction(QString(), this, &DesktopIntegration::quitRequested);

#ifdef Q_OS_MACOS
    // Native NSStatusItem: glyph plus a live "72%" title, which a
    // QSystemTrayIcon cannot show. The Qt menu is shared via its NSMenu.
    _native->statusItem = native::createStatusItem(_menu->toNSMenu());
#endif
    if (_native->statusItem) {
        native::setStatusItemVisible(_native->statusItem, _menuBarIcon);
        QGuiApplication::setQuitOnLastWindowClosed(!keepsRunningInBackground());
        return;
    }

    _tray = new QSystemTrayIcon(trayGlyph(), this);
    _tray->setContextMenu(_menu.get());
    // On Windows/Linux a left click usually means "open"; macOS always shows
    // the menu, which is what a menu bar extra should do.
    connect(_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::DoubleClick || reason == QSystemTrayIcon::Trigger) {
#ifndef Q_OS_MACOS
            emit showWindowRequested();
#endif
        }
    });
    _tray->setVisible(_menuBarIcon);
    QGuiApplication::setQuitOnLastWindowClosed(!keepsRunningInBackground());
}

void DesktopIntegration::_refreshTray() {
    if (!_menu || !_controller) return;
    auto* c = _controller.data();
    const bool connected = c->isConnected();
    const int battery = c->batteryLevel();

    QString status = connected ? c->deviceName() : c->t("disconnected");
    if (connected && battery >= 0)
        status += QStringLiteral(" · %1%%2").arg(battery).arg(c->isCharging() ? QStringLiteral(" ⚡") : QString());
    _status->setText(status);
    const QString toolTip = QStringLiteral("Sony Device Center — ") + status;
    if (_tray) _tray->setToolTip(toolTip);
    if (_native->statusItem) {
        const bool charging = connected && c->isCharging();
        const int level = (_menuBarPercent && connected) ? battery : -1;
        // Redraw only when the number or the bolt changes; the title stays
        // empty because the level is part of the glyph.
        const QString key = QString::number(level) + (charging ? "c" : "");
        const bool changed = key != _native->lastGlyphKey;
        native::updateStatusItem(_native->statusItem, changed ? glyphImage(level, charging, 2) : QImage(), QString(), toolTip);
        _native->lastGlyphKey = key;
    }

    _anc->setText(c->t("noise_cancelling"));
    _ambient->setText(c->t("ambient_sound"));
    _off->setText(c->t("noise_control_off"));
    _open->setText(c->t("tray_open"));
    _powerOff->setText(c->t("power_off_named").arg(c->deviceName()));
    _powerOff->setVisible(connected && c->hasPowerOff());
    _powerOff->setEnabled(!c->busy());
    _refreshDevices();
    _quit->setText(c->t("tray_quit"));

    const bool usable = connected && !c->busy();
    _anc->setVisible(c->hasAnc() || !connected);
    _ambient->setVisible(c->hasAmbient() || !connected);
    for (QAction* a : {_anc, _ambient, _off}) a->setEnabled(usable);

    const QString mode = c->noiseControlMode();
    _anc->setChecked(mode == QLatin1String("cancelling"));
    _ambient->setChecked(mode == QLatin1String("ambient"));
    _off->setChecked(mode == QLatin1String("off"));
    if (mode == QLatin1String("unknown")) {
        // An exclusive group keeps its last check; clear it so the menu does
        // not claim a mode the headset has not reported.
        _modes->setExclusive(false);
        for (QAction* a : {_anc, _ambient, _off}) a->setChecked(false);
        _modes->setExclusive(true);
    }
}

void DesktopIntegration::_refreshDevices() {
    if (!_devices || !_controller) return;
    auto* c = _controller.data();
    const QVariantList list = c->pairedDevices();
    QString signature = c->currentLanguage() + c->deviceAddress() + c->deviceName()
                      + QString::number(c->isConnected()) + QString::number(c->busy());
    for (const QVariant& entry : list)
        signature += entry.toMap().value("address").toString() + entry.toMap().value("name").toString();
    if (signature == _devicesSignature) return;
    _devicesSignature = signature;

    _devices->setTitle(c->t("switcher_title"));
    _devices->clear();
    if (list.isEmpty()) {
        _devices->addAction(c->t("no_devices_found"))->setEnabled(false);
        return;
    }
    for (const QVariant& entry : list) {
        const QVariantMap d = entry.toMap();
        const QString address = d.value("address").toString();
        const QString name = d.value("name").toString();
        const bool current = c->isConnected() && (c->deviceAddress().isEmpty() ? name == c->deviceName() : address == c->deviceAddress());
        QAction* a = _devices->addAction(name, this, [this, address, name, current] {
            if (_controller && !current) _controller->connectDevice(address, name);
        });
        a->setCheckable(true);
        a->setChecked(current);
        a->setEnabled(!c->busy());
    }
}

void DesktopIntegration::_checkBattery() {
    if (!_controller) return;
    const int level = _controller->batteryLevel();
    if (!_controller->isConnected() || level < 0) return;
    if (_controller->isCharging() || level > 25) { _alertedAt = 101; return; }
    if (!_batteryAlerts || !_hasIcon() || !_menuBarIcon) return;
    // One notification per crossing, for the lowest threshold reached; a first
    // reading of 8 % announces once, not once for 20 and again for 10.
    int crossed = 101;
    for (int threshold : kAlertThresholds)
        if (level <= threshold && _alertedAt > threshold) crossed = threshold;
    if (crossed > 100) return;
    _alertedAt = crossed;
    _notify(_controller->t("battery_low_title"),
            _controller->t("battery_low_body").arg(_controller->deviceName()).arg(level));
}

void DesktopIntegration::_notify(const QString& title, const QString& body) {
    if (_native->statusItem) native::postNotification(title, body);
    else if (_tray) _tray->showMessage(title, body, QSystemTrayIcon::Warning, 8000);
}

} // namespace sony::devicecenter
