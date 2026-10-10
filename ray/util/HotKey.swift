//
//  HotKey.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//
import Carbon

// Current hotkey: option and space
enum HotKey {
    static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(_ action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)

        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey),
                            EventHotKeyID(signature: OSType(0x72617931), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
