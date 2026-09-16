import AppleCalendarSetup
import SwiftUI
import UniformTypeIdentifiers

struct SetupWindow: View {
    @State private var model = SetupModel()
    @State private var choosingClient = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 0) {
                accessRow
                Divider()
                helperRow
                Divider()
                pinRow
            }
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))

            configuration

            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task { model.refresh() }
        .fileImporter(
            isPresented: $choosingClient,
            allowedContentTypes: [.application]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await model.pin(applicationAt: url.path(percentEncoded: false)) }
        }
    }

    // The window's title bar already names the app; repeating it here would
    // spend the top of the window saying nothing.
    private var header: some View {
        Text("Three things have to be true before an assistant can reach your calendar.")
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rows

    private var accessRow: some View {
        SetupRow(
            title: "Calendar access",
            detail: model.access.explanation,
            isDone: model.access.canRead
        ) {
            if !model.access.canRead {
                Button("Grant…") {
                    Task { await model.grantAccess() }
                }
                .disabled(model.busy != nil || model.access == .restricted)
            }
        }
    }

    private var helperRow: some View {
        SetupRow(
            title: "Helper",
            detail: model.helperInstalled
                ? "Runs in the background and holds the calendar permission."
                : model.helperState,
            isDone: model.helperInstalled
        ) {
            if model.helperInstalled {
                Button("Remove") { Task { await model.removeHelper() } }
                    .disabled(model.busy != nil)
            } else {
                Button("Install") { Task { await model.installHelper() } }
                    .disabled(model.busy != nil)
            }
        }
    }

    private var pinRow: some View {
        SetupRow(
            title: "Allowed client",
            detail: pinDetail,
            isDone: model.pinnedRequirement != nil
        ) {
            HStack(spacing: 8) {
                if model.pinnedRequirement != nil {
                    Button("Remove") { Task { await model.unpin() } }
                } else if let suggested = model.suggestedClient {
                    Button(name(of: suggested)) {
                        Task { await model.pin(applicationAt: suggested) }
                    }
                }
                Button("Choose…") { choosingClient = true }
            }
            .disabled(model.busy != nil)
        }
    }

    private var pinDetail: String {
        guard let requirement = model.pinnedRequirement else {
            return """
                Nothing is pinned. Any application on this Mac signed by the same \
                team as this one can reach your calendar through the helper.
                """
        }
        // The designated requirement is long and mostly certificate plumbing.
        // The identifier is the part a person can recognise.
        if let identifier = requirement.firstMatch(of: /identifier "([^"]+)"/)?.1 {
            return "Only \(identifier) may use the helper."
        }
        return "Only the pinned application may use the helper."
    }

    private func name(of path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // MARK: - Configuration

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add this inside \"mcpServers\" in your client's configuration")
                .font(.headline)

            // fixedSize, or the long path is truncated with an ellipsis and the
            // closing brace disappears — anyone retyping what they see would
            // produce invalid JSON.
            Text(model.configurationSnippet)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))

            HStack {
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                {
                    copy(model.configurationSnippet)
                }
                Spacer()
                Text("Then restart the client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// One line of the checklist: what it is, where it stands, what to do about it.
private struct SetupRow<Actions: View>: View {
    let title: String
    let detail: String
    let isDone: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isDone ? .green : .secondary)
                .font(.title3)
                .accessibilityLabel(isDone ? "Done" : "Not done yet")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
            actions
        }
        .padding(12)
    }
}
