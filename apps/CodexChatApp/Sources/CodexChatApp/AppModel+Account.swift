import AppKit
import CodexKit
import Foundation

extension AppModel {
    func cancelPendingChatGPTLoginForTeardown() {
        prepareForTeardown()
    }

    var isSignedInWithChatGPT: Bool {
        isChatGPTSignedIn(accountState)
    }

    func signInWithChatGPT() {
        if case .installCodex? = runtimeIssue {
            accountStatusMessage = "Install Codex and restart runtime to complete ChatGPT sign-in."
            return
        }

        guard let runtime else {
            accountStatusMessage = "Runtime is unavailable. Restart Runtime and try again."
            return
        }

        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                let loginStart = try await runtime.startChatGPTLogin()
                pendingChatGPTLoginID = loginStart.loginID
                NSWorkspace.shared.open(loginStart.authURL)
                accountStatusMessage = "Complete sign-in in your browser. Waiting for runtime confirmation…"
                appendLog(.info, "Started ChatGPT login flow")
                startChatGPTLoginPolling(loginID: loginStart.loginID)
            } catch {
                stopChatGPTLoginPolling()
                accountStatusMessage = "ChatGPT sign-in failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func presentAPIKeyPrompt() {
        pendingAPIKey = ""
        isAPIKeyPromptVisible = true
    }

    func cancelAPIKeyPrompt() {
        pendingAPIKey = ""
        isAPIKeyPromptVisible = false
    }

    func submitAPIKeyLogin() {
        let apiKey = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAPIKey = ""
        isAPIKeyPromptVisible = false

        guard !apiKey.isEmpty else {
            accountStatusMessage = "API key was empty."
            return
        }

        signInWithAPIKey(apiKey)
    }

    func signInWithAPIKey(_ apiKey: String) {
        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                try keychainStore.saveSecret(apiKey, account: APIKeychainStore.runtimeAPIKeyAccount)
                try await upsertProjectAPIKeyReferenceIfNeeded()

                if case .installCodex? = runtimeIssue {
                    accountStatusMessage = "API key saved in Keychain. Install Codex and restart runtime to finish sign-in."
                    appendLog(.info, "Stored API key while runtime binary is unavailable")
                    return
                }

                guard let runtime else {
                    accountStatusMessage = "API key saved in Keychain. Restart Runtime to finish sign-in."
                    appendLog(.info, "Stored API key while runtime is unavailable")
                    return
                }

                try await runtime.startAPIKeyLogin(apiKey: apiKey)
                try await refreshAccountState()
                await refreshRuntimeModelCatalog()
                accountStatusMessage = "Signed in with API key."
                appendLog(.info, "Signed in with API key")
                completeOnboardingIfReady()
                requestAutoDrain(reason: "account signed in")
            } catch {
                if let runtimeError = error as? CodexRuntimeError,
                   case .binaryNotFound = runtimeError
                {
                    accountStatusMessage = "API key saved in Keychain. Install Codex and restart runtime to finish sign-in."
                } else {
                    accountStatusMessage = "API key sign-in failed: \(error.localizedDescription)"
                }
                handleRuntimeError(error)
            }
        }
    }

    func logoutAccount() {
        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                if let runtime {
                    try await runtime.logoutAccount()
                }
                try keychainStore.deleteSecret(account: APIKeychainStore.runtimeAPIKeyAccount)
                if runtime != nil {
                    try await refreshAccountState()
                    await refreshRuntimeModelCatalog()
                } else {
                    accountState = .signedOut
                }
                enterOnboarding(reason: .signedOut)
                accountStatusMessage = "Logged out."
                appendLog(.info, "Account logged out")
            } catch {
                accountStatusMessage = "Logout failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func launchDeviceCodeLogin() {
        do {
            try CodexRuntime.launchDeviceAuthInTerminal()
            accountStatusMessage = "Device-auth started in Terminal. Availability depends on workspace settings."
            appendLog(.info, "Launched device-auth login in Terminal")
        } catch {
            accountStatusMessage = "Unable to start device-auth login: \(error.localizedDescription)"
            handleRuntimeError(error)
        }
    }

    func stopChatGPTLoginPolling(
        clearPendingLoginID: Bool = true,
        cancelRuntimeLogin: Bool = false
    ) {
        let loginID = pendingChatGPTLoginID
        chatGPTLoginPollingTask?.cancel()
        chatGPTLoginPollingTask = nil
        if clearPendingLoginID {
            pendingChatGPTLoginID = nil
        }

        guard cancelRuntimeLogin,
              let runtime,
              let loginID
        else {
            return
        }

        Task {
            do {
                try await runtime.cancelChatGPTLogin(loginID: loginID)
                appendLog(.debug, "Cancelled pending ChatGPT login session")
            } catch {
                appendLog(.debug, "Unable to cancel pending ChatGPT login session: \(error.localizedDescription)")
            }
        }
    }

    private func startChatGPTLoginPolling(loginID: String?) {
        chatGPTLoginPollingTask?.cancel()

        guard let runtime else { return }

        chatGPTLoginPollingTask = Task {
            defer {
                chatGPTLoginPollingTask = nil
            }

            for attempt in 1 ... 90 {
                if Task.isCancelled {
                    return
                }

                do {
                    let state = try await runtime.readAccount(refreshToken: true)
                    accountState = state

                    if isChatGPTSignedIn(state) {
                        pendingChatGPTLoginID = nil
                        await refreshRuntimeModelCatalog()
                        accountStatusMessage = "Signed in with ChatGPT."
                        appendLog(.info, "ChatGPT login confirmed by account polling")
                        completeOnboardingIfReady()
                        return
                    }
                } catch {
                    appendLog(.debug, "Waiting for ChatGPT login (\(attempt)/90): \(error.localizedDescription)")
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if let loginID {
                do {
                    try await runtime.cancelChatGPTLogin(loginID: loginID)
                } catch {
                    appendLog(.debug, "Unable to cancel stale ChatGPT login \(loginID): \(error.localizedDescription)")
                }
            }

            pendingChatGPTLoginID = nil
            accountStatusMessage = """
            Browser sign-in finished, but Codex runtime did not confirm login. Restart Runtime and retry, or use Device-Code Login.
            """
            appendLog(.warning, "Timed out waiting for account/login/completed")
        }
    }

    private func isChatGPTSignedIn(_ state: RuntimeAccountState) -> Bool {
        if state.authMode == .chatGPT, state.account != nil {
            return true
        }

        guard let account = state.account else {
            return false
        }

        return account.type.caseInsensitiveCompare("chatgpt") == .orderedSame
    }
}
