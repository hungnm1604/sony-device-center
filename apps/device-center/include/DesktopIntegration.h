#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

#include <memory>

class QAction;
class QActionGroup;
class QMenu;
class QSystemTrayIcon;

namespace sony::devicecenter {

class DeviceCenterController;

// Everything that lives outside the main window: the menu bar (tray) icon
// with quick noise-control actions, a system-wide shortcut that flips ANC and
// Ambient, low-battery alerts, and the OS "reduce motion" preference.
//
// It only calls the controller's public slots, so the worker-thread and
// busy-gating rules stay in one place.
class DesktopIntegration : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool trayAvailable READ trayAvailable CONSTANT)
    Q_PROPERTY(bool menuBarIcon READ menuBarIcon WRITE setMenuBarIcon NOTIFY preferencesChanged)
    // Battery percentage next to the menu bar glyph (macOS native item only).
    Q_PROPERTY(bool menuBarPercentAvailable READ menuBarPercentAvailable CONSTANT)
    Q_PROPERTY(bool menuBarPercent READ menuBarPercent WRITE setMenuBarPercent NOTIFY preferencesChanged)
    Q_PROPERTY(bool globalShortcutAvailable READ globalShortcutAvailable CONSTANT)
    Q_PROPERTY(bool globalShortcut READ globalShortcut WRITE setGlobalShortcut NOTIFY preferencesChanged)
    Q_PROPERTY(QString globalShortcutLabel READ globalShortcutLabel CONSTANT)
    Q_PROPERTY(bool batteryAlerts READ batteryAlerts WRITE setBatteryAlerts NOTIFY preferencesChanged)
    Q_PROPERTY(bool reduceMotion READ reduceMotion NOTIFY reduceMotionChanged)

public:
    explicit DesktopIntegration(DeviceCenterController* controller, QObject* parent = nullptr);
    ~DesktopIntegration() override;

    [[nodiscard]] bool trayAvailable() const;
    [[nodiscard]] bool menuBarIcon() const { return _menuBarIcon; }
    [[nodiscard]] bool menuBarPercentAvailable() const;
    [[nodiscard]] bool menuBarPercent() const { return _menuBarPercent; }
    [[nodiscard]] bool globalShortcutAvailable() const;
    [[nodiscard]] bool globalShortcut() const { return _globalShortcut; }
    [[nodiscard]] QString globalShortcutLabel() const;
    [[nodiscard]] bool batteryAlerts() const { return _batteryAlerts; }
    [[nodiscard]] bool reduceMotion() const { return _reduceMotion; }

    Q_INVOKABLE void setMenuBarIcon(bool enabled);
    Q_INVOKABLE void setMenuBarPercent(bool enabled);
    Q_INVOKABLE void setGlobalShortcut(bool enabled);
    Q_INVOKABLE void setBatteryAlerts(bool enabled);

    // ANC -> Ambient, anything else -> ANC. What the shortcut does.
    Q_INVOKABLE void toggleNoiseMode();

    // True when closing the window should hide it rather than quit.
    [[nodiscard]] bool keepsRunningInBackground() const;

signals:
    void preferencesChanged();
    void reduceMotionChanged();
    void showWindowRequested();
    void quitRequested();

private:
    void _buildTray();
    void _refreshTray();
    void _refreshDevices();
    void _checkBattery();
    void _applyHotkey();
    void _setReduceMotion(bool value);
    [[nodiscard]] bool _hasIcon() const;
    void _notify(const QString& title, const QString& body);

    QPointer<DeviceCenterController> _controller;
    std::unique_ptr<QMenu> _menu;
    QSystemTrayIcon* _tray{nullptr};
    QAction* _status{nullptr};
    QAction* _anc{nullptr};
    QAction* _ambient{nullptr};
    QAction* _off{nullptr};
    QAction* _powerOff{nullptr};
    QAction* _open{nullptr};
    QMenu* _devices{nullptr};
    QString _devicesSignature;  // skip rebuilding an unchanged (possibly open) submenu
    QAction* _quit{nullptr};
    QActionGroup* _modes{nullptr};

    bool _menuBarIcon{true};
    bool _menuBarPercent{true};
    bool _globalShortcut{true};
    bool _batteryAlerts{true};
    bool _reduceMotion{false};

    // Lowest alert threshold already announced since the last recharge, so a
    // reading that hovers around 20 % does not notify on every snapshot.
    int _alertedAt{101};

    struct Native;
    std::unique_ptr<Native> _native;
};

} // namespace sony::devicecenter
