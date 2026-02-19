import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    func approvalDangerWarning(for request: RuntimeApprovalRequest) -> String? {
        guard isPotentiallyRiskyApproval(request) else {
            return nil
        }
        return "This action appears risky. Review command/file details carefully before approving."
    }

    func runtimeSafetyConfiguration(
        for project: ProjectRecord,
        preferredWebSearch: ProjectWebSearchMode? = nil
    ) -> RuntimeSafetyConfiguration {
        let effectiveWebSearch: ProjectWebSearchMode = if let preferredWebSearch {
            preferredWebSearch
        } else {
            project.webSearch
        }

        return RuntimeSafetyConfiguration(
            sandboxMode: mapSandboxMode(project.sandboxMode),
            approvalPolicy: mapApprovalPolicy(project.approvalPolicy),
            networkAccess: project.networkAccess,
            webSearch: mapWebSearchMode(effectiveWebSearch),
            writableRoots: [project.path]
        )
    }

    func approvalSummary(for request: RuntimeApprovalRequest) -> String {
        var lines: [String] = []
        if let reason = request.reason, !reason.isEmpty {
            lines.append("reason: \(reason)")
        }
        if let risk = request.risk, !risk.isEmpty {
            lines.append("risk: \(risk)")
        }
        if let cwd = request.cwd, !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if !request.command.isEmpty {
            lines.append("command: \(request.command.joined(separator: " "))")
        }
        if !request.changes.isEmpty {
            lines.append("changes: \(request.changes.count) file(s)")
        }
        if lines.isEmpty {
            lines.append(request.detail)
        }
        return lines.joined(separator: "\n")
    }

    private func mapSandboxMode(_ mode: ProjectSandboxMode) -> RuntimeSandboxMode {
        switch mode {
        case .readOnly:
            .readOnly
        case .workspaceWrite:
            .workspaceWrite
        case .dangerFullAccess:
            .dangerFullAccess
        }
    }

    private func mapApprovalPolicy(_ policy: ProjectApprovalPolicy) -> RuntimeApprovalPolicy {
        switch policy {
        case .untrusted:
            .untrusted
        case .onRequest:
            .onRequest
        case .never:
            .never
        }
    }

    private func mapWebSearchMode(_ mode: ProjectWebSearchMode) -> RuntimeWebSearchMode {
        switch mode {
        case .cached:
            .cached
        case .live:
            .live
        case .disabled:
            .disabled
        }
    }

    private func isPotentiallyRiskyApproval(_ request: RuntimeApprovalRequest) -> Bool {
        let commandText = request.command.joined(separator: " ").lowercased()
        let riskyPatterns = [
            "rm -rf",
            "sudo ",
            "chmod ",
            "chown ",
            "mkfs",
            "dd ",
            "git reset --hard",
        ]

        if riskyPatterns.contains(where: { commandText.contains($0) }) {
            return true
        }

        if request.kind == .fileChange {
            return request.changes.contains(where: {
                $0.path.contains(".git/") || $0.path.contains(".codex/")
            })
        }

        return false
    }
}
