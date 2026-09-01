import AppKit
import Carbon.HIToolbox

/// Two global hotkeys: ⌥⌘P plays or stops, ⌥⌘M keeps the last minute.
///
/// Uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor,
/// which would need Accessibility permission for something this small.
@MainActor
final class Hotkeys {
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    /// Keyed by the hotkey id carried in the Carbon event.
    private static var actions: [UInt32: () -> Void] = [:]

    private static let signature = OSType(0x534B_5957) // 'SKYW'

    func register(playPause: @escaping () -> Void, keepMoment: @escaping () -> Void) {
        Self.actions = [1: playPause, 2: keepMoment]

        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // A C function pointer captures nothing, so the id is read back out of
        // the event and looked up in a static table.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            let which = id.id
            DispatchQueue.main.async { Hotkeys.actions[which]?() }
            return noErr
        }, 1, &type, nil, &handler)

        add(key: UInt32(kVK_ANSI_P), id: 1)
        add(key: UInt32(kVK_ANSI_M), id: 2)
    }

    private func add(key: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        guard RegisterEventHotKey(
            key,
            UInt32(optionKey | cmdKey),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        ) == noErr, let reference else { return }
        registered.append(reference)
    }

    /// Not a `deinit`: the Carbon handles are non-Sendable, and the hotkey lives
    /// as long as the app does anyway.
    func unregister() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        Self.actions = [:]
    }
}
