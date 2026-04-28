import SwiftUI

struct GradeRow: View {
    let grade: Grade

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.courseName)
                    .font(.body)
                Text("\(grade.courseCode) · \(grade.credits)學分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let score = grade.score {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.0f", score))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(scoreColor(score))
                    if let letter = grade.letterGrade {
                        Text(letter)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(grade.letterGrade ?? "尚未公布")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 90...: return .green
        case 80..<90: return .blue
        case 70..<80: return .orange
        case 60..<70: return .yellow
        default: return .red
        }
    }
}
