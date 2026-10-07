//
//  LocalizationHelper.swift
//  DevSwitcher2
//
//  Created by river on 2025-07-26.
//

import Foundation
import SwiftUI

// MARK: - Language Manager
class LanguageManager: ObservableObject {
    @Published var currentLanguage: AppLanguage = .system
    
    static let shared = LanguageManager()
    private let userDefaults = UserDefaults.standard
    private let languageKey = "DevSwitcher2Language"
    
    private init() {
        if let languageString = userDefaults.string(forKey: languageKey),
           let language = AppLanguage(rawValue: languageString) {
            self.currentLanguage = language
        }
        applyLanguage()
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        userDefaults.set(language.rawValue, forKey: languageKey)
        applyLanguage()
        
        // Notify app to update UI
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }
    
    private func applyLanguage() {
        let languageCode = currentLanguage.languageCode
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}

// MARK: - App Supported Languages
enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"
    
    var displayName: String {
        switch self {
        case .system:
            return "language_system".localized
        case .english:
            return "language_english".localized
        case .chinese:
            return "language_chinese".localized
        }
    }
    
    var languageCode: String {
        switch self {
        case .system:
            return Locale.preferredLanguages.first?.prefix(2).description ?? "en"
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }
}

extension String {
    var localized: String {
        let language = LanguageManager.shared.currentLanguage
        if language == .system {
            return NSLocalizedString(self, comment: "")
        }
        
        guard let path = Bundle.main.path(forResource: language.languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }
        
        return NSLocalizedString(self, tableName: nil, bundle: bundle, comment: "")
    }
    
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

struct LocalizedStrings {
    // MARK: - Language Settings
    static let language = "language".localized
    static let languageSectionTitle = "language_section_title".localized
    static let languageSelectionLabel = "language_selection_label".localized
    static let languageRestartNote = "language_restart_note".localized
    static let languageRestartNowButton = "language_restart_now_button".localized
    
    // MARK: - General Settings
    static let generalSettingsSectionTitle = "general_settings_section_title".localized
    static let launchAtStartup = "launch_at_startup".localized
    
    // MARK: - Status Bar
    static let statusItemTooltip = "status_item_tooltip".localized
    
    // MARK: - Permission Prompts
    static let accessibilityPermissionRequired = "accessibility_permission_required".localized
    static let openSystemPreferences = "open_system_preferences".localized
    static let accessibilityPermissionTitle = "accessibility_permission_title".localized
    static let accessibilityPermissionMessage = "accessibility_permission_message".localized
    static let openSystemPreferencesButton = "open_system_preferences_button".localized
    static let setupLater = "setup_later".localized
    static let accessibilityPermissionGranted = "accessibility_permission_granted".localized
    
    // MARK: - Restart Required
    static let restartRequiredTitle = "restart_required_title".localized
    static let restartRequiredMessage = "restart_required_message".localized
    static let restartNow = "restart_now".localized
    static let restartLater = "restart_later".localized
    
    // MARK: - Error Messages
    // MARK: - Menu Bar
    static let preferences = "preferences".localized
    static let quitApp = "quit_app".localized
    
    // MARK: - Preferences
    static let preferencesTitle = "preferences_title".localized
    static let hotkeySettings = "hotkey_settings".localized
    static let modifierKey = "modifier_key".localized
    static let triggerKey = "trigger_key".localized
    static let apply = "apply".localized
    static let reset = "reset".localized
    static let configuration = "configuration".localized
    static let currentHotkey = "current_hotkey".localized
    
    // MARK: - DS2 Settings
    static func currentHotkeyDisplay(_ modifier: String, _ trigger: String) -> String {
        return "current_hotkey_display".localized(with: modifier, trigger)
    }
    
    // MARK: - CT2 Settings
    
    // MARK: - Modifier Keys
    static let modifierCommand = "modifier_command".localized
    static let modifierOption = "modifier_option".localized
    static let modifierControl = "modifier_control".localized
    static let modifierFunction = "modifier_function".localized
    
    // MARK: - Trigger Keys
    static let triggerGrave = "trigger_grave".localized
    static let triggerTab = "trigger_tab".localized
    static let triggerSpace = "trigger_space".localized
    static let triggerSemicolon = "trigger_semicolon".localized
    static let triggerQuote = "trigger_quote".localized
    static let triggerComma = "trigger_comma".localized
    static let triggerPeriod = "trigger_period".localized
    static let triggerSlash = "trigger_slash".localized
    static let triggerBackslash = "trigger_backslash".localized
    static let triggerLeftBracket = "trigger_left_bracket".localized
    static let triggerRightBracket = "trigger_right_bracket".localized
    
    // MARK: - Window Title Configuration
    static let strategy = "strategy".localized
    static let delete = "delete".localized
    
    // MARK: - Title Extraction Strategies
    static let strategyFirstPart = "strategy_first_part".localized
    static let strategyLastPart = "strategy_last_part".localized
    static let strategyBeforeFirstSeparator = "strategy_before_first_separator".localized
    static let strategyAfterLastSeparator = "strategy_after_last_separator".localized
    static let strategyFullTitle = "strategy_full_title".localized
    
    // MARK: - Add App Configuration Dialog
    static let bundleId = "bundle_id".localized
    static let appName = "app_name".localized
    static let customSeparator = "custom_separator".localized
    static let save = "save".localized
    
    // MARK: - Separator Placeholders for Different Strategies
    
    // MARK: - Separator Help Text for Different Strategies
    
    // MARK: - Preview Functionality
    static let preview = "preview".localized
    
    // MARK: - App Selection UI
    
    // MARK: - Add App Config Dialog Section Titles
    
    // MARK: - Configuration Export/Import
    static let fileName = "file_name".localized
    
    // MARK: - Additional UI Labels
    static let ds2HotkeySectionTitle = "ds2_hotkey_section_title".localized
    static let ds2HotkeyDescription = "ds2_hotkey_description".localized
    static let hotkeyReset = "hotkey_reset".localized
    
    // MARK: - Switcher Display Settings
    // MARK: - Switcher Behavior Settings
    
    // MARK: - Switcher Position Settings
    
    // MARK: - Switcher Header Style Settings
    
    // MARK: - Switcher Layout Style Settings
    
    // MARK: - Circular Layout Size Settings
    
    // MARK: - Circular Layout Outer Ring Transparency Settings

    // MARK: - Selected Item Display Style Settings

    // MARK: - Color Scheme Settings
    
    // MARK: - About Page
    static let version = "version".localized
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
} 