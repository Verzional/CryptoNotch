import AppKit
import Carbon

/// Manages system-wide global hotkeys for the Dynamic Island using Carbon's RegisterEventHotKey.
/// This works system-wide across all applications without requiring macOS Accessibility permissions.
public final class HotKeyManager {
    private var hotKeyExpandRef: EventHotKeyRef?
    private var hotKeyDisableRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let islandController: DynamicIslandController

    public init(islandController: DynamicIslandController) {
        self.islandController = islandController
        setupCarbonHotKeys()
    }

    deinit {
        if let hotKeyExpandRef = hotKeyExpandRef {
            UnregisterEventHotKey(hotKeyExpandRef)
        }
        if let hotKeyDisableRef = hotKeyDisableRef {
            UnregisterEventHotKey(hotKeyDisableRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func setupCarbonHotKeys() {
        let expandID = EventHotKeyID(signature: OSType(0x434E5448), id: 1) // 'CNTH', 1 (Toggle Expansion)
        let disableID = EventHotKeyID(signature: OSType(0x434E5448), id: 2) // 'CNTH', 2 (Toggle Disable Notch)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
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
                guard status == noErr else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        guard installStatus == noErr else {
            print("Failed to install Carbon event handler: \(installStatus)")
            return
        }

        // Register Option + Shift + C (kVK_ANSI_C = 8) -> Toggle Expand
        let expandStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(optionKey | shiftKey),
            expandID,
            GetApplicationEventTarget(),
            0,
            &hotKeyExpandRef
        )
        if expandStatus != noErr {
            print("Failed to register Carbon expand hotkey: \(expandStatus)")
        }

        // Register Option + Shift + D (kVK_ANSI_D = 2) -> Toggle Disable Notch
        let disableStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(optionKey | shiftKey),
            disableID,
            GetApplicationEventTarget(),
            0,
            &hotKeyDisableRef
        )
        if disableStatus != noErr {
            print("Failed to register Carbon disable hotkey: \(disableStatus)")
        }
    }

    @MainActor
    private func handleHotKey(id: UInt32) {
        if id == 1 {
            islandController.toggleExpansion()
        } else if id == 2 {
            islandController.toggleDisableNotch()
        }
    }
}
