//
//  HotkeyManager.swift
//  DevSwitcher2
//
//  Created by river on 2025-07-26.
//

import Foundation
import Carbon
import AppKit

// MARK: - Notifications
extension Notification.Name {
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
}

class HotkeyManager {
    private var eventHotKeyRef: EventHotKeyRef?
    private let windowManager: WindowManager
    private var eventHandler: EventHandlerRef?
    private let settingsManager = SettingsManager.shared
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        
        // Listen for hotkey settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )
    }
    
    deinit {
        unregisterHotkey()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func hotkeySettingsChanged() {
        Logger.log("Hotkey settings changed, re-registering hotkeys.")
        unregisterHotkey()
        registerHotkey()
    }
    
    func registerHotkey() {
        // Register DS2 hotkey
        registerDS2Hotkey()
    }
    
    private func registerDS2Hotkey() {
        // Define DS2 hotkey ID
        let hotkeyId = EventHotKeyID(signature: OSType(0x44455653), id: 1) // 'DEVS'
        
        // Get hotkey configuration from settings
        let settings = settingsManager.settings
        let keyCode = settings.triggerKey.keyCode
        let modifiers = settings.modifierKey.carbonModifier
        
        Logger.log("Registering DS2 hotkey: \(settings.modifierKey.displayName) + \(settings.triggerKey.displayName)")
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        // Install the event handler if it hasn't been installed yet
        if eventHandler == nil {
            let result = InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let hotkeyManager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                
                var hotKeyID = EventHotKeyID()
                let getHotKeyResult = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                
                if getHotKeyResult == noErr {
                    hotkeyManager.handleHotkey(hotKeyID)
                }
                
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            
            if result != noErr {
                Logger.log("Install event handler failed: \(result)")
                return
            }
        }
        
        // Register the DS2 hotkey
        let registerResult = RegisterEventHotKey(keyCode, modifiers, hotkeyId, GetApplicationEventTarget(), 0, &eventHotKeyRef)
        
        if registerResult == noErr {
            Logger.log("DS2 hotkey registered successfully.")
        } else {
            Logger.log("Failed to register DS2 hotkey: \(registerResult)")
        }
    }
    
    func unregisterHotkey() {
        // Unregister DS2 hotkey
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    private func handleHotkey(_ hotKeyID: EventHotKeyID) {
        DispatchQueue.main.async {
            if hotKeyID.signature == OSType(0x44455653) && hotKeyID.id == 1 { // 'DEVS', DS2
                self.windowManager.switchToNextWindow()
            }
        }
    }
}
