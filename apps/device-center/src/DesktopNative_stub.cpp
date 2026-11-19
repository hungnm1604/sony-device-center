#include "DesktopNative.h"

namespace sony::devicecenter::native {

bool hotkeySupported() { return false; }
QString hotkeyLabel() { return {}; }
Handle registerHotkey(std::function<void()>) { return nullptr; }
void unregisterHotkey(Handle) {}

bool reduceMotion() { return false; }
Handle observeReduceMotion(std::function<void(bool)>) { return nullptr; }
void stopObservingReduceMotion(Handle) {}

} // namespace sony::devicecenter::native
