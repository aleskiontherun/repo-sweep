import RepoSweepCore
import SwiftUI

struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            checksIcon
                .frame(width: 14)
            Link(destination: pr.url) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("#\(pr.number)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(pr.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .help(pr.url.absoluteString)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if pr.isDraft { Badge("Draft", color: .gray) }
                if pr.hasConflicts { Badge("Conflicts", color: .red) }
                switch pr.review {
                case .approved: Badge("Approved", color: .green)
                case .changesRequested: Badge("Changes requested", color: .red)
                case .required: Badge("Review required", color: .orange)
                case .none: EmptyView()
                }
            }
            Text(pr.author.map { "\($0.login) · " } ?? "")
                + Text(pr.updatedAt, format: .relative(presentation: .named))
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var checksIcon: some View {
        switch pr.checks {
        case .passing:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Checks passing")
        case .failing:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Checks failing")
        case .pending:
            Image(systemName: "clock.fill").foregroundStyle(.orange).help("Checks running")
        case .none:
            Image(systemName: "circle.dashed").foregroundStyle(.tertiary).help("No checks")
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
