import Carbon
import Cocoa
import TranslateTheDamnCore

private let kSignature: OSType = 0x5474_446D

private func hotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData, let event = event else {
        return OSStatus(eventNotHandledErr)
    }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    var actualSize = 0
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        &actualSize,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    if hotKeyID.id == 0 {
        fputs("[HotkeyService] 🔥 Hotkey callback fired (translate, id=0)\n", stderr)
        service.translateAction?()
    } else if hotKeyID.id == 1 {
        fputs("[HotkeyService] 🔥 Hotkey callback fired (toggleListen, id=1)\n", stderr)
        service.toggleListenAction?()
    }
    return noErr
}

final class HotkeyService {
    private var translateHotKeyRef: EventHotKeyRef?
    private var toggleListenHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handlerInstalled = false

    fileprivate var translateAction: (() -> Void)?
    fileprivate var toggleListenAction: (() -> Void)?

    private func installEventHandlerIfNeeded() {
        guard !handlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        if status == noErr {
            handlerInstalled = true
        } else {
            NSLog("[HotkeyService] InstallEventHandler failed: %d", status)
        }
    }

    func register(hotkeyString: String, action: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregisterTranslateHotKey()

        let result = HotkeyParser.parse(hotkeyString)
        guard result.isValid else { return false }
        guard let carbonKeyCode = CarbonKeyMap.carbonKeyCode(fromVK: result.virtualKey) else { return false }

        let modifiers = CarbonKeyMap.carbonModifiers(
            hasControl: result.hasControl,
            hasAlt: result.hasAlt,
            hasShift: result.hasShift,
            hasWin: result.hasWin
        )

        let hotKeyID = EventHotKeyID(signature: kSignature, id: 0)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(carbonKeyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            NSLog("[HotkeyService] RegisterEventHotKey failed for '%@': %d", hotkeyString, status)
            return false
        }

        translateHotKeyRef = ref
        translateAction = action
        fputs("[HotkeyService] ✅ Registered translate hotkey '\(hotkeyString)': keycode=0x\(String(format: "%02X", carbonKeyCode)), modifiers=0x\(String(format: "%04X", modifiers))\n", stderr)
        return true
    }

    func registerToggleListen(hotkeyString: String, action: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregisterToggleListenHotKey()

        let result = HotkeyParser.parse(hotkeyString)
        guard result.isValid else { return false }
        guard let carbonKeyCode = CarbonKeyMap.carbonKeyCode(fromVK: result.virtualKey) else { return false }

        let modifiers = CarbonKeyMap.carbonModifiers(
            hasControl: result.hasControl,
            hasAlt: result.hasAlt,
            hasShift: result.hasShift,
            hasWin: result.hasWin
        )

        let hotKeyID = EventHotKeyID(signature: kSignature, id: 1)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(carbonKeyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            NSLog("[HotkeyService] RegisterEventHotKey (toggleListen) failed for '%@': %d", hotkeyString, status)
            return false
        }

        toggleListenHotKeyRef = ref
        toggleListenAction = action
        return true
    }

    func unregister() {
        unregisterTranslateHotKey()
        unregisterToggleListenHotKey()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
            handlerInstalled = false
        }
    }

    private func unregisterTranslateHotKey() {
        if let ref = translateHotKeyRef {
            UnregisterEventHotKey(ref)
            translateHotKeyRef = nil
        }
        translateAction = nil
    }

    private func unregisterToggleListenHotKey() {
        if let ref = toggleListenHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleListenHotKeyRef = nil
        }
        toggleListenAction = nil
    }
}
