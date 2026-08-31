import AppKit
import Carbon.HIToolbox

/// One global play/pause hotkey: ⌥⌘P.
///
/// Uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor,
/// which would need Accessibility permission for something this small.
@MainActor
final class Hotkeys {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private static var onTrigger: (() -> Void)?

    private static let signature = OSType(0x534B_5957) // 'SKYW'

    func register(onTrigger: @escaping () -> Void) {
        Self.onTrigger = onTrigger

        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // The callback is a C function pointer, so it cannot capture context.
            DispatchQueue.main.async { Hotkeys.onTrigger?() }
            return noErr
        }, 1, &type, nil, &handler)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(optionKey | cmdKey),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    /// Not a `deinit`: the Carbon handles are non-Sendable, and the hotkey lives
    /// as long as the app does anyway.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        Self.onTrigger = nil
    }
}
