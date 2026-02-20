import Foundation

extension AppModel {
    var composerInputPlaceholder: String {
        guard hasActiveDraftChatForSelectedProject,
              let selectedProjectName = selectedProject?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedProjectName.isEmpty
        else {
            return "Ask anything"
        }

        return "Message in \(selectedProjectName)"
    }
}
