import AppKit
import CodexKit
import Foundation

extension AppModel {
    func cancelPendingChatGPTLoginForTeardown() {
        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
    }

    func signInWithChatGPT() {
        guard let runtime else { return }

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
        guard let runtime else { return }

        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                try await runtime.startAPIKeyLogin(apiKey: apiKey)
                try keychainStore.saveSecret(apiKey, account: APIKeychainStore.runtimeAPIKeyAccount)
                try await upsertProjectAPIKeyReferenceIfNeeded()
                try await refreshAccountState()
                accountStatusMessage = "Signed in with API key."
                appendLog(.info, "Signed in with API key")
                requestAutoDrain(reason: "account signed in")
            } catch {
                accountStatusMessage = "API key sign-in failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func logoutAccount() {
        guard let runtime else { return }

        stopChatGPTLoginPolling(cancelRuntimeLogin: true)
        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                try await runtime.logoutAccount()
                try keychainStore.deleteSecret(account: APIKeychainStore.runtimeAPIKeyAccount)
                try await refreshAccountState()
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
                        accountStatusMessage = "Signed in with ChatGPT."
                        appendLog(.info, "ChatGPT login confirmed by account polling")
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
