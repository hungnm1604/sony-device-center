#include "DesktopNative.h"

#import <AppKit/AppKit.h>
#include <Carbon/Carbon.h>

// Carbon's RegisterEventHotKey is still the supported way to own a global
// shortcut without Accessibility permission: the system delivers only this
// one combination to us, so no keystroke monitoring is involved.

namespace sony::devicecenter::native {

namespace {

constexpr OSType kSignature = 'SDCh';
constexpr UInt32 kToggleId = 1;

struct HotkeyState {
    EventHotKeyRef ref{nullptr};
    EventHandlerRef handler{nullptr};
    std::function<void()> callback;
};

OSStatus onHotkey(EventHandlerCallRef, EventRef event, void* userData) {
    EventHotKeyID id{};
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, nullptr, sizeof(id), nullptr, &id);
    auto* state = static_cast<HotkeyState*>(userData);
    if (id.signature == kSignature && id.id == kToggleId && state->callback) state->callback();
    return noErr;
}

} // namespace

bool hotkeySupported() { return true; }

QString hotkeyLabel() { return QStringLiteral("⌃⌥N"); }

Handle registerHotkey(std::function<void()> callback) {
    auto* state = new HotkeyState{};
    state->callback = std::move(callback);
    EventTypeSpec spec{kEventClassKeyboard, kEventHotKeyPressed};
    if (InstallApplicationEventHandler(&onHotkey, 1, &spec, state, &state->handler) != noErr) {
        delete state;
        return nullptr;
    }
    const EventHotKeyID id{kSignature, kToggleId};
    if (RegisterEventHotKey(kVK_ANSI_N, controlKey | optionKey, id, GetApplicationEventTarget(), 0, &state->ref) != noErr) {
        RemoveEventHandler(state->handler);
        delete state;
        return nullptr;
    }
    return state;
}

void unregisterHotkey(Handle handle) {
    auto* state = static_cast<HotkeyState*>(handle);
    if (!state) return;
    if (state->ref) UnregisterEventHotKey(state->ref);
    if (state->handler) RemoveEventHandler(state->handler);
    delete state;
}

bool reduceMotion() {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}

Handle observeReduceMotion(std::function<void(bool)> callback) {
    NSNotificationCenter* center = [[NSWorkspace sharedWorkspace] notificationCenter];
    id token = [center addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                   object:nil
                                    queue:[NSOperationQueue mainQueue]
                               usingBlock:^(NSNotification*) { callback(reduceMotion()); }];
    // Retained explicitly: this target builds without ARC (like the Bluetooth
    // connector), and the returned token is autoreleased.
    return const_cast<void*>(CFBridgingRetain(token));
}

void stopObservingReduceMotion(Handle handle) {
    if (!handle) return;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:(__bridge id)handle];
    CFRelease(handle);
}

} // namespace sony::devicecenter::native
