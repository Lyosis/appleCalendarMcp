import AppleCalendarSetup
import SwiftUI

struct SetupWindow: View {
    @State private var model = SetupModel()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 0) {
                accessRow
                Divider()
                helperRow
                Divider()
                clientRow
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
    }

    // The window's title bar already names the app; repeating it here would
    // spend the top of the window saying nothing.
    private var header: some View {
        Text(
            "Two things have to be true before an assistant can reach your calendar.",
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

    // Not a step: nothing to do, nothing to undo. Said here so nobody goes
    // looking for a setting that does not exist.
    private var clientRow: some View {
        SetupRow(
            title: Text("Allowed client", bundle: .module),
            detail: Text(
                "Claude Desktop only. This is built into this version; any other client is refused.",
                bundle: .module
            ),
            isDone: nil
        ) {
            EmptyView()
        }
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
/// `isDone` is nil for a line that only informs.
private struct SetupRow<Actions: View>: View {
    let title: Text
    let detail: Text
    let isDone: Bool?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(isDone == true ? .green : .secondary)
                .font(.title3)
                .accessibilityLabel(stateLabel)

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

    private var symbol: String {
        switch isDone {
        case true: "checkmark.circle.fill"
        case false: "circle.dashed"
        case nil: "info.circle"
        }
    }

    private var stateLabel: Text {
        switch isDone {
        case true: Text("Done", bundle: .module)
        case false: Text("Not done yet", bundle: .module)
        case nil: Text("Information", bundle: .module)
        }
    }
}
