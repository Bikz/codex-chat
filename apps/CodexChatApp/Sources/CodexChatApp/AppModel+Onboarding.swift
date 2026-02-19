import Foundation

extension AppModel {
    func enterOnboarding(reason: OnboardingReason) {
        onboardingCompletionTask?.cancel()
        onboardingCompletionTask = nil
        onboardingMode = .active
        detailDestination = .none

        if reason == .signedOut {
            selectedThreadID = nil
            draftChatProjectID = nil
            refreshConversationState()
        }
    }

    func completeOnboardingIfReady() {
        guard onboardingMode == .active else {
            return
        }
        guard isOnboardingReadyToComplete else {
            return
        }
        guard onboardingCompletionTask == nil else {
            return
        }

        onboardingCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { onboardingCompletionTask = nil }

            let activated = await activateDefaultPostOnboardingContext()
            if activated {
                onboardingMode = .inactive
            }
        }
    }

    @discardableResult
    func activateDefaultPostOnboardingContext() async -> Bool {
        do {
            try await ensureGeneralProject()
            try await refreshProjects()
            guard let generalProjectID = generalProject?.id else {
                projectStatusMessage = "General project is unavailable."
                return false
            }

            selectedProjectID = generalProjectID
            selectedThreadID = nil
            draftChatProjectID = generalProjectID
            detailDestination = .thread
            try await persistSelection()
            try await refreshGeneralThreads(generalProjectID: generalProjectID)
            refreshConversationState()
            detailDestination = .thread
            return true
        } catch {
            let message = "Failed to initialize onboarding context: \(error.localizedDescription)"
            projectStatusMessage = message
            appendLog(.error, message)
            return false
        }
    }
}
