import SwiftUI

struct GPASummaryView: View {
    let summary: GPASummary

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                gpaItem(label: "學期 GPA", value: summary.semesterGPA, highlight: true)
                Divider().frame(height: 40)
                gpaItem(label: "累計 GPA", value: summary.cumulativeGPA, highlight: false)
            }

            HStack {
                creditItem(label: "已得學分", value: summary.totalCreditsEarned)
                Spacer()
                creditItem(label: "應修學分", value: summary.totalCreditsAttempted)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func gpaItem(label: String, value: Double, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value > 0 ? String(format: "%.2f", value) : "—")
                .font(highlight ? .title.weight(.bold) : .title2.weight(.semibold))
                .foregroundStyle(highlight ? .primary : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func creditItem(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
