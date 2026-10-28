//
//  HotKey.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import Carbon

enum HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    
    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKey.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
    
    static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?
    
    static func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers,
                                         EventHotKeyID(signature: OSType(0x72617931), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        nextID += 1
        refs[id] = ref
        handlers[id] = handler
        return id
    }
    
    static func unregister(_ id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
    }
}
