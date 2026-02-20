import CodexChatCore
import Foundation

extension AppModel {
    private enum LegacyThemeDefaults {
        static let accentHex = "#10A37F"
        static let sidebarHex = "#F5F5F5"
        static let backgroundHex = "#F9F9F9"
        static let panelHex = "#FFFFFF"
        static let sidebarGradientHex = "#8AA2B2"
        static let chatGradientHex = "#B9C6D0"
        static let gradientStrength = 0.35
    }

    func restoreUserThemeCustomizationIfNeeded() async {
        guard let preferenceRepository else { return }

        do {
            guard let raw = try await preferenceRepository.getPreference(key: .userThemeCustomizationV1),
                  let data = raw.data(using: .utf8)
            else {
                userThemeCustomization = .default
                return
            }

            let decoded = try JSONDecoder().decode(UserThemeCustomization.self, from: data)
            userThemeCustomization = normalizedThemeCustomization(decoded)
        } catch {
            userThemeCustomization = .default
            appendLog(.warning, "Failed to restore theme customization: \(error.localizedDescription)")
        }
    }

    func setUserThemeCustomization(_ customization: UserThemeCustomization) {
        let normalized = normalizedThemeCustomization(customization)
        guard normalized != userThemeCustomization else { return }
        userThemeCustomization = normalized
        scheduleUserThemeCustomizationPersistence()
    }

    func resetUserThemeCustomization() {
        setUserThemeCustomization(.default)
    }

    private func scheduleUserThemeCustomizationPersistence() {
        guard preferenceRepository != nil else { return }

        userThemePersistenceTask?.cancel()
        let snapshot = userThemeCustomization
        userThemePersistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.persistUserThemeCustomization(snapshot)
        }
    }

    private func persistUserThemeCustomization(_ customization: UserThemeCustomization) async {
        guard let preferenceRepository else { return }

        do {
            let data = try JSONEncoder().encode(customization)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "CodexChat.ThemeCustomization",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to encode theme customization as UTF-8 text."]
                )
            }
            try await preferenceRepository.setPreference(key: .userThemeCustomizationV1, value: text)
        } catch {
            appendLog(.warning, "Failed to persist theme customization: \(error.localizedDescription)")
        }
    }

    private func normalizedThemeCustomization(_ customization: UserThemeCustomization) -> UserThemeCustomization {
        var copy = customization
        copy.gradientStrength = UserThemeCustomization.clampedGradientStrength(copy.gradientStrength)
        if isLegacyDefaultCustomization(copy) {
            return .default
        }
        return copy
    }

    private func isLegacyDefaultCustomization(_ customization: UserThemeCustomization) -> Bool {
        guard customization.isEnabled else { return false }
        guard customization.transparencyMode == .solid else { return false }
        guard customization.accentHex == LegacyThemeDefaults.accentHex else { return false }
        guard customization.sidebarHex == LegacyThemeDefaults.sidebarHex else { return false }
        guard customization.backgroundHex == LegacyThemeDefaults.backgroundHex else { return false }
        guard customization.panelHex == LegacyThemeDefaults.panelHex else { return false }
        guard customization.sidebarGradientHex == LegacyThemeDefaults.sidebarGradientHex else { return false }
        guard customization.chatGradientHex == LegacyThemeDefaults.chatGradientHex else { return false }
        return abs(customization.gradientStrength - LegacyThemeDefaults.gradientStrength) < 0.0001
    }
}
