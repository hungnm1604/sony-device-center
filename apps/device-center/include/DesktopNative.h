#pragma once

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

[[nodiscard]] bool reduceMotion();
[[nodiscard]] Handle observeReduceMotion(std::function<void(bool)> callback);
void stopObservingReduceMotion(Handle handle);

} // namespace sony::devicecenter::native
