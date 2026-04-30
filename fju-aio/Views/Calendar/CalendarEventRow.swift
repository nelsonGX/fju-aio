import SwiftUI

struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            // Category color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(event.category.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(categoryColor)
                        .background(categoryColor.opacity(0.12), in: Capsule())
                }

                if let desc = event.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var categoryColor: Color {
        switch event.category {
        case .exam: return .red
        case .holiday: return .green
        case .registration: return .blue
        case .activity: return AppTheme.accent
        case .deadline: return .orange
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let start = formatter.string(from: event.startDate)
        if let end = event.endDate {
            let endStr = formatter.string(from: end)
            return "\(start) - \(endStr)"
        }
        return start
    }
}
