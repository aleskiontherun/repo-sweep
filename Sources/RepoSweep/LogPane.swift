import SwiftUI

struct LogPane: View {
    @Environment(Workspace.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearLog() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.log.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.log) { line in
                            row(line).id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.log.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .background(.background)
    }

    private func row(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(line.date, format: .dateTime.hour().minute().second())
                .foregroundStyle(.tertiary)
            if let repo = line.repo {
                Text(repo).foregroundStyle(.secondary)
            }
            Text(line.text)
                .foregroundStyle(line.isError ? .red : .primary)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
}
