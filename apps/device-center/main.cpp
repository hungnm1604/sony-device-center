#include <QApplication>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>

#include "DesktopIntegration.h"
#include "DeviceCenterController.h"

int main(int argc, char *argv[]) {
    // QApplication rather than QGuiApplication: the menu bar icon is a
    // QSystemTrayIcon, which needs the widgets platform integration.
    QApplication app(argc, argv);

    // Main.qml customises background/handle/indicator on its controls. The
    // native "Windows" and "macOS" styles Qt picks by default there refuse
    // that (one warning per control, and native-looking widgets), so pin the
    // one style that honours customisation on every platform.
    QQuickStyle::setStyle("Basic");
    app.setApplicationName("Sony Device Center");
    app.setOrganizationName("SonyBridge");
    app.setApplicationVersion(SONY_DEVICE_CENTER_VERSION);

    // Wayland and the GNOME/KDE shells match a window to its .desktop entry by
    // this name; without it the taskbar falls back to a generic placeholder
    // even though the window icon below is set.
    QGuiApplication::setDesktopFileName("sony-device-center");

    // The raster form is used deliberately: QIcon can only read the SVG brand
    // asset when Qt's qsvg image plugin is deployed alongside the binary.
    app.setWindowIcon(QIcon(":/resources/brand/app-icon.png"));

    sony::devicecenter::DeviceCenterController controller;

    sony::devicecenter::DesktopIntegration desktop(&controller);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("controller", &controller);
    engine.rootContext()->setContextProperty("desktop", &desktop);

    auto mainWindow = [&engine]() -> QQuickWindow* {
        const auto roots = engine.rootObjects();
        return roots.isEmpty() ? nullptr : qobject_cast<QQuickWindow*>(roots.first());
    };
    auto showMainWindow = [mainWindow] {
        if (auto* w = mainWindow()) { w->show(); w->raise(); w->requestActivate(); }
    };
    QObject::connect(&desktop, &sony::devicecenter::DesktopIntegration::showWindowRequested, &app, showMainWindow);
    QObject::connect(&desktop, &sony::devicecenter::DesktopIntegration::quitRequested, &app, &QCoreApplication::quit);
    // With the menu bar icon on, closing the window only hides it. Clicking
    // the Dock icon (macOS sends ApplicationActive) brings it back.
    QObject::connect(&app, &QGuiApplication::applicationStateChanged, &app, [mainWindow](Qt::ApplicationState state) {
        auto* w = mainWindow();
        if (state == Qt::ApplicationActive && w && !w->isVisible()) { w->show(); w->raise(); }
    });

    const QUrl url(QStringLiteral("qrc:/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
