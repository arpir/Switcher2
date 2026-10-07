//
//  WindowManager.swift
//  DevSwitcher2
//
//  Created by river on 2025-07-26.
//

import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import ApplicationServices

struct WindowInfo {
    let windowID: CGWindowID
    let title: String
    let projectName: String
    let appName: String
    let processID: pid_t
    let axWindowIndex: Int  // AX window index
}

class WindowManager {
    private var windows: [WindowInfo] = []
    
    // AX element cache item structure
    private struct AXCacheItem {
        let element: AXUIElement
        let processID: pid_t
        var lastAccessTime: Date
        
        init(element: AXUIElement, processID: pid_t) {
            self.element = element
            self.processID = processID
            self.lastAccessTime = Date()
        }
        
        mutating func updateAccessTime() {
            self.lastAccessTime = Date()
        }
    }
    
    // Improved AX element cache with more metadata
    private var axElementCache: [CGWindowID: AXCacheItem] = [:]
    private let maxAXCacheSize = 100  // Maximum cache of 100 AX elements
    private let axCacheCleanupThreshold = 120  // Start cleanup when reaching 120
    
    // Settings manager
    private let settingsManager = SettingsManager.shared
    
    // MARK: - Steam Application Support
    //
    // Steam applications (including Steam games) often create windows with non-zero layer values,
    // which causes them to be filtered out by standard window detection logic that only accepts layer 0.
    // This implementation provides special handling for Steam applications by:
    // 1. Detecting Steam apps by bundle ID patterns
    // 2. Allowing non-zero layers (typically 1-10) for Steam applications
    // 3. Providing enhanced logging for Steam window detection
    //
    // Based on research from the alt-tab-macos project and community reports of Steam window issues.
    
    /// Check if an application is Steam or a Steam game
    /// Steam games often have non-zero window layers which cause them to be filtered out
    private func isSteamApplication(_ bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        
        // Steam client itself
        if bundleId == "com.valvesoftware.steam" {
            return true
        }
        
        // Steam games - common patterns based on alt-tab-macos implementation
        // Steam games typically have bundle IDs starting with "com.valvesoftware."
        // or contain "steamapps" in their bundle ID
        if bundleId.hasPrefix("com.valvesoftware.") || 
           bundleId.contains("steamapps") ||
           bundleId.contains("steam") {
            return true
        }
        
        return false
    }
    
    /// Check if a window layer should be considered valid, with special handling for Steam apps
    private func isValidWindowLayer(_ layer: Int, forBundleId bundleId: String?) -> Bool {
        // Standard case: layer 0 (normal windows)
        if layer == 0 {
            return true
        }
        
        // Special case for Steam applications: allow certain non-zero layers
        if isSteamApplication(bundleId) {
            // Allow layers typically used by Steam games (based on community research)
            // Steam games and the Steam client may place windows on higher layers
            return layer >= 0 && layer <= 100
        }
        
        return false
    }

    /// Resolve the primary app (with regular activation policy) that should own a window
    private func resolvePrimaryApp(
        for windowProcessID: pid_t,
        ownerName: String?,
        runningAppMap: [pid_t: NSRunningApplication],
        bundlePrimaryApp: [String: NSRunningApplication]
    ) -> NSRunningApplication? {
        var windowRunningApp: NSRunningApplication?
        if let cachedApp = runningAppMap[windowProcessID] {
            windowRunningApp = cachedApp
        } else {
            windowRunningApp = NSRunningApplication(processIdentifier: windowProcessID)
        }
        
        if let app = windowRunningApp {
            if app.activationPolicy == .regular {
                return app
            }
            if let bundleId = app.bundleIdentifier, let primaryApp = bundlePrimaryApp[bundleId] {
                return primaryApp
            }
        }
        
        if let bundleId = windowRunningApp?.bundleIdentifier, let primaryApp = bundlePrimaryApp[bundleId] {
            return primaryApp
        }
        
        if let ownerName = ownerName?.lowercased(), ownerName.contains("steam"),
           let steamApp = bundlePrimaryApp.first(where: { isSteamApplication($0.key) })?.value {
            return steamApp
        }
        
        return nil
    }
    
    /// Determine whether a window belongs to the specified target application
    private func windowBelongsToApp(
        windowProcessID: pid_t,
        ownerName: String?,
        targetApp: NSRunningApplication,
        runningAppMap: [pid_t: NSRunningApplication],
        bundlePrimaryApp: [String: NSRunningApplication]
    ) -> Bool {
        if windowProcessID == targetApp.processIdentifier {
            return true
        }
        
        if let targetBundle = targetApp.bundleIdentifier,
           let windowApp = runningAppMap[windowProcessID],
           windowApp.bundleIdentifier == targetBundle {
            return true
        }
        
        if let resolvedApp = resolvePrimaryApp(
            for: windowProcessID,
            ownerName: ownerName,
            runningAppMap: runningAppMap,
            bundlePrimaryApp: bundlePrimaryApp
        ) {
            if resolvedApp.processIdentifier == targetApp.processIdentifier {
                return true
            }
            if let targetBundle = targetApp.bundleIdentifier,
               let resolvedBundle = resolvedApp.bundleIdentifier,
               resolvedBundle == targetBundle {
                return true
            }
        }
        
        if isSteamApplication(targetApp.bundleIdentifier) {
            if let ownerName = ownerName?.lowercased(), ownerName.contains("steam") {
                return true
            }
        }
        
        return false
    }
    
    deinit {
        // Clean up AX cache
        Logger.log("🗑️ WindowManager cleanup, releasing \(axElementCache.count) AX elements")
        axElementCache.removeAll()
    }
    
    // MARK: - AX Cache Management Methods
    
    // Smart AX cache cleanup
    private func cleanupAXCache() {
        guard axElementCache.count >= axCacheCleanupThreshold else { return }
        
        Logger.log("🧹 Starting AX cache LRU cleanup, current size: \(axElementCache.count)")
        
        // Get set of currently running application process IDs
        let runningProcesses = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })
        
        // First remove cache items for terminated processes
        var itemsToRemove: [CGWindowID] = []
        for (windowID, cacheItem) in axElementCache {
            if !runningProcesses.contains(cacheItem.processID) {
                itemsToRemove.append(windowID)
            }
        }
        
        for windowID in itemsToRemove {
            axElementCache.removeValue(forKey: windowID)
        }
        
        let afterProcessCleanup = axElementCache.count
        Logger.log("🗑️ Removing AX elements for terminated processes: \(itemsToRemove.count) items")
        
        // If still over limit, perform LRU cleanup
        if axElementCache.count > maxAXCacheSize {
            let sortedEntries = axElementCache.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
            let itemsToKeep = Array(sortedEntries.suffix(maxAXCacheSize))
            var newCache: [CGWindowID: AXCacheItem] = [:]
            for (key, value) in itemsToKeep {
                newCache[key] = value
            }
            
            let lruRemovedCount = axElementCache.count - newCache.count
            axElementCache = newCache
            
            Logger.log("🧹 LRU cleanup completed, removed \(lruRemovedCount) AX elements, current size: \(axElementCache.count)")
        }
    }
    
    // Get or cache AX element
    private func getCachedAXElement(windowID: CGWindowID, processID: pid_t, windowIndex: Int) -> AXUIElement? {
        // Check if exists in cache and update access time
        if var cachedItem = axElementCache[windowID] {
            cachedItem.updateAccessTime()
            axElementCache[windowID] = cachedItem
            return cachedItem.element
        }
        
        // Not in cache, get new AX element
        let (_, axElement) = getAXWindowInfo(windowID: windowID, processID: processID, windowIndex: windowIndex)
        
        if let element = axElement {
            // Check if cleanup is needed before adding to cache
            cleanupAXCache()
            
            // Add to cache
            axElementCache[windowID] = AXCacheItem(element: element, processID: processID)
            Logger.log("📦 Caching AX element: WindowID \(windowID), current cache size: \(axElementCache.count)")
        }
        
        return axElement
    }
    // MARK: - 快捷键直接切换（无切换器界面）
    /// 不显示任何界面，直接把焦点切到当前应用的下一个窗口。
    /// windows[0] 为当前聚焦窗口，因此取 windows[1] 即"下一个"；
    /// 激活后焦点变化，再次按快捷键会相对新焦点继续切换，形成循环。
    func switchToNextWindow() {
        getCurrentAppWindows()

        guard windows.count > 1 else {
            Logger.log("Switch: current app has only one window, nothing to switch")
            return
        }

        let targetWindow = windows[1]
        Logger.log("⚡️ Direct window switch -> \(targetWindow.title)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.activateWindowAsync(targetWindow)
        }
    }

    private func getCurrentAppWindows() {
        windows.removeAll()
        // 不再全量清空AX缓存，让智能清理机制处理
        
        // 打印所有运行的应用
        Logger.log("\n=== Debug Information Start ===")
        let allApps = NSWorkspace.shared.runningApplications
        let runningAppMap = Dictionary(uniqueKeysWithValues: allApps.map { ($0.processIdentifier, $0) })
        let bundlePrimaryApp = allApps.reduce(into: [String: NSRunningApplication]()) { partialResult, app in
            guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { return }
            if partialResult[bundleId] == nil {
                partialResult[bundleId] = app
            }
        }
        // Logger.log("All running applications:")
        // for app in allApps {
        //     let isActive = app.isActive ? " [ACTIVE]" : ""
        //     let bundleId = app.bundleIdentifier ?? "Unknown"
        //     Logger.log("  - \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier), Bundle: \(bundleId))\(isActive)")
        // }
        
        // 获取前台应用（排除自己）
        let frontmostApp = allApps.first { app in
            app.isActive && app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        
        // 获取所有窗口（统一获取，避免重复调用）
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // 如果无法获取前台应用，则使用最前面窗口对应的应用
        let targetApp: NSRunningApplication
        if let frontApp = frontmostApp {
            targetApp = frontApp
            Logger.log("✅ Using frontmost application as target app")
        } else {
            Logger.log("⚠️ Cannot get frontmost application, trying to use application of the frontmost window")
            
            // 找到第一个有效的可见窗口的应用（排除自己）
            // windowList已经按z-order排序（最前面的窗口在前）
            var topWindowApp: NSRunningApplication?
            for windowInfo in windowList {
                guard let processID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                      let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool,
                      let layer = windowInfo[kCGWindowLayer as String] as? Int else { continue }
                let ownerName = windowInfo[kCGWindowOwnerName as String] as? String

                if !isOnScreen {
                    continue
                }

                guard let resolvedApp = resolvePrimaryApp(
                    for: processID,
                    ownerName: ownerName,
                    runningAppMap: runningAppMap,
                    bundlePrimaryApp: bundlePrimaryApp
                ),
                resolvedApp.bundleIdentifier != Bundle.main.bundleIdentifier,
                isValidWindowLayer(layer, forBundleId: resolvedApp.bundleIdentifier) else {
                    continue
                }

                topWindowApp = resolvedApp
                Logger.log("🔍 Found application of frontmost window: \(resolvedApp.localizedName ?? "Unknown") (PID: \(resolvedApp.processIdentifier), Layer: \(layer))")
                if isSteamApplication(resolvedApp.bundleIdentifier) {
                    Logger.log("🎮 Detected Steam application with layer \(layer)")
                }
                break
            }
            
            guard let foundApp = topWindowApp else {
                Logger.log("❌ Cannot get any valid target application")
                return
            }
            
            targetApp = foundApp
        }
        
        Logger.log("\n🎯 Target application: \(targetApp.localizedName ?? "Unknown") (PID: \(targetApp.processIdentifier))")
        Logger.log("   Bundle ID: \(targetApp.bundleIdentifier ?? "Unknown")")
        Logger.log("\n📋 System found \(windowList.count) windows in total")
        
        // 筛选目标应用的窗口
        var candidateWindows: [[String: Any]] = []
        var validWindows: [[String: Any]] = []
        var windowCounter = 1
        var windowIndexByProcess: [pid_t: Int] = [:]

        for windowInfo in windowList {
            guard let processID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String

            if windowBelongsToApp(
                windowProcessID: processID,
                ownerName: ownerName,
                targetApp: targetApp,
                runningAppMap: runningAppMap,
                bundlePrimaryApp: bundlePrimaryApp
            ) {
                candidateWindows.append(windowInfo)
                
                let windowTitle = windowInfo[kCGWindowName as String] as? String ?? ""
                let layer = windowInfo[kCGWindowLayer as String] as? Int ?? -1
                let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID ?? 0
                let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
                
                Logger.log("🔎 Checking target application window:")
                Logger.log("   Owner: \(ownerName ?? "Unknown") (PID: \(processID))")
                Logger.log("   Title: '\(windowTitle)'")
                Logger.log("   Layer: \(layer)")
                Logger.log("   ID: \(windowID)")
                Logger.log("   OnScreen: \(isOnScreen)")
                
                let hasValidID = windowInfo[kCGWindowNumber as String] is CGWindowID
                let hasValidLayer = isValidWindowLayer(layer, forBundleId: targetApp.bundleIdentifier)
                let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any]
                let width = (bounds?["Width"] as? NSNumber)?.intValue ?? 0
                let height = (bounds?["Height"] as? NSNumber)?.intValue ?? 0
                let hasReasonableSize = width > 100 && height > 100 // 过滤掉太小的窗口
                
                Logger.log("   Filter check: ID=\(hasValidID), Layer=\(hasValidLayer), Size=\(width)x\(height), ReasonableSize=\(hasReasonableSize)")
                
                if hasValidID && hasValidLayer && hasReasonableSize {
                    validWindows.append(windowInfo)

                    let currentIndex = windowIndexByProcess[processID] ?? 0
                    windowIndexByProcess[processID] = currentIndex + 1
                    
                    let (axTitle, _) = getAXWindowInfo(windowID: windowID, processID: processID, windowIndex: currentIndex)
                    
                    let displayTitle: String
                    let projectName: String
                    
                    if !axTitle.isEmpty {
                        displayTitle = axTitle
                        projectName = settingsManager.extractProjectName(
                            from: axTitle,
                            bundleId: targetApp.bundleIdentifier ?? "",
                            appName: targetApp.localizedName ?? ""
                        )
                    } else if !windowTitle.isEmpty {
                        displayTitle = windowTitle
                        projectName = settingsManager.extractProjectName(
                            from: windowTitle,
                            bundleId: targetApp.bundleIdentifier ?? "",
                            appName: targetApp.localizedName ?? ""
                        )
                    } else {
                        displayTitle = "\(targetApp.localizedName ?? "App") window \(windowCounter)"
                        projectName = displayTitle
                        windowCounter += 1
                    }
                    
                    let window = WindowInfo(
                        windowID: windowID,
                        title: displayTitle,
                        projectName: projectName,
                        appName: targetApp.localizedName ?? "",
                        processID: processID,
                        axWindowIndex: currentIndex
                    )
                    
                    windows.append(window)
                    Logger.log("   ✅ Window added: '\(projectName)'")
                } else {
                    Logger.log("   ❌ Window filtered out")
                }
                Logger.log("")
            }
        }
        
                 Logger.log("📊 Statistics result:")
         Logger.log("   Target application candidate windows: \(candidateWindows.count)")
         Logger.log("   Valid windows: \(validWindows.count)")
         Logger.log("   Final added windows: \(windows.count)")
         Logger.log("=== Debug Information End ===\n")
     }
     
     // 通过 AX API 获取特定窗口ID对应的标题和AXUIElement
     private func getAXWindowInfo(windowID: CGWindowID, processID: pid_t, windowIndex: Int) -> (title: String, axElement: AXUIElement?) {
         let app = AXUIElementCreateApplication(processID)
         
         var windowsRef: CFTypeRef?
         guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWindows = windowsRef as? [AXUIElement] else {
             Logger.log("   ❌ Cannot get AX window list")
             return ("", nil)
         }
         
         Logger.log("   🔍 Total AX windows: \(axWindows.count), target index: \(windowIndex)")
         
         // 直接通过索引获取对应的AX窗口
         guard windowIndex < axWindows.count else {
             Logger.log("   ❌ Window index \(windowIndex) out of range (total: \(axWindows.count))")
             return ("", nil)
         }
         
         let axWindow = axWindows[windowIndex]
         
         // 获取窗口标题
         var titleRef: CFTypeRef?
         if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
            let title = titleRef as? String {
             Logger.log("   ✅ Window ID \(windowID) matched successfully through index[\(windowIndex)], title: '\(title)'")
             return (title, axWindow)
         } else {
             Logger.log("   ⚠️ Window ID \(windowID) matched successfully through index[\(windowIndex)], but no title")
             return ("", axWindow)
         }
     }

    /// 异步窗口激活方法，优化性能和流畅度
    private func activateWindowAsync(_ window: WindowInfo) {
        Logger.log("🚀 Async window activation started: \(window.title)")
        
        // 首先尝试快速激活应用
        guard let app = NSRunningApplication(processIdentifier: window.processID) else {
            Logger.log("❌ Cannot find application corresponding to process ID \(window.processID)")
            return
        }
        
        // 在主线程激活应用（系统要求）
        DispatchQueue.main.async {
            let activated = app.activate()
            Logger.log("   📱 Application activation result: \(activated ? "successful" : "failed")")
        }
        
        // 短暂延迟后激活具体窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.activateSpecificWindowFast(window)
        }
    }
    
    /// 快速窗口激活方法，简化复杂的多显示器处理
    private func activateSpecificWindowFast(_ window: WindowInfo) {
        Logger.log("⚡ Fast activation of specific window: \(window.title)")
        
        // 尝试从缓存获取AX元素
        if let axElement = getCachedAXElement(
            windowID: window.windowID,
            processID: window.processID, 
            windowIndex: window.axWindowIndex
        ) {
            // 使用AX API激活窗口
            let raiseResult = AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            Logger.log("   ⚡ AX activation result: \(raiseResult == .success ? "successful" : "failed")")
            
            if raiseResult == .success {
                // 尝试设置为主窗口和焦点窗口
                AXUIElementSetAttributeValue(axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                Logger.log("   ✅ Window activation completed")
                return
            }
        }
        
        // 如果AX方法失败，使用降级方案
        Logger.log("   ⚠️ AX method failed, using fallback solution")
        fallbackActivateAsync(window)
    }
    
    /// 异步降级激活方案
    private func fallbackActivateAsync(_ window: WindowInfo) {
        // 简化的降级方案，只激活应用
        if let app = NSRunningApplication(processIdentifier: window.processID) {
            app.activate()
            Logger.log("   📱 Fallback solution: application activated")
        }
        
        // 可选：尝试通过窗口ID进行基本操作（如果需要）
        // 这里可以添加其他轻量级的窗口操作
    }
}
