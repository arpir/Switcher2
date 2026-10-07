//
//  CompatibilityExtensions.swift
//  DevSwitcher2
//
//  Created for macOS version compatibility
//

import Foundation
import AppKit

// MARK: - NSApplication Compatibility Extension
extension NSApplication {
    /// 兼容性activate方法，支持macOS 12.0+
    /// 说明：无参 activate() 仅存在于 macOS 14+ SDK，用旧版 SDK（如 13.x）编译时该符号不存在，
    /// 因此统一调用 activate(ignoringOtherApps:)——所有 macOS 版本均可用，行为一致。
    func activateCompat() {
        self.activate(ignoringOtherApps: true)
    }
}

// MARK: - macOS Version Utilities
struct MacOSVersion {
    static let current = ProcessInfo.processInfo.operatingSystemVersion
    
    static var isMontereyOrLater: Bool {
        return current.majorVersion >= 12
    }
    
    static var isVenturaOrLater: Bool {
        return current.majorVersion >= 13
    }
    
    static var isSonomaOrLater: Bool {
        return current.majorVersion >= 14
    }
    
    static var displayString: String {
        return "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
    }
} 