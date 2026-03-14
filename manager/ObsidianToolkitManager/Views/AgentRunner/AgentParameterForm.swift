import SwiftUI
import AppKit

struct AgentParameterForm: View {
    let parameters: [ParameterDefinition]
    @Binding var values: [String: Any]

    var body: some View {
        let groups = groupedParameters()

        Form {
            ForEach(groups, id: \.label) { group in
                if let label = group.label {
                    // Mutually exclusive group — use Picker
                    mutuallyExclusiveSection(label: label, params: group.params)
                } else {
                    ForEach(group.params) { param in
                        parameterField(for: param)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func mutuallyExclusiveSection(label: String, params: [ParameterDefinition]) -> some View {
        Section("Input Source") {
            Picker("Source", selection: Binding(
                get: {
                    // Determine which param in the group has a non-empty value
                    for param in params {
                        if let val = values[param.name] as? String, !val.isEmpty {
                            return param.name
                        }
                    }
                    return params.first?.name ?? ""
                },
                set: { selected in
                    // Clear all params in group except selected
                    for param in params {
                        if param.name != selected {
                            values[param.name] = ""
                        }
                    }
                }
            )) {
                ForEach(params) { param in
                    Text(param.name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(param.name)
                }
            }
            .pickerStyle(.segmented)

            // Show field for selected param
            let selectedName = params.first(where: { param in
                if let val = values[param.name] as? String, !val.isEmpty { return true }
                return false
            })?.name ?? params.first?.name ?? ""

            if let selected = params.first(where: { $0.name == selectedName }) {
                parameterField(for: selected, hideLabel: true)
            }
        }
    }

    @ViewBuilder
    private func parameterField(for param: ParameterDefinition, hideLabel: Bool = false) -> some View {
        let label = hideLabel ? "" : param.description

        switch param.type {
        case .string:
            if let suggestions = param.suggestions, !suggestions.isEmpty {
                HStack {
                    TextField(label, text: stringBinding(for: param.name))
                    Menu {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                values[param.name] = suggestion
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
            } else {
                TextField(label, text: stringBinding(for: param.name))
            }

        case .bool:
            Toggle(label, isOn: boolBinding(for: param.name))

        case .filePath:
            HStack {
                TextField(label, text: stringBinding(for: param.name))
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        values[param.name] = url.path
                    }
                }
                .controlSize(.small)
            }

        case .stringArray:
            if let suggestions = param.suggestions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(label + " (comma-separated)", text: stringBinding(for: param.name))
                    HStack(spacing: 4) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                let current = (values[param.name] as? String) ?? ""
                                let items = current.components(separatedBy: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                                if !items.contains(suggestion) {
                                    let newValue = items.isEmpty ? suggestion : current + ", " + suggestion
                                    values[param.name] = newValue
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            } else {
                TextField(label + " (comma-separated)", text: stringBinding(for: param.name))
            }

        case .int:
            TextField(label, text: stringBinding(for: param.name))
                .onChange(of: (values[param.name] as? String) ?? "") { _, newValue in
                    // Filter to digits only
                    let filtered = newValue.filter { $0.isNumber || $0 == "-" }
                    if filtered != newValue {
                        values[param.name] = filtered
                    }
                }

        case .float:
            TextField(label, text: stringBinding(for: param.name))
                .onChange(of: (values[param.name] as? String) ?? "") { _, newValue in
                    // Filter to digits and decimal point
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                    if filtered != newValue {
                        values[param.name] = filtered
                    }
                }
        }
    }

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] as? String ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { values[key] as? Bool ?? false },
            set: { values[key] = $0 }
        )
    }

    struct ParameterGroup {
        let label: String?
        let params: [ParameterDefinition]
    }

    private func groupedParameters() -> [ParameterGroup] {
        var groups: [ParameterGroup] = []
        var exclusiveGroups: [String: [ParameterDefinition]] = [:]
        var standalone: [ParameterDefinition] = []

        for param in parameters {
            if let group = param.mutuallyExclusiveGroup {
                exclusiveGroups[group, default: []].append(param)
            } else {
                standalone.append(param)
            }
        }

        // Add exclusive groups first
        for (label, params) in exclusiveGroups.sorted(by: { $0.key < $1.key }) {
            groups.append(ParameterGroup(label: label, params: params))
        }

        // Add standalone params
        if !standalone.isEmpty {
            groups.append(ParameterGroup(label: nil, params: standalone))
        }

        return groups
    }
}
