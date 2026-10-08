import SwiftUI

struct ProfileEditorView: View {
    let title: String
    let actionTitle: String
    let initialName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        title: String,
        actionTitle: String,
        initialName: String,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(actionTitle) {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
