#include "DesktopIntegration.h"

#include "DesktopNative.h"
#include "DeviceCenterController.h"

#include <QAction>
#include <QActionGroup>
#include <QGuiApplication>
#include <QIcon>
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

// Menu bar glyph: the headphone outline from assets/mark.svg, drawn as a mask
// so macOS tints it for light, dark and highlighted menu bars by itself.
QIcon trayGlyph() {
    QIcon icon;
    for (int scale : {1, 2}) {
        const int px = 18 * scale;
        QPixmap pm(px, px);
        pm.setDevicePixelRatio(scale);
        pm.fill(Qt::transparent);
        QPainter p(&pm);
        p.setRenderHint(QPainter::Antialiasing);
        const qreal u = 18.0 / 24.0;  // the mark's 24-unit grid in points
        p.scale(u, u);
        QPen pen(Qt::black, 2.2, Qt::SolidLine, Qt::RoundCap);
        p.setPen(pen);
        QPainterPath band;
        band.moveTo(4.6, 13.2);
        band.arcTo(QRectF(4.6, 6.0, 14.4, 14.4), 180, -180);
        p.drawPath(band);
        p.setBrush(Qt::black);
        p.setPen(Qt::NoPen);
        p.drawEllipse(QPointF(4.6, 16.0), 2.8, 2.8);
        p.setBrush(Qt::NoBrush);
        p.setPen(QPen(Qt::black, 1.9));
        p.drawEllipse(QPointF(19.0, 16.0), 2.3, 2.3);
        p.end();
        icon.addPixmap(pm);
    }
    icon.setIsMask(true);
    return icon;
}

} // namespace

struct DesktopIntegration::Native {
    native::Handle hotkey{};
    native::Handle motionObserver{};
};

DesktopIntegration::DesktopIntegration(DeviceCenterController* controller, QObject* parent)
    : QObject(parent), _controller(controller), _native(std::make_unique<Native>()) {
    auto s = settings();
    _menuBarIcon = s.value("menuBarIcon", true).toBool();
    _globalShortcut = s.value("globalShortcut", true).toBool();
    _batteryAlerts = s.value("batteryAlerts", true).toBool();

    _reduceMotion = native::reduceMotion();
    _native->motionObserver = native::observeReduceMotion([this](bool value) { _setReduceMotion(value); });

    if (trayAvailable()) _buildTray();
    _applyHotkey();

    connect(controller, &DeviceCenterController::stateChanged, this, [this] { _refreshTray(); _checkBattery(); });
    connect(controller, &DeviceCenterController::capabilitiesChanged, this, &DesktopIntegration::_refreshTray);
    connect(controller, &DeviceCenterController::languageChanged, this, &DesktopIntegration::_refreshTray);
    _refreshTray();
}

DesktopIntegration::~DesktopIntegration() {
    native::unregisterHotkey(_native->hotkey);
    native::stopObservingReduceMotion(_native->motionObserver);
}

bool DesktopIntegration::trayAvailable() const { return QSystemTrayIcon::isSystemTrayAvailable(); }
bool DesktopIntegration::globalShortcutAvailable() const { return native::hotkeySupported(); }
QString DesktopIntegration::globalShortcutLabel() const { return native::hotkeyLabel(); }

bool DesktopIntegration::keepsRunningInBackground() const { return _tray != nullptr && _menuBarIcon; }

void DesktopIntegration::setMenuBarIcon(bool enabled) {
    if (_menuBarIcon == enabled) return;
    _menuBarIcon = enabled;
    settings().setValue("menuBarIcon", enabled);
    if (_tray) _tray->setVisible(enabled);
    // Without the icon there is no way back to a hidden window, so the app
    // returns to quitting when its window closes.
    QGuiApplication::setQuitOnLastWindowClosed(!keepsRunningInBackground());
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
    _open = _menu->addAction(QString(), this, &DesktopIntegration::showWindowRequested);
    _quit = _menu->addAction(QString(), this, &DesktopIntegration::quitRequested);

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
    if (!_tray || !_controller) return;
    auto* c = _controller.data();
    const bool connected = c->isConnected();
    const int battery = c->batteryLevel();

    QString status = connected ? c->deviceName() : c->t("disconnected");
    if (connected && battery >= 0)
        status += QStringLiteral(" · %1%%2").arg(battery).arg(c->isCharging() ? QStringLiteral(" ⚡") : QString());
    _status->setText(status);
    _tray->setToolTip(QStringLiteral("Sony Device Center — ") + status);

    _anc->setText(c->t("noise_cancelling"));
    _ambient->setText(c->t("ambient_sound"));
    _off->setText(c->t("noise_control_off"));
    _open->setText(c->t("tray_open"));
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

void DesktopIntegration::_checkBattery() {
    if (!_controller) return;
    const int level = _controller->batteryLevel();
    if (!_controller->isConnected() || level < 0) return;
    if (_controller->isCharging() || level > 25) { _alertedAt = 101; return; }
    if (!_batteryAlerts || !_tray || !_tray->isVisible()) return;
    // One notification per crossing, for the lowest threshold reached; a first
    // reading of 8 % announces once, not once for 20 and again for 10.
    int crossed = 101;
    for (int threshold : kAlertThresholds)
        if (level <= threshold && _alertedAt > threshold) crossed = threshold;
    if (crossed > 100) return;
    _alertedAt = crossed;
    _tray->showMessage(_controller->t("battery_low_title"),
                       _controller->t("battery_low_body").arg(_controller->deviceName()).arg(level),
                       QSystemTrayIcon::Warning, 8000);
}

} // namespace sony::devicecenter
