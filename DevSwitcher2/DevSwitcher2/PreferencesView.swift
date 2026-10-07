//
//  PreferencesView.swift
//  DevSwitcher2
//
//  Created by river on 2025-07-26.
//  重构：单页扁平偏好设置（快捷键 / 语言 / 通用）
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var languageManager = LanguageManager.shared
    @State private var selectedModifier: ModifierKey
    @State private var selectedTrigger: TriggerKey

    init() {
        let settings = SettingsManager.shared.settings
        _selectedModifier = State(initialValue: settings.modifierKey)
        _selectedTrigger = State(initialValue: settings.triggerKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 窗口切换快捷键
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(LocalizedStrings.ds2HotkeySectionTitle)

                HStack {
                Text(LocalizedStrings.ds2HotkeyDescription)
                    .font(.body)

                Spacer()

                HStack(spacing: 8) {
                    Picker("", selection: $selectedModifier) {
                        ForEach(ModifierKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 110)

                    Text("+")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedTrigger) {
                        ForEach(TriggerKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 110)
                }
                }
            }
            .onChange(of: selectedModifier) { _ in applyHotkey() }
            .onChange(of: selectedTrigger) { _ in applyHotkey() }

            sectionDivider()

            // MARK: - 语言
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(LocalizedStrings.languageSectionTitle)

                HStack {
                    Text(LocalizedStrings.languageSelectionLabel)
                        .font(.body)

                    Spacer()

                    Picker("", selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 170)
                    .onChange(of: languageManager.currentLanguage) { newLanguage in
                        languageManager.setLanguage(newLanguage)
                    }
                }

                HStack(spacing: 10) {
                    Text(LocalizedStrings.languageRestartNote)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(LocalizedStrings.languageRestartNowButton) {
                        restartApplication()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 10)
            }

            sectionDivider()

            // MARK: - 通用
            sectionHeader(LocalizedStrings.generalSettingsSectionTitle)

            HStack {
                Text(LocalizedStrings.launchAtStartup)
                    .font(.body)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { settingsManager.settings.launchAtStartup },
                    set: { newValue in
                        settingsManager.updateLaunchAtStartup(newValue)
                    }
                ))
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
            }

            Spacer(minLength: 24)

            // MARK: - 底部按钮
            HStack {
                Button(LocalizedStrings.hotkeyReset) {
                    selectedModifier = .command
                    selectedTrigger = .grave
                }
                .buttonStyle(.bordered)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(LocalizedStrings.currentHotkeyDisplay(selectedModifier.displayName, selectedTrigger.displayName))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 560, height: 400)
    }

    // MARK: - 样式组件

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3)
            .fontWeight(.bold)
            .padding(.bottom, 14)
    }

    private func sectionDivider() -> some View {
        Divider()
            .padding(.vertical, 20)
    }

    // MARK: - 动作

    private func applyHotkey() {
        settingsManager.updateHotkey(modifier: selectedModifier, trigger: selectedTrigger)
        NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
    }

    private func restartApplication() {
        Logger.log("🔄 Restarting application from preferences...")

        let appPath = Bundle.main.bundlePath

        let restartScript = """
        #!/bin/bash
        sleep 1
        open "\(appPath)"
        """

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("restart_devswitcher2.sh")

        do {
            try restartScript.write(to: tempURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.launchPath = "/bin/chmod"
            process.arguments = ["+x", tempURL.path]
            process.launch()
            process.waitUntilExit()

            let restartProcess = Process()
            restartProcess.launchPath = "/bin/bash"
            restartProcess.arguments = [tempURL.path]
            restartProcess.launch()

            NSApplication.shared.terminate(nil)
        } catch {
            Logger.log("❌ Failed to restart application: \(error)")
        }
    }
}
