import SwiftUI

struct CodexConfigFieldRow: View {
    @Binding var rootValue: CodexConfigValue
    let path: [CodexConfigPathSegment]
    let key: String
    let schema: CodexConfigSchemaNode

    @State private var isExpanded = true
    @State private var revealSensitive = false
    @State private var pendingMapKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch schema.kind {
            case .object:
                DisclosureGroup(isExpanded: $isExpanded) {
                    objectEditor
                } label: {
                    label
                }
            case .array:
                DisclosureGroup(isExpanded: $isExpanded) {
                    arrayEditor
                } label: {
                    label
                }
            case .string:
                primitiveRow {
                    TextField("Value", text: stringBinding)
                        .textFieldStyle(.roundedBorder)
                }
            case .integer:
                primitiveRow {
                    TextField("Value", text: integerBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            case .number:
                primitiveRow {
                    TextField("Value", text: numberBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            case .boolean:
                Toggle(isOn: booleanBinding) {
                    label
                }
            case .enumeration:
                primitiveRow {
                    Picker("Value", selection: enumBinding) {
                        ForEach(schema.enumValues, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            case .unknown:
                primitiveRow {
                    TextField("Value", text: stringBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let description = schema.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.body.weight(.medium))

            if schema.required {
                Text("Required")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15), in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func primitiveRow<Editor: View>(@ViewBuilder editor: () -> Editor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                label

                if CodexSensitiveFieldPolicy.isSensitive(path: path), schema.kind == .string {
                    Button(revealSensitive ? "Mask" : "Reveal") {
                        revealSensitive.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if CodexSensitiveFieldPolicy.isSensitive(path: path), schema.kind == .string, !revealSensitive {
                SecureField("Value", text: stringBinding)
                    .textFieldStyle(.roundedBorder)
            } else {
                editor()
            }
        }
    }

    private var objectEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if value?.objectValue == nil {
                Button("Add object") {
                    setValue(.object([:]))
                }
                .buttonStyle(.bordered)
            } else {
                ForEach(schema.properties.keys.sorted(), id: \.self) { childKey in
                    if let childSchema = schema.properties[childKey] {
                        CodexConfigFieldRow(
                            rootValue: $rootValue,
                            path: path + [.key(childKey)],
                            key: childKey,
                            schema: childSchema
                        )
                    }
                }

                if let object = value?.objectValue {
                    let extraKeys = object.keys.sorted().filter { schema.properties[$0] == nil }
                    if !extraKeys.isEmpty {
                        Divider()
                        Text("Custom Keys")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(extraKeys, id: \.self) { extraKey in
                            HStack(alignment: .top, spacing: 8) {
                                CodexConfigFieldRow(
                                    rootValue: $rootValue,
                                    path: path + [.key(extraKey)],
                                    key: extraKey,
                                    schema: schema.additionalProperties ?? .unknown
                                )

                                Button(role: .destructive) {
                                    removeValue(path: path + [.key(extraKey)])
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .padding(.top, 8)
                            }
                        }
                    }
                }

                if schema.additionalProperties != nil || schema.properties.isEmpty {
                    HStack(spacing: 8) {
                        TextField("New key", text: $pendingMapKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let trimmed = pendingMapKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let defaultValue = schema.additionalProperties?.defaultValue() ?? .string("")
                            setValue(defaultValue, at: path + [.key(trimmed)])
                            pendingMapKey = ""
                        }
                        .disabled(pendingMapKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !path.isEmpty {
                    Button(role: .destructive) {
                        removeCurrentValue()
                    } label: {
                        Text("Remove \(key)")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.leading, 8)
    }

    private var arrayEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if value?.arrayValue == nil {
                Button("Add array") {
                    setValue(.array([]))
                }
                .buttonStyle(.bordered)
            } else {
                let items = value?.arrayValue ?? []
                ForEach(Array(items.indices), id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        CodexConfigFieldRow(
                            rootValue: $rootValue,
                            path: path + [.index(index)],
                            key: "Item \(index)",
                            schema: schema.items ?? .unknown
                        )

                        Button(role: .destructive) {
                            removeValue(path: path + [.index(index)])
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 8)
                    }
                }

                Button("Add Item") {
                    var array = items
                    array.append(schema.items?.defaultValue() ?? .string(""))
                    setValue(.array(array))
                }
                .buttonStyle(.bordered)

                if !path.isEmpty {
                    Button(role: .destructive) {
                        removeCurrentValue()
                    } label: {
                        Text("Remove \(key)")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.leading, 8)
    }

    private var value: CodexConfigValue? {
        rootValue.value(at: path)
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: {
                value?.stringValue ?? ""
            },
            set: { newValue in
                setValue(.string(newValue))
            }
        )
    }

    private var integerBinding: Binding<String> {
        Binding(
            get: {
                if let integer = value?.integerValue {
                    return String(integer)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    removeCurrentValue()
                    return
                }
                guard let parsed = Int(trimmed) else {
                    return
                }
                setValue(.integer(parsed))
            }
        )
    }

    private var numberBinding: Binding<String> {
        Binding(
            get: {
                if let number = value?.numberValue {
                    return String(number)
                }
                if let integer = value?.integerValue {
                    return String(integer)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    removeCurrentValue()
                    return
                }
                guard let parsed = Double(trimmed) else {
                    return
                }
                setValue(.number(parsed))
            }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: {
                value?.booleanValue ?? false
            },
            set: { newValue in
                setValue(.boolean(newValue))
            }
        )
    }

    private var enumBinding: Binding<String> {
        Binding(
            get: {
                value?.stringValue ?? schema.enumValues.first ?? ""
            },
            set: { newValue in
                setValue(.string(newValue))
            }
        )
    }

    private func setValue(_ newValue: CodexConfigValue) {
        setValue(newValue, at: path)
    }

    private func setValue(_ newValue: CodexConfigValue, at targetPath: [CodexConfigPathSegment]) {
        var root = rootValue
        root.setValue(newValue, at: targetPath)
        rootValue = root
    }

    private func removeCurrentValue() {
        removeValue(path: path)
    }

    private func removeValue(path targetPath: [CodexConfigPathSegment]) {
        var root = rootValue
        root.removeValue(at: targetPath)
        rootValue = root
    }
}
