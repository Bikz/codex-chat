import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    func handleRuntimeEvent(_ event: CodexRuntimeEvent) {
        switch event {
        case let .threadStarted(threadID):
            appendLog(.debug, "Runtime thread started: \(threadID)")

        case let .turnStarted(turnID):
            if let context = activeTurnContext {
                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: context.localThreadID,
                            method: "turn/started",
                            title: "Turn started",
                            detail: "turnId=\(turnID)"
                        )
                    ),
                    to: context.localThreadID
                )
            }

        case let .assistantMessageDelta(itemID, delta):
            guard let context = activeTurnContext else {
                appendLog(.debug, "Dropped delta with no active turn")
                return
            }

            appendAssistantDelta(delta, itemID: itemID, to: context.localThreadID)
            var updatedContext = context
            updatedContext.assistantText += delta
            activeTurnContext = updatedContext

        case let .commandOutputDelta(output):
            handleCommandOutputDelta(output)

        case let .followUpSuggestions(batch):
            handleFollowUpSuggestions(batch)

        case let .fileChangesUpdated(update):
            handleFileChangesUpdate(update)

        case let .approvalRequested(request):
            handleApprovalRequest(request)

        case let .action(action):
            handleRuntimeAction(action)

        case let .turnCompleted(completion):
            isTurnInProgress = false
            if let context = activeTurnContext {
                let detail = if let errorMessage = completion.errorMessage {
                    "status=\(completion.status), error=\(errorMessage)"
                } else {
                    "status=\(completion.status)"
                }

                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: context.localThreadID,
                            method: "turn/completed",
                            title: "Turn completed",
                            detail: detail
                        )
                    ),
                    to: context.localThreadID
                )

                assistantMessageIDsByItemID[context.localThreadID] = [:]
                localThreadIDByCommandItemID = localThreadIDByCommandItemID.filter { $0.value != context.localThreadID }
                processModChangesIfNeeded(context: context)
                activeTurnContext = nil

                Task {
                    await persistCompletedTurn(context: context)
                }
            } else {
                appendLog(.debug, "Turn completed without active context: \(completion.status)")
            }
            requestAutoDrain(reason: "turn completed")

        case let .accountUpdated(authMode):
            appendLog(.info, "Account mode updated: \(authMode.rawValue)")
            Task {
                try? await refreshAccountState()
                requestAutoDrain(reason: "account updated")
            }

        case let .accountLoginCompleted(completion):
            stopChatGPTLoginPolling()
            if completion.success {
                accountStatusMessage = "Login completed."
                appendLog(.info, "Login completed")
                requestAutoDrain(reason: "account login completed")
            } else {
                let detail = completion.error ?? "Unknown error"
                accountStatusMessage = "Login failed: \(detail)"
                appendLog(.error, "Login failed: \(detail)")
            }
            Task {
                try? await refreshAccountState()
            }
        }
    }

    private func handleRuntimeAction(_ action: RuntimeAction) {
        if action.method == "runtime/stderr" {
            appendLog(.warning, action.detail)
        }

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: action.threadID,
            itemID: action.itemID
        ) ?? activeTurnContext?.localThreadID

        if action.method == "runtime/terminated" {
            handleRuntimeTermination(detail: action.detail)
        }

        guard let localThreadID else {
            appendLog(.debug, "Runtime action without thread mapping: \(action.method)")
            return
        }

        if action.itemType == "commandExecution",
           let itemID = action.itemID
        {
            localThreadIDByCommandItemID[itemID] = localThreadID
        }

        let card = ActionCard(
            threadID: localThreadID,
            method: action.method,
            title: action.title,
            detail: action.detail
        )
        appendEntry(.actionCard(card), to: localThreadID)

        if var context = activeTurnContext,
           context.localThreadID == localThreadID
        {
            context.actions.append(card)
            activeTurnContext = context
        }
    }

    private func handleCommandOutputDelta(_ output: RuntimeCommandOutputDelta) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: output.threadID,
            itemID: output.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.debug, "Command output delta without thread mapping")
            return
        }

        appendThreadLog(
            level: .info,
            text: output.delta,
            to: localThreadID
        )
    }

    private func handleFileChangesUpdate(_ update: RuntimeFileChangeUpdate) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: update.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.debug, "File changes update without thread mapping")
            return
        }

        reviewChangesByThreadID[localThreadID] = update.changes
    }

    private func handleApprovalRequest(_ request: RuntimeApprovalRequest) {
        approvalStateMachine.enqueue(request)
        activeApprovalRequest = approvalStateMachine.activeRequest
        approvalStatusMessage = nil

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: request.threadID,
            itemID: request.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.warning, "Approval request arrived without local thread mapping")
            return
        }

        let summary = approvalSummary(for: request)
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: request.method,
                    title: "Approval requested",
                    detail: summary
                )
            ),
            to: localThreadID
        )
    }

    func resolveLocalThreadID(runtimeThreadID: String?, itemID: String?) -> UUID? {
        if let itemID, let threadID = localThreadIDByCommandItemID[itemID] {
            return threadID
        }

        if let runtimeThreadID {
            if let mapped = localThreadIDByRuntimeThreadID[runtimeThreadID] {
                return mapped
            }
            if let activeTurnContext, activeTurnContext.runtimeThreadID == runtimeThreadID {
                return activeTurnContext.localThreadID
            }
        }

        return nil
    }
}
