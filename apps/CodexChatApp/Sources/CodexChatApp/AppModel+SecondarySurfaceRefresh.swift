import Foundation

extension AppModel {
    func scheduleProjectSecondarySurfaceRefresh(
        transitionGeneration: UInt64,
        targetProjectID: UUID?,
        projectContextChanged: Bool,
        reason: String
    ) {
        guard projectContextChanged else {
            return
        }

        secondarySurfaceRefreshTask?.cancel()
        refreshModsSurface()

        secondarySurfaceRefreshTask = Task { [weak self] in
            guard let self else { return }
            let span = await PerformanceTracer.shared.begin(
                name: "thread.secondarySurfaceRefresh",
                metadata: [
                    "reason": reason,
                    "projectID": targetProjectID?.uuidString ?? "nil",
                ]
            )
            defer {
                Task {
                    await PerformanceTracer.shared.end(span)
                }
            }

            let fallbackTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                guard !Task.isCancelled else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedProjectID == targetProjectID else { return }

                if case .loading = skillsState, skillStatusMessage == nil {
                    skillStatusMessage = "Refreshing skills…"
                }
                if case .loading = modsState, modStatusMessage == nil {
                    modStatusMessage = "Refreshing mods…"
                }
            }

            defer { fallbackTask.cancel() }

            do {
                try await refreshSkills()
                guard !Task.isCancelled else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedProjectID == targetProjectID else { return }
                await refreshSkillsCatalog()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedProjectID == targetProjectID else { return }
                appendLog(.warning, "Secondary surface refresh failed (\(reason)): \(error.localizedDescription)")
            }
        }
    }
}
