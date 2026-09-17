import AppKit
import Carbon.HIToolbox
import Foundation

/// Registers a single global hot key with Carbon/HIToolbox and dispatches a
/// callback on the main thread. No event tap, no accessibility/input-monitoring
/// permission, no polling (docs/CALENDAR_HOTKEY_PANEL.md §6.2).
@MainActor
final class GlobalHotKeyController {

    /// A physical key plus normalised Carbon modifier mask. This is the persisted
    /// identity; display text is derived from the current keyboard layout.
    struct HotKey: Equatable {
        var keyCode: UInt32
        var carbonModifiers: UInt32

        var isSet: Bool { keyCode != 0 || carbonModifiers != 0 }
    }

    enum ValidationError: Equatable {
        case missingModifier
        case missingKey
        case reserved
    }

    private static let signature: OSType = 0x43_41_4C_4D // 'CALM'
    private static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var lastPress: Date?
    private(set) var registered: HotKey?

    /// Holding the combination must not repeat-toggle the panel, so presses
    /// inside this window are ignored.
    private static let repeatInterval: TimeInterval = 0.35

    // MARK: - Registration

    /// Installs the event handler once and registers the hot key. Returns the
    /// OSStatus from RegisterEventHotKey (noErr on success).
    func register(_ hotKey: HotKey, onPress: @escaping () -> Void) -> OSStatus {
        unregister()
        installHandlerIfNeeded()
        let eventHotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            registered = hotKey
            self.onPress = onPress
        } else {
            hotKeyRef = nil
            registered = nil
            self.onPress = nil
        }
        return status
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registered = nil
        onPress = nil
        lastPress = nil
    }

    fileprivate func handlePress() {
        let now = Date()
        if let lastPress, now.timeIntervalSince(lastPress) < Self.repeatInterval { return }
        lastPress = now
        onPress?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            calmonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            handlerRef = nil
        }
    }

    // MARK: - Validation

    /// Requires a Command or Control modifier plus a letter/digit main key.
    nonisolated static func validate(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> ValidationError? {
        let carbon = carbonModifiers(from: modifiers)
        if carbon & (UInt32(cmdKey) | UInt32(controlKey)) == 0 { return .missingModifier }
        // Reserved check runs first so ⌘Q / ⌘, report "reserved" rather than
        // "missing key" even though punctuation is not alphanumeric.
        if isReserved(modifiers: modifiers, characters: characters) { return .reserved }
        guard let characters, characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar) else { return .missingKey }
        return nil
    }

    nonisolated static func isReserved(modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        let lower = characters?.lowercased()
        let hasCommand = modifiers.contains(.command)
        if hasCommand && (lower == "q" || characters == ",") { return true }
        // Space combinations reserved by the system (not capturable via local monitor
        // in normal use, kept as a guard for recorded values).
        if characters == " " { return true }
        return false
    }

    nonisolated static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    nonisolated static func modifierFlags(fromCarbon carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// Modifier symbols in the conventional order, e.g. "⌃⌥⇧⌘".
    nonisolated static func modifierSymbols(_ carbon: UInt32) -> String {
        var text = ""
        if carbon & UInt32(controlKey) != 0 { text += "⌃" }
        if carbon & UInt32(optionKey) != 0 { text += "⌥" }
        if carbon & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbon & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    /// Display text for a hot key, e.g. "⌃⌥C". The main key character is resolved
    /// from the current keyboard layout (not stored).
    nonisolated static func displayString(_ hotKey: HotKey) -> String {
        guard hotKey.isSet else { return "" }
        let key = keyCharacter(keyCode: UInt16(truncatingIfNeeded: hotKey.keyCode)) ?? "?"
        return modifierSymbols(hotKey.carbonModifiers) + key
    }

    nonisolated static func keyCharacter(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }
}

/// C callback installed on the application event target. Reads the hot key id
/// and forwards to the controller instance stored in `userData`.
private func calmonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.signature == 0x43_41_4C_4D else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.handlePress()
    }
    return noErr
}
