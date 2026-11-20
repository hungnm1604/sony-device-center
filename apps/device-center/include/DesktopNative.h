#pragma once

#include <QImage>
#include <QString>

#include <functional>

// Thin platform hooks for DesktopIntegration. macOS implements them in
// DesktopNative_mac.mm; other platforms get the inert fallbacks in
// DesktopNative_stub.cpp (no global shortcut, motion never reduced).
namespace sony::devicecenter::native {

using Handle = void*;

[[nodiscard]] bool hotkeySupported();
[[nodiscard]] QString hotkeyLabel();
// Registers the system-wide toggle shortcut (Control-Option-N on macOS). The
// callback runs on the main thread. Returns nullptr when registration fails,
// for instance because another app already owns the combination.
[[nodiscard]] Handle registerHotkey(std::function<void()> callback);
void unregisterHotkey(Handle handle);

// Native menu bar item (macOS NSStatusItem): a template glyph followed by a
// short title such as "72%", using the menu bar's own font and colours.
// `nsMenu` is QMenu::toNSMenu(), so the Qt menu stays the single source.
[[nodiscard]] bool statusItemSupported();
[[nodiscard]] Handle createStatusItem(void* nsMenu);
void updateStatusItem(Handle item, const QImage& glyph, const QString& title, const QString& toolTip);
void setStatusItemVisible(Handle item, bool visible);
void destroyStatusItem(Handle item);

// System notification (UserNotifications on macOS). Asks for permission the
// first time; silently does nothing if the user declines.
void postNotification(const QString& title, const QString& body);

[[nodiscard]] bool reduceMotion();
[[nodiscard]] Handle observeReduceMotion(std::function<void(bool)> callback);
void stopObservingReduceMotion(Handle handle);

} // namespace sony::devicecenter::native
