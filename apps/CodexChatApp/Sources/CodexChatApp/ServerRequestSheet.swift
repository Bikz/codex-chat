import CodexChatUI
import CodexKit
import SwiftUI

struct ServerRequestSheet: View {
    @ObservedObject var model: AppModel
    let request: RuntimeServerRequest

    var body: some View {
        ServerRequestDialogContent(model: model, request: request, isInline: false)
            .padding(18)
            .frame(minWidth: 620, minHeight: 360)
    }
}

struct InlineServerRequestView: View {
    @ObservedObject var model: AppModel
    let request: RuntimeServerRequest

    @Environment(\.designTokens) private var tokens

    var body: some View {
        ServerRequestDialogContent(model: model, request: request, isInline: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(hex: tokens.palette.panelHex).opacity(model.isTransparentThemeMode ? 0.78 : 0.95),
                in: RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
                    .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
            )
    }
}

private struct ServerRequestDialogContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimeServerRequest
    let isInline: Bool

    var body: some View {
        switch request {
        case let .permissions(permission):
            PermissionsRequestContent(model: model, request: permission, isInline: isInline)
        case let .userInput(userInput):
            UserInputRequestContent(model: model, request: userInput, isInline: isInline)
        case let .mcpElicitation(mcp):
            MCPElicitationRequestContent(model: model, request: mcp, isInline: isInline)
        case let .dynamicToolCall(tool):
            DynamicToolCallRequestContent(model: model, request: tool, isInline: isInline)
        case .approval:
            EmptyView()
        }
    }
}

private struct PermissionsRequestContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimePermissionsRequest
    let isInline: Bool

    @State private var grantedPermissions: Set<String>
    @State private var scopeText: String

    init(model: AppModel, request: RuntimePermissionsRequest, isInline: Bool) {
        self.model = model
        self.request = request
        self.isInline = isInline
        _grantedPermissions = State(initialValue: Set(request.permissions))
        _scopeText = State(initialValue: request.grantRoot ?? "")
    }

    private var isSubmitting: Bool {
        model.serverRequestDecisionInFlightRequestIDs.contains(request.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions Required")
                .font(.title3.weight(.semibold))

            labeledSection("Reason", request.reason ?? "The runtime requested additional permissions.")

            requestMetadata(cwd: request.cwd, itemID: request.itemID, method: request.method)

            VStack(alignment: .leading, spacing: 8) {
                Text("Requested permissions")
                    .font(.subheadline.weight(.semibold))
                ForEach(request.permissions, id: \.self) { permission in
                    Toggle(isOn: permissionBinding(permission)) {
                        Text(permission)
                            .font(.callout.monospaced())
                    }
                    .toggleStyle(.checkbox)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Optional scope", text: $scopeText)
                    .textFieldStyle(.roundedBorder)
            }

            statusFooter(model.serverRequestStatusMessage)

            HStack(spacing: 10) {
                Button("Deny") {
                    model.declinePermissionsRequest(requestID: request.id)
                }
                .buttonStyle(.bordered)

                Button(grantedPermissions.isEmpty ? "Submit Empty" : "Allow Selected") {
                    model.submitPermissionsRequestResponse(
                        requestID: request.id,
                        permissions: grantedPermissions,
                        scope: scopeText
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(isSubmitting)
        }
    }

    private func permissionBinding(_ permission: String) -> Binding<Bool> {
        Binding(
            get: { grantedPermissions.contains(permission) },
            set: { enabled in
                if enabled {
                    grantedPermissions.insert(permission)
                } else {
                    grantedPermissions.remove(permission)
                }
            }
        )
    }
}

private struct UserInputRequestContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimeUserInputRequest
    let isInline: Bool

    @State private var text: String
    @State private var selectedOptionID: String?

    init(model: AppModel, request: RuntimeUserInputRequest, isInline: Bool) {
        self.model = model
        self.request = request
        self.isInline = isInline
        _text = State(initialValue: request.value ?? "")
        _selectedOptionID = State(initialValue: request.options.first?.id)
    }

    private var isSubmitting: Bool {
        model.serverRequestDecisionInFlightRequestIDs.contains(request.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title ?? "Input Required")
                .font(.title3.weight(.semibold))

            labeledSection("Prompt", request.prompt)
            requestMetadata(cwd: nil, itemID: request.itemID, method: request.method)

            if !request.options.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choices")
                        .font(.subheadline.weight(.semibold))
                    Picker("Choices", selection: $selectedOptionID) {
                        Text("No preset choice").tag(String?.none)
                        ForEach(request.options) { option in
                            Text(option.label).tag(String?.some(option.id))
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if let selectedOptionID,
                       let option = request.options.first(where: { $0.id == selectedOptionID }),
                       let description = option.description,
                       !description.isEmpty
                    {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Response")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isInline {
                    TextField(request.placeholder ?? "Type a response", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15))
                        )
                }
            }

            statusFooter(model.serverRequestStatusMessage)

            HStack(spacing: 10) {
                Button("Dismiss") {
                    model.submitUserInputRequestResponse(
                        requestID: request.id,
                        text: nil,
                        optionID: nil
                    )
                }
                .buttonStyle(.bordered)

                Button("Submit") {
                    model.submitUserInputRequestResponse(
                        requestID: request.id,
                        text: text,
                        optionID: selectedOptionID
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(isSubmitting)
        }
    }
}

private struct MCPElicitationRequestContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimeMCPElicitationRequest
    let isInline: Bool

    @State private var text = ""

    private var isSubmitting: Bool {
        model.serverRequestDecisionInFlightRequestIDs.contains(request.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.serverName.map { "\($0) Needs Input" } ?? "MCP Elicitation")
                .font(.title3.weight(.semibold))

            labeledSection("Prompt", request.prompt)
            requestMetadata(cwd: nil, itemID: request.itemID, method: request.method)

            VStack(alignment: .leading, spacing: 6) {
                Text("Response")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isInline {
                    TextField("Type a response", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15))
                        )
                }
            }

            statusFooter(model.serverRequestStatusMessage)

            HStack(spacing: 10) {
                Button("Dismiss") {
                    model.submitMCPElicitationResponse(requestID: request.id, text: nil)
                }
                .buttonStyle(.bordered)

                Button("Submit") {
                    model.submitMCPElicitationResponse(requestID: request.id, text: text)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(isSubmitting)
        }
    }
}

private struct DynamicToolCallRequestContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimeDynamicToolCallRequest
    let isInline: Bool

    private var isSubmitting: Bool {
        model.serverRequestDecisionInFlightRequestIDs.contains(request.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dynamic Tool Call")
                .font(.title3.weight(.semibold))

            labeledSection("Tool", request.toolName)
            requestMetadata(cwd: nil, itemID: request.itemID, method: request.method)

            if let arguments = request.arguments {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Arguments")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(formatJSONValue(arguments))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: isInline ? 120 : 180)
                    .padding(8)
                    .tokenCard(style: .panel, radius: 8, strokeOpacity: 0.06)
                }
            }

            statusFooter(model.serverRequestStatusMessage)

            HStack(spacing: 10) {
                Button("Decline") {
                    model.submitDynamicToolCallResponse(requestID: request.id, approved: false)
                }
                .buttonStyle(.bordered)

                Button("Approve") {
                    model.submitDynamicToolCallResponse(requestID: request.id, approved: true)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(isSubmitting)
        }
    }
}

private func labeledSection(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(detail)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func requestMetadata(cwd: String?, itemID: String?, method: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
        labeledMeta("Method", method, monospaced: true)
        if let cwd, !cwd.isEmpty {
            labeledMeta("Working dir", cwd, monospaced: true)
        }
        if let itemID, !itemID.isEmpty {
            labeledMeta("Item", itemID, monospaced: true)
        }
    }
}

private func labeledMeta(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(value)
            .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

private func formatJSONValue(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8)
    else {
        return String(describing: value)
    }
    return string
}

@ViewBuilder
private func statusFooter(_ text: String?) -> some View {
    if let text, !text.isEmpty {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
