import SwiftUI

struct HistoryView: View {
    private var model = AppModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Marker")
                .font(.headline)
            Spacer()
            Text("⌥V pastes latest")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !model.axTrusted {
            VStack(spacing: 8) {
                Text("Marker needs Accessibility access to see text selections.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Button("Open System Settings") {
                    model.openAccessibilitySettings()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        } else if model.history.items.isEmpty {
            Text("Select text in any app — it lands here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.history.items) { item in
                        HistoryRow(item: item) {
                            Paster.copyToClipboard(item.text)
                            dismiss()
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var footer: some View {
        HStack {
            Button("Clear") {
                model.history.clear()
            }
            .disabled(model.history.items.isEmpty)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct HistoryRow: View {
    let item: SelectionItem
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(item.appName)
                    Text("·")
                    Text(item.date, format: .dateTime.hour().minute())
                    if isHovered {
                        Spacer()
                        Text("Click to copy")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear)
        .onHover { isHovered = $0 }
    }
}
