import SwiftUI

struct CodexConfigSchemaFormView: View {
    @Binding var rootValue: CodexConfigValue
    let schema: CodexConfigSchemaNode

    @State private var newTopLevelKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if schema.properties.isEmpty {
                Text("Schema metadata is unavailable. Use the raw editor.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schema.properties.keys.sorted(), id: \.self) { key in
                    if let propertySchema = schema.properties[key] {
                        CodexConfigFieldRow(
                            rootValue: $rootValue,
                            path: [.key(key)],
                            key: key,
                            schema: propertySchema
                        )
                    }
                }
            }

            let topLevelObject = rootValue.objectValue ?? [:]
            let customKeys = topLevelObject.keys.sorted().filter { schema.properties[$0] == nil }
            if !customKeys.isEmpty {
                Divider()
                Text("Top-level custom keys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(customKeys, id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
                        CodexConfigFieldRow(
                            rootValue: $rootValue,
                            path: [.key(key)],
                            key: key,
                            schema: schema.additionalProperties ?? .unknown
                        )

                        Button(role: .destructive) {
                            var root = rootValue
                            root.removeValue(at: [.key(key)])
                            rootValue = root
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 8)
                    }
                }
            }

            if schema.additionalProperties != nil {
                HStack(spacing: 8) {
                    TextField("New top-level key", text: $newTopLevelKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        let trimmed = newTopLevelKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            return
                        }
                        var root = rootValue
                        let defaultValue = schema.additionalProperties?.defaultValue() ?? .string("")
                        root.setValue(defaultValue, at: [.key(trimmed)])
                        rootValue = root
                        newTopLevelKey = ""
                    }
                    .disabled(newTopLevelKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
