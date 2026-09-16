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
        Text(
            "Three things have to be true before an assistant can reach your calendar.",
            bundle: .module
        )
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rows

    private var accessRow: some View {
        SetupRow(
            title: Text("Calendar access", bundle: .module),
            detail: accessDetail,
            isDone: model.access.canRead
        ) {
            if !model.access.canRead {
                Button {
                    Task { await model.grantAccess() }
                } label: {
                    Text("Grant…", bundle: .module)
                }
                .disabled(model.busy != nil || model.access == .restricted)
            }
        }
    }

    private var accessDetail: Text {
        switch model.access {
        case .fullAccess:
            Text("Full read and write access to calendar events.", bundle: .module)
        case .notDetermined:
            Text("Not granted yet.", bundle: .module)
        case .denied:
            Text("Refused. Grant it in System Settings › Privacy & Security › Calendars.", bundle: .module)
        case .restricted:
            Text("Blocked by a policy such as Screen Time or a configuration profile.", bundle: .module)
        case .writeOnly:
            Text("Only event creation is allowed. Reading events needs full access.", bundle: .module)
        case .unknown:
            Text("The system reported a status this version does not recognise.", bundle: .module)
        }
    }

    private var helperRow: some View {
        SetupRow(
            title: Text("Helper", bundle: .module),
            detail: helperDetail,
            isDone: model.helper == .installed
        ) {
            if model.helper == .installed {
                Button { Task { await model.removeHelper() } } label: {
                    Text("Remove", bundle: .module)
                }
                .disabled(model.busy != nil)
            } else {
                Button { Task { await model.installHelper() } } label: {
                    Text("Install", bundle: .module)
                }
                .disabled(model.busy != nil)
            }
        }
    }

    private var helperDetail: Text {
        switch model.helper {
        case .installed:
            Text("Runs in the background and holds the calendar permission.", bundle: .module)
        case .notInstalled:
            Text("Not installed.", bundle: .module)
        case .needsApproval:
            Text("Waiting for your approval in System Settings › General › Login Items.", bundle: .module)
        }
    }

    private var pinRow: some View {
        SetupRow(
            title: Text("Allowed client", bundle: .module),
            detail: pinDetail,
            isDone: model.isPinned
        ) {
            HStack(spacing: 8) {
                if model.isPinned {
                    Button { Task { await model.unpin() } } label: {
                        Text("Remove", bundle: .module)
                    }
                } else if let suggested = model.suggestedClient {
                    Button(name(of: suggested)) {
                        Task { await model.pin(applicationAt: suggested) }
                    }
                }
                Button { choosingClient = true } label: {
                    Text("Choose…", bundle: .module)
                }
            }
            .disabled(model.busy != nil)
        }
    }

    private var pinDetail: Text {
        guard model.isPinned else {
            return Text(
                """
                Nothing is pinned. Any application signed by the same team as this one \
                can reach your calendar through the helper.
                """,
                bundle: .module
            )
        }
        // A pin with no readable identifier is still a pin; say the true thing
        // rather than inventing a name for it.
        guard let identifier = model.pinnedIdentifier else {
            return Text("Only the pinned application may use the helper.", bundle: .module)
        }
        return Text("Only \(identifier) may use the helper.", bundle: .module)
    }

    private func name(of path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // MARK: - Configuration

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add this inside \"mcpServers\" in your client's configuration", bundle: .module)
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
                Button {
                    copy(model.configurationSnippet)
                } label: {
                    Label {
                        Text(copied ? "Copied" : "Copy", bundle: .module)
                    } icon: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                Spacer()
                Text("Then restart the client.", bundle: .module)
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
    let title: Text
    let detail: Text
    let isDone: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isDone ? .green : .secondary)
                .font(.title3)
                .accessibilityLabel(
                    isDone
                        ? Text("Done", bundle: .module)
                        : Text("Not done yet", bundle: .module)
                )

            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                detail
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
