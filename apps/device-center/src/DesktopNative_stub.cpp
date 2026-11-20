#include "DesktopNative.h"

namespace sony::devicecenter::native {

bool hotkeySupported() { return false; }
QString hotkeyLabel() { return {}; }
Handle registerHotkey(std::function<void()>) { return nullptr; }
void unregisterHotkey(Handle) {}

bool statusItemSupported() { return false; }
Handle createStatusItem(void*) { return nullptr; }
void updateStatusItem(Handle, const QImage&, const QString&, const QString&) {}
void setStatusItemVisible(Handle, bool) {}
void destroyStatusItem(Handle) {}
void postNotification(const QString&, const QString&) {}

bool reduceMotion() { return false; }
Handle observeReduceMotion(std::function<void(bool)>) { return nullptr; }
void stopObservingReduceMotion(Handle) {}

} // namespace sony::devicecenter::native
