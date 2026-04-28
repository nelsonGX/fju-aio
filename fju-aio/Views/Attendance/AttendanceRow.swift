import SwiftUI

struct AttendanceRow: View {
    let record: AttendanceRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.courseName)
                    .font(.body)
                Text(record.rollcallTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.status.rawValue)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
    }

    private var sourceIcon: String {
        switch record.source {
        case "qr": return "qrcode"
        case "radar": return "wave.3.right"
        case "number": return "number"
        default: return "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .present: return .green
        case .absent: return .red
        case .late: return .orange
        case .excused: return .blue
        }
    }
}
