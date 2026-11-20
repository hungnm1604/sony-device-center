#include "DesktopNative.h"

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
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

bool statusItemSupported() { return true; }

Handle createStatusItem(void* nsMenu) {
    NSStatusItem* item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [item retain];
    item.menu = static_cast<NSMenu*>(nsMenu);
    item.button.imagePosition = NSImageLeft;
    // Monospaced digits keep the item from jittering as the percentage changes.
    item.button.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightRegular];
    return item;
}

void updateStatusItem(Handle handle, const QImage& glyph, const QString& title, const QString& toolTip) {
    auto* item = static_cast<NSStatusItem*>(handle);
    if (!item) return;
    if (!glyph.isNull()) {
        CGImageRef cg = glyph.toCGImage();
        const qreal dpr = glyph.devicePixelRatio() > 0 ? glyph.devicePixelRatio() : 1.0;
        NSImage* image = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(glyph.width() / dpr, glyph.height() / dpr)];
        CGImageRelease(cg);
        [image setTemplate:YES];  // ("template" is a C++ keyword) the menu bar tints it for light, dark and highlighted states
        item.button.image = image;
        [image release];
    }
    item.button.title = title.isEmpty() ? @"" : [@" " stringByAppendingString:title.toNSString()];
    item.button.toolTip = toolTip.toNSString();
}

void setStatusItemVisible(Handle handle, bool visible) {
    auto* item = static_cast<NSStatusItem*>(handle);
    if (item) item.visible = visible;
}

void destroyStatusItem(Handle handle) {
    auto* item = static_cast<NSStatusItem*>(handle);
    if (!item) return;
    [[NSStatusBar systemStatusBar] removeStatusItem:item];
    [item release];
}

void postNotification(const QString& title, const QString& body) {
    // UNUserNotificationCenter raises for a process without a bundle id
    // (an unbundled dev binary), so only bundled builds post.
    if (![[NSBundle mainBundle] bundleIdentifier]) return;
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    NSString* t = title.toNSString();
    NSString* b = body.toNSString();
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError*) {
        if (!granted) return;
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = t;
        content.body = b;
        content.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"battery-low"
                                                                              content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:nil];
        [content release];
    }];
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
